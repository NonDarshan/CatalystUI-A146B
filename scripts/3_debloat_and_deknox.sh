#!/usr/bin/env bash
set -e

echo "🧹 [3/5] Debloating and De-Knox..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEBLOAT_LIST="$ROOT_DIR/lists/debloat.txt"
SEARCH_PATHS=(
    "$ROOT_DIR/mnt/system/system/app"
    "$ROOT_DIR/mnt/system/system/priv-app"
    "$ROOT_DIR/mnt/system/app"
    "$ROOT_DIR/mnt/system/priv-app"
    "$ROOT_DIR/mnt/product/app"
    "$ROOT_DIR/mnt/product/priv-app"
    "$ROOT_DIR/mnt/vendor/app"
    "$ROOT_DIR/mnt/vendor/priv-app"
    "$ROOT_DIR/mnt/system_ext/app"
    "$ROOT_DIR/mnt/system_ext/priv-app"
)

# ── User debloat list ────────────────────────────────────────────────
if [[ -f "$DEBLOAT_LIST" ]]; then
    echo "📄 Applying debloat list from: $DEBLOAT_LIST"
    while IFS= read -r app_name; do
        [[ -z "$app_name" || "$app_name" == \#* ]] && continue
        for base in "${SEARCH_PATHS[@]}"; do
            if [[ -d "$base/$app_name" ]]; then
                rm -rf "$base/$app_name"
                echo "   🗑️  REMOVED: $app_name"
            fi
        done
    done < "$DEBLOAT_LIST"
else
    echo "⚠️  debloat.txt not found — skipping user debloat."
fi

# ── Safe Knox removal ────────────────────────────────────────────────
# ⚠️  IMPORTANT: Do NOT remove KnoxCore, ContainerAgent, or BBCAgent.
#     These are referenced by Samsung's init.rc. Removing them causes a
#     silent bootloop before logcat ever starts.
#     Only the USER-FACING Knox apps below are safe to remove.
echo ""
echo "🛡️  Removing safe-to-remove Knox apps..."
SAFE_KNOX=(
    "KnoxAttestationAgent"     # License attestation — user-facing
    "KLMSAgent"                # Knox License Management — user-facing
    "KnoxVpnServices"          # Knox VPN addon
    "KnoxSetupWizardClient"    # Knox enrollment wizard
    "KnoxGuard"                # Remote lock/wipe (user-facing only)
    "SamsungPassIntelligence"  # Samsung Pass AI helper
    "SecureFolder"             # Secure Folder container app
)

for app in "${SAFE_KNOX[@]}"; do
    for base in "${SEARCH_PATHS[@]}"; do
        if [[ -d "$base/$app" ]]; then
            rm -rf "$base/$app"
            echo "   ☠️  REMOVED: $app"
        fi
    done
done

echo "✅ Debloat and De-Knox complete."
