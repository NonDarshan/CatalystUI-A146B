#!/usr/bin/env bash
set -e

echo "🧹 [3/5] Debloating and neutralizing Knox..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEBLOAT_LIST="$ROOT_DIR/lists/debloat.txt"

SYSTEM_APP="$ROOT_DIR/mnt/system/app"
SYSTEM_PRIV="$ROOT_DIR/mnt/system/priv-app"
PRODUCT_APP="$ROOT_DIR/mnt/product/app"
PRODUCT_PRIV="$ROOT_DIR/mnt/product/priv-app"

mkdir -p "$SYSTEM_APP" "$SYSTEM_PRIV" "$PRODUCT_APP" "$PRODUCT_PRIV"

rmrf() {
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo rm -rf "$@" || true
  else
    rm -rf "$@" || true
  fi
}

echo "📄 Reading debloat list: $DEBLOAT_LIST"
if [[ -f "$DEBLOAT_LIST" ]]; then
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    pkg="$(echo "$pkg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$pkg" ]] && continue
    [[ "$pkg" =~ ^# ]] && continue

    echo "🗑️  Removing: $pkg"
    rmrf "$SYSTEM_APP/$pkg" "$SYSTEM_PRIV/$pkg" "$PRODUCT_APP/$pkg" "$PRODUCT_PRIV/$pkg"
  done < "$DEBLOAT_LIST"
else
  echo "⚠️  debloat.txt not found; skipping debloat stage."
fi

echo "🛡️  Removing Knox components..."
rmrf \
  "$ROOT_DIR/mnt/system/priv-app/KnoxCore" \
  "$ROOT_DIR/mnt/system/priv-app/KnoxGuard" \
  "$ROOT_DIR/mnt/system/priv-app/KLMSAgent" \
  "$ROOT_DIR/mnt/system/priv-app/KnoxAnalyticsAgent" \
  "$ROOT_DIR/mnt/system/priv-app/KnoxPushManager" \
  "$ROOT_DIR/mnt/system/priv-app/RLC" \
  "$ROOT_DIR/mnt/system/app/KnoxAttestationAgent" \
  "$ROOT_DIR/mnt/system/app/KnoxStub" \
  "$ROOT_DIR/mnt/system/framework/knoxsdk.jar" \
  "$ROOT_DIR/mnt/system/framework/knoxsdk2.jar" \
  "$ROOT_DIR/mnt/system/framework/knoxsdk3.jar" \
  "$ROOT_DIR/mnt/system/framework/knoxvpnproxyhandler.jar" \
  "$ROOT_DIR/mnt/system/etc/knoxguard" \
  "$ROOT_DIR/mnt/system/etc/knox" \
  || true

echo "🛡️ Catalyst UI: Samsung Knox has been neutralized."
