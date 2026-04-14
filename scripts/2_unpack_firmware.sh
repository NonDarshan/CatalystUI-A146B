#!/usr/bin/env bash
set -e

echo "📡 Fetching latest firmware directly from Samsung FOTA..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WORKSPACE="$ROOT_DIR/workspace"
EXTRACTED="$WORKSPACE/fw_extracted"
mkdir -p "$WORKSPACE"

echo "🦀 Installing modern Samloader-RS (by Topjohnwu)..."
# GitHub Actions Ubuntu has Rust pre-installed. Compiling takes ~1 min.
cargo install --git https://github.com/topjohnwu/samloader-rs.git
export PATH="$HOME/.cargo/bin:$PATH"

MODEL="SM-A146B"
REGION="INS"

# Note: The command in Rust is "check" instead of "checkupdate"
echo "🔎 Checking latest firmware for MODEL=$MODEL REGION=$REGION ..."
VERSION="$(samloader -m "$MODEL" -r "$REGION" check | tr -d '\r' | tail -n 1)"
if [[ -z "$VERSION" ]]; then
  echo "❌ Failed to fetch firmware version from FOTA."
  exit 1
fi
echo "✅ Latest version found: $VERSION"

echo "⬇️  Downloading and decrypting firmware to workspace/ (Multi-threaded)..."
# We move INTO the workspace, download automatically, and move back out. No flags needed!
cd "$WORKSPACE"
samloader -m "$MODEL" -r "$REGION" download
cd "$ROOT_DIR"

echo "📦 Locating downloaded ZIP file..."
shopt -s nullglob
zip_files=("$WORKSPACE"/*.zip)
shopt -u nullglob
if [[ ${#zip_files[@]} -lt 1 ]]; then
  echo "❌ No .zip firmware file found in workspace/ after download."
  ls -la "$WORKSPACE" || true
  exit 1
fi
FIRMWARE_ZIP="${zip_files[0]}"
echo "✅ Firmware package: $(basename "$FIRMWARE_ZIP")"

echo "📦 Extracting firmware package..."
rm -rf "$EXTRACTED"
mkdir -p "$EXTRACTED"
unzip -q "$FIRMWARE_ZIP" -d "$EXTRACTED"

shopt -s nullglob
ap_files=("$EXTRACTED"/AP_*.tar.md5)
shopt -u nullglob
if [[ ${#ap_files[@]} -lt 1 ]]; then
  echo "❌ AP_*.tar.md5 not found in extracted firmware."
  ls -la "$EXTRACTED" || true
  exit 1
fi
AP_TAR="${ap_files[0]}"
echo "✅ AP file: $(basename "$AP_TAR")"

echo "🔨 Extracting super.img.lz4 from the AP file..."
tar -xf "$AP_TAR" -C "$WORKSPACE" "super.img.lz4"

echo "🧹 Cleaning up large temporary files..."
rm -f "$FIRMWARE_ZIP" || true
rm -rf "$EXTRACTED" || true

SUPER_LZ4="$WORKSPACE/super.img.lz4"
SUPER_RAW_SPARSE="$WORKSPACE/super.img"
SUPER_RAW="$WORKSPACE/super_raw.img"

if [[ ! -f "$SUPER_LZ4" ]]; then
  echo "❌ super.img.lz4 not found in workspace/ after AP extraction."
  ls -la "$WORKSPACE" || true
  exit 1
fi

echo "🗜️  Decompressing LZ4..."
if [[ -x "$ROOT_DIR/tools/lz4" ]]; then
  "$ROOT_DIR/tools/lz4" -d "$SUPER_LZ4" "$SUPER_RAW_SPARSE"
else
  echo "⚠️  tools/lz4 not present or not executable; cannot decompress."
  exit 1
fi

echo "🧱 Converting sparse to raw (simg2img)..."
if [[ -x "$ROOT_DIR/tools/simg2img" ]]; then
  "$ROOT_DIR/tools/simg2img" "$SUPER_RAW_SPARSE" "$SUPER_RAW"
else
  echo "⚠️  tools/simg2img not present or not executable; cannot convert sparse image."
  exit 1
fi

echo "🧩 Unpacking super image (lpunpack)..."
mkdir -p "$WORKSPACE/lp"
if [[ -x "$ROOT_DIR/tools/lpunpack" ]]; then
  "$ROOT_DIR/tools/lpunpack" "$SUPER_RAW" "$WORKSPACE/lp"
else
  echo "⚠️  tools/lpunpack not present or not executable; cannot unpack super image."
  exit 1
fi

SYSTEM_IMG="$WORKSPACE/lp/system.img"
VENDOR_IMG="$WORKSPACE/lp/vendor.img"
PRODUCT_IMG="$WORKSPACE/lp/product.img"
ODM_IMG="$WORKSPACE/lp/odm.img"

echo "🧪 Extracting EROFS partitions to mnt/ (fsck.erofs --extract)..."
mkdir -p "$ROOT_DIR/mnt/system" "$ROOT_DIR/mnt/vendor" "$ROOT_DIR/mnt/product" "$ROOT_DIR/mnt/odm"

extract_erofs() {
  local img="$1"
  local outdir="$2"
  if [[ -f "$img" && -x "$ROOT_DIR/tools/fsck.erofs" ]]; then
    echo "📂 Extracting $(basename "$img") -> $outdir"
    "$ROOT_DIR/tools/fsck.erofs" --extract="$outdir" "$img"
  else
    echo "❌ Missing $(basename "$img") or tools/fsck.erofs; cannot extract."
    exit 1
  fi
}

extract_erofs "$SYSTEM_IMG" "$ROOT_DIR/mnt/system"
extract_erofs "$VENDOR_IMG" "$ROOT_DIR/mnt/vendor"
extract_erofs "$PRODUCT_IMG" "$ROOT_DIR/mnt/product"
extract_erofs "$ODM_IMG" "$ROOT_DIR/mnt/odm"

echo "✅ Firmware unpack stage completed."
