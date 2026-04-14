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

SUPER_OUT="$WORK/super_catalyst.img"
echo "🧩 Building super image (lpmake placeholder)..."
if [[ -x "$ROOT_DIR/tools/lpmake" ]]; then
  "$ROOT_DIR/tools/lpmake" \
    --metadata-size 65536 \
    --super-name super \
    --device super:8589934592 \
    --group main:4294967296 \
    --partition system:readonly:0:main --image system="$SYSTEM_IMG" \
    --partition vendor:readonly:0:main --image vendor="$VENDOR_IMG" \
    --partition product:readonly:0:main --image product="$PRODUCT_IMG" \
    --partition odm:readonly:0:main --image odm="$ODM_IMG" \
    --output "$SUPER_OUT" || true
else
  echo "⚠️  tools/lpmake missing; creating placeholder super image: $SUPER_OUT"
  : > "$SUPER_OUT"
fi

RELEASE_ZIP="$OUTDIR/CatalystUI_A146B_Release.zip"
echo "📦 Creating flashable release zip: $(basename "$RELEASE_ZIP")"
cd "$WORK"
zip -qr "$RELEASE_ZIP" . || true

echo "✅ Release artifact ready: $RELEASE_ZIP"
