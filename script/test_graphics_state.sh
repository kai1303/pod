#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/graphics-state
uv run --python 3.12 --with fonttools==4.68.0 python tools/graphics_state_check.py test-out/graphics-state --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/graphics_state_test.swift zig-out/lib/libpod_native.a -o .build/graphics-state-test
.build/graphics-state-test test-out/graphics-state
uv run --with pymupdf==1.26.5 --with numpy==1.26.4 python tools/graphics_state_check.py test-out/graphics-state
