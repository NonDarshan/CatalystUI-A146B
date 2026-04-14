#!/usr/bin/env bash
set -e

echo "🧰 [1/5] Preparing workspace and tools..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p workspace tools out mnt/system mnt/vendor mnt/product mnt/odm

echo "📥 Downloading Linux x86 ROM Tools..."

# Install standard Ubuntu tools required for unpacking
sudo apt-get update -y
sudo apt-get install -y lz4 android-sdk-libsparse-utils simg2img xz-utils

# Download specialized Android unpacking binaries (lpunpack, mkfs.erofs, lpmake)
mkdir -p tools
wget -q "https://github.com/nabil2000/android-tools-linux/archive/refs/heads/main.zip" -O tools.zip
unzip -q tools.zip -d extracted_tools
mv extracted_tools/android-tools-linux-main/* tools/
chmod +x tools/*
rm -rf tools.zip extracted_tools

echo "✅ ROM Tools successfully installed."
