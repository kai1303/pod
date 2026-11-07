#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/captions
python3 tools/caption_check.py test-out/captions --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/caption_test.swift zig-out/lib/libpod_native.a -o .build/caption-test
.build/caption-test test-out/captions
uv run --python 3.12 --with pymupdf==1.26.5 --with pypdf==6.21.4 --with numpy==1.26.4 --with pillow==11.3.0 --with fonttools==4.60.1 --with reportlab==5.1.0 python tools/caption_check.py test-out/captions
