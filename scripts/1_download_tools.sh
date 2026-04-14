#!/usr/bin/env bash
echo "🧰 [1/5] Preparing workspace and tools..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p tools workspace out mnt/system mnt/vendor mnt/product mnt/odm

export DEBIAN_FRONTEND=noninteractive

echo "📥 Installing System Tools..."
sudo apt-get update -y
sudo apt-get install -y lz4 android-sdk-libsparse-utils xz-utils unzip wget curl || true

echo "📥 Downloading specialized Android binaries..."
# Using a different, more reliable source for lpunpack/lpmake
wget -q "https://github.com/haggertk/binaries/raw/master/linux-x86_64/bin/lpunpack" -O tools/lpunpack
wget -q "https://github.com/haggertk/binaries/raw/master/linux-x86_64/bin/lpmake" -O tools/lpmake
wget -q "https://github.com/haggertk/binaries/raw/master/linux-x86_64/bin/simg2img" -O tools/simg2img

# Install erofs-utils directly via apt (it's much safer on Ubuntu 24.04)
sudo apt-get install -y erofs-utils || true
ln -sf $(which mkfs.erofs) tools/mkfs.erofs || true
ln -sf $(which fsck.erofs) tools/fsck.erofs || true
ln -sf $(which lz4) tools/lz4 || true

chmod +x tools/*
echo "✅ ROM Tools successfully installed."
exit 0
