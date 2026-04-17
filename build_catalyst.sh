#!/usr/bin/env bash
set -e

export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "🚀 Starting Catalyst UI Build Process..."
chmod -R +x scripts/

run_step() {
    local num="$1" label="$2" script="$3"
    echo ""
    echo "══════════════════════════════════════════"
    echo "  STEP $num: $label"
    echo "══════════════════════════════════════════"
    if ! "$script"; then
        echo ""
        echo "❌ Build FAILED at step $num: $label"
        exit 1
    fi
}

run_step 1 "Installing Tools"              ./scripts/1_download_tools.sh
run_step 2 "Fetching and Unpacking Firmware" ./scripts/2_unpack_firmware.sh
run_step 3 "Debloating and De-Knox"        ./scripts/3_debloat_and_deknox.sh
run_step 4 "Injecting Catalyst Features"  ./scripts/4_catalyst_features.sh
run_step 5 "Repacking Catalyst UI"        ./scripts/5_repack_catalyst.sh

echo ""
echo "🎉 Catalyst UI Build Complete!"
echo "   Output: out/AP_CatalystUI_A146B.tar.md5"
echo "   Flash : Odin3 → AP slot → Start"
