#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/inline-images
uv run --python 3.12 --with reportlab==5.1.0 --with pillow==11.3.0 python tools/inline_image_fixtures.py test-out/inline-images
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/image_test.swift zig-out/lib/libpod_native.a -o .build/inline-image-test
.build/inline-image-test test-out/inline-images
uv run --with pymupdf==1.26.5 --with pillow==11.3.0 --with numpy==2.0.2 python tools/image_check.py test-out/inline-images
