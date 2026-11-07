#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "${1:-}" != --built ]]; then ./script/build_and_run.sh --build; fi
mkdir -p .build
swiftc -swift-version 5 macos/ReactEditor.swift macos/react_editor_test.swift -framework AppKit -framework WebKit -o .build/react-editor-test
.build/react-editor-test "$ROOT_DIR/web/dist"
TEST_APP="$ROOT_DIR/.build/PodReactUITest.app"
if [[ -d "$TEST_APP" ]]; then rm -rf "$TEST_APP"; fi
ditto dist/Pod.app "$TEST_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.pod.pdf.react-ui-test' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Pod UI Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP" 2>/dev/null
TEST_COMMAND=("$TEST_APP/Contents/MacOS/Pod" -ApplePersistenceIgnoreState YES)
POD_REACT_SMOKE=1 "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_READING_SMOKE=1 "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_CREATE_TEXT_SMOKE=1 "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_CREATE_TEXT_SMOKE=1 "${TEST_COMMAND[@]}"
python3 tools/link_fixtures.py test-out/links
POD_REACT_SMOKE=1 POD_DESTINATION_SMOKE="$ROOT_DIR/test-out/links/destinations.pdf" "${TEST_COMMAND[@]}"

mkdir -p test-out/comment-ui
uv run --with pymupdf==1.26.5 python tools/comment_view_check.py test-out/comment-ui --fixtures
POD_REACT_SMOKE=1 POD_COMMENT_SMOKE="$ROOT_DIR/test-out/comment-ui/page-view.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_COMMENT_SMOKE="$ROOT_DIR/test-out/comment-ui/page-view.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_COMMENT_SMOKE="$ROOT_DIR/test-out/comment-ui/page-view-no-ap.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_COMMENT_SMOKE="$ROOT_DIR/test-out/comment-ui/page-view-no-ap.pdf" "${TEST_COMMAND[@]}"

uv run --with pymupdf==1.26.5 python tools/comment_popup_check.py test-out/comment-popups --fixtures
POD_REACT_SMOKE=1 POD_POPUP_SMOKE="$ROOT_DIR/test-out/comment-popups/open.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_POPUP_SMOKE="$ROOT_DIR/test-out/comment-popups/open.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_POPUP_SMOKE="$ROOT_DIR/test-out/comment-popups/rich.pdf" "${TEST_COMMAND[@]}"

uv run --with pymupdf==1.26.5 python tools/reply_check.py test-out/replies --fixtures
POD_REACT_SMOKE=1 POD_REPLY_SMOKE="$ROOT_DIR/test-out/replies/note.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_REPLY_SMOKE="$ROOT_DIR/test-out/replies/note.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_REPLY_SMOKE="$ROOT_DIR/test-out/replies/highlight.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_REPLY_SMOKE="$ROOT_DIR/test-out/replies/no-view.pdf" "${TEST_COMMAND[@]}"

uv run --python 3.12 --with reportlab==5.1.0 --with pillow==11.3.0 python tools/inline_image_fixtures.py test-out/inline-ui
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/inline-ui/inline-reportlab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/inline-ui/inline-reportlab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/inline-ui/inline-jpeg-progressive.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/inline-ui/inline-jpeg-progressive.pdf" "${TEST_COMMAND[@]}"

uv run --python 3.12 --with reportlab==5.1.0 python tools/dash_fixtures.py test-out/dash-ui
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/dash-ui/dash-reportlab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/dash-ui/dash-reportlab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_EXPECT_METAL_BUDGET_FALLBACK=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/dash-ui/dash-grid.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/dash-ui/dash-grid.pdf" "${TEST_COMMAND[@]}"

uv run --with pymupdf==1.26.5 python tools/shape_check.py test-out/shape-ui --fixtures
POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/mupdf-line.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/mupdf-line.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/states.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/states.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/fallback-square-dashed.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/fallback-square-dashed.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/fallback-circle-insets.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/fallback-circle-insets.pdf" "${TEST_COMMAND[@]}"
for shape in fallback-line-leader-negative fallback-polyline-solid fallback-polygon-solid; do
  POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/$shape.pdf" "${TEST_COMMAND[@]}"
  POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/$shape.pdf" "${TEST_COMMAND[@]}"
done

uv run --with pymupdf==1.26.5 --with pillow==11.3.0 python tools/image_check.py test-out/image-ui --fixtures
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/mupdf.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/mupdf.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/soft-matte-interpolate.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/soft-matte-interpolate.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/pillow-indexed.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/pillow-indexed.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/cie-lab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/cie-lab.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/cie-rgb-object-stream.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/image-ui/cie-rgb-object-stream.pdf" "${TEST_COMMAND[@]}"

python3 tools/caption_check.py test-out/caption-ui --fixtures
for caption in inline leader multiline; do
  POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/caption-ui/$caption.pdf" "${TEST_COMMAND[@]}"
  POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/caption-ui/$caption.pdf" "${TEST_COMMAND[@]}"
done
POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/line-caption.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/shape-ui/line-caption.pdf" "${TEST_COMMAND[@]}"

uv run --with pymupdf==1.26.5 python tools/freetext_check.py test-out/freetext-ui --fixtures
uv run --with pypdf==6.21.4 --with fonttools==4.60.1 python tools/freetext_font_fixtures.py test-out/freetext-ui
for text in mupdf-left callout-three rich fallback-mupdf-left fallback-wrap fallback-callout-three resource-truetype resource-direct-truetype resource-mixed-cmap resource-auto-cid fallback-hscale-wide fallback-hscale-auto-rotated resource-hscale-cid resource-hscale-auto-mixed fallback-spacing-combined fallback-spacing-backwards-words fallback-spacing-auto-negative resource-spacing-remapped resource-spacing-auto-mixed; do
  POD_REACT_SMOKE=1 POD_SHAPE_SMOKE="$ROOT_DIR/test-out/freetext-ui/$text.pdf" "${TEST_COMMAND[@]}"
  POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_SHAPE_SMOKE="$ROOT_DIR/test-out/freetext-ui/$text.pdf" "${TEST_COMMAND[@]}"
done

uv run --with pillow==11.3.0 python tools/jpeg_check.py test-out/jpeg --fixtures
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/jpeg/ui.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/jpeg/ui.pdf" "${TEST_COMMAND[@]}"

POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/jpeg/progressive-ui.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/jpeg/progressive-ui.pdf" "${TEST_COMMAND[@]}"

uv run --with pillow==11.3.0 python tools/fax_check.py test-out/fax --fixtures
POD_REACT_SMOKE=1 POD_IMAGE_SMOKE="$ROOT_DIR/test-out/fax/ui.pdf" "${TEST_COMMAND[@]}"
POD_REACT_SMOKE=1 POD_RENDERER=cpu POD_IMAGE_SMOKE="$ROOT_DIR/test-out/fax/ui.pdf" "${TEST_COMMAND[@]}"
