#!/usr/bin/env bash
set -e

echo "🧹 [3/5] Debloating and De-Knox..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEBLOAT_LIST="$ROOT_DIR/lists/debloat.txt"

# The Master Search Paths! (Accounting for System-as-Root on A14)
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

if [[ -f "$DEBLOAT_LIST" ]]; then
  echo "📄 Reading debloat list: $DEBLOAT_LIST"
  while IFS= read -r app_name; do
    # Skip empty lines and comments in your txt file
    [[ -z "$app_name" || "$app_name" == \#* ]] && continue

    for base_path in "${SEARCH_PATHS[@]}"; do
      if [[ -d "$base_path/$app_name" ]]; then
        rm -rf "$base_path/$app_name"
        echo "   🗑️ NUKED: $app_name (from $(basename $(dirname "$base_path"))/$(basename "$base_path"))"
      fi
    done
  done < "$DEBLOAT_LIST"
else
  echo "⚠️  No debloat.txt found at $DEBLOAT_LIST. Skipping standard debloat."
fi

echo "🛡️  Neutralizing Samsung Knox..."
# Hardcoded list of notorious Knox agents
KNOX_APPS=(
  "KnoxCore"
  "KnoxAttestationAgent"
  "KLMSAgent"
  "KnoxGuard"
  "ContainerAgent"
  "KnoxVpnServices"
  "BBKAgent"
  "KnoxSetupWizardClient"
)

for knox_app in "${KNOX_APPS[@]}"; do
  for base_path in "${SEARCH_PATHS[@]}"; do
    if [[ -d "$base_path/$knox_app" ]]; then
      rm -rf "$base_path/$knox_app"
      echo "   ☠️ DESTROYED: $knox_app"
    fi
  done
done

echo "✅ Catalyst UI: Samsung Knox has been neutralized."
