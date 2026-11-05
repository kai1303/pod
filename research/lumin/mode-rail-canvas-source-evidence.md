# Lumin mode rail and viewer canvas: shipped-source evidence

This is a static REA decomposition of the downloaded Lumin viewer artifacts. No captured JavaScript was executed, no browser/native interaction was performed, and no screenshots were captured or used. Only public component definitions, geometry, style declarations, token roles and icon definitions are included; account and document content are excluded.

The machine-readable result is [mode-rail-canvas-source-rules.json](/Users/kai/works/side-project/pod/research/lumin/mode-rail-canvas-source-rules.json). Its 56 artifact records contain original artifact SHA256, excerpt SHA256, zero-based character spans and UTF-8 byte spans. All span ends are exclusive. Bounded source excerpts are under the ignored directory `research/lumin/toolbar-source/extracted/mode-rail/`; `manifest.json` inventories them. Character offsets differ from byte offsets in bundles containing Unicode.

## Source locations

| Component evidence | Downloaded artifact | Character span |
| --- | --- | --- |
| Navigation button styles | `2orfcd3fei0sw.css` | 603–3921 |
| Navigation button variant selection | `0qwcgrq08z83b.js` | 70812–72193 |
| Collapsed/expanded navigation and hover menus | `0qwcgrq08z83b.js` | 133272–136999 |
| Bottom focus action | `0qwcgrq08z83b.js` | 137020–141865 |
| Focus restore strip and handler | `1vmims6r5cffr.js` | 423748–426939 |
| Viewer shell and outer canvas wrapper | `1vmims6r5cffr.js` | 426939–430833 |
| Left mode rail geometry | `1vmims6r5cffr.js` | 535309–537545 |
| Icon registry | `2wlhxxp1u3z2q.js` | 1899347–1901632 |
| Canvas styled component | `3kktv-litzpgh.js` | 122612–128577 |
| Scrollbar styles | `24v2-cy106wrz.css` | 468–948 |
| Document/page styles | `24v2-cy106wrz.css` | 3039–3279 |
| Focus keyboard shortcut | `3zmc88ww60v7f.js` | 25915–25948 |

All source filenames in this table are relative to `research/lumin/toolbar-source/markup_files/`. Token records identify their own bounded spans in `0hmqw_9wcmxid.css`. Original SVG definition spans are recorded individually in the icon manifest.

## Rail structure and states

The collapsed rail is 80px wide. Its mode content has 4px padding and a 16px row gap. Modes are Popular, Fill & Sign, Mark up, Edit text, Security, Organize, then Explore. A full-width mode button therefore occupies 72px horizontally; its column consists of a 40×40 icon wrapper, 2px gap and 16px label line, giving 58px content height. The wrapper uses 8px padding and 8px radius. Labels use Inter at 12px, weight 500, line-height 16px. Original SVG height is 24px; natural width is either 24px or 25px depending on the shipped variant. The CSS supports wrapping/hyphenation.

The rail base is transparent over the editor low surface. The active icon wrapper uses `core-primary-container`, its SVG paths use `core-on-primary-container`, and its label uses `core-primary`. These are three separate roles. Inactive icon and text use `surface-on-surface-variant`; inactive hover applies `surface-surface-container-high` to the icon wrapper. Active hover retains its primary-container fill. Disabled mode opacity is 0.5. The premium badge is the original `/pdf-assets/lumin-svgs/badge_premium.svg`, positioned at left 12px/top 0 with width 16px.

| Role | Light | Dark |
| --- | --- | --- |
| Active label / core-primary | #035970 | #8EDEF4 |
| Active icon / core-on-primary-container | #012832 | #C4F0FD |
| Active icon background / core-primary-container | #C4F0FD | #087191 |
| Inactive label and icon | #42474A | #C2C7CA |
| Inactive hover icon background | #E7E8EA | #282B2C |
| Editor low surface under rail | #F3F4F6 | #191C1D |

Navigation expansion is a separate state with width 276px. The expanded branch renders an upload area and a dynamically loaded document-history component. It is not the collapsed mode list stretched into rows. This pass does not reconstruct that dynamic history component.

Ordinary mode hover menus use width 280px, position `left-start`, offsets main-axis 5px/cross-axis −24px, 400ms open delay and `fade-right` transition over 200ms. The deferred menu clear is 200ms. Edit text disables this hover menu. Explore uses width 336px, position `left`, offset 5px, the same 200ms transition and 400ms debounced hover opening, as well as its click trigger.

## Original SVG variants

The [icon manifest](/Users/kai/works/side-project/pod/research/lumin/mode-rail-icon-sources.json) records 28 state/theme variants from 19 distinct shipped React SVG modules. Each record includes the original bundle SHA256, module ID, source span, SVG SHA256, geometry SHA256, dimensions and path count. The SVG files are in `research/lumin/toolbar-source/extracted/mode-rail/icons/`. Their names follow `{tab}-{normalLight|normalDark|activeLight|activeDark}.svg`.

These files were reconstructed from the literal `React.createElement("svg", …)` definitions without evaluating the bundle. Original path data, path attributes, dimensions and fill values are retained. No synthetic viewBox or normalization was added. All 28 files parse as XML.

The source NavigationButton explicitly chooses `active[theme]` versus `normal[theme]`. All six main modes have different active geometry from their normal geometry. Explore reuses one SVG in all states. Normal light/dark variants also differ in geometry for Fill & Sign, Mark up, Edit text, Security and Organize; most dark normal variants have a 25px root width where the light root is 24px, with corresponding path shifts. Mark up active geometry also differs between themes. Popular light/dark geometry is identical within each state. Consequently a faithful implementation must switch the SVG variant and then apply CSS paint roles; recoloring a single normal icon cannot reproduce the active shape.

## Focus control and restore behavior

The bottom 40×40 control uses the 24px `pdf-icon-lg_collapse_right_panel` glyph, in a container with 16px padding. Its action toggles `isInFocusMode`; it does not expand navigation. It is disabled during document loading and is hidden in expanded navigation. The shortcut is Command+backslash on macOS and Ctrl+backslash elsewhere. Focus or presenter state sets the left rail to width 0, opacity 0 and visibility hidden.

The restore indicator is `.sc-e8665097-1[data-is-focus-mode=true]`, left 0/bottom 12px, padding 4px, radius `0 8px 8px 0`. Its button `.sc-e8665097-2` is 28px wide and 40px high with `pdf-icon-lg_expand_right_panel`. The indicator itself has no direct `onClick` in the component source. Hover reveals `.sc-e8665097-0`; the actual restore button inside that hover rail receives `onExpand` from the same focus toggle. The strip is 8px wide before hover and 80px while hovered, with top-right radius 16px, padding `20px 16px 16px`, lowest surface and shadow token 2. Parent live DOM interaction can distinguish event bubbling/reveal behavior from the handler placement shown statically.

## Canvas and page surfaces

The outer `DocumentOuterContainer` uses border-box and horizontal 2px padding; the `data-editor-shell="v2"` branch uses 4px. The next wrapper fills available width/height and uses `surface-surface-container`. The scrollable DocumentContainer uses `surface-surface`, with a radial gradient: `color-mix(in srgb, var(--kiwi-colors-surface-on-surface) 16%, transparent) 1px`, then transparent at 1px. Its tile is 26×26px. No explicit background-position or attachment is present, so the CSS defaults are 0% 0% and scroll; a default centered radial gradient places each dot at the center of its tile (13px/13px). This placement is a CSS inference, not a live measured pixel origin.

| Surface | Light | Dark |
| --- | --- | --- |
| Scrollable canvas | #F8F9FB | #111415 |
| Outer canvas wrapper | #EDEEF0 | #1D2021 |
| Dot source color, mixed at 16% | #191C1D | #E1E2E4 |

DocumentContainer is a flex column with overflow auto, width 100%, margin `0 auto` and user-select none. The legacy branch has `48px 0` padding. The LuminEngine branch overrides padding to 0 and sets document width 100%/margin 0; its text layer uses user-select text. Without a banner/phone state, the legacy branch rounds the two top corners by 8px, while LuminEngine rounds all corners by 8px; banner or phone states clear this radius. These are source alternatives, not proof of the current live branch.

The document is centered with `margin: 0 auto`. `.pageSection[id*=pageSection]` has `box-shadow: none`. `.pageContainer` is relative, with legacy surface background; its `:after` overlay has absolute inset 0, z-index 31 and 1px solid `le_main_outline_variant`, resolving in the legacy palette to #BCCFDC light / #325167 dark.

Scrollbar declarations include standard `scrollbar-width: thin` and transparent track color. WebKit rules specify width 10px, transparent track, 16px thumb radius and 2px transparent border with padding-box background clip. Modern standard scrollbar properties can take precedence over WebKit width; use computed live geometry before asserting the actual gutter is 10px.

## Verification and limits

The source/excerpt hashes and both span representations are mechanically checked against the original bytes. All extracted SVG XML and SVG SHA256 values are checked. No native implementation files were changed in this pass.

Live DOM remains necessary to establish the active renderer branch, exact page gaps and sizes, scroll origin, computed scrollbar geometry, focus header/right-control behavior and responsive variants. Static metadata does not establish raster paint, glyph baselines, antialiasing or clipping. Private document/account data was not included in this report or the source excerpts.


## Follow-up: settled live DOM and engine layout

The parent pass additionally inspected live DOM/computed styles without screenshots. Six clean rail fixtures cover Popular, Fill & Sign, Mark up, Security, Organize and Popular with Explore open. Forty-two live SVG path arrays and intrinsic dimensions matched the extracted originals. The five ordinary states were recaptured after the previous selection transition settled: intermediate inactive rgba fills were transient, while their final fill is transparent. The reference was restored to Popular with focus mode false and the temporary research tab closed.

The live target uses the legacy renderer branch: horizontal outer gutter2, top-only radius8 and48px vertical padding. Its canvas gradient uses26px tiles and on-surface at16%; no page-section shadow is present. Focus removes the56px header,80px mode rail and56px utility rail, leaving the48px toolbar and floating dock. The clean fixture records normal/focus canvas rectangles and the36×48 restore indicator at left0/bottom12.

Twelve bounded excerpts from `webviewer-core.min.js` resolve page layout. Its SHA256 is `6c06e417b22bc341b2fc6ffa97ff4adcdf0926aec3d20f6de234ad6078c611b0`; exact spans and hashes are in the source-rules artifact list. Default margin4 scales to `round(max(1,4*zoom))`. Page container dimensions are floored; the document flow width includes two margins and is ceiled. At267%, the504×661 source page has margin11, flow width1368 and border1345×1764. In the1372px canvas it starts at13/59 relative to the canvas. The earlier margin4 sample was unsettled and is not the final zoomed margin. Native image/annotation coordinates retain fractional scaled dimensions inside the floored border.

`LuminModeRail.swift` now switches all28 original theme/state assets. `LuminCanvasStyle.swift` owns the viewport-attached dot pattern and source page/shell geometry. `PageCanvas` uses that geometry without changing PDF coordinate transforms; focus layout is integrated in the app. Expanded document navigation, ordinary mode hover menus, focus hover-reveal, platform scrollbar details and all transition/raster states remain open. A native check exposed an existing Organize layout loop; the preview now reuses its accessibility buttons across repeated layouts, with a failing-then-passing regression.
