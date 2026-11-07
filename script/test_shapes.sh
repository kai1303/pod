#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/shapes
pdfbox=.tools/pdfbox-app-3.0.5.jar
if [[ ! -f "$pdfbox" ]]; then
  curl --fail --location --silent --show-error https://repo.maven.apache.org/maven2/org/apache/pdfbox/pdfbox-app/3.0.5/pdfbox-app-3.0.5.jar -o "$pdfbox.tmp"
  mv "$pdfbox.tmp" "$pdfbox"
fi
echo "d076467fd02214ebc7b5b9d5b3b9ac0891ef768168114ed8a4811b5d16606285  $pdfbox" | shasum -a 256 -c -
uv run --with pymupdf==1.26.5 python tools/shape_check.py test-out/shapes --fixtures
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/shape_test.swift zig-out/lib/libpod_native.a -o .build/shape-test
.build/shape-test test-out/shapes
uv run --with pymupdf==1.26.5 --with pypdf==6.21.4 --with numpy==1.26.4 python tools/shape_check.py test-out/shapes
