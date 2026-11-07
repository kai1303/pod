#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/forms
uv run --python 3.12 --with reportlab==5.1.0 --with fonttools==4.68.0 python tools/form_check.py test-out/forms --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/form_test.swift zig-out/lib/libpod_native.a -o .build/form-test
.build/form-test test-out/forms
uv run --with pymupdf==1.26.5 --with numpy==1.26.4 --with pypdf==6.21.4 python tools/form_check.py test-out/forms
