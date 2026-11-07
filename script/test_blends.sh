#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/blends
uv run --python 3.12 --with fonttools==4.68.0 --with reportlab==5.1.0 python tools/blend_check.py test-out/blends --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/blend_test.swift zig-out/lib/libpod_native.a -o .build/blend-test
.build/blend-test test-out/blends
uv run --with pymupdf==1.26.5 --with numpy==1.26.4 python tools/blend_check.py test-out/blends
