# PDF page tools implementation plan

**Goal:** Extend the native Pod editor with merge, extract/split, reorder, rotation and cropping, using Stirling as a workflow reference and retaining Pod's own Zig engine.

**Architecture:** Page assembly clones the selected pages' object graphs into a fresh document with materialized inherited resources and geometry. Reject catalog/page structures that cannot be preserved. Crop and rotation use standard PDF metadata and a shared coordinate contract through the native bridge. Swift performs operations on temporary documents; only validated, renderable results replace the current snapshot. Save/export never overwrites an existing path.

**Tech stack:** Zig 0.17.1, Swift/AppKit, existing C bridge; no new libraries or Stirling code.

- [x] Add failing engine tests for page selection/order, multiple source documents with colliding object IDs, annotations, inherited geometry, malformed selections and unsupported document relationships.
- [x] Implement `src/page_tools.zig` with bounded graph cloning and selection. Add standard inherited CropBox/Rotate parsing in `src/document.zig`, and rotation/crop raster transforms in `src/render.zig`. Round-trip with the existing writer.
- [x] Expose operations in `src/c_api.zig` and `macos/PodBridge.h`; use output-buffer APIs so source handles are unchanged. Exercise them through Swift in `macos/engine_test.swift`.
- [x] Add Swift operations and geometry conversions in `macos/Engine.swift`, adapt hit testing and display in `macos/PageCanvas.swift`, and wire the Pages menu/dropdown and dialogs in `macos/PodApp.swift`. Clamp undo navigation when page counts change.
- [x] Verify via `script/test_macos.sh`, independent PDFKit page/count/text/rotation/crop checks, and native UI smoke checks. Record measured executable size and supported-subset limitations in README.

Validation cases: selection `[1,0]` reverses two pages; `[1]` extracts just the second page; empty, duplicate and out-of-range selections fail; source documents remain byte-identical. Merge separate resource graphs and preserve markup, edits, crop and rotation. Test 0/90/180/270-degree coordinate mappings including nonzero crop origins, clipped page content and save/reopen. Invalid crop and rotation fail before publication. Undo after extracting/merging cannot navigate beyond the restored document.

Advanced text editing, OCR, images-to-PDF, Office conversion, signatures and permanent redaction are outside this first page-management milestone. Cropping changes visibility; it does not remove hidden content.


Verified 2026-11-04: `script/test_macos.sh` passed (37 Zig tests, C and Swift integration, PDFKit interoperability). Native UI smoke checks exercised rotation, rotated text selection, crop, reorder and undo on the included sample. Independent review found no additional correctness defects; assembly now rejects trailer metadata it cannot retain. Executable: 599,248 bytes (585.2 KiB); no PDFKit linkage. No Stirling source copied.

Integration: reconciled the main checkout’s concurrent design-system changes in PageCanvas, PodApp and test_macos.sh. The combined main-checkout test script passed, including design-system checks and PDFKit page-tool checks. Combined executable: 632,944 bytes (618.1 KiB); app-bundle file sizes total 2,188,011 bytes (about 2.09 MiB), including the icon. The standalone page-tools commit is c2faabe on codex/pdf-page-tools; integrated changes remain in the main working copy alongside the existing design-system edits. No push performed.
