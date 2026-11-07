#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/comment-popups
uv run --with pymupdf==1.26.5 python tools/comment_popup_check.py test-out/comment-popups --fixtures
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/comment_popup_test.swift zig-out/lib/libpod_native.a -o .build/comment-popup-test
.build/comment-popup-test test-out/comment-popups
uv run --with pymupdf==1.26.5 python tools/comment_popup_check.py test-out/comment-popups
