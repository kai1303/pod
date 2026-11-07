#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build test-out/comments
python3 script/make_demo.py test-out/comments/sample.pdf
uv run --with pymupdf==1.26.5 python tools/comment_check.py test-out/comments --fixtures
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift \
  macos/comment_test.swift zig-out/lib/libpod_native.a -o .build/comment-test
.build/comment-test test-out/comments
"${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build-exe -lc --dep pod -Mroot=tools/comment_roundtrip.zig -Mpod=src/pod.zig -femit-bin=.build/comment-roundtrip
.build/comment-roundtrip test-out/comments
.build/comment-test test-out/comments --verify-imports
uv run --with pymupdf==1.26.5 python tools/comment_check.py test-out/comments

uv run --with pymupdf==1.26.5 python tools/comment_view_check.py test-out/comments --fixtures
.build/comment-test test-out/comments --page-view
uv run --with pymupdf==1.26.5 python tools/comment_view_check.py test-out/comments
