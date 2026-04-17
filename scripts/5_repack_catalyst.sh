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

    if "$LPMAKE" "${LPMAKE_ARGS[@]}" && [[ -f "$SUPER_OUT" ]]; then
        echo "  ✅ super.img built ($(du -sh "$SUPER_OUT" | cut -f1))"
        for part in "${BUILT_PARTS[@]}"; do rm -f "$WORK/${part}.img"; done
    else
        echo "  ❌ lpmake failed or file missing! Keeping individual partition images."
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

# ── Create TWRP Flashable ZIP ─────────────────────────────────────────
echo ""
echo "📦 Preparing TWRP-flashable ZIP..."

cd "$WORK"

# 1. Bring in the META-INF folder from your repo
if [[ -d "$ROOT_DIR/META-INF" ]]; then
    echo "  🗂️ Injecting META-INF installer..."
    cp -r "$ROOT_DIR/META-INF" "$WORK/"
else
    echo "  ❌ WARNING: META-INF folder not found in repo root!"
    echo "     This ZIP will just contain images and won't flash in TWRP."
fi

RELEASE_ZIP="$OUTDIR/CatalystUI_A146B_Release.zip"
echo "  📼 Zipping everything together (compression level 1 for speed)..."

# 2. We use -1 (fast compression) because .img files are already compressed 
# and we don't want GitHub to hang for 20 minutes trying to compress 6GB.
zip -r -1 "$RELEASE_ZIP" ./* > /dev/null

SIZE=$(du -sh "$RELEASE_ZIP" | cut -f1)
echo ""
echo "✅ Output: CatalystUI_A146B_Release.zip ($SIZE)"
echo ""
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║  TWRP Flash Instructions:                     ║"
echo "  ║  1. Boot to TWRP                              ║"
echo "  ║  2. Wipe -> Format Data -> 'yes'              ║"
echo "  ║  3. Install -> CatalystUI_A146B_Release.zip   ║"
echo "  ║  4. Reboot System                             ║"
echo "  ╚═══════════════════════════════════════════════╝"
