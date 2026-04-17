#!/usr/bin/env bash
set -e

echo "✨ Injecting Catalyst UI Premium Features..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

sedi() {
  local expr="$1"
  local file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file" || true
  else
    sed -i '' "$expr" "$file" || true
  fi
}

# 🚨 FIX: Updated path to system/system/etc to bypass the symlink trap
FLOATING="$ROOT_DIR/mnt/system/system/etc/floating_feature.xml"

if [[ ! -f "$FLOATING" ]]; then
  echo "⚠️  floating_feature.xml not found; creating a minimal placeholder."
  # 🚨 FIX: Ensure -p is used so it safely ignores existing directories
  mkdir -p "$(dirname "$FLOATING")"
  cat > "$FLOATING" <<'EOF'
<SecFloatingFeatureSet>
    <SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>FALSE</SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>
    <SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>FALSE</SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>
</SecFloatingFeatureSet>
EOF
fi

echo "🧬 Enabling flagship floating features..."
sedi 's#<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>FALSE#<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>TRUE#g' "$FLOATING"
sedi 's#<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>FALSE#<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>TRUE#g' "$FLOATING"

CSC1="$ROOT_DIR/mnt/odm/optics/configs/carriers/single/cscfeature.xml"
# 🚨 FIX: Updated system OMC path to system/system/omc
CSC2="$ROOT_DIR/mnt/system/system/omc/single/cscfeature.xml"
CSC3="$ROOT_DIR/mnt/product/omc/single/cscfeature.xml"

CSC="$CSC1"
if [[ -f "$CSC2" ]]; then CSC="$CSC2"; fi
if [[ -f "$CSC3" ]]; then CSC="$CSC3"; fi

if [[ ! -f "$CSC" ]]; then
  echo "⚠️  cscfeature.xml not found; creating a minimal placeholder at: $CSC"
  # 🚨 FIX: Ensure -p is used here too
  mkdir -p "$(dirname "$CSC")"
  cat > "$CSC" <<'EOF'
<FeatureSet>
</FeatureSet>
EOF
fi

echo "📲 Appending CSC premium features (call recording, camera toggles, 5G Force)..."
cat >> "$CSC" <<'EOF'

<CscFeature_VoiceCall_ConfigRecording>RecordingAllowed</CscFeature_VoiceCall_ConfigRecording>
<CscFeature_Camera_ShutterSoundMenu>TRUE</CscFeature_Camera_ShutterSoundMenu>
<CscFeature_Message_EnableSaveRestore>TRUE</CscFeature_Message_EnableSaveRestore>
<CscFeature_Setting_SupportReal5G>TRUE</CscFeature_Setting_SupportReal5G>
<CscFeature_RIL_ConfigNetworkMode>5G_ONLY</CscFeature_RIL_ConfigNetworkMode>
EOF

echo "✅ Catalyst feature injection completed."
