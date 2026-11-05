# Pod

A native PDF engine written from scratch in Zig, with speed, executable size and explicit memory ownership as design constraints. It includes a native macOS editor, CPU and Metal renderers, a library and a CLI for the supported PDF subset. It has no PDF library dependencies.

## Native macOS app

The editor now uses bundled React/shadcn controls around the existing native PDF canvas and Zig engine. Building also requires Node/npm; the resulting app runs without a web server. See [native editor integration](web/docs/native-editor.md) and run `./script/test_react_editor.sh` for the screenshot-free WKWebView and sample-engine checks.

On Apple Silicon with macOS 14 or later, Xcode command-line tools and the pinned Zig compiler:

```sh
./script/build_and_run.sh             # build and open dist/Pod.app
./script/build_and_run.sh --build     # build only
./script/test_macos.sh                # engine, C/Swift bridge and independent reader checks
./script/test_lumin_source_ui.sh      # original assets and DOM/CSS geometry/style/state checks; no images
```

The Codex Run action uses the same launch script. A two-page sample is included. Open a supported PDF, select text to replace it, or use the Mark up toolbar. Save a Copy writes a new file; the input is preserved. Quit an existing Pod instance after saving before launching the updated build.

Use **Pages** in the toolbar or menu bar to:

- **Merge PDF:** append another supported document, preserving its page content and Pod markup.
- **Extract Pages:** export a selection such as `1, 3-5` into a new PDF without changing the open document.
- **Split into Separate Pages:** create a new uniquely named folder with one PDF per page.
- **Reorder Pages / Move Page Earlier or Later:** change page order with undo/redo.
- **Rotate / Crop / Reset Crop:** change the current page's standard PDF rotation or crop box; selection and markup follow the displayed geometry.

Page operations retain the current supported subset. Merge, extract, split and reorder refuse document-level metadata/relationships (including Info, outlines, forms and named destinations) or unsupported page dictionaries rather than silently dropping them. Page numbers must be valid and unique; reorder requires every page exactly once. Cropping only changes visibility, **not permanent redaction**. Exports never overwrite existing files. All editing remains in memory until Save a Copy.

The Lumin-inspired markup palettes were reconstructed from live DOM/CSS observations, using native AppKit controls. Eighteen annotation variants are implemented: rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick, text highlight, freehand highlight, underline, squiggly underline, strikeout, ink, free text and comment. They are stored as PDF annotations with appearance streams, and survive save/reopen in other readers. Select annotations to move, resize, change styles or delete; Delete removes the selected annotation. Undo/redo restores document snapshots. Click successive points for polyline/polygon, then Return or double-click to finish; Escape cancels. Text markup selects whole supported text runs.

Press **F** to draw. Tap for a dot or drag for a smooth line. Strokes started within 100 ms of the previous lift on the same page form one editable ink annotation. Click **Draw** again and select the ink to move it, drag its round handle to rotate it, or change its style in the inspector. Brush across the ink with **Eraser** to cut out a section. The surviving lines stay together. **Delete** removes the whole selected drawing. Undo restores either action in one step.

The ongoing Lumin UI reconstruction uses original source fonts/icons and HTML/CSS-derived controls. Explore, Type, the shared color picker and zoom/View controls have source-derived implementations. In the default editor, the **View and navigation** group includes thumbnails and PDF outlines, animated page layouts, counterclockwise view rotation, Select, Pan, Undo and Redo. Choose a page in a continuous or two-page reading layout to edit it. View rotation leaves the saved PDF orientation intact. [The active fidelity audit](research/lumin/FIDELITY.md) records the remaining work.

Zig parses, edits and writes the PDF, decodes TrueType outlines and expands strokes. On macOS the editor sends those outlines to Metal in PDF paint order. A compute shader paints the visible viewport with the same 4 × 4 coverage rule as the Zig CPU rasterizer. Scrolling reuses the page geometry. Zooming out can reuse it too, while finer geometry or a one-pixel hairline requires a new scene. Editor controls and document thumbnails use a separate preview up to 512 pixels wide.

Pod falls back to CPU rendering when Metal is unavailable or a page exceeds the GPU path's precision or complexity limits. To force CPU rendering for comparison, launch the built executable with `POD_RENDERER=cpu dist/Pod.app/Contents/MacOS/Pod`. The native tests compare CPU and GPU pixels and exercise scrolled viewports. Run `POD_REQUIRE_METAL=1 ./script/test_react_editor.sh` on a Metal Mac to check presentation, zoom and scrolling through the editor. **PDFKit is used only by independent test tools and is not linked into or bundled with the application.** The renderer reads the installed Courier New font as a substitute without bundling it. Fonts, image/scanned PDFs, forms, signing and measurements beyond the subset below are not implemented yet. This preview cannot open arbitrary production PDFs.

The verified local arm64 build with page tools and the design system has a 632,944-byte executable (618.1 KiB). The app bundle contains 2,188,011 bytes of files (about 2.09 MiB), including its icon and sample PDF. This excludes macOS system frameworks and is not a memory-use measurement. The app is locally ad-hoc signed, not notarized. See the [native acceptance report](docs/benchmarks/macos-markup.md), [native design](docs/superpowers/specs/2026-11-04-macos-app-design.md) and [observed Lumin markup rules](docs/superpowers/specs/2026-11-04-markup-design.md).

## Direct shared drawing (preview)

Choose **Share** or **Collaborate → Share Drawing**, enter this Mac’s reachable address and listening port, then copy the `pod://draw` invitation. On the other Mac, open the link with Pod or paste it into **Collaborate → Join Drawing**. Both Macs need this build. The starting PDF transfers to the guest; ink strokes appear while drawing. Moving over the PDF shows a colored cursor with a Host/Guest label on the other app, including a drawing indicator. Cursors follow PDF coordinates at each person’s zoom level and appear only on the matching page; they disappear on leaving the page, focus loss, scrolling, disconnect, or 10 seconds of inactivity. Cursor presence is never saved or added to Undo history. Create a fresh invitation with both apps on this build (drawing protocol v4). Select one of your own strokes to edit it while sharing. Edits and eraser cuts appear on the other Mac. Undo and Redo operate on your own gestures. **Save a Copy** embeds the shared drawings into a normal PDF. **End Drawing Session** closes the connection, revokes the invitation, and keeps the drawings in your local document.

This version uses a direct TLS connection authenticated by a random invitation secret. It does not contact a signaling server, STUN service, relay or cloud storage. On a LAN, use the host’s LAN address. Across the internet, the host needs an independently reachable address and an open/forwarded TCP port; Pod does not configure the router. The advertised port must match the listening port. A failed connection stays failed—there is no relay fallback. Anyone holding the invitation can occupy the guest slot, so share it with the intended collaborator only.

Two peers and freehand ink only; existing PDF content and page structure stay fixed during a session. Shared PDFs are limited to 32 MiB, individual strokes to 4096 points, and the session to 10,000 retained records / 250,000 points. Brief disconnects preserve local drawings; the guest can choose **Collaborate → Reconnect** to merge both sides’ changes. State and undo history live in memory until saved: quitting and reopening does not restore the collaboration session. If the guest restarts, the host must end the old session and create a new invitation. Save copies before closing either app.

The native Swift drawing CRDT uses immutable stroke IDs plus permanent deletion records, with transient pen previews sent separately. It is inspired by the Yjs separation of shared state, editor binding and transport, but does not embed Yjs or use its protocol. See the [design and Yjs review](docs/superpowers/specs/2026-11-04-direct-drawing.md). Run `./script/test_macos.sh` for model, real TLS loopback, PDF export and existing engine checks. Loopback tests do not establish cross-network connectivity.

## Build and use

Zig **0.17.1** is required. The local pinned compiler is at `.tools/zig-aarch64-macos-0.17.1/zig` in the main checkout. The CLI uses libc for file and process I/O; PDF parsing, interpretation and writing are implemented in `src/`.

```sh
zig build test
zig build -Doptimize=safe
./zig-out/bin/pod create original.pdf 'Hello world'
./zig-out/bin/pod inspect original.pdf
./zig-out/bin/pod replace original.pdf edited.pdf 1 0 'Hi'
./zig-out/bin/pod inspect edited.pdf
```

`create OUTPUT.pdf [TEXT]` writes a one-page Courier PDF. The optional text is followed by a second run, ` - Pod`, so the following-position invariant can be checked. `inspect INPUT.pdf` emits JSON with one-based page numbers and zero-based run IDs:

```json
{"pages":[{"number":1,"runs":[{"id":0,"text":"Hello world","x":72,"y":720,"font_size":12,"advance":79.2}]}]}
```

The example shows the schema and omits the second run. Each run is one `Tj` or `TJ` operation, including a `TJ` array's strings and numeric adjustments. `x` and `y` are the starting baseline position after text rise and the current transform, in page user space. `font_size` is the nominal `Tf` size. `advance` is horizontal text-space movement including character/word spacing, horizontal scaling and `TJ` adjustments; it is not a page-space bounding box. Run IDs identify operations within the loaded page and are not persistent document identifiers.

`replace INPUT.pdf OUTPUT.pdf PAGE RUN_ID REPLACEMENT` replaces that operation's text operands. The new advance must fit the original nonnegative advance. A `TJ` adjustment preserves the original total advance, so subsequent operations retain their position. Other operators and resources are retained. Text inside a selected `TJ` is replaced as one run; its previous internal kerning is not retained. Shared page-content streams are rejected for editing rather than changing other uses.

Output paths must not exist, including the input path or aliases to an existing file. Creation uses exclusive open. Input bytes are preserved. Diagnostics use stderr and failures return a nonzero exit status. JSON is emitted only after successful inspection.

## Supported subset and limits

- Classic cross-reference tables and one revision; ordinary indirect references, including indirect stream lengths.
- PDF null, booleans, integers, decimal reals, names, escaped/nested literal strings, hex strings, arrays and dictionaries.
- Page trees with inherited resources, media boxes, crop boxes and quarter-turn rotation; uncompressed content streams and arrays of streams.
- Standard, unembedded Type 1 Courier with default StandardEncoding or explicit StandardEncoding/WinAnsiEncoding; printable character codes 32–126. Custom encodings, widths, embedded fonts and ToUnicode mappings are rejected.
- `BT ET Tf Tm Td TD T* Tc Tw Tz TL Ts Tr Tj TJ q Q cm`. Rendering modes 0–3 are recognized; text clipping modes are rejected. Font size and horizontal scaling must be positive.
- Basic path construction, painting, line-width and device-color operators are preserved. Operators that require additional interpretation, including XObjects, external graphics state, clipping, marked content and inline images, return `UnsupportedOperator`.

Encrypted documents, incremental revisions, xref streams and filtered page-content streams have explicit unsupported errors. Unsupported data is not silently skipped. Content-array state can continue between streams, but a single operand/operator expression must be contained within one stream. The renderer supports basic paths and standard Courier text using unhinted outlines, plus annotations created by Pod and standard imported text markup. It does not shape complex text, decompress streams, load arbitrary PDF fonts, reconstruct paragraphs or reflow text. Pod renders imported highlights with multiply blending and follows each marked line for underlines, strikethroughs, and squiggles. Select a marked line to change its color, opacity, position, size or plain-text note, then use Save a Copy. Editing the appearance generates a fresh PDF appearance stream. A note-only edit preserves the original stream. The current import supports visible, unlocked text markup with RGB or grayscale colors on otherwise supported PDFs. Other foreign annotation types remain outside this subset.

Limits include 256 MiB input files, one million object slots, 100,000 pages, 64 nested syntax/page/reference/graphics levels, one million syntax nodes per parser, 1 MiB string/name tokens, 128 operands per operation, and finite numeric content operands bounded to magnitude 10¹². Page-tree nodes may be visited only once, rejecting both cycles and repeated sibling references. These are guardrails, not a claim that hostile PDFs have been exhaustively fuzzed or that peak memory is capped at input size.

## Library ownership

Import the `pod` module from `build.zig`:

```zig
const bytes = try pod.create(allocator, "Hello world");
defer allocator.free(bytes);
var document = try pod.Document.open(allocator, bytes);
defer document.deinit();
const pages = try document.inspect();
try document.replace(1, 0, "Hi");
const saved = try document.save(allocator);
defer allocator.free(saved);
```

The document **borrows** the input bytes: keep them alive and unchanged until `deinit`. Parsed objects, decoded strings, inspected pages/runs and edited content belong to its arena. Do not free them individually. After an edit, call `inspect` again for a current view; previously returned views are stale. `create` and `save` return slices owned by their supplied allocator. `save` rewrites objects reachable from the trailer and the xref/trailer; deleted annotation dictionaries and their unreferenced appearance streams are omitted. Saving is proportional to reachable objects and output size, and can fail on malformed reachable data.

## Validation and performance

`zig build test` covers syntax boundaries, document errors, round trips, text/graphics state, advance preservation and unsafe edit rejection. `python3 tools/validate.py --help` describes independent fixture and macOS PDFKit interoperability checks, including visual artifacts. The external reader is a test tool, not an engine dependency. `script/test_macos.sh` also checks page assembly, coordinate conversions, split output, unchanged sources, invalid selections, and independent PDFKit checks of page order, crop and rotation. Broader fuzzing and document-corpus work remain necessary before accepting arbitrary user PDFs.

CodeGraph is initialized locally. The installed indexer currently discovers the Python/Swift validation tools but no Zig symbols; core work therefore uses direct source inspection and compiler checks.

Zig 0.17.1 optimization modes are `debug`, `safe`, `fast` and `small`. Debug and safe retain compiler runtime safety checks; fast and small disable them. Explicit input validation remains in all modes. Release executables are stripped. The provisional macOS arm64 CLI target is less than 1 MiB; measure the executable rather than assuming a build mode meets it. See `tools/benchmark.py` and `tools/bench.zig` for process and in-process measurements.

Use `safe` as the starting release configuration: it meets the initial size budget while keeping compiler runtime checks. The [initial benchmark report](docs/benchmarks/initial.md) records all three release modes, timings, memory and reproduction commands.

The approved design and later rendering/font milestones are in [the engine design](docs/superpowers/specs/2026-11-04-pod-engine-design.md).
