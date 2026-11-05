# Lumin main-toolbar source evidence

Inspected the downloaded application HTML/CSS/JavaScript on 2026-11-05. This report distinguishes static declarations from the parent's live DOM measurements. No captured JavaScript was executed and no screenshots were used. Bounded original source excerpts and SHA-256/range provenance are under Git-ignored `toolbar-source/extracted/main-toolbar/manifest.json`.

## Source map

| Concern | Source | Character range |
| --- | --- | --- |
| Outer shell and two section rows | `1vmims6r5cffr.js` |806179–807207 |
| Width observer and measurements | Same |668246–671808 |
| Collapse algorithm | Same |805105–806127 |
| Common editing left section | Same |665794–666762 |
| Security left section | Same |667863–668230 |
| Ordered right groups | Same |799083–803362 |
| More-tools overflow and reverse order | Same |803797–808168 |
| Split-button styling/component | Same |108130–111186 |
| Legacy main tool button | `16ymg1nau8f0s.js` |38109–40752 |
| Per-item collapse context | `2hfmg20_g-b3u.js` |35540–36109 |
| Width constants / large-screen override | `2r6nqfv294i-d.js` |137542–138173 |
| Window size hook | Same |196209–196527 |
| Breakpoint constants | `26cuxqjqfw5gv.js` |68995–69230 |
| Sign securely trigger / menu | `1vmims6r5cffr.js` |736748–739881 |
| Password trigger | Same |653183–653508 |

Ranges are half-open Unicode character offsets. The manifest also records exact UTF-8 byte ranges and whole-file/excerpt hashes. The files carry several toolbar variants. The current observed toolbar uses the **legacy** button classes, so modern `ToolButton`/Radix variants and their `forceSingle` presentation rules must not replace this source branch.

## Toolbar structure

`ToolbarInner` is a flex row with `align-items:center`, `justify-content:space-between`, padding8, source surface-container background and16px top-left/top-right radii. It contains separate left and right sections. The section wrapper is flex, column-gap4, center alignment and source toolbar-height variable. Direct vertical dividers have height18. The parent live DOM, rather than a guessed aggregate native row, supplies exact rectangles and resolved variable values.

The normal editing left section is:

1. Thumbnails split button.
2. Vertical divider.
3. Read aloud, if enabled and persistent controls are embedded.
4. Vertical divider following Read aloud.
5. Zoom field.
6. View controls.
7. Rotate view.
8. Vertical divider.
9. Select, Pan.
10. Vertical divider.
11. Undo, Redo.

There is **no trailing divider after Redo**. The free space between left and right rows comes from the outer `space-between`, not a divider or a concatenated single tool row. With hidden embedded persistent controls, Select/Pan and Undo/Redo are omitted; the Read aloud branch is also omitted. Read-aloud mode has a different rate/previous/play/next section and is outside this normal-state inventory.

Security uses its own left wrapper: Thumbnails, divider, Zoom, View controls, Rotate view, divider, Select, Pan. It omits Read aloud and Undo/Redo. Its CSS wrapper is center-aligned flex/column-gap4/toolbar-height but lacks the common section’s direct-divider18px override. The parent live DOM confirms32px security dividers and a300px first group.

## Ordered right-section groups

The integer beside each tool is its source `order`, which is forwarded unchanged as `collapsibleOrder`. A divider has `order:null` and does not count as a tool.

| Mode | Source order |
| --- | --- |
| Popular | Eraser0, Shape1, Highlight2, Draw3, Type4, divider, Signature5, divider, Add comment6, Sign securely7 |
| Fill & Sign | Prepare form0, divider, Cross1, Tick2, Dot3, Stamp4, Date5, Type6, Signature7, Sign securely8 |
| Mark up | Perform OCR0, divider, Image1, Eraser2, Shape3, Text tools4, Highlight5, Draw6, Type7, divider, Measure8, divider, Add comment9 |
| Security | Redaction0, Password protection1 |
| Legacy Organize | Crop0, Insert1, Move2, Delete3, Rotate4, Split5, Merge6, optional Bates numbering7 |
| Edit text | Add paragraph0, Edit PDF actions1; actual gated content must not be inferred from these identifiers |

When measurement capability is absent, Mark up filters out Measure and removes redundant/trailing/leading dividers. Original order numbers remain; Add comment is still order9. The collapse denominator is the number of non-null entries in the source array, **not the number of actually rendered buttons**. A component may return null for storage, permissions or capability reasons. Premium-badge visibility likewise depends on runtime tool availability; static use of an availability wrapper is not evidence that the badge is currently shown.

## Actual collapse algorithm

The source does not use a single fixed viewport threshold such as1450px. Relevant constants:

| Constant | CSS px |
| --- | ---: |
| Default left navigation rail |80 |
| Default right utility rail |50 |
| Minimum gap allowance used in width arithmetic |96 |
| Fallback right panel |368 |
| Expanded viewer navigation |260 |
| Collapse difference |54 |
| xxl breakpoint |1440 |
| Large-screen override |1808 (=1440+368) |

`windowSize.width` is `window.innerWidth`. The maximum right-section width is computed as:

```text
maxRight = innerWidth - ToolbarInner.children[0].clientWidth
           - (rightPanelOpen ? actualRightPanel.clientWidth or368 :0)
           - (viewerNavigationExpanded ?260 :0)
           -96 -80 -50
```

The first child can be an outer persistent-controls host, so measure `ToolbarInner.children[0]`, not an assumed descendant row. Preview-original mode and the new form-builder flow skip this computation. The ToolbarInner ResizeObserver calls a100ms-debounced measurement callback. `maxRight` is additionally debounced100ms with `leading:true` before collapse decisions.

`defaultRight` is read from `ToolbarInner.children[1].clientWidth` once per toolbar-value change, using `Y.current` to skip repeated measurements. It is not remeasured merely because fonts finish loading or a conditional tool finishes rendering. A new form-builder flow resets this baseline to0. The right section initially has `collapsedItem:0`.

For declared non-null tool count `count`, with `shortage = defaultRight - maxRight` and54px difference:

```text
if maxRight or defaultRight is falsy: collapsed=0
else if largeScreenOverride && !hasNarrowingPanel: collapsed=0
else if shortage >= maxRight: collapsed=null (More tools)
else if shortage <=0: collapsed=0
else if ceil(shortage /54) >= count: collapsed=null (More tools)
else: collapsed=min(ceil((shortage +27)/54), count)
```

Labels that consume the collapse context hide when `collapsedItem > collapsibleOrder`; thus low-order labels disappear first. The source hides a label span using `visibility:hidden; width:0; margin-left:0`, leaving the icon/button present. The algorithms use approximate54px reductions, not measured width of every label. `collapsed=count` can still render all icons until the separate overflow condition becomes true.

The hook accepts `hasNarrowingPanel`, but the inspected legacy caller passes only numberOfToolsItem and a context containing maxRight/defaultRight. It does **not** supply hasNarrowingPanel, so that legacy call uses the defaultfalse. Do not silently infer that a visible panel suppresses the1808px override in this branch. The right row has a temporary opacity0/visibility-hidden state during initial collapsing calculations.

**Initial-sample discrepancy resolved for Popular:** the parent’s first1512px capture had all labels visible, despite current full widths implying a small shortage. After switching away/back with fonts settled, Popular hid Eraser’s label and measured837.90625px, matching collapse order0. At1180px Popular hides all seven ordinary labels while Sign securely keeps its label (group533.953125px). This confirms that the initial one-time baseline can differ from a later full-width DOM measurement; a1512px exception must not be invented.

The parent also observed Mark up at1180 with all ten labels hidden and no More-tools fallback (group503px). The source denominator is explicitly `tools.filter(item => item.order !== null).length`, which is10 here, **not React.Children including dividers**. All ten labels hidden without overflow is possible when shortage is greater than432 and at most486: `ceil((shortage+27)/54)=10` while `ceil(shortage/54)<10`. Parent/child layout-effect timing and previous-mode widths can make the one-time defaultRight sample partially collapsed; this is an inference until that sampled state is observed. Do not equate a later fully expanded row width with the stored baseline or alter the denominator to fit it.

## Main tool button and split styling

The legacy toolbar button (`8886441`) declares height32/min-width32, horizontal padding4, source primary radius, no text transform, no shadow, nowrap, source editor transition and original Inter **12/460/115%** (`le_label_medium`). Idle color is legacy `le_main_on_surface_variant`. Active background is legacy `le_main_secondary_container` and foreground `le_main_on_secondary_container`. Idle hover uses legacy variant-hovered RGBA; active hover preserves its active secondary background. Pressed state uses the same secondary container/on-secondary-container pair. Disabled foreground uses `le_disable_on_container`.

The visible label span has margin-left4 and width100%; the hidden state sets margin-left/width0. A separate MUI `label` style declares flex centering/gap4, but that legacy class may be unused with the runtime MUI version. **Do not add both gaps without checking the live DOM's root/wrapper gap.** Parent live computed CSS is authoritative for the resolved gap and button text metrics.

A split wrapper is inline-flex/center, padding1, border-box, source primary radius, overflow-hidden, relative. Its primary child is the same legacy toolbar button, but a styled wrapper resets its background transparent except `data-active=true`, which uses legacy secondary-container. Its20px secondary button has min-width20/padding0 and a20px `sm_down_stroke` glyph; it is not a32px standard button. The container therefore measures34px high for32px primary content. Its compact width is54px when the primary is32 and secondary20.

On split-wrapper hover:

- Wrapper background becomes newer Kiwi surface-container.
- Primary background becomes that same surface-container, or newer Kiwi primary-container when `data-active=true`.
- Wrapper `:after` draws legacy on-surface hover RGBA at z1; primary child has z2. It is not an arbitrary full-button overlay composited over every child.
- Secondary hover itself remains transparent and legacy variant-colored. Secondary pressed foreground is legacy on-secondary-container. Disabled secondary declares opacity.38 and transparent background.

The styled primary also declares a legacy surface-container background for `.Mui-disabled`. Exact interaction with generated disabled-rule specificity should be checked from live computed styles; the bounded declarations alone do not prove a resolved unavailable-tool appearance.

The premium marker is a16px image positioned absolute top−2/left−4 at z2 by the base toolbar component. Its visible clipping depends on the surrounding split wrapper. Preserve original asset and current runtime state rather than adding a generic crown after the label.

Legacy roles newly relevant here:

| Role | Light | Dark |
| --- | --- | --- |
| secondary-container |`#D0E6F2` |`#3C535D` |
| on-secondary-container |`#081E27` |`#D0E6F2` |
| on-surface-variant |`#325167` |`#BCCFDC` |
| surface-container |`#EEEFF1` |`#1A2025` |
| disabled-on-container |`rgba(22,28,33,.38)` |`rgba(228,231,236,.38)` |

The exact extracted role strings are in `extracted/main-toolbar/theme-roles.json`. Newer Kiwi colors used by split hover remain a distinct token family.

## Special controls and overflow

Sign securely is a separate Kiwi filled button, with original **20px LmSignature SVG** and **20px CaretDown SVG**, `colorType:lumin_sign`, and a CSS-module override to custom-brand-sign surface-container/on-sign-container. It does not read the collapse index for its normal label. Its tooltip opens after1000ms. Its CSS resolves the sign background to dark`#3A28C0`/light`#D0CCFF`, and foreground to dark`#D0CCFF`/light`#160F57` in `0hmqw_9wcmxid.css` (`:root,.dark-mode` /`:root,.light-mode`). Its menu is below-start, declared332px width/min160/max-height dialogs-md. It contains certified-version and request-signatures rows. The332px menu declaration is static evidence; its full live menu/dialog states still need capture. Do not render its trigger as an ordinary PDF-icon toolbar button.

Password protection is likewise a special menu trigger: legacy24px `lg_password` icon, label plus20px arrow, dense menu/min-width200. Its current trigger does not read the label-collapse context, despite having an order1 entry in the right array. It has permission/AI/busy disabled states. Source presence does not prove every account can activate it.

When the right section collapses to More tools, the legacy menu is width280, bottom-end, main-axis offset4/cross-axis12, close-on-item-clickfalse. It maps `menuTools`: reverse the source tools excluding dividers, Prepare form and Sign securely; then append Prepare form/Sign securely in their original relative order. Its trigger uses original `kiwi-icon-dots-md`, glyphU+E9AF. It renders each tool in menu-item mode with its option trigger enabled. Item wrappers are width100%/positionrelative; suffix wrappers are absolute top50%/right4/translateY(−50%)/z10, with a24px `chevron-right-md` button and vertical divider margins4px8px. The list wrapper is flex-column (`13oun9t944hks.css`). This is a whole alternate right-section presentation, not a horizontal scroll fallback.

## Coverage limits

This is static source/control-flow evidence. Current flags, button labels, selected/hover styles, loaded source identity and fractional widths require the parent's live DOM/computed-style captures. No premium-gated toolbar, responsive threshold discrepancy, source toast, animation or full native parity is claimed verified by these excerpts.

## Reconstruction and source-only verification

`main-toolbar-layout-fixture.json` records clean toolbar/button/group rectangles for the four observed editing modes at expanded2000px and settled/compact/overflow viewports1512/1180/900px. It also records the226×80 thumbnails menu,280×416 Mark up overflow menu and the56px utility rail with its eight default controls. Raw HTML remains ignored. Original sign SVGs, premium marker, AI/marketplace artwork and source label metrics are retained under `macos/Resources/Lumin/Toolbar/` with hashes/provenance.

`LuminMainToolbar.swift` replaces the concatenated generic row with source left/right groups,32px buttons,34px split wrappers,20px suffixes,18px editing/32px Security dividers, source mode order and collapse arithmetic. The native baseline uses original full-label metrics deterministically; the web’s one-time stale initial sample/transition timing is not reproduced. `LuminToolbarMenus.swift` reconstructs thumbnails and overflow default structures; `LuminUtilityRail.swift` reconstructs the measured default rail. Opening native inspector panels participates in the right-section width budget. Existing action/palette callbacks are retained. Organize and gated branches remain separate unverified previews.

Some live color samples were captured during CSS transitions, such as `rgba(189,207,220,.98)` moving toward legacy variant. The clean fixture preserves these samples; native final color-role assertions use the independently extracted shipped declarations rather than copying an intermediate animation frame. Light/dark legacy secondary/disabled and custom-brand sign roles are verified. This does not verify all transitions, hover/pressed/disabled combinations, source tooltips or premium-state flows.

The source popper excerpt declares `rootBoundary:viewport`. A native nested300×300 panel regression exposed position calculation against its parent’s small bounds; `LuminPopper` now places nested panels against the top-level viewer and observes both owner/viewer geometry. The exact child position and parent/child cleanup checks pass. Source-only suite: `./script/test_lumin_source_ui.sh`. Final app build and all five suites passed; no screenshot checking was used.
