#!/usr/bin/env bash
set -e

echo "🚀 Starting Catalyst UI Build Process..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

chmod +x scripts/*.sh

sudo -v >/dev/null 2>&1 || true

./scripts/1_download_tools.sh
./scripts/2_unpack_firmware.sh
./scripts/3_debloat_and_deknox.sh
./scripts/4_catalyst_features.sh
./scripts/5_repack_catalyst.sh
