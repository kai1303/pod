#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/calibrated-colors
uv run --with pymupdf==1.26.5 python tools/calibrated_color_check.py test-out/calibrated-colors --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/color_test.swift zig-out/lib/libpod_native.a -o .build/calibrated-color-test
.build/calibrated-color-test test-out/calibrated-colors
uv run --with pymupdf==1.26.5 python tools/calibrated_color_check.py test-out/calibrated-colors
