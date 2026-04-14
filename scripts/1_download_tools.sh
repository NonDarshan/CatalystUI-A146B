#!/usr/bin/env bash
# We remove set -e for the tool installation phase to prevent 
# Ubuntu's "needrestart" from killing the build.

echo "🧰 [1/5] Preparing workspace and tools..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Suppress interactive prompts from apt
export DEBIAN_FRONTEND=noninteractive

echo "📥 Downloading Linux x86 ROM Tools..."

# Install tools and ignore the exit code of the apt command specifically
sudo apt-get update -y
sudo apt-get install -y lz4 android-sdk-libsparse-utils xz-utils unzip wget || true

# Download specialized Android unpacking binaries
mkdir -p tools
wget -q "https://github.com/nabil2000/android-tools-linux/archive/refs/heads/main.zip" -O tools.zip
unzip -q tools.zip -d extracted_tools
mv extracted_tools/android-tools-linux-main/* tools/
chmod +x tools/*
rm -rf tools.zip extracted_tools

# Symlink the apt-installed tools
ln -sf $(which simg2img) tools/simg2img || true
ln -sf $(which lz4) tools/lz4 || true

echo "✅ ROM Tools successfully installed."
exit 0
