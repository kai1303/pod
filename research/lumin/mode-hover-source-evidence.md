# Lumin mode-rail hover menus: shipped-source evidence

This pass traces the existing downloaded viewer artifacts without executing captured JavaScript, taking screenshots, operating the browser, or changing native implementation files. It supplements the parent’s current live DOM captures. Static declarations, runtime-dependent conditions and parent-observed values are kept distinct.

The machine-readable result is `research/lumin/mode-hover-source-rules.json`. All39 bounded source records retain original artifact SHA256, excerpt SHA256, zero-based character spans and UTF8 byte spans (ends exclusive). The bounded excerpts and their manifest are under the ignored `research/lumin/toolbar-source/extracted/mode-hover/` directory. Every hash and both span representations were checked against the original bytes.

## Key source chain

| Evidence | Original artifact | Character span |
| --- | --- | --- |
| navigation-hover.source.js | 0qwcgrq08z83b.js | 133272–136999 |
| tool-registry.source.js | 1vmims6r5cffr.js | 798454–803362 |
| tool-menu-action.source.js | 1vmims6r5cffr.js | 102453–103049 |
| legacy-menu-tool-renderer.source.js | 1vmims6r5cffr.js | 795403–797098 |
| mantine-menu-hover.source.js | 3paunvfp0my3g.js | 49896–54055 |
| menu-item.css | 0hmqw_9wcmxid.css | 287715–290261 |
| legacy-highlight-menu-item.source.js | 3ecqp71ogrms5.js | 20880–27661 |
| highlight-navigation.source.js | 1vmims6r5cffr.js | 702930–709447 |
| form-navigation.source.js | 1vmims6r5cffr.js | 713012–722896 |
| form-navigation.css | 2bovcb6362u_6.css | 104469–104943 |
| sign-navigation.source.js | 1vmims6r5cffr.js | 736748–738074 |
| sign-navigation.css | 2orfcd3fei0sw.css | 7526–8927 |
| password-navigation.source.js | 1vmims6r5cffr.js | 649465–653513 |
| organize-tool-definitions.source.js | 1vmims6r5cffr.js | 681094–691637 |

## Hover state and placement

The collapsed navigation component uses a controlled280px Menu, hover trigger, declared `left-start`, main-axis offset5/cross-axis−24,400ms open delay, `fade-right` transition200ms, and a200ms delayed clear of the hovered tab. The underlying Mantine Menu defaults to100ms close delay. The400ms delays from the navigation state and Menu target occur in parallel, rather than adding to800ms. Parent DOM determines the effective flipped placement; a rail at the viewer’s left edge can flip the declared left placement to right-start.

Hover changes the hovered tab only; it does not change the selected toolbar. Focus mode, an already-open Quick Search, Edit text and a guard suppressed by clicking can block opening. Leaving resets the click guard and cancels a pending hover open. Edit text explicitly disables the ordinary hover Menu. Clicking a different mode selects that mode; clicking tools can switch mode through ToolbarItemContext before the tool action. The source applies document, offline, permission and premium checks, so a captured menu is one runtime branch.

## Registry order versus rendered rows

`useGetRightSectionTools` declares toolbar lists, then creates menuTools by reversing them, removing dividers, and appending `form_builder` and `sign_send` at the end. Security deliberately uses the unreversed tools list. Components can expand into multiple rows or rich sections, so a registry entry is not proof of one menu row.

| Mode | Rendered sequence / conditions |
| --- | --- |
| Popular | Comment, Signature, Type, Draw, Text highlight, Freehand highlight, Shape, Eraser; rich Lumin Sign footer |
| Fill & Sign | Signature, Type, Date, Stamp, Dot, Tick, Cross; Form builder heading, Prepare form and conditional AI auto-detect; rich Lumin Sign footer |
| Mark up | Comment, conditional Measure, Type, Draw, Text highlight, Freehand highlight, Text tools, Shape, Eraser, Image, conditional Perform OCR |
| Security | Redaction; conditional Set password or Change password; Remove password |
| Organize | Conditional Bates numbering, Merge, Split & Extract, Rotate, Delete, Move, Insert blank pages, Crop |

Measurement is conditioned on the SDK measurement feature. OCR supports specific source storage services. Bates numbering is appended only in the newer Organize layout. Auto-detect requires its feature, a non-system document and online state. Set/Change/Remove password follow canSet/canChange/canDelete, template, user and offline/permission conditions.

## Ordinary rows

The legacy toolbar renderer uses Kiwi MenuItem in regular size: minimum40px height,8px padding,8px radius,8px gap, original24px glyphs and Inter14/500/20 labels. The surface is bright: dark#282B2C/light#FFFFFF. Default text uses on-surface dark#E1E2E4/light#191C1D. Hover and pressed use8%/12% on-surface state layers. Disabled opacity38% applies to the whole row; child computed colors remain their original value. Activated rows use primary-container dark#087191/light#C4F0FD; their pseudo-layer also uses primary-container.

Ordinary rail menus explicitly pass showOptionButton=false, so split-tool chevrons/dividers are absent. The renderer only shows shortcut suffixes when Quick Search is open, which excludes these menus. Tooltips can still contain shortcut text. The shared action wrapper exits read-aloud, calls the navigation switch for non-premium tools, then performs the tool action unless a source conversion modal intercepts. Normal available non-premium rows close the menu; Signature and Stamp are exceptions because their nested picker needs to stay open. Premium paths use availability modals.

## Highlight’s two legacy Mui rows

Highlight detects navigation context when mounted and renders both Text highlight and Freehand highlight directly. Descriptions and actual suffix buttons are removed. However, it still passes a renderSuffix function; that causes the shared Mui MenuItem to retain an empty64px suffix wrapper,16px right margin for the text wrapper, and zero right padding. The24px icon has an8px right margin but no flex-shrink:0. Parent DOM measured23.8359375px glyph width and text x47.8359375. This is a real flex-layout effect, not a different source icon.

The rows use the legacy icon component plus new Text(label,md) labels. The latter are Inter14/500/20 and on-surface, while the legacy icon paint role differs. Parent DOM observed icon#E3E5E8 and label#E1E2E4. The ordinary menu’s generic24px icon placement therefore cannot be reused blindly for these rows. Clicking an available highlight exits read-aloud, switches navigation if needed, closes the rail menu and switches the appropriate highlight tool. Unavailable actions enter the premium path.

## Prepare form expansion

The source returns FormBuilderTool.popoverWrapper with margin-top8, an absolute divider at top0,left−8,width100%+16, then a title and two conditional menu rows. The title translation is generalLayout.toolProperties.formBuilder; parent HTML confirms “Form builder”. Its padding is12px8px8px. Kiwi title-sm declares14/500/20; the old module declares font-weight700, but the parent’s current computed DOM confirms500. The700 declaration is overridden or ineffective in this runtime; its mere presence does not justify drawing700.

The next row uses pencil-lg24 and translation customizeFields, currently “Prepare form”. AI auto-detect uses sparkles-lg24, with loading skeleton icon/text branches and no-user/quota/sync disabled states. The current captured title box is264×40 with the48px margin/title region after Cross. Do not represent this whole entry as a single normal “Prepare form” row.

## Lumin Sign footer

`sign_send` does not render an ordinary “Sign securely” row in a navigation menu. The renderAsMenuItem branch uses margin-top8,padding8 and an absolute full-menu divider; a body-md paragraph with8px vertical padding; then a full-width filled lumin_sign button. Parent HTML resolves the paragraph to “Digitally sign your documents with Lumin Sign” and the button to “Request signatures”.

The paragraph uses Inter14/420/20 and wraps to two text lines at248px width, making a56px padded box. The button’s default md size is32px high,6px12px padding,radius8,Inter14/500/20 and original LmSignatureIcon20. Dark paint is#3A28C0/#D0CCFF; light is#D0CCFF/#160F57. Parent DOM measured264×104 wrapper,248×56 description and248×32 button. With eight40px rows, outer padding and margin, Popular is280×448. Fill & Sign’s expanded Form builder section makes its captured total280×536.

## Organize original glyphs

The source declares pdf-icon-md_crop,md_insert,md_move,md_delete,md_rotate,md_split andmd_merge. Bates numbering uses kiwi-icon-ph-list-numbers. The menu labels are the tool-specific labels, not Quick Search’s longer “Rotate pages”/“Move pages” variants. Premium badges remain availability-dependent for Bates and Split.

## Remaining uncertainty

The parent’s live DOM captures are authoritative for current feature/premium/password branches, font cascade, final placement and menu heights. Static code alone does not prove those runtime values. Full keyboard focus/loop behavior, pointer crossing and close timing, tooltip delays, selected/pressed branches, all account/document states and raster glyph/text/shadow fidelity remain separate verification work. No private document, account or signature contents are included in this report or the bounded excerpts.


## Parent live DOM corroboration and implementation

Five current source menus were captured through native pointer movement and read-only DOM/computed styles; no screenshots or captured JavaScript execution were used. The clean fixture is `mode-hover-layout-fixture.json`. Popular/Fill & Sign/Mark up/Security/Organize measure280×448/536/456/136/336 respectively. At1512×834, effective placement is right-start, x81 and each anchor's top minus24. The original declared left-start placement flips at the left viewport boundary. Edit text produced no menu. Hovering other modes left Popular selected.

The original LmSignatureIcon path data in the footer exactly matches the bundled `Toolbar/sign-logo.svg`. Premium badges have4px inner label spacing, distinct from the8px icon/label section gap. The Form builder heading's live computed font is14/500/20. Security's disabled direct-text label keeps the ordinary216px label slot. Popular keyboard traversal was directly observed as Comment→Signature→Type→Draw→Shape→Eraser→Comment, skipping the legacy Mui highlight rows and the signing button.

`LuminModeMenu.swift` reproduces these default desktop branches, including original Organize glyphs, mixed legacy highlight geometry/colors, the form section and the rich signing footer. `LuminPopper` adds opt-in side start/end alignment while retaining centered defaults for existing side poppers. ViewerChrome implements400ms delayed opening,100ms pointer exit close, target-to-menu cancellation,200ms anchor-state clearing, click suppression and host-mode/Type routing. Signature opens as a child without replacing the parent. A review found that child-window keys could reach the parent menu; a failing-then-passing regression now verifies window-scoped keyboard handling.

Cloud actions remain deferred. Stamp/premium/form/security/organize downstream UI, alternate account/document/feature branches, source fade/ripple/tooltips, complete focus/keyboard paint and exact text/shadow rasterization remain open. These default-state checks do not establish full application parity.


## Follow-up: Escape with Signature nested under a rail menu

Seven additional bounded excerpts trace this branch. Signature controller1561561 uses the shared9123382 tool popup. That popup passes disablePortal=true to its underlying MUI Popper and wraps it with5452091. The wrapper registers useKey(“Escape”,close). Hook5520012 defaults to keydown, and8094186 defaults its target to window; neither hook stops propagation or prevents default.

Separately, the parent Mantine Popover.Dropdown has an onKeyDownCapture handler that calls onClose/onDismiss for Escape, and Popover’s default closeOnEscape is true. When focus remains in the parent dropdown or is inside its nonportaled child, this capture path predicts closure/unmounting of both parent and Signature. That is an event-path inference from shipped code, not a static observation of focus or animation timing. The parent independently checked live DOM after the transition settled and found both absent; its clean runtime fixture owns that observation. No native Escape behavior was changed for this follow-up.


Final validation: all twelve source-only suites and the final app build passed. The focused geometry suite passed after an additional font-metric refinement: the original Highlight glyph advances are24px, so native paint remains24px while the source flex box is23.8359375px. Source/excerpt hashes and spans pass for39 records. A native component probe using the actual ViewerChrome/menu classes verified the menu AX tree, Down/Down/Return opening the Signature child, child-arrow isolation and Escape closing both panels. Live source showed the same settled Escape result; its immediate transition DOM still contained both panels. Main-app pointer-hover delivery was not established through CUA; actual controller callbacks/timers/windows are covered by the integration test. The final app was reloaded at Popular/Select/page1/95%, with Undo disabled. The source and temporary probe were closed. Screenshots and image-render checking were not used.
