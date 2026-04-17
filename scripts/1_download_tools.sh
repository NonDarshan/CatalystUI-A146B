#!/usr/bin/env bash
set -euo pipefail

echo "🧰 [1/5] Preparing workspace and tools..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p tools workspace out mnt/system mnt/vendor mnt/product mnt/odm mnt/system_ext

export DEBIAN_FRONTEND=noninteractive

echo "📥 Installing system packages..."
sudo apt-get update -q
sudo apt-get install -y \
    lz4 \
    android-sdk-libsparse-utils \
    xz-utils \
    unzip \
    wget \
    curl \
    python3 \
    python3-pip \
    erofs-utils \
    zip \
    tar \
    xxd

# Symlink system tools so scripts can find them under tools/
which simg2img  >/dev/null 2>&1 && ln -sf "$(which simg2img)"  tools/simg2img  || true
which img2simg  >/dev/null 2>&1 && ln -sf "$(which img2simg)"  tools/img2simg  || true
which lz4       >/dev/null 2>&1 && ln -sf "$(which lz4)"       tools/lz4       || true
which mkfs.erofs>/dev/null 2>&1 && ln -sf "$(which mkfs.erofs)" tools/mkfs.erofs || true
which fsck.erofs>/dev/null 2>&1 && ln -sf "$(which fsck.erofs)" tools/fsck.erofs || true

echo "📥 Installing Python samloader (replaces slow cargo/samloader-rs)..."
python3 -m pip install --quiet --upgrade pip 2>/dev/null || true
python3 -m pip install --quiet git+https://github.com/nlscc/samloader.git

# Helper: download a binary and verify it is actually an ELF, not an HTML 404 page
download_binary() {
    local url="$1" dest="$2"
    local name; name="$(basename "$dest")"
    if wget -q --timeout=30 "$url" -O "$dest" 2>/dev/null; then
        if file "$dest" 2>/dev/null | grep -qE 'ELF|executable'; then
            chmod +x "$dest"
            echo "  ✅ $name"
            return 0
        fi
        rm -f "$dest"
    fi
    echo "  ⚠️  $name: download failed or returned non-binary (404?)"
    return 1
}

echo "📥 Downloading LP partition tools (lpmake, lpdump)..."
# Using a stable OtakuKitchen tools repository
TOOLS_REPO="https://github.com/1-100/OtakuKitchen/raw/main/tools/linux/x86"

download_binary "$TOOLS_REPO/lpmake"  tools/lpmake  || echo "  ❌ lpmake unavailable"
download_binary "$TOOLS_REPO/lpdump"  tools/lpdump  || echo "  ℹ️  lpdump unavailable"

echo "📥 Downloading Python lpunpack..."
wget -q "https://raw.githubusercontent.com/unix3dgforce/lpunpack/master/lpunpack.py" \
    -O tools/lpunpack.py && echo "  ✅ lpunpack.py" || echo "  ❌ lpunpack.py failed"

echo "📥 Downloading avbtool.py (for vbmeta patching — CRITICAL)..."
# Pulling the official Android Open Source Project avbtool directly from Google
wget -q --timeout=30 \
    "https://android.googlesource.com/platform/external/avb/+/refs/heads/master/avbtool.py?format=TEXT" \
    -O tools/avbtool_base64.txt
# Google Source serves text files as base64, so we decode it:
base64 -d tools/avbtool_base64.txt > tools/avbtool.py 2>/dev/null || true
rm -f tools/avbtool_base64.txt

if [[ -s tools/avbtool.py ]]; then
    echo "  ✅ avbtool.py"
else
    echo "  ❌ avbtool.py MISSING — modified ROM will NOT boot without vbmeta patching!"
fi

chmod +x tools/* 2>/dev/null || true

echo ""
echo "🔍 Tool status:"
for t in tools/lz4 tools/simg2img tools/mkfs.erofs tools/fsck.erofs \
          tools/lpmake tools/avbtool.py tools/lpunpack.py; do
    [[ -f "$t" ]] && echo "  ✅ $t" || echo "  ❌ $t MISSING"
done
echo "✅ Tool setup complete."
