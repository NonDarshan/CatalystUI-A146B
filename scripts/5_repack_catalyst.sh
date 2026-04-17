#!/usr/bin/env bash
set -e

echo "📦 [5/5] Repacking Catalyst UI release..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTDIR="$ROOT_DIR/out"
WORK="$ROOT_DIR/workspace/repack"
WORKSPACE="$ROOT_DIR/workspace"
mkdir -p "$OUTDIR" "$WORK"

# ── Load super metadata saved during unpack ──────────────────────────
# BUG FIX: old code hardcoded 8 GB — wrong for A146B (~5.5 GB).
# We now read the real size from the raw super image stat.
if [[ -f "$WORKSPACE/super_metadata.env" ]]; then
    # shellcheck source=/dev/null
    source "$WORKSPACE/super_metadata.env"
    echo "📊 Super: ${SUPER_DEVICE_SIZE} bytes ($(( SUPER_DEVICE_SIZE / 1024 / 1024 )) MB)"
else
    echo "⚠️  super_metadata.env missing — using A146B known defaults"
    SUPER_DEVICE_SIZE=5905580032   # ~5.5 GB typical for SM-A146B INS
    SUPER_GROUP_SIZE=5901385728    # super - 4 MB
fi

# ── Build EROFS images ───────────────────────────────────────────────
echo ""
echo "🧱 Building EROFS partition images..."

MKFS="$ROOT_DIR/tools/mkfs.erofs"
[[ -x "$MKFS" ]] || MKFS="$(which mkfs.erofs 2>/dev/null || true)"
[[ -n "$MKFS" ]] || { echo "❌ mkfs.erofs not found!"; exit 1; }

mk_erofs() {
    local part="$1"
    local src="$ROOT_DIR/mnt/$part"
    local out="$WORK/${part}.img"
    if [[ ! -d "$src" || -z "$(ls -A "$src" 2>/dev/null)" ]]; then
        echo "  ⏭  $part: empty/missing, skipping"
        return 0
    fi
    echo "  🧩 Building ${part}.img..."
    "$MKFS" -zlz4hc,9 "$out" "$src" \
        && echo "     ✅ $(du -sh "$out" | cut -f1) — ${part}.img" \
        || { echo "     ❌ mkfs.erofs failed for $part!"; return 1; }
}

# BUG FIX: read the list of partitions that were actually extracted
# (system, vendor, product, odm, system_ext, vendor_dlkm, odm_dlkm)
BUILT_PARTS=()
if [[ -f "$WORKSPACE/partition_list.txt" ]]; then
    while IFS= read -r part; do
        mk_erofs "$part"
        [[ -f "$WORK/${part}.img" ]] && BUILT_PARTS+=("$part")
    done < "$WORKSPACE/partition_list.txt"
else
    for part in system vendor product odm system_ext; do
        mk_erofs "$part"
        [[ -f "$WORK/${part}.img" ]] && BUILT_PARTS+=("$part")
    done
fi
echo "  Built: ${BUILT_PARTS[*]}"

# ── Build super.img ──────────────────────────────────────────────────
echo ""
echo "🏗️  Building super.img with lpmake..."

LPMAKE="$ROOT_DIR/tools/lpmake"
[[ -x "$LPMAKE" ]] || LPMAKE="$(which lpmake 2>/dev/null || true)"

SUPER_OUT="$WORK/super.img"

if [[ -z "$LPMAKE" ]]; then
    echo "⚠️  lpmake not found — individual images will be packaged for manual flash"
else
    LPMAKE_ARGS=(
        "--metadata-size" "65536"
        "--super-name"    "super"
        "--device"        "super:${SUPER_DEVICE_SIZE}"
        "--group"         "main:${SUPER_GROUP_SIZE}"
        "--sparse"
        "--output"        "$SUPER_OUT"
    )
    # BUG FIX: dynamically add ALL built partitions (old code missed system_ext)
    for part in "${BUILT_PARTS[@]}"; do
        LPMAKE_ARGS+=(
            "--partition" "${part}:readonly:0:main"
            "--image"     "${part}=$WORK/${part}.img"
        )
    done

    if "$LPMAKE" "${LPMAKE_ARGS[@]}"; then
        echo "  ✅ super.img built ($(du -sh "$SUPER_OUT" | cut -f1))"
        for part in "${BUILT_PARTS[@]}"; do rm -f "$WORK/${part}.img"; done
    else
        echo "  ❌ lpmake failed! Keeping individual partition images."
        rm -f "$SUPER_OUT"
    fi
fi

# ── Collect boot-critical images from workspace ──────────────────────
echo ""
echo "🔍 Collecting boot-critical partition images..."

collect_img() {
    local target="$1"
    local dest="$WORK/${target}.img"
    local lz4_file raw_file
    lz4_file=$(find "$WORKSPACE" -path "$WORK" -prune -o -name "${target}.img.lz4" -print 2>/dev/null | head -1)
    raw_file=$(find "$WORKSPACE"  -path "$WORK" -prune -o -name "${target}.img"     -print 2>/dev/null | head -1)
    if [[ -n "$lz4_file" ]]; then
        lz4 -d -f "$lz4_file" "$dest" && echo "  ✅ $target (from lz4)"
    elif [[ -n "$raw_file" ]]; then
        cp "$raw_file" "$dest"         && echo "  ✅ $target (raw)"
    else
        echo "  ⚠️  ${target}.img not found in workspace"
    fi
}

for img in boot dtbo vendor_boot prism optics; do
    collect_img "$img"
done

# ── CRITICAL: Patch vbmeta ───────────────────────────────────────────
# This is the #1 reason modified Samsung ROMs bootloop with zero logs.
# AVB2.0 verifies system/vendor/product/odm hashes at boot. Any change
# to those partitions fails the hash check → device reboots silently
# before init even starts → no logs in TWRP, no crash dump, nothing.
# Setting flag 2 (VERIFICATION_DISABLED) tells the bootloader to skip
# all partition verification. Requires OEM unlock to be enabled.
echo ""
echo "🔐 Patching vbmeta (CRITICAL — disables AVB verification)..."

patch_vbmeta() {
    local img_name="$1"
    local dest="$WORK/${img_name}.img"
    if [[ -f "$ROOT_DIR/tools/avbtool.py" ]]; then
        python3 "$ROOT_DIR/tools/avbtool.py" make_vbmeta_image \
            --flag 2 \
            --padding_size 4096 \
            --output "$dest" \
            && echo "  ✅ $img_name patched (AVB DISABLED)" \
            || echo "  ⚠️  $img_name patch failed"
    else
        echo "  ❌ avbtool.py missing — $img_name NOT patched (bootloop WILL occur!)"
    fi
}

# Always create a clean patched vbmeta regardless of whether original exists
patch_vbmeta "vbmeta"

# Handle Samsung-specific secondary vbmeta images
for extra in vbmeta_system vbmeta_vendor; do
    if find "$WORKSPACE" \( -name "${extra}.img" -o -name "${extra}.img.lz4" \) \
        -not -path "$WORK/*" 2>/dev/null | grep -q .; then
        collect_img "$extra"
        [[ -f "$WORK/${extra}.img" ]] && patch_vbmeta "$extra"
    fi
done

# ── Create Odin AP tar.md5 ───────────────────────────────────────────
# BUG FIX: old output was `zip -r` of raw images — Odin cannot flash
# that. Odin requires a tar containing lz4-compressed images, with an
# md5 hash appended to the end of the tar (Samsung's format).
echo ""
echo "📦 Creating Odin-flashable AP tar.md5..."

cd "$WORK"

LZ4_FILES=()
for img_file in *.img; do
    [[ -f "$img_file" ]] || continue
    echo "  🗜️  Compressing $img_file..."
    lz4 -B6 --content-size "$img_file" "${img_file}.lz4" \
        && LZ4_FILES+=("${img_file}.lz4") \
        || echo "  ⚠️  Compression failed for $img_file"
done

if [[ ${#LZ4_FILES[@]} -eq 0 ]]; then
    echo "❌ No images to package — build failed upstream."
    exit 1
fi

ODIN_TAR="$OUTDIR/AP_CatalystUI_A146B.tar"
echo "  📼 Packaging: ${LZ4_FILES[*]}"
tar -H ustar -c "${LZ4_FILES[@]}" > "$ODIN_TAR"

# Append md5 in Samsung Odin format (text line at end of tar binary)
md5sum "$ODIN_TAR" >> "$ODIN_TAR"
mv "$ODIN_TAR" "${ODIN_TAR}.md5"

SIZE=$(du -sh "${ODIN_TAR}.md5" | cut -f1)
echo ""
echo "✅ Output: AP_CatalystUI_A146B.tar.md5 ($SIZE)"
echo ""
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║  Flash instructions (OEM unlock required):    ║"
echo "  ║  1. Odin3 v3.14.4 on Windows PC               ║"
echo "  ║  2. AP → select AP_CatalystUI_A146B.tar.md5   ║"
echo "  ║  3. Options: Auto Reboot ✓  F. Reset Time ✓   ║"
echo "  ║  4. Phone in Download Mode → START            ║"
echo "  ╚═══════════════════════════════════════════════╝"
