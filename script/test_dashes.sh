#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --built ]]; then "${POD_ZIG:-.tools/zig-aarch64-macos-0.17.1/zig}" build; fi
mkdir -p .build test-out/dashes
pdfbox=.tools/pdfbox-app-3.0.5.jar
if [[ ! -f "$pdfbox" ]]; then
  curl --fail --location --silent --show-error https://repo.maven.apache.org/maven2/org/apache/pdfbox/pdfbox-app/3.0.5/pdfbox-app-3.0.5.jar -o "$pdfbox.tmp"
  mv "$pdfbox.tmp" "$pdfbox"
fi
echo "d076467fd02214ebc7b5b9d5b3b9ac0891ef768168114ed8a4811b5d16606285  $pdfbox" | shasum -a 256 -c -
uv run --python 3.12 --with reportlab==5.1.0 python tools/dash_fixtures.py test-out/dashes
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/form_test.swift zig-out/lib/libpod_native.a -o .build/dash-test
.build/dash-test test-out/dashes
uv run --with pymupdf==1.26.5 --with numpy==1.26.4 --with pypdf==6.21.4 python tools/form_check.py test-out/dashes
