#!/usr/bin/env bash
set -e

# Get the absolute path of where this script is located
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "🚀 Starting Catalyst UI Build Process..."

# Force permissions again just to be safe
chmod -R +x scripts/

echo "🧰 [1/5] Installing Tools..."
./scripts/1_download_tools.sh

echo "📡 [2/5] Fetching and Unpacking Firmware..."
./scripts/2_unpack_firmware.sh

echo "🧹 [3/5] Debloating and De-Knox..."
./scripts/3_debloat_and_deknox.sh

echo "✨ [4/5] Injecting Catalyst Optimizations..."
./scripts/4_catalyst_features.sh

echo "🏗️ [5/5] Repacking Catalyst UI..."
./scripts/5_repack_catalyst.sh

echo "🎉 Catalyst UI Build Complete!"
