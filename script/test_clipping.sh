#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/clipping
python3 tools/clipping_check.py test-out/clipping --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/clipping_test.swift zig-out/lib/libpod_native.a -o .build/clipping-test
.build/clipping-test test-out/clipping
uv run --with pymupdf==1.26.5 --with numpy==1.26.4 python tools/clipping_check.py test-out/clipping
