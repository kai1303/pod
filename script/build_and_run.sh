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
swiftc -swift-version 5 -Osize -whole-module-optimization -target arm64-apple-macos14.0 -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MarkupPalette.swift macos/Engine.swift macos/PageCanvas.swift macos/PodApp.swift zig-out/lib/libpod_native.a -framework AppKit -framework UniformTypeIdentifiers -o "$APP_BUNDLE/Contents/MacOS/Pod"
strip -x "$APP_BUNDLE/Contents/MacOS/Pod"
python3 script/make_demo.py "$APP_BUNDLE/Contents/Resources/Welcome to Pod.pdf"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Pod</string>
<key>CFBundleIdentifier</key><string>dev.pod.pdf</string>
<key>CFBundleName</key><string>Pod</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
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
