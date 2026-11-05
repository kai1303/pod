<p align="center">
  <img src="web/public/pod.png" width="88" alt="Pod app icon">
</p>
<h1 align="center">Pod</h1>

Pod is a PDF editor for macOS with its own Zig engine. You can replace a line of text, mark up a page, rearrange a document, or draw with someone on a second Mac. The same engine powers a command-line tool for inspecting and editing PDFs.

**Start with the bundled sample.** This is a developer preview for uncompressed PDFs with standard Courier text and basic vector graphics. Scans, encrypted files, embedded fonts, and compressed page content fall outside the current format support.

![Pod displaying its two-page sample with page thumbnails, markup tools, and the properties inspector](docs/images/pod-editor.jpg)

## What you can do

| Task | In Pod |
| --- | --- |
| Edit text | Select a text run and type a replacement that fits its original width. The next run keeps its position. |
| Mark up a page | Highlight, underline, strike through, add shapes and comments, or press **F** to draw. Erase part of a stroke or select the drawing to move, rotate, or restyle it. |
| Organize pages | Merge documents, extract a page range, split a document, reorder pages, rotate, or crop. Cropping changes the visible area. The underlying content remains in the file. |
| Draw together | Connect two Macs directly to see each other's ink and cursors. Each person can undo their own strokes and save a copy of the result. |

## Quick start

Use an Apple Silicon Mac running macOS 14 or later. Install the Xcode Command Line Tools, Python 3, Node.js 22.12 or later with npm, and Zig **0.17.1**. Put `zig` on your `PATH`.

```sh
git clone https://github.com/kai1303/pod.git
cd pod
./script/build_and_run.sh
```

Pod opens a two-page sample. On the first page, select “Make the page yours.” and replace it with “Hello, Pod.” Press **F** and circle the new text. Choose **File → Save a Copy** to write your edited PDF. Use **File → Open Sample** to try again.

For a build without launching the editor, run `./script/build_and_run.sh --build`. The script produces `dist/Pod.app` with its interface and sample bundled inside.

## Draw with someone on a second Mac

1. Open a supported PDF of up to 32 MiB. Choose **Collaborate → Share Drawing** and enter an address and TCP port the other Mac can reach. On the same Wi-Fi network, use the host Mac's LAN address.
2. Send the private `pod://draw` invitation to your collaborator. With the same Pod build, they can open the link or paste it into **Collaborate → Join Drawing**.
3. Draw on either Mac. Pod sends the starting PDF and synchronizes freehand ink over a direct TLS connection. Choose **Save a Copy** before quitting to keep the drawings.

The invitation admits one guest. Outside the LAN, the host needs a reachable address and an open or forwarded port. The session runs directly between the two apps. [Drawing protocol and design](docs/superpowers/specs/2026-11-04-direct-drawing.md)

## Try the CLI

From the repository root, create a PDF, inspect its text runs, and replace the first run on page 1. Use fresh output filenames each time.

```sh
zig build -Doptimize=safe
./zig-out/bin/pod create original.pdf 'Hello world'
./zig-out/bin/pod inspect original.pdf
./zig-out/bin/pod replace original.pdf edited.pdf 1 0 'Hi'
./zig-out/bin/pod inspect edited.pdf
```

Page numbers start at **1** and run IDs start at **0**. Compare the second run in the two JSON outputs. Its starting position stays the same even though the first run is shorter.

## How the pieces fit together

| Start here | What to look for |
| --- | --- |
| [Zig engine](src/) | Parses PDF objects, interprets page content, edits text and annotations, and writes the result. Start with [the library entry point](src/pod.zig). |
| [macOS app](macos/) | Owns the document, file dialogs, editing history, peer connection, and native page canvas. The canvas uses Metal where available and can fall back to the Zig CPU renderer. |
| [Editor interface](web/docs/native-editor.md) | React controls run inside a bundled WKWebView. Toolbar actions cross a local bridge to the native editor. |
| [Checks and benchmarks](docs/benchmarks/) | Independent PDF-reader checks and dated measurements of the engine and editor. |

### Run the checks

```sh
zig build test                              # Zig parser, editor, and writer
POD_ZIG="$(command -v zig)" ./script/test_macos.sh  # Native app, bridges, PDF output, shared ink
./script/test_react_editor.sh --built       # Bundled editor, after the native build
```

<details>
<summary><strong>PDF compatibility and Zig library ownership</strong></summary>

### Supported PDF subset

- Classic cross-reference tables and one revision; ordinary indirect references, including indirect stream lengths.
- PDF null, booleans, integers, decimal reals, names, escaped/nested literal strings, hex strings, arrays and dictionaries.
- Page trees with inherited resources, media boxes, crop boxes and quarter-turn rotation; uncompressed content streams and arrays of streams.
- Standard, unembedded Type 1 Courier with default StandardEncoding or explicit StandardEncoding/WinAnsiEncoding; printable character codes 32–126. Custom encodings, widths, embedded fonts and ToUnicode mappings are rejected.
- `BT ET Tf Tm Td TD T* Tc Tw Tz TL Ts Tr Tj TJ q Q cm`. Rendering modes 0–3 are recognized; text clipping modes are rejected. Font size and horizontal scaling must be positive.
- Basic path construction, painting, line-width and device-color operators are preserved. Operators that require additional interpretation, including XObjects, external graphics state, clipping, marked content and inline images, return `UnsupportedOperator`.

Encrypted documents, incremental revisions, xref streams and filtered page-content streams have explicit unsupported errors. Unsupported data is not silently skipped. Content-array state can continue between streams, but a single operand/operator expression must be contained within one stream. The renderer supports basic paths and standard Courier text using unhinted outlines, plus annotations created by Pod and standard imported text markup. It does not shape complex text, decompress streams, load arbitrary PDF fonts, reconstruct paragraphs or reflow text. Pod renders imported highlights with multiply blending and follows each marked line for underlines, strikethroughs, and squiggles. Select a marked line to change its color, opacity, position, size or plain-text note, then use Save a Copy. Editing the appearance generates a fresh PDF appearance stream. A note-only edit preserves the original stream. The current import supports visible, unlocked text markup with RGB or grayscale colors on otherwise supported PDFs. Other foreign annotation types remain outside this subset.

Limits include 256 MiB input files, one million object slots, 100,000 pages, 64 nested syntax/page/reference/graphics levels, one million syntax nodes per parser, 1 MiB string/name tokens, 128 operands per operation, and finite numeric content operands bounded to magnitude 10¹². Page-tree nodes may be visited only once, rejecting both cycles and repeated sibling references. These are guardrails, not a claim that hostile PDFs have been exhaustively fuzzed or that peak memory is capped at input size.

### Using the Zig library

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

</details>
