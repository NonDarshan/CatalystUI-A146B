#!/usr/bin/env bash
set -e

echo "📦 [5/5] Repacking Catalyst UI release..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTDIR="$ROOT_DIR/out"
WORK="$ROOT_DIR/workspace/repack"
mkdir -p "$OUTDIR" "$WORK"

SYSTEM_DIR="$ROOT_DIR/mnt/system"
VENDOR_DIR="$ROOT_DIR/mnt/vendor"
PRODUCT_DIR="$ROOT_DIR/mnt/product"
ODM_DIR="$ROOT_DIR/mnt/odm"

SYSTEM_IMG="$WORK/system.img"
VENDOR_IMG="$WORK/vendor.img"
PRODUCT_IMG="$WORK/product.img"
ODM_IMG="$WORK/odm.img"

echo "🧱 Building EROFS images (mkfs.erofs)..."
mk_erofs() {
  local src="$1"
  local out="$2"
  if [[ -x "$ROOT_DIR/tools/mkfs.erofs" ]]; then
    echo "🧩 mkfs.erofs $(basename "$out")"
    "$ROOT_DIR/tools/mkfs.erofs" -zlz4hc,9 "$out" "$src" || true
  else
    echo "⚠️  tools/mkfs.erofs missing; creating placeholder image: $out"
    : > "$out"
  fi
}

mk_erofs "$SYSTEM_DIR" "$SYSTEM_IMG"
mk_erofs "$VENDOR_DIR" "$VENDOR_IMG"
mk_erofs "$PRODUCT_DIR" "$PRODUCT_IMG"
mk_erofs "$ODM_DIR" "$ODM_IMG"

# --- THE FIRMWARE HUNTER ---
echo "🔍 Hunting down matching boot.img, vbmeta.img, and core partitions..."
# Array of target partitions we want to bundle, exactly like ReCoreUI
TARGETS=("boot" "vbmeta" "dtbo" "vendor_boot" "prism" "optics")

for target in "${TARGETS[@]}"; do
  # Search for .lz4 or raw .img anywhere in the root dir (excluding our output work folder)
  LZ4_FILE=$(find "$ROOT_DIR" -path "$WORK" -prune -o -name "${target}.img.lz4" -print | head -n 1)
  IMG_FILE=$(find "$ROOT_DIR" -path "$WORK" -prune -o -name "${target}.img" -print | head -n 1)

  if [[ -n "$LZ4_FILE" ]]; then
    echo "📦 Found ${target}.img.lz4! Decompressing directly into output..."
    lz4 -d "$LZ4_FILE" "$WORK/${target}.img" || echo "⚠️ Failed to extract $LZ4_FILE"
  elif [[ -n "$IMG_FILE" ]]; then
    echo "📦 Found raw ${target}.img! Copying to output..."
    cp "$IMG_FILE" "$WORK/${target}.img"
  else
    echo "ℹ️  ${target}.img not found in workspace. Skipping."
  fi
done
# ---------------------------

SUPER_OUT="$WORK/super_catalyst.img"
echo "🧩 Building super image (lpmake)..."
if [[ -x "$ROOT_DIR/tools/lpmake" ]]; then
  # If lpmake succeeds, we pack super.img and clean up the raw files to save space!
  if "$ROOT_DIR/tools/lpmake" \
    --metadata-size 65536 \
    --super-name super \
    --device super:8589934592 \
    --group main:4294967296 \
    --partition system:readonly:0:main --image system="$SYSTEM_IMG" \
    --partition vendor:readonly:0:main --image vendor="$VENDOR_IMG" \
    --partition product:readonly:0:main --image product="$PRODUCT_IMG" \
    --partition odm:readonly:0:main --image odm="$ODM_IMG" \
    --output "$SUPER_OUT"; then
    echo "✅ Super image built successfully! Removing raw partition images to match ReCoreUI layout..."
    rm -f "$SYSTEM_IMG" "$VENDOR_IMG" "$PRODUCT_IMG" "$ODM_IMG"
    mv "$SUPER_OUT" "$WORK/super.img"
  else
    echo "⚠️ lpmake failed. Leaving individual images in the zip for manual fastboot flashing."
  fi
else
  echo "⚠️ tools/lpmake missing. Leaving individual images in the zip for manual fastboot flashing."
fi

RELEASE_ZIP="$OUTDIR/CatalystUI_A146B_Release.zip"
echo "📦 Creating flashable release zip: $(basename "$RELEASE_ZIP")"
cd "$WORK"
zip -qr "$RELEASE_ZIP" . || true

echo "✅ Release artifact ready: $RELEASE_ZIP"
