# Pod PDF engine design

Status: approved by the user on 4 November 2026; first milestone authorized for implementation.

Pod will be a native PDF engine written in Zig. We will own its PDF parser, object model, content interpreter, font handling, renderer, editing operations and serializer. Speed, binary size and memory use are primary design constraints.

The engine will follow the PDF and font specifications. The Apryse investigation supplies architectural observations; vendor source and binaries remain research artifacts and will not become engine dependencies.

## Language choice

Zig is the proposed choice because it makes allocation and native integration explicit and provides separate optimization settings for speed and size. Rust is also a viable native implementation language; this choice does not assert that Zig is intrinsically faster or smaller.

The implementation pins Zig 0.17.1 and records its exact version with every benchmark. The compiler is installed locally under the project's ignored `.tools` directory. The existing Rust installations are not a project dependency.

The core will use the Zig standard library and operating-system interfaces. It will not delegate PDF parsing, PDF writing, font interpretation or page rendering to PDFium, MuPDF, PDFKit, pdf-lib, lopdf or Apryse. Independent PDF readers may be used to validate test outputs.

## Delivery order

An entire PDF engine spans several independently testable subsystems. Development starts with a complete file-editing round trip, then adds native rendering and broader compatibility.

1. PDF object foundation, content interpretation, basic text editing and writing.
2. Native CPU renderer and our own TrueType outline/font-table reader.
3. Font encoding and document compatibility expansion, images and compression.
4. Text-region reconstruction, paragraph editing, reflow and richer graphics.

This document defines the first milestone in detail and the boundaries that later subsystems must fit. Completing milestone one does not mean arbitrary PDFs are supported or the renderer is complete.

## First milestone

Build a reusable Zig library and a native CLI that can create a simple PDF, read it, inspect its text, replace one supported text run, save a new PDF and reopen it.

Supported input is a deliberately small PDF subset:

- Classic cross-reference tables and trailers with a single revision.
- Booleans, null, integer and real numbers, names, literal/hex strings, arrays, dictionaries, indirect objects and references.
- Uncompressed streams with checked lengths, including indirect length references.
- Page trees with inherited page resources and media boxes.
- Horizontal text using the standard Courier font and printable ASCII character codes.
- Text state and positioning needed for the supported content operators: `BT`, `ET`, `Tf`, `Tm`, `Td`, `TD`, `T*`, `Tc`, `Tw`, `Tz`, `TL`, `Ts`, `Tr`, `Tj`, and `TJ`; graphics-state `q`, `Q`, and `cm` where their scope affects text.
- Text-run selection by page and a stable identifier within a loaded document. Identifiers need not persist after reopening.

Editing updates the original content stream's text-showing operands. It does not cover text with a white rectangle or append a replacement annotation. Changes retain unrelated operators and resources. If a changed run affects the position of subsequent text, the serializer compensates for its advance so following content remains in place. Initial edits must fit within the selected run's original advance; overflow returns a specific error instead of silently shrinking or reflowing text.

Unsupported fonts, character encodings, encrypted input, incremental revisions, cross-reference streams and filtered content streams receive explicit unsupported-feature errors in editing. Inspection must distinguish unsupported data from malformed input. No operation should claim success after dropping content it cannot interpret.

The CLI operations are `create`, `inspect`, and `replace`. Each reports errors with useful file/object/operator context. Output is written to a different path; the input is preserved. CLI stdout is reserved for results, and diagnostics use stderr.

## Component boundaries

| Component | Responsibility |
| --- | --- |
| Syntax | Tokenize bounded byte slices and parse PDF values without resolving references |
| Document | Resolve cross-reference entries, cache parsed objects and traverse page trees |
| Content | Interpret supported graphics/text state and retain original operator spans |
| Text | Associate glyph codes, text advances, transforms and source operands |
| Edit | Validate a command and produce a reversible change to affected content |
| Writer | Serialize changed objects and a valid cross-reference table/trailer |
| CLI | File input/output and command arguments; no PDF logic |

Keep the first implementation in one small library rather than creating a plugin framework or a separate package per component. Interfaces should accept explicit allocators and document lifetimes. Add a C ABI when there is an actual application consumer.

## Speed and size

- Retain original file bytes and refer to stable source spans where practical instead of copying every token and string.
- Resolve objects on demand from cross-reference entries and cache resolved objects once.
- Use document-lifetime allocation for parsed objects, with separate scratch storage for page operations.
- Make edits proportional to affected content where the representation permits it. Initial full-file saves still require reading/writing the whole output; do not describe them as constant-time operations.
- Keep font and page caches bounded when rendering is added.
- Start single-threaded. Introduce page-level parallelism only after a measured workload demonstrates a benefit.
- Keep the CLI and library headless. Application UI, a browser runtime, sample files, fonts and research artifacts are not bundled into the engine binary.
- Compare size-optimized and speed-optimized builds on the same fixtures. Keep explicit input validation in both. Runtime-safety choices must be recorded, not silently changed to improve a benchmark.

The provisional first-milestone size budget is a stripped macOS arm64 CLI under 1 MiB, excluding the compiler, debug symbols and test fixtures. This is a design target, not a measured result or a promise for the eventual complete application.

Record executable bytes, startup time, parse/inspect latency, edit latency, save latency and peak resident memory. Separate cold process startup from in-process operations. Publish fixture sizes, object/page counts, compiler version, optimization mode, hardware, iteration count and median/tail results. Establish latency baselines before setting numeric regression budgets.

## Validation

The central acceptance case is: create a one-page Courier document, inspect its text and positions, replace a run with shorter text, save, reopen and confirm the replacement and unchanged subsequent positions.

Required tests include escaped and nested literal strings, hex strings, delimiters/comments, numeric edge cases, incorrect cross-reference offsets, invalid stream lengths, missing references, cyclic page trees, truncated files, malformed content operands, and unsupported-feature rejection.

Use checked arithmetic and limits for file size, token length, nesting, object counts and reference traversal. Tests must verify errors rather than crashes on malformed inputs. Broader fuzzing becomes a release requirement before handling arbitrary user documents.

Validate at least one generated and one edited PDF with an independent PDF reader, including visual inspection. Unit tests that use only our own reader and writer are insufficient to establish interoperability. Retain the validation artifact and describe the precise subset tested.

## Renderer and font milestones

The renderer will consume an engine-owned display list produced by the content interpreter. A CPU rasterizer will implement paths, fills, strokes, transforms and clipping, with explicit pixel-buffer dimensions and memory limits.

Our TrueType reader will load mapping, metrics and outline tables, convert glyph contours into paths, and support compound glyphs with bounded recursion. Font decoding, shaping, bidi and hinting are separate concerns; complex-script and Type 1/CFF support require their own compatibility milestones. The first renderer will not claim pixel equivalence with mature PDF engines.

The editor will eventually reconstruct selectable text regions from glyph positions and style runs, apply commands, update the affected display list, and regenerate PDF content. The PDF model remains the source of truth; UI selection state is separate.

## References

- [PDF specification archive](https://pdfa.org/resource/pdf-specification-archive/).
- [OpenType font structure](https://learn.microsoft.com/en-us/typography/opentype/spec/otff).
- [Zig documentation](https://ziglang.org/documentation/), with implementation details checked against the selected stable compiler version.
- [Local Apryse architecture investigation](../../../research/apryse/README.md).
