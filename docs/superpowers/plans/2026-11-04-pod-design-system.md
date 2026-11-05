# Pod Design System Implementation Plan

**Goal:** Apply the selected open-folio icon and a reusable native design system grounded in the supplied Lumin viewer.

**Architecture:** Keep AppKit and the existing editor behavior. Extract semantic colors, typography and dimensions into `macos/DesignSystem.swift`, with native button and choice controls. Apply them to existing surfaces and expose a native gallery through the View menu.

**Tech Stack:** Swift/AppKit, existing Zig engine, shell build scripts.

## Work

- [x] Inspect the live viewer with browser DOM/CSS and screenshots. Record observed values separately from authored Pod brand adaptations.
- [x] Confirm the selected icon is bundled through `CFBundleIconFile` and `macos/Resources/Pod.icns`.
- [x] Add `macos/design_system_test.swift` for light/dark contrast, accessible control size/labels, and exclusive choice behavior; confirm missing implementation fails compilation.
- [x] Implement `PodTheme`, `PodMetrics`, `PodTypography`, `PodButton`, `PodSurfaceView`, `PodSurfaceStack`, and `PodChoiceGroup` in `macos/DesignSystem.swift`.
- [x] Apply shared components to `PodApp.swift`, `MarkupPalette.swift`, and `PageCanvas.swift`. Preserve document ink colors and PDF behavior.
- [x] Add `macos/DesignSystemGallery.swift`, reachable through View → Design System, showing the same native components used by the editor.
- [x] Add evidence and usage documentation plus portable token data under `design/system/`.
- [x] Include sources in `script/build_and_run.sh` and run the design-system checks from `script/test_macos.sh`.
- [x] Build, run native checks and existing PDF interoperability tests, then inspect the app and gallery with computer use. Verify gallery dimensions, selected tools, palette controls, and both appearances.

## Boundaries

The Lumin tab was inspected in dark mode. Light-mode colors are authored Pod adaptations, not claimed observations. Native SF typography and symbols replace Inter and Lumin icon glyphs. REA was unavailable in the active session; evidence is browser observation, not REA output. No cloud collaboration, premium tools, or unsupported PDF features are added. No changes to the remote document.

## Expanded toolbar research

- [x] Download rendered HTML, associated CSS/JavaScript, the app icon and favicon.
- [x] Inspect all seven toolbar navigation entries and accessible option families; document the Edit Text upgrade gate.
- [x] Extract tool identifiers, token declarations, icon mappings, toolbar CSS and styled-component templates into local indexes with checksums.
- [x] Keep the raw authenticated capture out of Git and link the research from the design-system guide.

The full native suite passed before concurrent page-tool/collaboration changes. Final shared-tree verification is recorded separately in the task response; later changes are not attributed to this design-system work.

Final shared-tree run: app build, design-system checks, C bridge, Swift engine, independent PDFKit annotation and page-operation checks passed. The concurrently added drawing suite stopped at `Undo eraser restores the local stroke`; that collaboration test is outside this design-system change.
