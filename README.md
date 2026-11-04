# Pod

A native PDF engine written from scratch in Zig, with speed, executable size and explicit memory ownership as design constraints. The first milestone provides a headless library and CLI for a small, testable PDF editing subset. It has no PDF library dependencies and does not contain a renderer.

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

Encrypted documents, incremental revisions, xref streams and filtered page-content streams have explicit unsupported errors. Unsupported data is not silently skipped. Content-array state can continue between streams, but a single operand/operator expression must be contained within one stream. The engine does not render, shape text, decompress streams, load arbitrary fonts, reconstruct paragraphs or reflow text.

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

The document **borrows** the input bytes: keep them alive and unchanged until `deinit`. Parsed objects, decoded strings, inspected pages/runs and edited content belong to its arena. Do not free them individually. After an edit, call `inspect` again for a current view; previously returned views are stale. `create` and `save` return slices owned by their supplied allocator. `save` fully rewrites live objects and the xref/trailer; it is proportional to the whole output and can fail on malformed unused objects discovered during saving.

## Validation and performance

`zig build test` covers syntax boundaries, document errors, round trips, text/graphics state, advance preservation and unsafe edit rejection. `python3 tools/validate.py --help` describes independent fixture and macOS PDFKit interoperability checks, including visual artifacts. The external reader is a test tool, not an engine dependency. Broader fuzzing and document-corpus work remain necessary before accepting arbitrary user PDFs.

CodeGraph is initialized locally. The installed indexer currently discovers the Python/Swift validation tools but no Zig symbols; core work therefore uses direct source inspection and compiler checks.

Zig 0.17.1 optimization modes are `debug`, `safe`, `fast` and `small`. Debug and safe retain compiler runtime safety checks; fast and small disable them. Explicit input validation remains in all modes. Release executables are stripped. The provisional macOS arm64 CLI target is less than 1 MiB; measure the executable rather than assuming a build mode meets it. See `tools/benchmark.py` and `tools/bench.zig` for process and in-process measurements.

Use `safe` as the starting release configuration: it meets the initial size budget while keeping compiler runtime checks. The [initial benchmark report](docs/benchmarks/initial.md) records all three release modes, timings, memory and reproduction commands.

The approved design and later rendering/font milestones are in [the engine design](docs/superpowers/specs/2026-11-04-pod-engine-design.md).
