# Lumin zoom and View controls implementation plan

**Goal:** Reconstruct the source top-toolbar zoom field/menu and View controls grid from downloaded HTML/CSS/JS and live DOM measurements, keeping the full application fidelity goal active.

**Architecture:** AppKit source-style controls in `LuminViewControls.swift`, using existing original fonts/glyphs and `LuminPopper`. Keep legacy typography/color roles separate from newer Kiwi controls. A small view-state model preserves six transition/layout combinations. Zoom controls keep local preview state; PDF layout/render integration remains the later functionality phase requested by the user. Existing engine work stays intact.

**Tech stack:** Swift/AppKit/CoreText; original source assets; clean JSON DOM/CSS fixtures.

- [x] Capture source grid, field and zoom menu HTML, computed styles, relative rectangles and open/close behavior. Raw captures stay ignored; public fixture excludes account content.
- [x] Add source-fixture tests for grid geometry, original glyphs, independent transition/layout state, zoom menu ordering/separators, input frame and local state, keyboard and keep-open behavior. Confirm the missing-component failure before implementation.
- [x] Implement the275.4375×104 grid with five32px glyph buttons and source14/420 labels; preserve selected/hover roles and independent choices.
- [x] Implement68×32 zoom field and166.4140625×306 menu, eight32px rows, separator margins, source shortcuts and local preview values. Preserve editing while open through narrowly scoped popper focus/anchor options.
- [x] Replace generic ViewerChrome controls/previews, route Explore View controls into the same grid, retain state across mode changes, update build and test scripts.
- [x] Build and run source-property/geometry/behavior tests plus existing popper/Explore/assets regressions; native accessibility check menus and editable field. No screenshots or image-based checks.
- [x] Update fidelity audit with actual results and remaining gaps. No commit/push/publication or source account/document mutation.

Validation: final application build and `script/test_lumin_source_ui.sh` passed. Native accessibility checked grid choices/reopen persistence, menu order, in/out keep-open, presets closing, editable126% rounding from125.5, text-field arrow handling, Tab entry and synchronized top/footer300% preview. Root app was relaunched to Popular/Select/95%. Direct native focus regression verifies the on-focus callback; CUA’s AX text-field focus/selection path was inconsistent, so immediate mouse-focus parity is not claimed from that tool. Full engine/image suites were not rerun in this pass. The full application objective remains incomplete.
