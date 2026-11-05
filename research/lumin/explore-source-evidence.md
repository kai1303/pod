# Lumin Explore source evidence

Inspected the already-downloaded shipped JavaScript/CSS on 2026-11-05. No downloaded JavaScript was executed. This is static source evidence; live account flags, permissions, document state and layout must be verified separately. The implementation should use the parent's live `explore-*-live.json` captures for visible rows and geometry.

All machine-readable files below are local under `research/lumin/toolbar-source/extracted/explore/` (Git-ignored). `manifest.json` records original source file, module ID, character and UTF-8 byte offsets, and excerpt hashes.

## Source map

| Scope | Original source | Relevant location |
| --- | --- | --- |
| Command groups, render, input, guideline, trigger | `0qwcgrq08z83b.js`, module **9358512** | Group builder `im` near char112000; results renderer `ib` near char124000; search input `iO` near127000; container `iR` near129000; trigger `iP` near130000. Exact excerpt offsets are in manifest. |
| Search state | `2wlhxxp1u3z2q.js`, module **392949**, char1193568 | Initial `isOpenQuickSearch:false`, `searchKeyword:null`, `matchedTools:[]`; cleanup resets results. |
| Fuse library | `2wlhxxp1u3z2q.js`, module **3866243**, char104728 | **Fuse 6.6.2**, literal `U.version="6.6.2"` at char118189. Saved bounded module is evidence only. |
| Transliteration | Same bundle, grouped module **4547918** | Function near char2406495 and 901-entry literal map. |
| Layout | `13oun9t944hks.css` | `QuickSearch-module-scss-module__RqliQa__*`, `GroupToolsMenu-module-scss-module__KeY1_a__*`, `QuickSearchGuideline-module-scss-module__E2f4oa__*`. |
| Base Menu / keyboard | `3paunvfp0my3g.js`, exports **1207548**, Mantine Menu module **8172278** | Wrapper near52500; menu defaults near50800; menu item key handlers near43000/48000; dropdown key handler near45300. |
| Global shortcut | `3zmc88ww60v7f.js`, module **9191210** | Static `quickSearch` shortcut: Mac `Option /`, other `Alt /`. |

## Consumable data

- `command-definitions-en.json`: 14 ordered source groups and 76 declared command variants, all English labels resolved from saved locale module6041205 (`13u9fibag1vur.js`); includes search-only groups, feature conditions, toolbar routing and alternate labels. Mutually exclusive View controls versus Grid/Single variants must be filtered before flattening.
- `translations-en.json`: exact guideline and search-tail strings from that locale.
- `search-aliases.json`: exact merged alias dictionary, **77 tool keys**, up to **15 languages** (`de,en,es,fr,id,it,ja,ko,nl,pl,pt,ru,th,vi,zh`).
- `search-aliases-en.json`: English projection.
- `search-alias-key-order.json`: preserve this order for equal alias-rank ties.
- `normalization-map.json`: exact **901-character** transliteration table.
- `search-semantics.json`: options, ranking, state, visibility and keyboard rules in data form.
- `aliases-module-*.json`: original separate literal dictionaries and provenance references.
- `group-builder.source.js`, `results-render.source.js`, `search-input.source.js`, `explore-container.source.js`: exact bounded shipped source for reconstruction.
- `explore.css`: exact matching stylesheet rules.
- `fuse-6.6.2.source.js`: bounded library evidence. If executing Fuse locally, use a pinned licensed official distribution, not captured application bundle code.

The alias dictionaries were recovered by parsing object/array/string literals and `JSON.parse` string payloads without executing the module. JSON key order is preserved and additionally written as a dedicated array. `addParagraph` is present only in aliases, not the current command definitions; any such result is discarded by the renderer because its key has no tool/group lookup entry.

## Exact search algorithm

1. Flatten all command definitions, including search-only groups. Each Fuse item contains at least:

   ```json
   {"key":"type","fuseTitle":"Type","fuseTokens":["Type"]}
   ```

   Display fields such as `title`, original component and group metadata can coexist; Fuse indexes only `fuseTitle` and `fuseTokens`.
2. `fuseTitle = normalize(title)`; `fuseTokens = normalize(title).split(" ")`. The normalizer replaces each character matching `/[^A-Za-z0-9]/g` with its character-table value, or leaves it untouched. It **preserves case and spaces**. This is not generic NFD accent stripping; unmapped Unicode stays as-is.
3. Instantiate **Fuse 6.6.2** with `keys:["fuseTitle","fuseTokens"]`, `includeScore:true`, `includeMatches:true`, `threshold:0.3`.
4. All other library defaults remain: `isCaseSensitive:false`, `shouldSort:true`, `findAllMatches:false`, `minMatchCharLength:1`, `location:0`, `distance:100`, `useExtendedSearch:false`, `ignoreLocation:false`, `ignoreFieldNorm:false`, `fieldNormWeight:1`. Default sorting uses score then original item index. App code additionally sorts score ascending.
5. Search with `Fuse.search(normalize(rawInput))`. Keep result keys in ascending score order.
6. Compute aliases separately: `rawInput.trim().toLowerCase().split(/\s+/)`. For each tool's alias array in the current language, normalize lowercase aliases and query terms; **every query term must be a substring of at least one alias**. Each term gets its first matching alias index. Rank the tool by the minimum of those indexes. If language is missing, use an empty alias list, not English fallback.
7. Sort alias matches by rank ascending, preserving dictionary key order for ties. Append alias result keys **only if not already in Fuse matches**. Fuse matches always precede aliases; this is not a combined score.
8. Dispatch the raw input string plus the merged tool keys. Input processing is **debounced 300 ms**. Input focus is requested after **200 ms** when opened. Closed input is read-only.

Example source aliases: `type` includes `insert,type,add,text,add text,input,fill,form`; `signature` includes `insert,sign,add,signature,add signature`; `shape` includes rectangle/ellipse/arrow/polyline/polygon/cloud/star/cross/tick/circle/line. Literal substring-only title filtering misses these behaviors.

## Rendering and empty results

- Empty query: groups appear in original order; omit `onlyVisibleOnSearch` groups.
- Nonempty query: every matched tool is rendered in its ranked position as an individual group wrapper. **Hide all group labels and default inter-group spacing**. Do not regroup by category, since that would destroy relevance order.
- Append an animated chatbot search row if query is nonempty and chatbot command state permits it.
- Append an animated document-search row for every nonempty query.
- The locale defines `viewer.quickSearch.noResult = "No results found"`, but the inspected component does not reference it. There is **no dedicated “No results” label** in this component. When no tools match, the query-search rows can still remain. Exact wording is resolved by `viewer.quickSearch.searchInChatbot` / `searchInDoc` translations.
- Search-only groups include right utility tools (AI assistant/comments history/print), help links, left viewer controls, rename/focus mode/Sign securely.
- The only default groups containing labels are AgreementGen, conditional AI, conditional mini-apps, Mark up, Security, Fill & Sign, Edit text, Organize, Other, Compress & Convert. Existing `toolbar-catalog.json` already inventories visible groups; this report does not redefine their denominator.

## Visibility conditions

- AI group depends on enabled chatbot; mini-apps depend on marketplace flag.
- Measurement is removed when the SDK measurement feature is absent.
- Office conversion entries are removed without SDK officeConversion.
- Bates numbering is conditional on the new Organize layout.
- Configure-access label is Change password if permission/state permits changing, otherwise Set password.
- Sidebar wording flag selects Annotate/Mark up, Edit PDF/Edit text, Page tools/Organize.
- Search definitions can include entries whose rendered component returns null (permissions, signed-out user, no current document, etc.). The flattened key/title universe and the visible runtime rows are not identical.

## Layout / guideline

- Trigger popover configured **width336**, position `left` with main-axis offset5. On the left mode rail this may flip to the right; use actual placement from live DOM.
- CSS root `quickSearch`: **height500**, padding8, column flex, align-start, overflow hidden. The parent's live capture separately proves outer336×516 and inner320×500; preserve both container levels.
- Search input is full width with a **20 px** `ph-magnifying-glass` glyph (live computed style supersedes the initial static inference) colored core on-secondary-container. Placeholder is Search.
- Result list: width/height100%, flex1, margin-top12, vertical auto overflow; scrollbar10px, transparent track; thumb uses scrollbar token, rounded-lg, 2px transparent border.
- Default groups after the first have margin-top12. Labels have padding4px8px, label-sm typography and surface-on-surface-low foreground.
- Guideline: margin-top8, padding8, gap4, radius-md, information-container background. Header has bottom padding8, NEW badge and small close icon. Close is absolute top-4/right0.
- Guideline hides when `metadata.hasClosedQuickSearchGuideline` is true; dismissal first updates local Redux user metadata optimistically, then calls `updateUserMetadata({key: HAS_CLOSED_QUICK_SEARCH_GUIDELINE,value:true})` through a mutation. Thus it persists across later opens/account sessions rather than merely hiding for the current popup. Do not write remote metadata from the clone preview.
- Opening/closing guideline animation uses opacity/scale (exit scale .85); result/group label fades are .25 seconds. Trigger menu uses fade-right200ms.
- Hovering Explore schedules opening after400ms; mouse leave cancels the pending open. Click toggles immediately. Cleanup resets search and sidebar hover state.

## Keyboard behavior

- Global Mac shortcut is Option + / (other platforms Alt + /). `0-ijaa_iuctuw.js` directly checks `event.altKey && (event.key === "/" || event.which === 191)` and toggles the prior open state. It requires focus mode off, expanded viewer navigation off, original-version preview off. Root handler also skips modal/dialog/signature-modal, document time-limit, rich-text/content-edit/read-aloud, annotations-not-loaded, and active `chatBotInput` contexts. The toggle closure itself does not call `preventDefault`. Exact bounded source is `global-keyboard.source.js`.
- Explore TextInput does **not** declare its own Enter submit handler; do not infer “Enter selects first result.”
- Base Menu traps focus and returns focus on close. Default close-on-item-click is true; Escape close comes from Popover default.
- Menu dropdown's ArrowUp/ArrowDown handler prevents default and focuses the first non-disabled menu item when navigation originates from the dropdown/input.
- Focused menu items use vertical sibling navigation, skip `data-disabled` items and loop. Home/End focus first/last item.
- Keyboard activation of the target toggles initial-focus-placeholder behavior. Exact text-input/event propagation should be confirmed by the parent’s live probes before claiming all key handling matches.

## Source icon and asset references

The parent's live catalog contains authoritative rendered icon classes and asset URLs. Static additional references:

- Mini-app images: `/app/pdf/assets/images/invoice-extraction.svg`, `translate-pdf.svg`, `resume-checker.svg`, each24×24.
- Download/conversion group uses original Phosphor components: ResizeIcon (compress), MicrosoftWordLogoIcon, MicrosoftExcelLogoIcon, MicrosoftPowerpointLogoIcon, FileJpgIcon, FilePngIcon, ArrowLineDownIcon (flatten), ArrowsClockwiseIcon (generic conversion), size24.
- Search-only help links use QuestionIcon, ChatsCircleIcon, feedback icon, plus external-link-sm suffix.
- Select/Pan/Undo/Redo search-only rows use CursorIcon, HandIcon, ArrowUUpLeftIcon, ArrowUUpRightIcon, size24.
- Default tools instantiate the actual source toolbar components inside `ToolbarItemContext(renderAsMenuItem:true,useModal:true,customLabel:title,showOptionButton:false)`. The menu thus omits toolbar dropdown arrows and presents the tool's own icon, shortcut and disabled/premium state.

## Limits

Source extraction is lexical and focused on the Explore implementation and dependencies above. No remote document or account state changed. This report does not claim source code alone proves current feature flags, permission-gated actions, responsive placement or exact pixel rendering; use live DOM/computed-style and native property/geometry checks for those claims. Screenshots are not used for checking, per the user’s instruction.

## Live DOM/CSS verification

`explore-layout-fixture.json` is a clean public fixture from a correctly encoded source tab. It records relative rectangles and computed typography/color/padding/radius values, excluding account or document content. The raw `explore-css-verification-live.json` HTML/computed-style capture remains Git-ignored. This verifies the20px search glyph, input offset27/full32px height, original AgreementGen25.0078125px glyph advance/41.0078125px label offset, source dark color roles and default panel geometry. `lumin_explore_test.swift` compares native frames/font-file identity/theme values and search sequences directly; it does not export or compare screenshots.
