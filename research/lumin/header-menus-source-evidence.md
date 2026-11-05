# Header File, Share and Help menus — shipped source

This pass inspected downloaded shipped JavaScript/CSS only. It used no screenshots, browser interactions, source account data or app implementation changes. `header-menus-source-rules.json` records the rules, conditional row inventory, original icon identities and exact artifact SHA256/character/UTF-8 spans. Bounded source excerpts plus a manifest remain in Git-ignored `toolbar-source/extracted/header-menus/`.

## File menu

`0qwcgrq08z83b.js` characters77900–92400 declares the item components and default order. The menu target at97000–98100 uses the newer Kiwi `Menu` with `itemSize:"dense"` and `FileMenu` dropdown class. It does not explicitly pass a position; do not infer bottom-end from other tool menus. The parent live DOM measured bottom-center with8px gap,304×451 for the reachable current state.

`2orfcd3fei0sw.css`14520–14945 sets `FileMenu...fileMenuDropdown{min-width:304px}`. Its shortcut is14/420/20 with newer on-surface-variant. Generic menu declarations in `0hmqw_9wcmxid.css`287715–290600 specify surface-bright, dense row padding4px8px, min-height32px, radius4px, gap8px,14/500/20 typography and newer on-surface. Source hover/pressed layers are8%/12%; disabled rows use38% opacity.

Default order is Star, Make a copy, Move, Download, optional Save as template, optional Available offline, optional Auto-sync, separator, theme mode, Full screen, Dark page, Presenter mode, separator, File information, Version history, separator, Open in desktop app with NEW badge, optional separator/New PDF Viewer. The JSON retains the source's visibility/permission/offline/template/system-file conditions instead of asserting all rows are simultaneously visible.

Most original PDF/Kiwi menu icons are24px. Full screen is20px; Available offline is20px. Dark page, Save as template, Open in desktop app and New PDF Viewer use original Phosphor SVG exports (`MoonStarsIcon`, `StickerIcon`, `MonitorArrowUpIcon`, `SparkleIcon`); parent DOM extraction owns those exact paths. Presenter shortcut is `⌘ Enter` on Mac and `Ctrl Enter` otherwise, confirmed in `3zmc88ww60v7f.js`25760–26490.

Legacy source separators use `888413` in `2dqtb2c9lrr2n.js`60395–60900: theme outline-variant background,8px vertical margin,1px minimum width. Their final border/height must come from the parent's computed DOM evidence.

## Share caret menu

`0qwcgrq08z83b.js`161400–164820 declares two dense rows: **Copy link** (`kiwi-icon-link-lg`,24px) and **Send for signatures** (`kiwi-icon-send-lg`,24px). Send's permission condition is retained in JSON. The `Menu` explicitly uses bottom-end, close-on-item and close-on-outside. The parent measured194.7578125×80 with8px gap; this dimension comes from live evidence, not the static source pass.

Generic `Menu` in `3paunvfp0my3g.js`50000–54680 sets8px padding, radius8 and shadow2. It defaults to trapped focus, return focus, looping item navigation, item tabindex−1 and an initial focus placeholder; a keydown on the target disables that placeholder for keyboard opening. These states still require a faithful native implementation/runtime check.

## Small switches

`3paunvfp0my3g.js`89834–96200 plus `0hmqw_9wcmxid.css`305991–308230 defines Kiwi Switch. Default small track is36×20,1px border,16px thumb for off/on,32px hover halo. Off uses low-surface track, outline border, on-surface-variant thumb; checked uses secondary track/border and on-secondary thumb. Static CSS supplies transitions, hover halo and pressed behavior. These are separate newer roles, not the legacy toolbar palette.

## Help menu

`1vmims6r5cffr.js`793107–794980 declares **Help center**, **Contact Support**, **Give Feedback**. Viewer structure is a legacy MUI MenuList UL whose anchor `LinkItem` wraps a newer dense `MenuItemBase`; row typography/color therefore resets to newer14/500/20/on-surface even though the outer link has legacy title-small styling. `13awzrgnr9-2o.js`57615–58020 retains `sc-6bee0aff-13`. `3ecqp71ogrms5.js`20443–23430 retains the MenuList8px padding.

The generic MUI popper in `12f_9niz_vx64.js`23732–26060 uses offset8px without an arrow (22px with arrow), viewport prevent-overflow padding8 with alt-axis correction, Fade300ms and default Paper elevation1. The parent observed bottom-center/8px,141.765625×112. Link destinations/actions were not invoked here.

## Limits

Static declaration is evidence for implementation structure and CSS, not proof of reachable permissions, row geometry or paint. The parent's live DOM captures establish the current desktop state and inline SVG paths. All hover/focus/keyboard/permission/mobile states, appearance variants and source font rasterization remain separately verifiable. No native files were changed by this source research.


## Native reconstruction and live DOM fixtures

The subsequent `header-menus-layout-fixture.json` captures public menu labels, clean CSS/style rectangles and the source keyboard-focus style, with no account identity or source document data. File is304×451 with twelve32px rows and three1px dividers/margin8. Share options is194.7578125×80 with two32px rows; Help is141.765625×112 with three text-only rows. File and Help are bottom-center/gap8; Share is bottom-end/gap8. Help's legacy Popper rounds offsets at the observed devicePixelRatio2; Mantine File/Share preserve their fractional placement.

`LuminHeaderMenus.swift` replaces the native File/Collaborate fallback dropdowns and implements Help. Original template, moon-stars and monitor-arrow SVGs are retained in Resources/Lumin/Header and rasterized at4× for native use; manifest hashes identify both formats. File menu Full screen deliberately uses20px original PDF glyph, while the other default glyph sections are24px. Source text uses original Inter Medium14/500/20; presenter shortcut uses variable14/420/20, and NEW uses12/500/16. The yellow badge background is constant#e79a00; its text is the semantic warning-container role (light#ffefcf,dark#5a4300).

The source File menu starts focus on a placeholder. Arrow Down enters its first row; keyboard focus has a2px#228be6 outline at offset2, with transparent background. Tab from a row enters the lone focusable Dark page switch and loops there; the switch track uses the same focus outline. The native menu follows these captured states. Starred and Dark page keep the dropdown open; local starred state updates to the source unstar glyph/label, and dark-page chrome state is shared with Explore. Neither operation writes to the reference account. File Download/Make a copy preserve the existing local Save a Copy action; app appearance and full-screen controls use existing native app capabilities. Remaining commands are UI previews pending their source dialogs/functionality.

The targeted source-only regression compares every default row, allocated label/icon frame, divider, root size, original asset availability, placement, dark foreground/background roles, badge geometry/colors, basic keyboard selection and switch/star variants. It covers these captured desktop branches rather than all permissions/account states.

Remaining: source main Share dialog; File subdialogs/panels; notification/account/navigation/status UI; alternate offline/auto-sync/new-viewer and permission-dependent rows; exact CSS shadow/text rasterization, hover halo/ripple/transitions; full Help/Share Tab/return-focus and accessibility-state parity. The native macOS command menu bar retains local Open/Save/Collaborate capabilities. No screenshot or image-comparison verification was used.

## Native verification result

The application build passed, all eight source-only suites passed, and the final header-menu regression passed again after the accessibility fix. The native File menu exposes twelve distinct rows plus one Dark page checkbox through AppKit's unignored button-cell descendants. Accessibility observed Tab→checkbox, Space→on, Space→off, Arrow Down→Presenter mode, and Escape→File trigger. Share options exposed exactly Copy link/Send for signatures; Help exposed exactly Help center/Contact Support/Give Feedback; each Escape returned to its own header trigger. Earlier local starred toggling changed to Remove from starred while keeping the menu open. All test interactions left the sample at page1/2,95%, without PDF edits or sharing. The temporary research tab was closed; the original user tab was left open. No screenshots were used.
