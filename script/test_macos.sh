#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./script/build_and_run.sh --build
ZIG="${POD_ZIG:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.tools/zig-aarch64-macos-0.17.1/zig}"
"$ZIG" build test
mkdir -p test-out
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminControls.swift macos/LuminPopper.swift macos/LuminColorPicker.swift macos/LuminMenuPreviews.swift macos/LuminViewControls.swift macos/MarkupPalette.swift macos/DesignSystem.swift macos/DesignSystemGallery.swift macos/design_system_test.swift -o test-out/design_system_test
test-out/design_system_test test-out/design-system
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/lumin_assets_test.swift -o test-out/lumin_assets_test
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminControls.swift macos/LuminPopper.swift macos/LuminColorPicker.swift macos/LuminMenuPreviews.swift macos/LuminViewControls.swift macos/MarkupPalette.swift macos/DesignSystem.swift macos/LuminTypeToolbar.swift macos/lumin_type_test.swift -o test-out/lumin_type_test
test-out/lumin_type_test
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminPopper.swift macos/DesignSystem.swift macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift macos/lumin_explore_test.swift -framework JavaScriptCore -o test-out/lumin_explore_test
test-out/lumin_explore_test
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminPopper.swift macos/DesignSystem.swift macos/LuminViewControls.swift macos/lumin_view_controls_test.swift -o test-out/lumin_view_controls_test
test-out/lumin_view_controls_test
swiftc -swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminPopper.swift macos/DesignSystem.swift macos/LuminViewControls.swift macos/LuminMainToolbar.swift macos/LuminToolbarMenus.swift macos/LuminUtilityRail.swift macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift macos/lumin_toolbar_test.swift -framework JavaScriptCore -o test-out/lumin_toolbar_test
test-out/lumin_toolbar_test
swiftc -swift-version 5 -parse-as-library macos/LuminPopper.swift macos/lumin_popper_test.swift -o test-out/lumin_popper_test
test-out/lumin_popper_test
test-out/lumin_assets_test
python3 script/make_demo.py test-out/sample.pdf
clang -O2 macos/bridge_test.c zig-out/lib/libpod_native.a -o test-out/bridge_test
test-out/bridge_test test-out/sample.pdf '/System/Library/Fonts/Supplemental/Courier New.ttf'
swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/engine_test.swift zig-out/lib/libpod_native.a -o test-out/engine_test
test-out/engine_test test-out/sample.pdf test-out/edited.pdf
swift tools/pdfkit_check.swift test-out/edited.pdf test-out/independent.png > test-out/independent.json
python3 -c 'import json; d=json.load(open("test-out/independent.json")); assert d["pages"]==2 and "Hello Pod" in d["text"]; print("Independent PDFKit verification passed")'
swift tools/annotation_check.swift test-out/annotations.pdf test-out/annotations-independent.png
swift tools/page_tools_check.swift test-out

swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/DrawingModel.swift macos/DirectPeer.swift macos/DrawingSession.swift macos/drawing_test.swift zig-out/lib/libpod_native.a -o test-out/drawing_test
test-out/drawing_test test-out/sample.pdf

swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/metal_render_test.swift zig-out/lib/libpod_native.a -o test-out/metal_render_test
python3 - <<'FIXTURES'
from pathlib import Path
from tools.validate import fixture
Path("test-out/fill-rules.pdf").write_bytes(fixture(b"0 0 0 rg 30 30 200 200 re 50 50 100 100 re f* 0 w 35 35 m 90 210 l S\n"))
Path("test-out/large-edge.pdf").write_bytes(fixture(b"0.3 g 10 10 100000 50 re f\n"))
FIXTURES
test-out/metal_render_test test-out/sample.pdf test-out/fill-rules.pdf test-out/large-edge.pdf

swiftc -swift-version 5 -O -import-objc-header macos/PodBridge.h macos/Markup.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/imported_highlight_test.swift zig-out/lib/libpod_native.a -o test-out/imported_highlight_test
test-out/imported_highlight_test test-out/sample.pdf test-out/imported-highlight.pdf
