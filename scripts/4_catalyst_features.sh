#!/usr/bin/env bash
set -e

echo "✨ [4/5] Injecting Catalyst UI Features..."
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

sedi() {
    local expr="$1" file="$2"
    [[ -f "$file" ]] || return 0
    if sed --version >/dev/null 2>&1; then sed -i "$expr" "$file" || true
    else sed -i '' "$expr" "$file" || true
    fi
}

# ── floating_feature.xml ─────────────────────────────────────────────
FLOATING="$ROOT_DIR/mnt/system/system/etc/floating_feature.xml"
if [[ ! -f "$FLOATING" ]]; then
    echo "⚠️  floating_feature.xml not found — creating placeholder"
    mkdir -p "$(dirname "$FLOATING")"
    cat > "$FLOATING" <<'EOF'
<SecFloatingFeatureSet>
    <SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>FALSE</SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>
    <SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>FALSE</SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>
</SecFloatingFeatureSet>
EOF
fi
echo "🧬 Enabling 3D backgrounds and edge lighting..."
sedi 's|<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>FALSE|<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>TRUE|g' "$FLOATING"
sedi 's|<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>false|<SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_BG>TRUE|g' "$FLOATING"
sedi 's|<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>FALSE|<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>TRUE|g' "$FLOATING"
sedi 's|<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>false|<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING>TRUE|g' "$FLOATING"

# ── cscfeature.xml ───────────────────────────────────────────────────
# BUG FIX: old code used `cat >>` which appended AFTER </FeatureSet>
# → invalid XML → CSC parser crash on boot. Now using Python to insert
# the new tags safely BEFORE the closing tag.
CSC=""
for candidate in \
    "$ROOT_DIR/mnt/odm/optics/configs/carriers/single/cscfeature.xml" \
    "$ROOT_DIR/mnt/system/system/omc/single/cscfeature.xml" \
    "$ROOT_DIR/mnt/product/omc/single/cscfeature.xml"; do
    [[ -f "$candidate" ]] && CSC="$candidate" && break
done

if [[ -z "$CSC" ]]; then
    CSC="$ROOT_DIR/mnt/product/omc/single/cscfeature.xml"
    echo "⚠️  cscfeature.xml not found — creating at: $CSC"
    mkdir -p "$(dirname "$CSC")"
    printf '<FeatureSet>\n</FeatureSet>\n' > "$CSC"
fi

echo "📲 Injecting CSC features into: $CSC"
python3 - "$CSC" <<'PYEOF'
import sys
filepath = sys.argv[1]
# ⚠️  NOTE: CscFeature_RIL_ConfigNetworkMode=5G_ONLY was removed from the
# original script — forcing 5G-only mode breaks voice calls and data on
# non-5G bands. Do not add it back.
new_features = """\
  <CscFeature_VoiceCall_ConfigRecording>RecordingAllowed</CscFeature_VoiceCall_ConfigRecording>
  <CscFeature_Setting_SupportReal5G>TRUE</CscFeature_Setting_SupportReal5G>
  <CscFeature_Setting_SupportRealTimeNetworkSpeed>TRUE</CscFeature_Setting_SupportRealTimeNetworkSpeed>
  <CscFeature_Camera_ShutterSoundMenu>TRUE</CscFeature_Camera_ShutterSoundMenu>
  <CscFeature_Audio_ConfigActionEnableHearingDamage>FALSE</CscFeature_Audio_ConfigActionEnableHearingDamage>
  <CscFeature_Message_EnableSaveRestore>TRUE</CscFeature_Message_EnableSaveRestore>
  <CscFeature_AppLock_ConfigAppLock>TRUE</CscFeature_AppLock_ConfigAppLock>
  <CscFeature_SmartManager_ConfigDashboard>applock</CscFeature_SmartManager_ConfigDashboard>
"""
marker = '<!-- catalyst-injected -->'
with open(filepath, 'r', errors='replace') as f:
    content = f.read()
if marker in content:
    print(f"  ✅ Already patched, skipping: {filepath}")
    sys.exit(0)
closing = '</FeatureSet>'
if closing not in content:
    print(f"  ⚠️  No </FeatureSet> found in {filepath} — cannot inject safely")
    sys.exit(0)
content = content.replace(closing, new_features + marker + '\n' + closing, 1)
with open(filepath, 'w') as f:
    f.write(content)
print(f"  ✅ Features injected into {filepath}")
PYEOF

# ── build.prop tweaks ────────────────────────────────────────────────
BUILDPROP="$ROOT_DIR/mnt/system/system/build.prop"
if [[ -f "$BUILDPROP" ]]; then
    echo "🔧 Patching build.prop..."
    if ! grep -q "ro.catalyst.build" "$BUILDPROP"; then
        printf '\n# CatalystUI\nro.catalyst.build=1\n' >> "$BUILDPROP"
    fi
    # Add your custom build.prop changes below, e.g.:
    # sedi 's|^ro.product.model=.*|ro.product.model=CatalystUI A14|' "$BUILDPROP"
fi

echo "✅ Feature injection complete."
