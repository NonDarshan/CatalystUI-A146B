#!/usr/bin/env bash
set -euo pipefail

echo "🧰 [1/5] Preparing workspace and tools..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p tools workspace out mnt/system mnt/vendor mnt/product mnt/odm mnt/system_ext

export DEBIAN_FRONTEND=noninteractive

echo "📥 Installing system packages..."
sudo apt-get update -q
sudo apt-get install -y lz4 android-sdk-libsparse-utils xz-utils unzip wget curl python3 python3-pip erofs-utils zip tar xxd

echo "📥 Compiling Rust samloader (TopJohnWu's maintained version)..."
# We are returning to the Rust version! It is 100% immune to Samsung FOTA blocks.
cargo install samloader

echo "📥 Downloading LP partition tools (lpmake, lpdump)..."

# Mirror 1 (Primary): OtakuKitchen repo
wget -q "https://raw.githubusercontent.com/1-100/OtakuKitchen/main/tools/linux/x86/lpmake" -O tools/lpmake || \
# Mirror 2 (Fallback): LonelyFool static builds
wget -q "https://raw.githubusercontent.com/LonelyFool/lpmake_static/main/lpmake" -O tools/lpmake || \
echo "❌ lpmake failed on all mirrors"

wget -q "https://raw.githubusercontent.com/1-100/OtakuKitchen/main/tools/linux/x86/lpdump" -O tools/lpdump || true

echo "📥 Downloading Python lpunpack..."
wget -q "https://raw.githubusercontent.com/unix3dgforce/lpunpack/master/lpunpack.py" -O tools/lpunpack.py || echo "  ❌ lpunpack.py failed"

echo "📥 Downloading avbtool.py (for vbmeta patching — CRITICAL)..."
wget -q "https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-21.0/avbtool.py" -O tools/avbtool.py || echo "  ❌ avbtool.py failed"

chmod +x tools/* 2>/dev/null || true

echo "✅ Tool setup complete."
