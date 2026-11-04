# Pod

A native PDF engine written from scratch in Zig, with speed, executable size and explicit memory ownership as design constraints. It includes a native macOS editor, an own CPU renderer, a library and a CLI for the supported PDF subset. It has no PDF library dependencies.

## Native macOS app

On Apple Silicon with macOS 14 or later, Xcode command-line tools and the pinned Zig compiler:

```sh
./script/build_and_run.sh             # build and open dist/Pod.app
./script/build_and_run.sh --build     # build only
./script/test_macos.sh                # engine, C/Swift bridge and independent reader checks
```

The Codex Run action uses the same launch script. A two-page sample is included. Open a supported PDF, select text to replace it, or use the Mark up toolbar. Save a Copy writes a new file; the input is preserved. Quit an existing Pod instance after saving before launching the updated build.

The Lumin-inspired markup palettes were reconstructed from live DOM/CSS observations, using native AppKit controls. Eighteen annotation variants are implemented: rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick, text highlight, freehand highlight, underline, squiggly underline, strikeout, ink, free text and comment. They are stored as PDF annotations with appearance streams, and survive save/reopen in other readers. Select annotations to move, resize, change styles or delete; Eraser removes annotations. Undo/redo restores document snapshots. Click successive points for polyline/polygon, then Return or double-click to finish; Escape cancels. Text markup selects whole supported text runs.

Zig parses, edits, rasterizes and writes the PDF, including its own TrueType outline decoder. AppKit provides the desktop UI; CoreGraphics displays our RGBA bitmap. **PDFKit is used only by independent test tools and is not linked into or bundled with the application.** The renderer reads the installed Courier New font as a substitute without bundling it. Fonts, image/scanned PDFs, forms, signing and measurements beyond the subset below are not implemented yet. This preview cannot open arbitrary production PDFs.

The verified local arm64 build has a 528,592-byte executable (516.2 KiB) and occupies about 532 KiB on disk as an app bundle. This excludes macOS system frameworks and is not a memory-use measurement. The app is locally ad-hoc signed, not notarized. See the [native acceptance report](docs/benchmarks/macos-markup.md), [native design](docs/superpowers/specs/2026-11-04-macos-app-design.md) and [observed Lumin markup rules](docs/superpowers/specs/2026-11-04-markup-design.md).

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
- Page trees with inherited resources and media boxes; uncompressed content streams and arrays of streams.
- Standard, unembedded Type 1 Courier with default StandardEncoding or explicit StandardEncoding/WinAnsiEncoding; printable character codes 32–126. Custom encodings, widths, embedded fonts and ToUnicode mappings are rejected.
- `BT ET Tf Tm Td TD T* Tc Tw Tz TL Ts Tr Tj TJ q Q cm`. Rendering modes 0–3 are recognized; text clipping modes are rejected. Font size and horizontal scaling must be positive.
- Basic path construction, painting, line-width and device-color operators are preserved. Operators that require additional interpretation, including XObjects, external graphics state, clipping, marked content and inline images, return `UnsupportedOperator`.

Encrypted documents, incremental revisions, xref streams and filtered page-content streams have explicit unsupported errors. Unsupported data is not silently skipped. Content-array state can continue between streams, but a single operand/operator expression must be contained within one stream. The renderer supports basic paths and standard Courier text using unhinted outlines, plus annotations created by Pod. It does not shape complex text, decompress streams, load arbitrary PDF fonts, reconstruct paragraphs or reflow text. Unsupported foreign annotation appearances return an error.

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

`zig build test` covers syntax boundaries, document errors, round trips, text/graphics state, advance preservation and unsafe edit rejection. `python3 tools/validate.py --help` describes independent fixture and macOS PDFKit interoperability checks, including visual artifacts. The external reader is a test tool, not an engine dependency. Broader fuzzing and document-corpus work remain necessary before accepting arbitrary user PDFs.

CodeGraph is initialized locally. The installed indexer currently discovers the Python/Swift validation tools but no Zig symbols; core work therefore uses direct source inspection and compiler checks.

Zig 0.17.1 optimization modes are `debug`, `safe`, `fast` and `small`. Debug and safe retain compiler runtime safety checks; fast and small disable them. Explicit input validation remains in all modes. Release executables are stripped. The provisional macOS arm64 CLI target is less than 1 MiB; measure the executable rather than assuming a build mode meets it. See `tools/benchmark.py` and `tools/bench.zig` for process and in-process measurements.

Use `safe` as the starting release configuration: it meets the initial size budget while keeping compiler runtime checks. The [initial benchmark report](docs/benchmarks/initial.md) records all three release modes, timings, memory and reproduction commands.

The approved design and later rendering/font milestones are in [the engine design](docs/superpowers/specs/2026-11-04-pod-engine-design.md).
