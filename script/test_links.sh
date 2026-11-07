#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then
  "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build
fi
mkdir -p .build
python3 tools/link_fixtures.py test-out/links
swiftc -swift-version 5 -g -import-objc-header macos/PodBridge.h \
  macos/Markup.swift macos/LuminAssets.swift macos/LuminPopper.swift macos/DesignSystem.swift \
  macos/LuminViewControls.swift macos/LuminCanvasStyle.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/DrawingModel.swift \
  macos/MetalPageView.swift macos/ReadingTools.swift macos/PageCanvas.swift macos/link_test.swift \
  zig-out/lib/libpod_native.a -o .build/link-test
.build/link-test test-out/links
