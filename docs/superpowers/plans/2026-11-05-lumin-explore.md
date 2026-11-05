# Lumin Explore reconstruction

**Goal:** Replace the native Explore menu with the captured source panel, including its default/filtered states, original assets, matching search results and keyboard behavior. Keep the full application fidelity audit active.

**Architecture:** Native AppKit panel in the existing arrowless `LuminPopper`. A clean JSON catalog joins captured rendered labels/icons/shortcuts with the shipped command keys/search titles. Use the source Fuse6.6.2 algorithm through macOS JavaScriptCore, with the exact normalization and active-English aliases; no application bundle JavaScript executes. Existing preview callbacks handle chosen commands. Cloud and PDF operations remain separate.

**Source evidence:** `explore-default-live.json`, `explore-type-search-live.json`, `explore-all-search-live.json`, `explore-unmatched-live.json`, and bounded source/aliases under `toolbar-source/extracted/explore/`. See `research/lumin/explore-source-evidence.md`. Default outer336×516; content inset16; search304×32; guideline304×94; result viewport304×338. Without guideline the viewport grows to440. Group label24 high, group gap12, standard row40 with24px icons,14/500 text and14/420 shortcuts. Filtered results omit labels and append query actions; wrapped query rows grow to56px. Right-side popover placement has5px gap/overflow inset.

- [x] Recover clean command/asset catalog, original image/SVG assets, official pinned Fuse distribution/license, aliases and normalization. Preserve original capture checksums and scope.
- [x] Add tests comparing source query result sequences (`type`, `rect`, unmatched and space), source geometry, default/filtered headings, keyboard skipping/wrapping, callback/dismissal and assets.
- [x] Add right-side popper placement and initial responder support with default behavior unchanged for other tool menus.
- [x] Implement `LuminExploreSearch.swift` and `LuminExploreMenu.swift`, including debounced search, source guideline, 40px rows/shortcuts/premium badges/switch, dynamic result heights, focus handling and scroll.
- [x] Replace `ViewerChrome.showExplore`'s NSMenu; route Type and existing UI previews and expose Option-/ toggle. Preserve existing document-engine work.
- [x] Fix the confirmed static Inter Medium vs variable420 source distinction; verify400 via live platform-font evidence and add source font file regressions.
- [x] Final application rebuild and source-fixture checks passed after search-field/glyph corrections. Native accessibility confirmed default/query states and Type routing. Verification uses source HTML/CSS geometry/style assertions without screenshots; fidelity audit records remaining gaps.

No commit, upload, publication, cloud call or new PDF operation is part of this pass. Dark-page switching, navigation and command selection are local UI state only until their functionality is addressed.
