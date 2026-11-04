# Native macOS markup acceptance — 4 November 2026

This phase implements the user's selected Mark up tools: shapes, drawing, highlights, text and comments. Fill & Sign and measurement tools remain later phases. The native design and markup design describe the supported PDF subset and the observed Lumin DOM/CSS measurements; this is a native adaptation rather than pixel-identical browser chrome.

## Reproduce

Run `./script/test_macos.sh` on Apple Silicon with Xcode command-line tools, Zig 0.17.1 and the installed Courier New font. The script builds `dist/Pod.app`, runs Zig tests, exercises the C ABI and Swift wrapper, and validates exported text and annotations through an independent PDFKit reader. PDFKit is confined to test processes.

Fresh final validation passed:

- Zig unit tests: syntax, document, content, renderer, font and annotation behavior; every annotation kind paints visible pixels and survives save/reopen with stable geometry/styles.
- C ABI: open/render, bounds and error handling, text replacement, save/reopen, all 18 annotation kinds, update/delete and cache invalidation.
- Swift wrapper: two pages, text editing, original-byte preservation, overflow rejection, empty replacement, save/reopen, all 18 annotations, transform/delete, stable colors, closed freehand strokes and geometry-based hit testing.
- Independent reader: saved text, two-page export, 18 annotations across 12 standard PDF subtypes, comment/free-text contents and rendered output. Images are generated at `test-out/independent.png` and `test-out/annotations-independent.png`.
- Deleted annotation text and appearance objects are pruned from saved bytes; reachable page metadata survives. Repeated annotation edits reuse appearance objects; batch appends use geometric storage growth.

## Native UI observation

Tested a separate `dev.pod.pdf.qa` bundle to preserve the user's open Pod instance. Actual UI actions created a polyline, text highlight, free-text annotation and comment; a cancelled polyline did not create an undo entry. The four-annotation sample was saved using the native Save a Copy dialog and reopened using the native Open dialog. The persisted comment “Review this section.” was visible in the Comments panel.

Rebuilt the isolated bundle from the final source and reopened that saved file. Confirmed page 2 navigation, zoom from 95% to 110%, saved-comment selection, deletion and Undo restoring the comment. Inspected the rendered native shape popover with ten tools in the observed seven-plus-three layout, color swatches, Fill/Border controls, width and opacity. Earlier native checks exercised rectangle creation, moving/resizing and undo/redo. Unsupported font and PDF data remain explicit errors.

## Size and dependencies

Local `safe` Zig plus Swift `-Osize` build, arm64 macOS 14 deployment target:

- `stat -f '%z' dist/Pod.app/Contents/MacOS/Pod`: **528,592 bytes**, about **516.2 KiB**.
- `du -sk dist/Pod.app`: **532 KiB** allocated app-bundle storage on this host.
- `otool -L` confirms AppKit/CoreGraphics/Foundation/system Swift runtime dependencies and no PDFKit link. App code has no PDFKit import or CoreGraphics PDF drawing calls. CoreGraphics presents the engine's RGBA bitmap.

System frameworks and the installed font are excluded from bundle size. These sizes do not measure runtime memory. UI status render timings on the small sample ranged from roughly 10 ms on the sparse second page to hundreds of milliseconds on the first page with annotations at Retina scale. These are individual observations, not an arbitrary-PDF opening benchmark or a latency guarantee.

## Boundaries

This preview supports classic xref tables, uncompressed page content, basic paths and printable ASCII standard Courier. Rendering uses our own bounded, unhinted TrueType outline decoder and CPU rasterizer. Arbitrary fonts, compressed/image/scanned documents, forms, signatures, OCR and measurements are not supported. Text markup selects whole text runs. Free text uses Courier regular; font formatting that the engine cannot represent is not exposed. The app is locally ad-hoc signed and has not been notarized or tested on Intel Macs.
