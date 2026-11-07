#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/jpeg
uv run --with pillow==11.3.0 python tools/jpeg_check.py test-out/jpeg --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/codec_image_test.swift zig-out/lib/libpod_native.a -o .build/jpeg-test
.build/jpeg-test test-out/jpeg
uv run --with pillow==11.3.0 --with pymupdf==1.26.5 --with numpy==2.0.2 python tools/jpeg_check.py test-out/jpeg
