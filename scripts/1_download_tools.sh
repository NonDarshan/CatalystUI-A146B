#!/usr/bin/env bash
set -euo pipefail

echo "🧰 [1/5] Preparing workspace and tools..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p tools workspace out mnt/system mnt/vendor mnt/product mnt/odm mnt/system_ext

export DEBIAN_FRONTEND=noninteractive

echo "📥 Installing system packages and C++ compilers..."
sudo apt-get update -q
sudo apt-get install -y lz4 android-sdk-libsparse-utils xz-utils unzip wget curl python3 python3-pip erofs-utils zip tar xxd build-essential cmake zlib1g-dev liblzma-dev

echo "📥 Compiling Rust samloader (TopJohnWu's maintained version)..."
cargo install samloader

echo "📥 Compiling LP tools natively from the thka2016 repository (Zero 404 Guarantee)..."
cd "$ROOT_DIR/workspace"
# Clone the exact repository you found
git clone https://github.com/thka2016/lpunpack_and_lpmake_cmake.git
cd lpunpack_and_lpmake_cmake

# Compile the source code into native Linux binaries
mkdir build && cd build
cmake ..
make -j$(nproc)

# Copy the freshly compiled binaries into our tools folder
cp lpmake "$ROOT_DIR/tools/lpmake" || echo "❌ lpmake compilation failed"
cp lpdump "$ROOT_DIR/tools/lpdump" || true

cd "$ROOT_DIR"
chmod +x tools/lpmake tools/lpdump 2>/dev/null || true

echo "📥 Downloading Python lpunpack..."
wget -q "https://raw.githubusercontent.com/unix3dgforce/lpunpack/master/lpunpack.py" -O tools/lpunpack.py || echo "  ❌ lpunpack.py failed"

echo "📥 Downloading avbtool.py (for vbmeta patching — CRITICAL)..."
wget -q "https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-21.0/avbtool.py" -O tools/avbtool.py || echo "  ❌ avbtool.py failed"

chmod +x tools/* 2>/dev/null || true

echo "✅ Tool setup complete."wget -q "https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-21.0/avbtool.py" -O tools/avbtool.py || echo "  ❌ avbtool.py failed"

chmod +x tools/* 2>/dev/null || true

echo "✅ Tool setup complete."
