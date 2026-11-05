#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "${1:-}" != --built ]]; then ./script/build_and_run.sh --build; fi
mkdir -p .build
swiftc -swift-version 5 macos/ReactEditor.swift macos/react_editor_test.swift -framework AppKit -framework WebKit -o .build/react-editor-test
.build/react-editor-test "$ROOT_DIR/web/dist"
TEST_APP="$ROOT_DIR/.build/PodReactUITest.app"
if [[ -d "$TEST_APP" ]]; then rm -rf "$TEST_APP"; fi
ditto dist/Pod.app "$TEST_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.pod.pdf.react-ui-test' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Pod UI Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP" 2>/dev/null
POD_REACT_SMOKE=1 "$TEST_APP/Contents/MacOS/Pod"
