# Lumin dropdown source evidence

Read-only extraction from downloaded source on 2026-11-04. These are static source facts, not a claim that every feature branch is active in the supplied account. Use live DOM measurements to choose between legacy and v2 branches.

Exact bounded source excerpts are retained locally under `research/lumin/toolbar-source/extracted/dropdown-modules/`, with source filenames/module IDs/byte offsets in `manifest.json`. No downloaded code was executed. Raw captures remain Git-ignored.

## Shared palette and primitives

| Component | Source | Exact rules / structure |
| --- | --- | --- |
| Base style palette | `16ymg1nau8f0s.js`, module 7372858, `sc-36ca6eb1-0`, `data-cy=base_style_palette_wrapper` | Column flex, gap `le_gap_2` = 16 px. Default padding 16 px. If configured width is finite: `maxWidth=configured`, `width:100%`, `minWidth:300`. Source maximum widths are not necessarily the final rendered widths. |
| Tool popper | `1tn7lso3420mt.js`, module 9123382 | Default inner `maxWidth:300`; configured `containerMaxWidth` also becomes inner width. Fixed popper strategy, viewport overflow padding 8; default bottom-end; elevation 5; click-away close. `paperProps` can override overflow. Quick-search mode offset `[0,16]`. |
| Spacing | `2wlhxxp1u3z2q.js`, module 6126816 | `le_gap_0_25=2`, `_0_5=4`, `_1=8`, `_1_25=10`, `_1_5=12`, `_2=16`, `_3=24`, `_4=32`. |
| Title small | `2wlhxxp1u3z2q.js`, module 8130060 | Inter 14 px, weight 520, line-height 170%, letter-spacing -0.6857142857%. |
| Label medium | Same | Inter 12 px, weight 460, line-height 115%, letter-spacing 0. |
| Label large | Same | Inter 14 px, weight 520, line-height 115%, letter-spacing -0.6857142857%. |
| Body medium | Same | Inter 14 px, weight 420, line-height 150%, letter-spacing -0.6857142857%. |

## Shapes

`16ymg1nau8f0s.js`, module **2189580**, source excerpt `shape.source.js`.

- Outer `sc-41817255-3`: column gap 16.
- Heading/grid group `sc-41817255-0`: column gap 8.
- Heading `sc-41817255-1`: `le_title_small`, `le_main_on_surface`.
- Shape icons grid `sc-41817255-2`: **seven equal columns**, gap 8 px. The ten source tools fill seven then three slots; native SF Symbols are not the source glyphs.
- Then frame palette (module 7033557), then opacity (module 6422015) **with heading**.
- Base palette factory configured maximum 313; actual supplied viewer previously measured 300. Do not substitute max-width for the live box width.

## Fill / Border line tabs

`16ymg1nau8f0s.js`, module **7033557**, and `0okfv-1m_fl0f.js` tab component `sc-4fb83bf3-0`.

- `sc-7a464921-0` title: `le_title_small`, bottom margin 8.
- `sc-7a464921-2` track: height **32 px**, bottom margin 8, background `le_main_surface_container_lowest`, pill radius 9999999.
- Tab itself: Inter label large, padding **8px 18px**, equal available width, pill radius. Default foreground `le_main_on_surface_variant`; hover `le_state_layer_on_surface_hovered`; selected foreground `le_main_on_primary_container`, selected background `le_main_primary_container`; disabled opacity .5.
- Initial available palette selection uses first supported property in `[FillColor, StrokeColor]`.
- Fill view contains only color palette, `includeNoFill:true`.
- Border view contains color palette then stroke-width row. Both use `sc-7a464921-4` column gap 8 and color palette padding-left 4.
- Shape source always includes tabs, with unsupported tabs disabled according to tool data; do not remove the visual tab merely because one property is unsupported.

## Color palette / picker

`1f--bcbx6doxs.js`, modules **7631469**, **82830**.

- Wrapper `sc-687e5858-0`: flex wrap, align center, justify space-between, overflow visible, children flex-shrink 0.
- Color cell `sc-687e5858-1`, `data-cy=color_cell`: **22 × 22 px** (free-text variant 18 × 18); circle; 1 px `--kiwi-colors-surface-outline-variant` border; pointer cursor.
- Selected: **1 px** outline `--kiwi-colors-surface-on-surface`, outline-offset **2 px**. This is not an accent-color ring.
- Click target pseudo-element inset -3 px.
- No-fill cell: transparent, outline border, 1 px diagonal slash **#F2385A** at -45 degrees.
- Disabled cell: pointer-events none, opacity .5. Whole disabled palette applies .5 to children.
- Seven standard colors plus custom-picker trigger; optional no-fill is an additional cell. Custom colors are user-dependent and scope-specific; do not assume a fresh user's palette exactly matches a logged-in user's.
- No native macOS `NSColorWell` appears in source. Custom picker is module-dependent ChromePicker-style UI; its surrounding source in `16ymg1nau8f0s.js` uses `kiwi_colors_surface_surface_bright`, min-width 205 px.

Default source colors (`2zdt-fptlpnpz.js`, module **1448411**):

| Palette | RGBA colors, all alpha 1 |
| --- | --- |
| Fill/stroke/type | (0,0,0), (215,48,39), (69,117,180), (90,180,172), (254,224,144), (224,243,248), (255,255,255) |
| Highlight | (254,224,139), (252,141,89), (255,255,191), (230,245,152), (153,213,148), (50,136,189), (213,62,79) |
| Comment palette constant | (3,89,112), (69,117,180), (90,180,172), (127,191,123), (215,48,39), (253,174,107), (175,141,195) |

The comment constant is defined but not mapped to Sticky in this module's `PALETTE_TYPE_MAPPER`; use live DOM to determine whether the fallback palette is actually used. This is a concrete static/runtime distinction.

## Stroke width / eraser

`3y9v4kdmzf0qu.js` (also duplicated in `1f--bcbx6doxs.js`), module **2798867**; embedded slider module **3245585**.

- Outer `sc-7fe7a05-0`: height **32 px**, width 100%.
- Row `sc-7fe7a05-1`: flex row wrap, align center, min-width0, **16 px gap**.
- Leading **24 px `md_stroke`** glyph, then flexible slider, then numeric field if not hidden.
- Numeric field wrapper max-width60; input padding-left0; unit `pt` inside field adornment.
- Thumb **16 × 16 px**, color `le_main_inverse_surface`, border1 `le_main_outline`, no shadow; thumb after zero size.
- Track `le_main_on_surface_variant`, left/right margin -2 px. Rail `le_main_outline_variant`, opacity1, left/right -2, width calc(100% + 4px).
- Eraser wrapper in `1vmims6r5cffr.js` at offset ~692867 uses max32, min8, step8, marks=true, **hideInput=true**; base palette configured max304; outer popper max312. Native arbitrary 0–100 slider is incorrect.

## Opacity

`16ymg1nau8f0s.js`, module **6422015**, `data-cy=opacity_slider_wrapper` / `opacity_input_wrapper`.

- Outer `sc-9ac6ae0c-8`: column, gap4. Optional `le_title_small` heading.
- Row `sc-9ac6ae0c-0`: flex row wrap, min-width0, gap16.
- Flexible slider has **12 px high rounded track**. Bottom layer white→black horizontal gradient; top layer 16px checkerboard PNG embedded as a data URL, border1 `le_main_outline_variant`. Both centered with translateY(calc(-50% - 2px)).
- Material slider rail/track opacity0 so the custom background is visible. Thumb background `le_main_surface`, border1 `le_main_outline`.
- Numeric input fixed **60 px**, percent adornment inside the field; range 0–100, rounds to integer.
- A native single-color macOS slider and external % label do not match this source.

## Text tools

`16ymg1nau8f0s.js`, module **670272**.

- Factory maximum274, subject to common min300 rule.
- **One horizontal heading row**: flex-grow title `Choose style` on left, three icons on right, icon gap8 (`sc-3c93f07b-0..2`).
- Divider immediately below heading row with margin0.
- Color palette, then opacity row **without separate heading**.
- Existing native vertical title + a second full-width icon row differs.

## Draw

`16ymg1nau8f0s.js`, module **628246**, `sc-4279ee07-0`.

- Column gap **8 px** inside base wrapper configured max304.
- Order: stroke-width row, stroke-color palette, opacity row. No section heading and no separate Opacity heading.

## Highlight dropdown

`1vmims6r5cffr.js`, excerpt offsets 701000–708500.

- Actual legacy branch is two menu items: text highlight `(H)`, then freehand highlight with explanatory description. Each has a **24 px `md_more_horizontal_menu`** suffix button opening its style subpanel.
- Text subpanel reuses text-tools style palette (no tools header), freehand subpanel reuses Draw palette.
- V2 branch also exists: width283 outer menu; per-item submenu **236 px width**, padding10, side offset8, align offset-4. Do not apply this branch unless the live source is running it.

## Type floating toolbar

`1vmims6r5cffr.js`, bounded excerpt **462900–469400**; CSS `2bovcb6362u_6.css`, prefix `FreeTextToolbar-module-scss-module__9yfyKW__`.

- This is a **horizontal floating toolbar**, not a vertical font popover.
- Order: family select (**108 px**) → divider → size select (**78 px**) → divider → text decoration controls → divider → text color → text frame → divider → opacity.
- Font select displays each option in its own font; source uses Inter/default style and all available source font families.
- Text color trigger: text-T glyph above **20 × 4 px color bar**; popover width278.
- Text frame trigger: **20 × 20 px**, current fill/outline. Frame panel has Fill section then Border line section, gap16, heading bottom padding8.
- Opacity trigger: masked **17 × 24 px drop icon** plus percentage, gap8; its popover reuses opacity row.
- Frame/opacity generic popover default width304, bottom-start, dense padding. Select wrappers remove borders and focus-within borders.
- Exact CSS rules copied to `extracted/dropdown-modules/free-text-toolbar.css`. Source assets include `/pdf-assets/images/drop.png` and `/pdf-assets/images/empty.png`.

## Signature dropdown

`1vmims6r5cffr.js`, bounded excerpt **761000–778800**, component family `sc-e71e988-*`.

- Live dropdown is a **saved-signature list**, not the Draw/Type/Upload creation dialog.
- Body text uses `le_body_small`; section heading uses `le_title_small`, margin-bottom4.
- Add signature button `sc-6caa2aed-0`: **48 px high**, full width, **1 px dashed** `le_main_outline` border, radius8, `le_label_large`, leading icon margin4.
- Each saved signature `sc-e71e988-6`: height64, padding8, radius8, background `le_signature_signature_container`, foreground `le_signature_on_signature_container`, flex centered, overflow hidden. Hover/drag overlays use dedicated signature state-layer roles. Disabled opacity .5.
- Per-signature delete controls absolute top4/right4, gap4. Signature image centered, height calc(100% - 16px).
- Repeat checkbox and certification CTA are separate entries. The source also contains v2 signature UI. Use live screenshot to select branch and avoid exporting user's saved signature content.

## Fidelity gaps to remove

1. SF Symbols/system font versus source PDF/Kiwi icon glyphs and variable Inter.
2. Native sliders, native pop-up selects and native color well versus custom source controls.
3. Generic vertical Type/Signature preview panels instead of the actual toolbar/saved-signature dropdown.
4. Wrong eraser range/marks and wrong Opacity track.
5. Text-tools heading/icon arrangement and missing divider.
6. Coral/sand interaction tokens versus source teal/neutral tokens when exact Lumin appearance is requested.


## Live color-picker states — follow-up

The source override is module **3872256**; confirmation component **2257615**. Bounded source and checksum/byte offsets are in `extracted/dropdown-modules/color-picker.source.js` and `color-picker-manifest.json`. Live captures are `color-picker-live.json` (transparent initial fill) and `color-picker-hex-live.json` (opaque text color).

- Outer205 ×297.7421875, padding8, raised Kiwi surface, radius8. Saturation189 ×103.9453125 (55% width). Preview10 ×10; its column is22 wide. Hue167 ×10, 16 px below saturation. Hue handle12 ×12, white with shadow; saturation marker12 ×12 with white inset ring.
- Input top157.4453125 relative to picker; input height21. Three RGB/HSL fields48.33 wide, horizontal gap6. One Hex field157 wide. Labels start190.7421875. Format toggle is the original24px inline SVG.
- The initial branch depends on alpha: opaque colors start **Hex**, transparent “No fill” starts **RGB**. Opaque colors cycle Hex → RGB → HSL → Hex. Non-opaque drafts skip Hex. No alpha slider is displayed. The initial transparent-fill capture alone did not prove the opaque branch; the later source/code capture corrected that assumption.
- Confirm and Cancel are189 ×32, y217.7421875 and257.7421875, gap8. Confirm uses Kiwi core secondary/on-secondary; Cancel is outlined. The fields/labels use legacy theme roles: dark text `#BCCFDC`, border `#325167`; light text `#325167`, border `#BCCFDC`.
- The source keeps changes in local draft state, commits an opaque RGBA only on Confirm, then appends the custom color to the scoped seven-color row. Cancel discards the draft. Scope history is account metadata in the source; Pod currently retains the selected custom color locally and does not call Lumin's service.
