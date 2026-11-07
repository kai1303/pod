#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build
python3 tools/unicode_fixtures.py test-out/unicode zig-out/bin/pod
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/unicode_test.swift zig-out/lib/libpod_native.a -o .build/unicode-test
.build/unicode-test test-out/unicode
# An independent reader is required for inherited UseCMap, which PDFKit does not resolve.
uv run --with pymupdf==1.26.5 python tools/unicode_check.py test-out/unicode
