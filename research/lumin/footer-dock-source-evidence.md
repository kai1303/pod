# Floating page/zoom dock

The reconstruction uses downloaded shipped HTML/CSS/JS and read-only live DOM/computed styles. No screenshots or image comparison were used.

## Evidence

- `footer-dock-source-rules.json` records artifact SHA256, bounded character spans and exact layout/input rules; raw bounded excerpts are Git-ignored under `toolbar-source/extracted/footer/`.
- `footer-dock-layout-fixture.json` records clean DOM geometry, fonts, colors, glyph codepoints and disabled states in a fresh source tab at1512×778. It contains no account identity or document title.
- The dock is368.1640625×44 with `/324`, centered on the full viewport at x571.91796875,y718,16px above the viewport bottom. Width follows content. Container padding6px8px, radius8, idle opacity.7, active1; mouse leave/focus exit schedules inactivity after3seconds.
- Both zoom buttons are32×32 with original20px PDF glyphs. Navigation uses original20px Kiwi glyphs and32×32 buttons,4px gaps. Disabled navigation glyphs use the newer on-surface role at38% opacity; zoom uses legacy roles.
- Inputs have minimum40px content width plus4px padding each side, yielding48×32. Inter variable12/420/18; total uses original Inter Medium12/500/16. Input surface is newer surface-container-low; hover outline1px, focus secondary-container shadow3px.
- Source declares a16px divider, but both original and fresh live DOM resolve it to0px high through competing MUI rules. The reconstruction keeps the measured1×0 frame and4px margins.
- Invalid page input retains current page; invalid bottom zoom outside5–9999 retains current percentage. Top toolbar zoom has different clamp behavior and is not reused for validation.

## Implemented and verified

`LuminFooterDock.swift` replaces the full-width footer with a floating overlay. The PDF body now reaches the bottom edge. Existing page navigation and native zoom button targets are retained; bottom numeric zoom previews the chrome state, matching the existing UI-first top zoom phase.

`lumin_footer_test.swift` asserts every captured control frame, original glyph asset presence/class, default disabled states, dynamic first/last and zoom bounds, input fallback/commit callbacks and idle/active alpha. The shared source-only script emits no images.

## Remaining differences

AppKit text rasterization, baseline placement and shadow blur/inset rendering are not proven pixel-identical to CSS. The native dock approximates the source multi-layer shadow with AppKit shadows and a thin inset light stroke. CSS transitions/ripples, scroll-triggered activation, full keyboard/focus traversal, presenter/focus/phone variants and right-panel/expanded-navigation geometry remain unverified. Native app minimum width1160 excludes the source mobile stacked dock. Actual PDF zoom/layout/fit functionality retains the existing engine limits and is outside this UI pass.

Native accessibility verification on the built root app observed page1/2, Last page→2 with Next/Last disabled, First page→1 with First/Previous disabled, and editable page input `2`→page2. It returned to the unchanged sample at page1/95%. The latest build reopened with the source header and floating dock controls. No image capture was used.
