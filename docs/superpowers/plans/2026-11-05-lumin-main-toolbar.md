# Lumin main toolbar reconstruction

**Goal:** Reconstruct the common viewer controls and four observed editing-mode toolbars, their responsive labels/overflow and thumbnails dropdown from the shipped HTML/CSS/JS. Keep the entire application fidelity goal active.

**Architecture:** `LuminMainToolbar.swift` owns source button/split drawing and two-group layout, original label metrics, explicit mode groups and the source collapse arithmetic. `LuminToolbarMenus.swift` owns the two-item thumbnails menu and280px overflow menu, reusing the source menu row. `ViewerChrome` keeps existing action/palette callbacks. Original SVGs and clean metrics live in `Resources/Lumin/Toolbar`. The toolbar's right boundary must align with the observed56px utility rail. Other UI and PDF functionality remain independently incomplete.

- [x] Recover expanded/settled/compact/overflow HTML, geometry, labels, assets, source order and width algorithm. Original raw captures stay ignored.
- [x] Add failing DOM-fixture geometry/state tests, including418px common /300px Security, per-mode source groups, original button/label sizes, split geometry, responsive1/4/7/10 labels, More tools and menu layouts.
- [x] Implement source toolbar button/split roles, original sign SVGs/premium marker and source label widths. Preserve active/history callbacks.
- [x] Implement two aligned groups, exact dividers and responsive arithmetic; wire ViewerChrome and align the56px utility-rail boundary.
- [x] Reconstruct thumbnails226×80 and overflow280px menus, source order/options and offset4/cross12 placement.
- [x] Build and run source-only checks; native accessibility verify real toolbar states and action continuity. Use no screenshots.
- [x] Update audit with actual verification and remaining gaps. Do not commit/push or mutate the reference account/document.

Validation: final app build and all five `script/test_lumin_source_ui.sh` suites passed. Geometry checks cover four observed editing modes and expanded/settled/compact/overflow variants at900/1180/1512/2000px, plus the default56px utility rail. Original glyph names and steady-state legacy/sign color roles are checked against shipped declarations; some raw capture colors were intermediate CSS transition samples and remain recorded as such. Native accessibility confirmed thumbnails/options, Security omissions, Shape palette callback, Comments-driven More tools collapse, source reverse menu order and More→Type routing. Root app returned to Popular/Select/95%.

The shared popper regression first failed on nested position; using the top-level viewer viewport fixed the source `rootBoundary:viewport` mismatch. Size alone had been insufficient because AppKit can enforce the child controller’s preferred size after placement. Popup positioning and cleanup regressions now pass.

The full UI objective remains incomplete: header/footer, mode rail, Organize/gated branches, outline panel content, utility panels, security/forms/signature creation, tooltip/animation and broader interaction/disabled states still need reconstruction/verification. Existing preview icons remain in the not-yet-rebuilt branches. No screenshots, commit or remote mutation were used.
