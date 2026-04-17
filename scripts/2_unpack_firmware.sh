#!/usr/bin/env bash
set -euo pipefail

echo "📡 [2/5] Fetching and unpacking firmware..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORKSPACE="$ROOT_DIR/workspace"
mkdir -p "$WORKSPACE"

MODEL="SM-A146B"
REGION="INS"

echo "⬇️  Downloading firmware via samloader-rs (~4 GB, please wait)..."
mkdir -p "$WORKSPACE/dl"
cd "$WORKSPACE/dl"

# The Rust samloader automatically checks the latest version, downloads it, and decrypts it into a standard zip!
~/.cargo/bin/samloader -m "$MODEL" -r "$REGION" download

cd "$ROOT_DIR"

shopt -s nullglob
zip_files=("$WORKSPACE/dl/"*.zip)
shopt -u nullglob
if [[ ${#zip_files[@]} -lt 1 ]]; then
    echo "❌ No firmware zip found after download. Network issue or Samsung FOTA block."
    exit 1
fi
FIRMWARE_ZIP="${zip_files[0]}"
echo "✅ Found: $(basename "$FIRMWARE_ZIP")"

# ── Extract AP tar ───────────────────────────────────────────────────
EXTRACTED="$WORKSPACE/fw_extracted"
rm -rf "$EXTRACTED"; mkdir -p "$EXTRACTED"
echo "📦 Extracting firmware package..."
unzip -q "$FIRMWARE_ZIP" -d "$EXTRACTED"

shopt -s nullglob
ap_files=("$EXTRACTED"/AP_*.tar.md5 "$EXTRACTED"/AP_*.tar)
shopt -u nullglob
if [[ ${#ap_files[@]} -lt 1 ]]; then
    echo "❌ AP_*.tar.md5 not found. Contents of extracted firmware:"
    ls -la "$EXTRACTED"
    exit 1
fi
AP_TAR="${ap_files[0]}"
echo "✅ AP file: $(basename "$AP_TAR")"

echo "🔨 Extracting critical images from AP tar..."
tar -xf "$AP_TAR" -C "$WORKSPACE" super.img.lz4 boot.img.lz4 vbmeta.img.lz4 || {
    echo "❌ Core images missing from AP tar!"
    exit 1
}

echo "🔨 Extracting hardware images from BL tar..."
shopt -s nullglob
bl_files=("$EXTRACTED"/BL_*.tar.md5 "$EXTRACTED"/BL_*.tar)
shopt -u nullglob
if [[ ${#bl_files[@]} -gt 0 ]]; then
    tar -xf "${bl_files[0]}" -C "$WORKSPACE" dtbo.img.lz4 vendor_boot.img.lz4 prism.img.lz4 optics.img.lz4 || echo "⚠️ Some BL images missing (this is usually fine)"
fi

echo "🧹 Freeing space (removing raw firmware download)..."
rm -f "$FIRMWARE_ZIP" || true
rm -rf "$EXTRACTED"   || true

# ── Decompress LZ4 ─────────────────────────────────────────────────
SUPER_LZ4="$WORKSPACE/super.img.lz4"
SUPER_SPARSE="$WORKSPACE/super.img"
SUPER_RAW="$WORKSPACE/super_raw.img"

echo "🗜️  Decompressing super.img.lz4 → super.img..."
lz4 -d -f "$SUPER_LZ4" "$SUPER_SPARSE"
rm -f "$SUPER_LZ4"

# ── Sparse → raw ────────────────────────────────────────────────────
echo "🧱 Converting sparse → raw (if needed)..."
SPARSE_MAGIC=$(xxd -l 4 -p "$SUPER_SPARSE" 2>/dev/null || echo "")
if [[ "${SPARSE_MAGIC,,}" == "3aff26ed" ]]; then
    echo "  → Sparse format detected, converting with simg2img..."
    simg2img "$SUPER_SPARSE" "$SUPER_RAW"
else
    echo "  → Already raw, copying..."
    cp "$SUPER_SPARSE" "$SUPER_RAW"
fi

# ── Save super metadata (used in repack to get correct size) ───
SUPER_DEVICE_SIZE=$(stat -c %s "$SUPER_RAW" 2>/dev/null || stat -f %z "$SUPER_RAW" 2>/dev/null || echo "5905580032")
SUPER_GROUP_SIZE=$(( SUPER_DEVICE_SIZE - 4 * 1024 * 1024 ))

echo "📊 Super partition size: ${SUPER_DEVICE_SIZE} bytes ($(( SUPER_DEVICE_SIZE / 1024 / 1024 )) MB)"
{
    echo "SUPER_DEVICE_SIZE=$SUPER_DEVICE_SIZE"
    echo "SUPER_GROUP_SIZE=$SUPER_GROUP_SIZE"
} > "$WORKSPACE/super_metadata.env"

# ── Unpack super image ───────────────────────────────────────────────
echo "🧩 Unpacking super image with lpunpack..."
mkdir -p "$WORKSPACE/lp"

if [[ -x "$ROOT_DIR/tools/lpunpack" ]]; then
    "$ROOT_DIR/tools/lpunpack" "$SUPER_RAW" "$WORKSPACE/lp" \
        || python3 "$ROOT_DIR/tools/lpunpack.py" "$SUPER_RAW" "$WORKSPACE/lp"
elif [[ -f "$ROOT_DIR/tools/lpunpack.py" ]]; then
    python3 "$ROOT_DIR/tools/lpunpack.py" "$SUPER_RAW" "$WORKSPACE/lp" \
        || python3 "$ROOT_DIR/tools/lpunpack.py" "$SUPER_SPARSE" "$WORKSPACE/lp"
else
    echo "❌ Neither lpunpack binary nor lpunpack.py found!"
    exit 1
fi

echo ""
echo "📊 Partitions found in super:"
ls -la "$WORKSPACE/lp/"

# ── Extract EROFS partitions ─────────────────────────────────────────
FSCK="$ROOT_DIR/tools/fsck.erofs"
[[ -x "$FSCK" ]] || FSCK="$(which fsck.erofs 2>/dev/null || true)"

extract_erofs() {
    local part="$1"
    local outdir="$ROOT_DIR/mnt/$part"
    mkdir -p "$outdir"

    local img="$WORKSPACE/lp/${part}.img"
    [[ -f "$img" ]] || img="$WORKSPACE/lp/${part}_a.img"

    if [[ ! -f "$img" ]]; then
        return 0
    fi
    echo "  📂 $part → $outdir"
    "$FSCK" --extract="$outdir" "$img" >/dev/null 2>&1 || true
}

EXTRACTED_PARTS=()
for part in system vendor product odm system_ext vendor_dlkm odm_dlkm; do
    extract_erofs "$part"
    if [[ -n "$(ls -A "$ROOT_DIR/mnt/$part" 2>/dev/null)" ]]; then
        EXTRACTED_PARTS+=("$part")
    fi
done

printf '%s\n' "${EXTRACTED_PARTS[@]}" > "$WORKSPACE/partition_list.txt"
echo "✅ Extracted: ${EXTRACTED_PARTS[*]}"
echo "✅ Firmware unpack complete."
