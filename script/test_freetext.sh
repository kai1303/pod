#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/freetext
uv run --with pymupdf==1.26.5 python tools/freetext_check.py test-out/freetext --fixtures
uv run --with pypdf==6.21.4 --with fonttools==4.60.1 python tools/freetext_font_fixtures.py test-out/freetext
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/freetext_test.swift zig-out/lib/libpod_native.a -o .build/freetext-test
.build/freetext-test test-out/freetext --fixtures
uv run --with pymupdf==1.26.5 --with pypdf==6.21.4 python tools/freetext_check.py test-out/freetext --normalize-pdfkit
.build/freetext-test test-out/freetext
uv run --python 3.12 --with pymupdf==1.26.5 --with pypdf==6.21.4 --with numpy==1.26.4 --with pillow==11.3.0 --with fonttools==4.60.1 --with reportlab==5.1.0 python tools/freetext_check.py test-out/freetext
