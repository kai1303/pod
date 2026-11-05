# Pod design system

Pod retains the approved layered open-folio app icon and reconstructs the [Lumin PDF viewer](https://www.luminpdf.com/app/pdf/viewer/building-event-driven-microservices-636b09b620c811cc94d171a5) with original Inter fonts, PDF/Kiwi glyphs, SVG assets and teal/neutral styles. Current source and verification limits are tracked in [FIDELITY.md](../../research/lumin/FIDELITY.md); full parity is incomplete.

The earlier coral/sand styling exploration is historical. Runtime chrome now follows the original source roles. `macos/DesignSystem.swift` owns the common Kiwi colors; legacy viewer roles and the upload menu's Radix neutral roles remain distinct. The portable reference is [tokens.json](tokens.json).

| Foundation | Current implementation |
| --- | --- |
| Header / main toolbar |56 /48 source points |
| Controls | Source32/40px sizes, per-component radii and spacing |
| Typography | Original Inter variable and static Medium500 files, original icon fonts |
| Surfaces | Header#191C1D, toolbar#1D2021, Kiwi menus#282B2C, canvas#111415 in dark appearance |
| Upload menu | Separate Radix#171717/#FAFAFA dark roles,10px outer radius,8px rows |
| Canvas |26px dot tile,2px gutter,8px top corners,48px vertical padding and zoom-scaled page margins |
| Navigation |80px modes /276px document panel; source header and responsive toolbar budget |

Source-styled controls preserve AppKit target/action and accessibility while using the recovered geometry and assets. `LuminPopper` and `LuminModal` implement the source panel structures. The PDF engine's existing editing and local file operations remain separate from UI previews and deferred cloud actions. Source account/document data is not bundled.

Build and run the source-only checks:

```sh
./script/build_and_run.sh --build
./script/test_lumin_source_ui.sh
```

The fifteen suites check original asset identities, DOM/CSS geometry, colors, state/routing and popup lifecycle without screenshots or image-render checking. Broader historical rendering checks are not part of this workflow. The selected OS artwork remains `design/brand/pod-icon-open-folio-v1.png` and `macos/Resources/Pod.icns`.

## Exact Lumin fidelity pass (active)

The latest user direction supersedes the earlier coral/sand styling adaptation: chrome now uses the original Lumin teal/neutral semantic colors, Inter variable and original static Medium fonts, PDF/Kiwi icon fonts and recovered navigation SVGs. Font assets and provenance live in `macos/Resources/Lumin/`; `LuminAssets.swift` registers and draws them. Native source-styled slider and numeric-field components are replacing platform-default controls. The selected Pod icon remains the OS application icon.

The full visual reconstruction is **not complete**. [FIDELITY.md](../../research/lumin/FIDELITY.md) is the active requirement audit and supersedes earlier UI-preview completion language. It records header/footer, menus, preview panels and other remaining mismatches. The original Share colors have 4.2834:1 contrast; fidelity tests preserve that source pair rather than altering it to meet a different palette target.

Current verification follows the user’s source-only direction: use downloaded HTML/CSS/JS, live DOM/computed styles, original asset identities and native property/geometry checks, without screenshots. Run `./script/test_lumin_source_ui.sh` for the asset, popper, Explore, zoom/View controls main toolbar/utility, header and floating-dock regressions. Earlier gallery/image checks remain historical and are not used for current UI checking. See the clean `research/lumin/*-layout-fixture.json` files and their source-evidence reports.

The main toolbar now uses source left/right grouping and responsive labels/More tools, with original label metrics and Sign securely/premium artwork. The observed default utility rail uses56px width and original glyph/SVG/bitmap assets. Nested menus position within the top-level viewer viewport. These components have DOM/CSS fixture checks; complete interaction-state and remaining-branch parity stays open in the audit.

The56px document header and44px floating page/zoom dock now use source DOM/CSS geometry and original glyphs. Their clean fixtures cover the default desktop state; header menus/account state and all dock variants still remain open. See `research/lumin/header-source-evidence.md` and `research/lumin/footer-dock-source-evidence.md`.

Header File, Share-options and Help menus now use source-derived dense rows, original glyphs/SVG assets and source placement rules. The source-only script includes their default desktop geometry/style/state regression. Conditional branches and source subdialogs remain open in the fidelity audit.

The Share UI now uses original PPAgrandir headings and two16px-radius Paper panels, with source link-access and bulk/export permission views. Its state is local; sharing/network actions are deferred. The source-only suite verifies captured desktop layout, colors, assets, drafts and modal placement/lifecycle. See `research/lumin/share-dialog-source-evidence.md`.


Mode navigation now uses all28 original theme/selection SVG variants and static Inter Medium12/500 labels. The canvas uses the recovered26px dot tile,16% on-surface dots,2px outer gutter,8px top corners and48px vertical padding. Page margins and container rounding follow the shipped viewer engine; fractional image/annotation coordinates are retained. The bottom rail button and Cmd+\ toggle focus mode, with the source restore control. Expanded navigation and focus hover-reveal remain open.

Build with `./script/build_and_run.sh --build`, then run `./script/test_lumin_source_ui.sh`. Its fifteen suites include rail/canvas source fixtures and actual viewer layout/annotation regressions; no image captures or renders are produced. See `research/lumin/mode-rail-canvas-source-evidence.md` for the original SVG provenance and bounded engine excerpts.


The rail's five ordinary hover menus now use their actual source structures: two inline Highlight rows, the Form builder section, original Organize glyphs and the separate Lumin Sign footer. The fifteen-suite source-only command includes their DOM/CSS geometry and the real400ms open/100ms close lifecycle, click suppression, host/Type routing and nested Signature keyboard ownership. Source transitions, downstream dialogs and conditional branches remain open in the active audit. See `research/lumin/mode-hover-source-evidence.md`.


Expanded document navigation now includes the source back/close header, upload card, recent-document row and neutral Radix upload dropdown. Current local data supplies its filename/thumbnail; cloud/dashboard/new-window actions are deferred. The source-only command includes their frames/colors/assets, collapse/dismissal and keyboard checks. See `research/lumin/expanded-navigation-source-evidence.md` for57 bounded source records and remaining limits.

Core editing palettes now follow the active legacy source branch: Shape Fill/Border, Text tools, Draw, Eraser and nested Highlight properties. Their clean DOM fixture retains fractional line boxes,22px swatches,32px picker targets,14/420 numeric type and legacy slider colors/texture. Native controls keep local annotation styles. AppKit rounds outer borderless windows to its grid; exact shadow/raster/transition and remaining state parity stay open. See `research/lumin/core-palettes-source-evidence.md`.

Signature now includes its source400px menu and880px Draw/Image/Type creation dialog, six original cursive fonts, nested font/color menus and local draft states. The source check command covers measured default geometry, font identity, counters/validation, nested ownership and dismissal. The shared `LuminTextLabel` and `LuminDialogPaper` keep Signature and Share on the same recovered line-box/Paper foundation. PDF/cloud signature persistence and the remaining conditional/raster flows are tracked separately in the fidelity audit.

Date reuses the source secondary text toolbar with independent style state, current-family font fallback and source DOM geometry checks. The current Stamp profile opens the304×230 source premium gate with original stars artwork; licensed Stamp dropdown/creator evidence and assets are retained as static-only research. See `research/lumin/date-source-evidence.md` and `research/lumin/stamp-source-evidence.md`.

Security uses the source200×80 password menu and480×213 modal access gate, separate from Stamp’s304px popover. Original set/remove glyphs, premium/disabled states, Agrandir headline and menu restoration are source-derived. Licensed password forms are documented as static-only research in `research/lumin/password-source-evidence.md`.

Edit text opens the source480×229 access dialog with the original magic PNG, PPAgrandir headline and preserved editor/Explore state. It does not select an inaccessible editing mode. The three observed premium layouts use named variants; alternate catalog branches remain research in `premium-catalog-source-evidence.md`.

Prepare form now uses the observed266×80 menu and360px legacy side panel, source field-tab glyphs, empty Properties state and Cancel/disabled Apply footer. The canvas reserves the source364px wrapper including gutters. Tab previews remain local; detection and PDF field creation are deferred.
