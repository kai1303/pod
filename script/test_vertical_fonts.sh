#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build
uv run --python 3.12 --with fonttools==4.68.0 python tools/vertical_font_fixtures.py test-out/vertical-fonts
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/truetype_test.swift zig-out/lib/libpod_native.a -o .build/vertical-font-test
.build/vertical-font-test test-out/vertical-fonts
uv run --with pymupdf==1.26.5 python tools/vertical_font_check.py test-out/vertical-fonts zig-out/bin/pod
