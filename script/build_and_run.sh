#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--build|--debug|--logs|--telemetry) ;; *) echo 'Usage: script/build_and_run.sh [--build|--verify|--debug|--logs|--telemetry]' >&2; exit 2;; esac
COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
ZIG="${POD_ZIG:-$(dirname "$COMMON_DIR")/.tools/zig-aarch64-macos-0.17.1/zig}"
if [[ ! -x "$ZIG" ]]; then ZIG="$(command -v zig)"; fi
"$ZIG" build -Doptimize=safe -Dtarget=aarch64-macos.14.0
APP_BUNDLE="$ROOT_DIR/dist/Pod.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp assets/font-metrics/NOTICE "$APP_BUNDLE/Contents/Resources/FontMetricsNotices.txt"
swiftc -swift-version 5 -Osize -whole-module-optimization -target arm64-apple-macos14.0 -import-objc-header macos/PodBridge.h macos/LuminAssets.swift macos/LuminControls.swift macos/LuminColorPicker.swift macos/LuminPopper.swift macos/LuminMenuPreviews.swift macos/LuminSignatureDialog.swift macos/LuminPremiumGate.swift macos/LuminPasswordMenu.swift macos/LuminFormBuilder.swift macos/DesignSystem.swift macos/DesignSystemGallery.swift macos/LuminTypeToolbar.swift macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift macos/LuminViewControls.swift macos/LuminMainToolbar.swift macos/LuminToolbarMenus.swift macos/LuminUtilityRail.swift macos/LuminFooterDock.swift macos/LuminNavigation.swift macos/LuminDocumentHeader.swift macos/LuminHeaderMenus.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminShareMenus.swift macos/LuminShareDialog.swift macos/LuminModeRail.swift macos/LuminModeMenu.swift macos/LuminCanvasStyle.swift macos/ViewerChrome.swift macos/Markup.swift macos/MarkupPalette.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/DrawingModel.swift macos/DirectPeer.swift macos/DrawingSession.swift macos/DrawingNetworkAddress.swift macos/MetalPageView.swift macos/ReadingTools.swift macos/PageCanvas.swift macos/ReactEditor.swift macos/NavigationPreviews.swift macos/PodApp.swift zig-out/lib/libpod_native.a -framework AppKit -framework WebKit -framework JavaScriptCore -framework UniformTypeIdentifiers -framework Network -framework Security -framework CryptoKit -o "$APP_BUNDLE/Contents/MacOS/Pod"
strip -x "$APP_BUNDLE/Contents/MacOS/Pod"
python3 script/make_demo.py "$APP_BUNDLE/Contents/Resources/Welcome to Pod.pdf"
cp -R macos/Resources/Lumin "$APP_BUNDLE/Contents/Resources/"
cp macos/Resources/Pod.icns "$APP_BUNDLE/Contents/Resources/Pod.icns"
if [[ ! -d web/node_modules ]]; then npm --prefix web ci; fi
npm --prefix web run build
rm -rf "$APP_BUNDLE/Contents/Resources/Web"
cp -R web/dist "$APP_BUNDLE/Contents/Resources/Web"
cp research/lumin/toolbar-catalog.json "$APP_BUNDLE/Contents/Resources/ViewerToolbarCatalog.json"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Pod</string>
<key>CFBundleIdentifier</key><string>dev.pod.pdf</string>
<key>CFBundleName</key><string>Pod</string>
<key>CFBundleIconFile</key><string>Pod.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Connect directly to another Mac to share a PDF and draw together.</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>dev.pod.drawing</string><key>CFBundleURLSchemes</key><array><string>pod</string></array><key>CFBundleTypeRole</key><string>Editor</string></dict></array>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>PDF document</string><key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Alternate</string></dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null
if [[ "$MODE" == --build ]]; then echo "$APP_BUNDLE"; exit 0; fi
# Preserve edits in an already-open preview; build-only is always available.
if pgrep -x Pod >/dev/null; then
  echo 'Updated build is ready. Quit Pod after saving your edits, then run this script again.' >&2
  exit 1
fi
case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/Pod";;
  *) /usr/bin/open -n "$APP_BUNDLE";;
esac
case "$MODE" in
  --verify) sleep 1; pgrep -x Pod;;
  --logs) /usr/bin/log stream --info --style compact --predicate 'process == "Pod"';;
  --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.pod.pdf"';;
esac
