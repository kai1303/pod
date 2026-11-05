# Lumin Type and color picker implementation plan

**Goal:** Continue the approved Lumin reconstruction by removing the native color dialog and verifying Type's source-based menus. The full fidelity audit remains the completion criterion for the overall goal.

**Architecture:** Keep the native AppKit viewer. Use one shared, source-measured color picker in nested arrowless `LuminPopper` panels. Draft RGB/HSL changes stay local until Confirm; Cancel, Escape and click-away discard them. Use original assets and Inter.

**Evidence:** `research/lumin/toolbar-source/color-picker-live.json`, its cropped RGB capture, downloaded modules 3872256/2257615, and `dropdown-source-evidence.md`. The live picker is 205 × 297.7421875, padding8, saturation189 × 103.9453125, hue167 × 10, three21px inputs, Hex/RGB/HSL toggle, Confirm/Cancel189 × 32 separated by8. Alpha is disabled. Opaque colors cycle Hex → RGB → HSL → Hex. Transparent initial colors start in RGB and skip Hex while non-opaque.

- [x] Add native UI checks for Type's 40px strip, 18 original font previews, 5–45pt list, scroll/keyboard selection and start-aligned submenu placement.
- [x] Add picker checks for measured geometry, RGB/HSL switching, draft/cancel/confirm behavior, invalid input and nested-panel cleanup.
- [x] Build `macos/LuminColorPicker.swift` with source gradients, original toggle SVG, adaptive original theme roles and accessible custom controls.
- [x] Integrate the picker into `MarkupStyleView` and `LuminTypeColorRow`; remove their native color-panel paths. Keep seven palette colors and append a confirmed custom color by replacing the oldest entry, as in source.
- [x] Route Explore's Type command to the actual Type strip. Add centered popper alignment and child cleanup.
- [x] Build, run relevant native tests, then verify font scrolling, picker opening/cancel/confirm and dismissal in Pod. Record actual results and remaining mismatches in the fidelity audit.

Changes stay in the current worktree to preserve concurrent document-engine work. No commit, publication or backend feature work is included in this pass.
