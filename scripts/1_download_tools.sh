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
LINEAGE="https://github.com/LineageOS/android_prebuilts_tools-lineage/raw/master/linux-x86/bin"
LINEAGE_21="https://github.com/LineageOS/android_prebuilts_tools-lineage/raw/lineage-21/linux-x86/bin"

download_binary "$LINEAGE/lpmake"  tools/lpmake  || \
download_binary "$LINEAGE_21/lpmake" tools/lpmake || \
echo "  ❌ lpmake unavailable — will skip super.img build"

download_binary "$LINEAGE/lpdump"  tools/lpdump  || \
download_binary "$LINEAGE_21/lpdump" tools/lpdump || \
echo "  ℹ️  lpdump unavailable — super size will be read from raw image stat"

echo "📥 Downloading Python lpunpack..."
wget -q "https://raw.githubusercontent.com/unix3dgforce/lpunpack/master/lpunpack.py" \
    -O tools/lpunpack.py && echo "  ✅ lpunpack.py" || echo "  ❌ lpunpack.py failed"

echo "📥 Downloading avbtool.py (for vbmeta patching — CRITICAL)..."
wget -q --timeout=30 \
    "https://raw.githubusercontent.com/LineageOS/android_external_avb/lineage-21/avbtool.py" \
    -O tools/avbtool.py \
  && echo "  ✅ avbtool.py" \
  || echo "  ❌ avbtool.py MISSING — modified ROM will NOT boot without vbmeta patching!"

chmod +x tools/* 2>/dev/null || true

echo ""
echo "🔍 Tool status:"
for t in tools/lz4 tools/simg2img tools/mkfs.erofs tools/fsck.erofs \
          tools/lpmake tools/avbtool.py tools/lpunpack.py; do
    [[ -f "$t" ]] && echo "  ✅ $t" || echo "  ❌ $t MISSING"
done
echo "✅ Tool setup complete."
