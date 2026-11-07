#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/fax
uv run --with pillow==11.3.0 python tools/fax_check.py test-out/fax --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/codec_image_test.swift zig-out/lib/libpod_native.a -o .build/fax-test
.build/fax-test test-out/fax
uv run --with pillow==11.3.0 --with pymupdf==1.26.5 python tools/fax_check.py test-out/fax
