#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build
uv run --python 3.12 --with fonttools==4.68.0 --with reportlab==5.1.0 python tools/truetype_fixtures.py test-out/truetype
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/truetype_test.swift zig-out/lib/libpod_native.a -o .build/truetype-test
.build/truetype-test test-out/truetype
uv run --with pymupdf==1.26.5 --with pypdf==6.21.4 python tools/truetype_check.py test-out/truetype zig-out/bin/pod
