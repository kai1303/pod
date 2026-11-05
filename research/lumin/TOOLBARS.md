# Lumin toolbar reconstruction

Inspected the [supplied viewer](https://www.luminpdf.com/app/pdf/viewer/building-event-driven-microservices-636b09b620c811cc94d171a5) on 4 November 2026. This combines rendered DOM, computed CSS, a browser-saved HTML page and its downloaded styles/scripts. The machine-readable inventory is [toolbar-catalog.json](toolbar-catalog.json).

## Downloads

All raw files are local under `research/lumin/toolbar-source/`, excluded from Git because the full page includes authenticated account UI. No downloaded JavaScript was executed for extraction.

| Local artifact | Contents |
| --- | --- |
| `markup.html` | 529,885-byte rendered Mark up page |
| `markup_files/` | 528 resources, including 106 CSS and 404 JavaScript files |
| `assets/` | Separate browser asset export: 54 CSS files and Lumin's SVG wordmark, with original URL manifest |
| `brand/lumin-app-icon.png` | Original 180 × 180 app icon, saved through the browser |
| `brand/lumin-favicon.ico` | Original favicon exported through the browser asset capability |
| `extracted/ToolbarInner.html` | Actual toolbar subtree, without document pages or account header |
| `extracted/leftSideBar.html` | Actual mode-navigation subtree |
| `extracted/inline-styles.css` | 140 inline style elements retained by Save Page As |
| `extracted/toolbar-rules.css` | 46 matching toolbar/organizer stylesheet rules, each with source attribution |
| `extracted/styled-toolbar-source.json` | 11 styled-component templates recovered from downloaded JavaScript |
| `extracted/css-token-declarations.json` | 1,463 declarations covering 406 distinct Kiwi token names across the downloaded application CSS |
| `extracted/icon-glyphs.json` | 1,458 icon-class mappings from the downloaded PDF/Kiwi icon CSS |
| `extracted/source-tools.json` | 67 tool identifiers recovered from the source enumeration |
| `extracted/checksums.json` | Local source file sizes and SHA-256 checksums |

Regenerate the extracts with `python3 research/lumin/extract_toolbar_source.py`. This is a lexical source index, not a CSS cascade evaluator or a reconstructed application. Token variants retain selectors and source filenames; nested media/layer context is not resolved. Some styled-component rules are generated at runtime and absent from saved style tags, so their source templates are retained separately. Live computed values are in [the design-system observations](../../design/system/lumin-observations.json).

The initial font requests used an incorrect host and returned403. Later exact-asset passes recovered the original Inter variable, static Inter Medium, PDF/Kiwi icon fonts and navigation SVGs from the actual loaded `static.luminpdf.com` URLs. Original font binaries/codepoints and URL-bound descriptors now drive native rendering; `macos/Resources/Lumin/source-manifest.json` and the active fidelity audit record current evidence.

## Toolbar coverage

| Mode | Controls observed |
| --- | --- |
| Popular | Eraser, Shape, Highlight, Draw, Type, Signature, Add comment, Sign securely |
| Fill & Sign | Prepare form, Cross, Tick, Dot, Stamp, Date, Type, Signature, Sign securely |
| Mark up | OCR, Image, Eraser, Shape, Text tools, Highlight, Draw, Type, Measure, Add comment |
| Edit text | Upgrade gate; Edit content is listed in Explore. The gated editing toolbar was not visible. |
| Security | Redaction, Password protection → Set password / Remove password |
| Organize | Page selection/range, thumbnail size, Bates numbering, Crop, Insert, Split & Extract, Merge |
| Explore | Searchable command menu covering all modes plus AI, mini-apps, file actions, presentation, compression and conversion |

The common viewer controls are thumbnails, zoom, view layout, rotate view, Select and Pan. Editing modes also show Read aloud and Undo/Redo. Footer controls cover zoom and first/previous/current/next/last page. The utility rail exposes search, comments, download, print and copy link. Availability changes with the active workflow.

The catalog records 14 panel/menu families, including ten shapes, three text-markup styles, two highlight types, six measurement types plus scale/snapping, and four form-field controls. Form builder was opened and cancelled. Signature controls were inspected without exporting signature images. Organize's Bates menu and per-page overflow menu were opened without applying operations.

Explore exposes commands beyond the seven main modes. Its full grouped inventory and observed keyboard shortcuts are in the JSON catalog. A source identifier's presence does not prove it is available to this account or works for this document.

## Component rules recovered

The editing toolbar combines Material UI controls, styled-components and Kiwi semantic tokens. The newer Organize toolbar uses Radix-style `data-slot` controls, utility classes and inline SVG icons, while continuing to reference Kiwi colors.

- **Editing shell:** 56 px header, 48 px toolbar, 80 px navigation rail. Toolbar has 8 px padding and 16 px top corner radii.
- **Buttons:** 32 px compact controls, 8 px corner radii; split dropdown trigger uses a 20 px glyph. Main tool glyphs are 24 px. The split wrapper has 1 px padding and a hover overlay; selected child buttons use a semantic container color.
- **Palettes:** 300 px width, 16 px inset, 268 px content width and 16 px section gaps. Fill/Border choices are exclusive 32 px pill controls. Sliders pair with numeric fields and explicit units.
- **Editing text:** Inter, 12 px medium toolbar labels; 14 px medium palette tabs. Selected, hover and disabled states use separate semantic roles.
- **Organizer:** 32 px action buttons; 12 px/500/16 px label typography. `data-density=icons` explicitly hides action labels. Page selection includes a 170 px range input. The thumbnail slider is 96 px wide, with a 16 px thumb and 6 px track in the observed DOM.
- **Responsive behavior:** the source uses `ResizeObserver` and remaining width after sidebar/panel deductions to manage toolbar presentation. Labels are not safe to assume permanently visible. The saved Mark up HTML contains labels that were visually hidden at the observed width.

Source pointers: `markup_files/1vmims6r5cffr.js` contains toolbar composition, width logic and split-button styling; `markup_files/430os3-b8uoa3.js` contains the tool enum; `markup_files/2o2zur-nq3cc9.css` contains organizer labels and density rules. The extracted indexes preserve these filenames.

## Applied to Pod

Pod's [native design system](../../design/system/README.md) adopts the measured dimensions, surface hierarchy, exclusive style choices and explicit control states. It retains the approved open-folio OS icon; the current chrome uses recovered Lumin teal/neutral roles and source fonts/glyphs. Lumin's downloaded app icon remains a research reference.

The raw HTML capture covers Mark up; the remaining mode inventories come from live DOM inspection. This is broad toolbar coverage, not a claim that every nested dialog, premium workflow, cloud service or PDF operation was reproduced or tested. The remote PDF was unchanged, and the viewer was restored to Mark up, Select, page 3 at 149% zoom.

The current zoom/View controls pass replaces the generic preview with the source grid,68×32 field and original eight-row zoom menu. [Source evidence](view-controls-source-evidence.md) and [clean DOM/CSS fixture](view-controls-layout-fixture.json) record declarations, dimensions and runtime state observations. These new choices are local UI state until the requested functionality phase. Source-only checks are available through `script/test_lumin_source_ui.sh`; screenshot comparisons are not used.

The later main-toolbar pass adds exact four-mode grouping, source responsive label/overflow arithmetic,226px thumbnails and280px overflow menus, the default56px utility rail and original sign/AI/marketplace assets. [Main source evidence](main-toolbar-source-evidence.md), [layout fixture](main-toolbar-layout-fixture.json) and [rules data](main-toolbar-source-rules.json) distinguish downloaded declarations, live snapshots and native verification. Organize/gated branches and the remaining panels are still incomplete.
