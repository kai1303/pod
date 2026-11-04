#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./script/build_and_run.sh --build
ZIG="${POD_ZIG:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.tools/zig-aarch64-macos-0.17.1/zig}"
"$ZIG" build test
mkdir -p test-out
python3 script/make_demo.py test-out/sample.pdf
clang -O2 macos/bridge_test.c zig-out/lib/libpod_native.a -o test-out/bridge_test
test-out/bridge_test test-out/sample.pdf '/System/Library/Fonts/Supplemental/Courier New.ttf'
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/Engine.swift macos/engine_test.swift zig-out/lib/libpod_native.a -o test-out/engine_test
test-out/engine_test test-out/sample.pdf test-out/edited.pdf
swift tools/pdfkit_check.swift test-out/edited.pdf test-out/independent.png > test-out/independent.json
python3 -c 'import json; d=json.load(open("test-out/independent.json")); assert d["pages"]==2 and "Hello Pod" in d["text"]; print("Independent PDFKit verification passed")'
swift tools/annotation_check.swift test-out/annotations.pdf test-out/annotations-independent.png
