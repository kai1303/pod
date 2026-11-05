# Lumin expanded navigation: shipped-source evidence

This pass statically decomposes the original downloaded JavaScript/CSS and uses the parent’s sanitized live DOM measurements to distinguish active defaults from declared branches. No screenshots, image rendering, browser/native interaction or captured JavaScript execution were performed by this worker. Private recent-document names, URLs, thumbnails and account contents are excluded.

The machine-readable [source rules](/Users/kai/works/side-project/pod/research/lumin/expanded-navigation-source-rules.json) contain57 bounded artifact/excerpt records with original and excerpt SHA256, zero-based character spans and UTF8 byte spans; end offsets are exclusive. Every record is mechanically checked against original bytes. Bounded excerpts and their manifest are in the ignored `toolbar-source/extracted/expanded-navigation/` directory.

## Original source and asset identity

The lazy history loader4819234 resolves to component4958191. Multiple retained loader copies declared different chunk sets. The currently observed `3ybmjzk1ffctr.js` declares `1iy_7psowvg9i.js` and `01n40zifuc5s6.css`; the parent confirmed the exact latter stylesheet link in live DOM, even though the pageAssets inventory omitted it. Downloading those declared/observed public URLs produced the matching component and `DocumentHistoryList…zwY0Ea` selectors:

| Artifact | SHA256 |
| --- | --- |
| `1iy_7psowvg9i.js` | `2e6a3648fa5d265d7942761bb11389d7564be831bfcc839fd259b5eb5ef09d56` |
| `01n40zifuc5s6.css` | `7bf4cc79d3e30111c3e5fe5dee40d33527a0c7cb3ed7f0be9fc7ecd19861cb47` |

Exact download URLs, resolved URLs, MIME types and byte counts are retained in `toolbar-source/expanded-navigation-live/history-direct-downloads.json` and the rules JSON. The last-observed `2eca914jstb3z.js` is English Intl.DisplayNames locale data, not the history component. Runtime registration retains the first existing module factory; inventory order alone does not prove execution order, so the matching module/CSS/live selectors provide the useful reconstruction evidence.

[Icon provenance](/Users/kai/works/side-project/pod/research/lumin/expanded-navigation-icon-sources.json) records literal regular Phosphor paths for CloudArrowUp20, ArrowSquareOut20 and Desktop at CSS18px. All three path-attribute arrays exactly match parent live SVGs. The source IconBase defaults to regular weight and viewBox0 0 256 256. No bundle code was evaluated. Desktop’s original root dimensions are1em, overridden to18px by the dropdown CSS; the extracted display SVG makes that size explicit while retaining its paths/viewBox.

Four original public SVGs were downloaded unchanged: `logo-googledrive-md.svg`, `logo-onedrive-md.svg`, `logo-dropbox-md.svg` and `pdf-xl.svg`. Their URL, MIME, dimensions and SHA256 manifest is `toolbar-source/extracted/expanded-navigation/icons/public-assets-manifest.json`. Provider images are displayed at18px despite differing intrinsic dimensions. All files parse as SVG; no image view or rendering check was used.

## Header and rail state

The feature is available to a signed-in user behind the viewer-navigation flag. The visible expanded state is the Redux flag combined with a current user. The header toggles that flag; the ordinary80px rail becomes276px through the original width variable. Its content switches to upload/history, rather than stretching the mode buttons. Content padding is4px vertically and16px horizontally, with16px gaps and auto height. The mode/footer focus button is absent while expanded; an empty bottom padding container remains.

The header’s expanded left region has fixed276px width, left padding0 and right padding12. Its inner flex uses gap4 and space-between. It contains a text back button with the route’s label, then a close button. Current live label is “My documents”. The back glyph is `kiwi-icon-arrow-narrow-left-md`; close uses `kiwi-icon-x-md`. Both current glyphs are20px and the controls are32px high, radius8, Inter14/500/20 and secondary foreground. Back padding is6px vertically/12px horizontally; close uses6px on every side. Current live frames are back `[8,12,147.21875,32]`, close `[240,12,32,32]`, with glyphs `[20,18,20,20]` and `[246,18,20,20]`. The back content’s icon/text gap is4px. The collapsed header instead uses the hamburger control.

The original keyboard handler explicitly requires `!viewerNavigationSelectors.isExpanded` before Cmd/Ctrl+backslash toggles focus mode. This matches the parent’s independent live checks with both Upload popup closed and BODY focused. The ordinary bottom focus control is also not rendered while expanded. Do not allow the native shortcut to enter focus from this state.

## Upload card and its separate dropdown system

The current upload card is244×86 at x16/y60. It has1px dashed surface-outline border,8px radius,8px padding and8px gap. The header is226×28 with4px vertical padding, original CloudArrowUp20,8px icon/text gap and body-sm12/420/16 caption. The public caption is “Click or drag and drop to upload”. Its role is on-surface. Dark border is#8C9194.

The outlined Upload button is226×32 at x25/y105. It uses Inter14/500/20,8px radius,1px secondary border/foreground and transparent background; effective padding is5px vertically/11px horizontally inside that border. Current dark color is#B2CAD6. The caption/header/card heights follow directly from the border, padding,20px icon and32px button. Outer click or Enter/Space launches the source file picker; the Upload button stops the outer click and opens the provider menu. No file picker or upload action is needed to reconstruct these styles.

The provider menu uses the newer Radix/Tailwind design system, distinct from Kiwi Paper. Static utility names alone did not establish pixel radius: current DS tokens resolve rounded-lg to10px and rounded-md to8px. Parent live DOM confirms a226×136 menu at x25/y141, with4px padding and four32px rows. Rows have6px horizontal/4px vertical padding,8px gap,18px icons,8px radius and Inter14/400/20. The default sequence is From my device, From Google Drive, From OneDrive, From Dropbox. Storage flags, offline, Electron and PWA/file-system support add/remove/disable branches. The PWA “Open from my computer” branch is declared but not part of the current default capture.

| Radix role | Light | Dark |
| --- | --- | --- |
| Popover | #FFFFFF | #171717 |
| Popover text | #0A0A0A | #FAFAFA |
| Focus/hover accent | #F5F5F5 | #404040 |
| Accent text | #171717 | #FAFAFA |
| Muted glyph | #737373 | #A3A3A3 |

These roles come from `36i91pvs6_85-.css` root/dark declarations, corroborated by parent computed dark values. Its font family is Inter, text-sm14/20, radius-md8/radius-lg10. Shadow-md is `0 4px 6px -1px` and `0 2px 4px -2px`, both black10%, plus the dropdown’s1px foreground10% ring. The popup defaults to bottom-start,4px offset, trigger width, min-width128 and100ms animation; the component is nonmodal and nonportaled.

## Recent documents

The online heading is “Recent documents”; offline uses the cached-document heading/list. This is a local recent-document collection, not a remote document-history API: newest entries are prepended, deduplicated by ID and capped at20; stored values and thumbnails are not exported here.

The heading uses Inter12/500/16, padding4px vertically/8px horizontally and4px bottom margin. The current nonempty container is244×68 at x16/y162. Its list has4px row gap, horizontal margin−12, horizontal padding12 and overflow-y auto. Thus the live list box is268px wide at x4/y190 while the actual row is244×40 at x16/y190.

Each item is the regular MenuItemBase rendered as a link:8px padding,8px icon/text gap,8px radius and Inter14/500/20 on-surface text. Current-document ID activates primary-container background, dark#087191. Activated hover’s pseudo-layer also uses primary-container; it does not replace the background with neutral. Clicking a row closes expanded navigation and routes to its document.

Thumbnail is the24px small avatar, with1px outline-variant border,4px radius and22px inner image. It uses object-cover, so a native thumbnail should crop to fill rather than aspect-fit. The image-less branch uses primary-container and the original public `pdf-xl.svg`. The name is nowrap/ellipsis with40px right padding: the current196px text box leaves156px for visible text.

The32×32 action at right4/vertical center is **Open in new tab**, not a remove or menu button. Its original ArrowSquareOut20 has6px padding. The action is opacity0 until list-item hover, fading over200ms. Hover on that action uses an8% on-surface layer with4px radius. Its tooltip is bottom-end/cross-axis20; the document-name tooltip waits1second and is disabled while the action is hovered. The source action prevents the surrounding link and opens another viewer window.

The empty state keeps the heading and adds the public copy “The latest documents you open will be shown here.” Its container has4px top margin,1px dashed outline-variant border,8px radius and4px vertical padding; the empty text has4px/8px padding and Inter12/420/16 on-surface-variant color. Loading and offline branches are declared separately.

## Toolbar budget and verification limits

The expanded navigation adds a260px term to the source toolbar-collapse budget. This is deliberately distinct from actual276px rail width. The recovered maximum right-section width is viewport minus measured common width, right-panel width if open, expanded260, and fixed96+80+50 terms. Resize observation debounces100ms. Replacing260 with276 would alter the original collapse decisions.

The parent’s sanitized DOM files establish the current one-row desktop branch, header/upload metrics, Radix menu and glyph paths. Static source additionally covers empty/loading/offline/PWA/provider conditions. Multiple-row scroll constraints, motion/ripple/focus paths, all conditional branches and exact raster/shadow/dash sampling remain unresolved; one default DOM capture does not prove them. Recent-document persistence, cloud providers, local opening, back destination and new-window actions are functionality and remain deferred per the user’s UI-first instruction. No native application files were edited by this worker.


## Parent implementation and source-only validation

The clean `expanded-navigation-layout-fixture.json` contains the276px rail,1180px toolbar and1176px canvas at1512×834, the expanded back/close header, upload card, current-document row and226×136 upload dropdown. File names, private document URLs and account data are excluded. CloudArrowUp, open-in-new-tab and desktop SVG paths match the shipped regular definitions; the provider and PDF fallback SVGs retain their original public bytes. Seven original public/inline SVGs and unchanged4× display assets are bundled; no source document thumbnail or account content is bundled. Native data uses the current local filename and first-page image already rendered by the existing PDF engine.

The upload popup is Radix rather than Kiwi: neutral background/foreground,10px root,8px rows,14/400/20 text,18px provider artwork and foreground/10 edge. Source keyboard reads prove Down stops at Dropbox and Tab remains inside; parent native AX reads confirm that behavior plus Escape returning focus to Upload. Source Cmd+backslash and Option+slash produce no focus/search UI while expanded; native checks confirm both exclusions and normal focus restoration after collapse. Header close and selecting the current document both restore the mode rail.

The app build, all13 source-only suites,57 source/excerpt hash/span records,7 asset hash/dimension records and git diff --check passed. Native state ended at Popular/Select/page1/95% with Undo disabled. The source returned to collapsed/Popular/focusfalse and its temporary tab closed. No screenshots or image-render checks were used. Code review corrected Upload anchor-toggle behavior, card hover, focused light text and menu edge. Synthetic posted input did not exercise AppKit local monitors and was not retained as evidence; actual controller/action tests and native keyboard checks cover the named scope.

Remaining limits: the native1px inside edge approximates the CSS outset ring; exact outset/shadow/motion/raster states remain open. Long-list/empty-state runtime layout, upload drag/offline/storage branches, complete focus/typeahead/accessibility variants and the rest of the application are not proven. Empty layout follows the shipped box model without a live empty-state capture. Dashboard/cloud/new-window operations are deferred as requested; their downstream UI remains in the overall audit. This pass is progress, not full application parity.
