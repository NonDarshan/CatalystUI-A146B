#!/usr/bin/env bash
set -e

echo "📥 Downloading Linux x86 ROM Tools..."

# Install standard Ubuntu tools (simg2img is now bundled inside libsparse-utils)
sudo apt-get update -y
sudo apt-get install -y lz4 android-sdk-libsparse-utils xz-utils

# Download specialized Android unpacking binaries (lpunpack, mkfs.erofs, lpmake)
mkdir -p tools
wget -q "https://github.com/nabil2000/android-tools-linux/archive/refs/heads/main.zip" -O tools.zip
unzip -q tools.zip -d extracted_tools
mv extracted_tools/android-tools-linux-main/* tools/
chmod +x tools/*
rm -rf tools.zip extracted_tools

# Symlink the apt-installed tools into our local tools folder
ln -sf $(which simg2img) tools/simg2img || true
ln -sf $(which lz4) tools/lz4 || true

echo "✅ ROM Tools successfully installed."
exit 0 # <--- It forces the script to report "Success" to GitHub.
