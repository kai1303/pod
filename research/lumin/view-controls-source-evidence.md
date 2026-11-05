# Lumin View controls and zoom source evidence

Inspected downloaded shipped JavaScript on 2026-11-05. Extraction was lexical; no captured JavaScript was executed. This report describes source declarations and control flow. Live computed CSS/geometry is separate evidence collected by the parent in `toolbar-source/view-controls-live.json`, `zoom-controls-live.json`, and `zoom-field-live.json`. Screenshots are not used for checking.

The bounded snippets and exact source/excerpt hashes live under Git-ignored `research/lumin/toolbar-source/extracted/view-controls/`. `manifest.json` records half-open Unicode character and UTF-8 byte ranges. No account information, document content or authentication data appears in these excerpts.

## Source locations

| Excerpt | Original downloaded file | Character range | UTF-8 byte range |
| --- | --- | --- | --- |
| `zoom-input.source.js` | `1x14mso6dmfsd.js` | 24125–25912 | 24129–25916 |
| `zoom-menu.source.js` | `1x14mso6dmfsd.js` | 41278–43992 | 41282–43996 |
| `zoom-trigger.source.js` | `1x14mso6dmfsd.js` | 42954–43992 | 42958–43996 |
| `view-controls.source.js` | `1vmims6r5cffr.js` | 655115–658253 | 655294–658432 |
| `legacy-icon-button.source.js` | `2wlhxxp1u3z2q.js` | 1908975–1911750 | 1911328–1914103 |
| `zoom-thresholds.source.js` | `2wlhxxp1u3z2q.js` | 1687398–1687755 | 1689741–1690098 |
| `legacy-theme-light.source.js` | `2wlhxxp1u3z2q.js` | 1199401–1218209 | See manifest |
| `legacy-theme-dark.source.js` | `2wlhxxp1u3z2q.js` | 1218215–1236957 | See manifest |

Whole-file SHA-256:

- `1x14mso6dmfsd.js`: `0c4b8f23b6edabdc1d10c5047047424668b0c747c9e6035c929ed33cf8e82608`
- `1vmims6r5cffr.js`: `641d0db6ce76196a3ec71d4bd55c3901e8f241faa5016b568d077405d17d34bd`
- `2wlhxxp1u3z2q.js`: `9524d773cfee5b5d5e8ff236caaa716c8b0b9b25a51d689805fcf692222c0139`

## View controls structure and state

The source `sc-29eda551-0` wrapper is CSS grid: `grid-template-columns: 3fr 1fr 1fr 1fr`, `grid-gap: 8px 16px`, padding16, internal radius16. The outer shared Paper uses its separate radius8. The first row has Page transition, two icon buttons, then an invisible placeholder button. The second has Layout and three icon buttons. The placeholder is explicitly `visibility:hidden; pointer-events:none`; it is not a sixth visible option.

The source `le_body_medium` typography is original Inter, weight420, size14, line-height150% (21px), letter-spacing `-0.6857142857%`. Labels align vertically center. The same module declares five controls:

| Value | Original PDF icon class | Source data-element | Source tooltip key |
| --- | --- | --- | --- |
| default | `md_single_page_view` | `defaultPageTransitionButton` | `option.pageTransition.default` |
| continuous | `md_continues_page_view` | `continuousPageTransitionButton` | `option.pageTransition.continuous` |
| single | `md_one_page_view` | `singleLayoutButton` | `option.layout.single` |
| double | `md_two_page_view` | `doubleLayoutButton` | `option.layout.double` |
| cover | `md_cover_page_view` | `coverLayoutButton` | `generalLayout.toolbar.coverFacingPage` |

All five instantiate source legacy IconButton (`786255`) with iconSize24 and default medium32px size. Picking a transition preserves the layout; picking a layout preserves the transition. The exact source mapping is:

| Page transition | Layout | SDK displayMode |
| --- | --- | --- |
| default | single | Single |
| continuous | single | Continuous |
| default | double | Facing |
| continuous | double | FacingContinuous |
| default | cover | CoverFacing |
| continuous | cover | Cover |

The click callbacks call `setDisplayMode` and do not invoke a popper-close callback. The panel remains open when changing a choice. The toolbar trigger always uses `md_single_page_view` plus its dropdown arrow, regardless of the selected document layout. AI processing disables that trigger.

Live DOM measured outer275.4375×104. The label column was97.71875px and each1fr track32.578125px. Buttons are32×32, with x129.71875 /178.2890625 /226.859375 and y16 /56. The 32px buttons do not stretch to fill their fractional grid tracks. These dimensions come from the parent's live capture, not from a hardcoded source panel width.

## Legacy IconButton state precedence

`sc-77bdab6e-0` declares padding4, radius8 and default32×32/min-width32. Small is20 and large40. Idle foreground uses `le_main_on_surface_variant`; disabled foreground uses `le_disable_on_container`. Hover background uses `le_state_layer_on_surface_variant_hovered`. Active background uses `le_main_primary_container` and active foreground uses `le_main_on_surface`.

**Hover replaces the active background.** The hover selector has an extra pseudo-class, so its specificity beats the active background on the generated base class even though the active declaration appears later. Active foreground remains `le_main_on_surface`. Do not composite an8% overlay on top of the active teal background; the source hover background is the translucent variant role itself. This agrees with the parent's live selected-and-hovered DOM observation.

The active `:before` marker is transparent under the default `NORMAL` activeStyle used by these controls. Other active styles can give it a2px primary-colored marker with60% height, but those styles are not selected here. No dedicated pressed or focus styling is declared in this bounded IconButton wrapper. Global/MUI focus/ripple behavior is outside that bounded negative statement; do not invent a persistent pressed color from theme tokens alone.

## Zoom input and menu behavior

The top toolbar input (`sc-2c6d103c-0`) is68×32, padding `0 4px 0 8px`, radius Kiwi-md8. Wrapper typography declares Inter12/480/135%, but its direct input overrides this with `le_label_medium`: Inter12/460/115%, letter-spacing0. The original20px `sm_down_stroke` suffix and input text use `le_main_on_surface_variant`.

Idle fieldset border is transparent. On focus it becomes1px `le_main_primary`, and the input cursor becomes text. Hover while unfocused uses `le_state_layer_on_surface_variant_hovered`; focused hover instead resolves to `le_main_surface_container`. Focus alone does not declare a field background. The suffix opens the popper; it does not toggle it closed. Focusing the input also opens it. The numeric formatter appends `%` and reports its numeric float value.

The menu is below-start with offset8. Source order is Fit width, Fit height with⌘0, divider,50%,100%,200%,300%, divider, Zoom in with⌘+, Zoom out with⌘-. **Fit actions and percentage presets close the menu; Zoom in/out keep it open.** Enter commits the input but does not close the menu. Click-away commits the current input and closes unless the click target has the zoom input flag. AI processing disables the field and prevents the menu from being open.

A styled `sc-6109516d-2`160px-width declaration exists in the same module but is not assigned or rendered by the current `ej` menu. Do not impose160px from that dead styled declaration. The live menu measures166.4140625×306: padding8, eight32px rows, two1px separators each with8px vertical margins. Live row radius is4; text is Inter14/420 with21px line height. Main text is the legacy on-surface role; shortcut text is legacy on-surface-variant.

The input submission function clamps below5% to5 and above9999% to9999, showing a source toast when out of range. The separate bottom-bar hook rejects invalid values and falls back to current state; it must not be substituted for the top input's clamp semantics. Source ratio step map for zoom-in/out is .075 for[0,.8], .125 for[.8,1.5], .25 for[1.5,2.5], .5 for[2.5,infinity], using the first matching inclusive range at shared endpoints.

## Exact legacy roles

These controls use legacy roles mixed with the newer Kiwi Paper surface. Do not replace their foreground roles with the similarly named newer text colors.

| Role | Light | Dark |
| --- | --- | --- |
| `le_main_on_surface` | `#161C21` | `#E3E5E8` |
| `le_main_on_surface_variant` | `#325167` | `#BCCFDC` |
| `le_main_primary` | `#087191` | `#74D6F1` |
| `le_main_primary_container` | `#C4F0FD` | `#087191` |
| `le_main_surface_container` | `#EEEFF1` | `#1A2025` |
| `le_main_outline_variant` | `#BCCFDC` | `#325167` |
| `le_state_layer_on_surface_hovered` | `rgba(22,28,33,.08)` | `rgba(227,229,232,.08)` |
| `le_state_layer_on_surface_variant_hovered` | `rgba(50,81,103,.08)` | `rgba(188,207,220,.08)` |
| `le_state_layer_on_surface_pressed` | `rgba(22,28,33,.12)` | `rgba(227,229,232,.12)` |
| `le_state_layer_on_surface_variant_pressed` | `rgba(50,81,103,.12)` | `rgba(188,207,220,.12)` |
| `le_disable_on_container` | `rgba(22,28,33,.38)` | `rgba(228,231,236,.38)` |

Theme JSON and each role's exact source character offset are in the ignored extraction manifest. Pressed-role declarations in this table do not prove these components consume them. The current source report does not claim native PDF layout/zoom behavior has been implemented, light mode has been exercised live, or all MUI/global focus behavior is covered.

## Zoom focus and keyboard scope

This follow-up inspects only the Zoom component, MenuList dependency and Popper dependency. The current Zoom `ej` passes **children only** to `eR.default` (module2628430). That wrapper forwards remaining props unchanged to MUI MenuList4405964 and adds styles/context; it does not set focus props or forward input key events into the list.

MenuList defaults are `autoFocus:false`, `autoFocusItem:false`, `disabledItemsFocusable:false`, `disableListWrap:false`, `variant:"selectedMenu"`. It adds `role="menu"`, list `tabIndex:-1` (0 only when autoFocus is true), and `tabIndex:0` to the first eligible child. That child receives an `autoFocus` prop only when autoFocusItem is true. Thus being the first tabbable item does **not** itself focus the menu or its first row.

The list's own `onKeyDown` handles ArrowDown/ArrowUp, Home/End, and one-character typeahead with a500ms reset window. Navigation wraps by default and skips disabled/non-tabbable nodes. The handler is attached to the list UL, not to the overall toolbar or Zoom input. In `eF`, input and Popper are siblings in a fragment; the menu UL is inside the Popper sibling. Therefore typing-field ArrowUp/Down/Home/End events do not bubble through the menu UL. The input's explicit handler checks only Enter and commits its percentage. Preserve input focus and ordinary text editing until focus enters the list; then apply list navigation.

The `d.default` import in the Zoom wrapper is MUI Popper2181483. That forwards to base Popper1511446, which manages placement, flip/overflow, mounting and portal rendering. Neither bounded module introduces a focus trap, autofocus, global key handler or input-to-list keyboard bridge. Zoom passes `disablePortal:true`, placement bottom-start and offset8; these do not change the sibling event topology above. This is not a claim about unrelated global shortcuts.

Additional bounded provenance (half-open character ranges):

| Excerpt | Downloaded source | Character range |
| --- | --- | --- |
| `menu-list-wrapper.source.js` | `3ecqp71ogrms5.js` | 27662–27951 |
| `mui-menu-list-keyboard.source.js` | `2syt59692jqqx.js` | 7652–11782 |
| `zoom-popper-focus.source.js` | `2wlhxxp1u3z2q.js` | 59492–63839 |
| `zoom-wrapper-imports.source.js` | `1x14mso6dmfsd.js` | 18531–18925 |

Exact byte ranges, source hashes and excerpt hashes remain in `extracted/view-controls/manifest.json`; these modules were read, not executed.
