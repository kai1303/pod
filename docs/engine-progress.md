# PDF engine completion

Active goal from 6 November 2026: continue building and finish Pod's PDF engine.

The engine is still a developer preview. The delivery order and ownership constraints in
[the engine design](superpowers/specs/2026-11-04-pod-engine-design.md) apply. The current
work also includes compatibility with annotations created by other PDF applications.
A completed initial milestone or a passing fixture suite does not establish general PDF support.

## Completed in the current continuation

- Shared decoding for Flate, LZW, ASCIIHex, ASCII85, and RunLength, including ordered
  filter chains and indirect filter names and decode parameters.
- PNG and TIFF predictor reconstruction at 1, 2, 4, 8, and 16 bits per component.
- LZW early-change variants, code-width changes, and dictionary resets.
- Flate checksum validation and bounded decoded output. Intermediate filter buffers
  are freed between stages. Document and page-view caches own their decoded bytes.
- Compressed content interpretation, rendering, text replacement, save/reopen, and page
  extraction. Edited streams lose their former encoding metadata. Untouched encoded
  streams retain their original data. Metadata-only changes preserve stream payloads.
- Imported ink appearances and ICC stream inspection use the same decoder.

Verification lives in `src/filters.zig` and `tools/validate.py`. Independent fixtures are
produced with Python's zlib/base85 and a literal-code LZW encoder. The validation command
can also use the existing PDFKit helper to check text and render saved PDFs independently.

### Cross-reference and object compatibility

- Classic and compressed cross-reference sections, hybrid files, latest-revision precedence,
  free-object masking, generation checks, and trailer inheritance.
- Lazy object-stream indexing and resolution, with member identity and offset validation.
- Forward reference chains in linearized files. Full saves consolidate the current reachable
  objects and remove obsolete cross-reference navigation keys.
- Limits on revision traversal, cross-reference record counts, member counts, and decoded
  stream sizes, including explicit rejection of cycles and malformed indices.

`tools/xref_fixtures.py` checks 11 hand-built valid layouts, 16 malformed cases and 128 reproducible mutations, and an
additional mixed-reference transition. With `--pikepdf-check`, it also generates four
independent qpdf layouts and checks the saved output with qpdf. `--pdfkit-check` uses the
existing compiled helper for external text extraction and rendering. `--native-check`
accepts the executable built from `tools/xref_bridge_check.c` to cover indexed reads,
rendering, extraction, text/annotation editing and save/reopen through the C bridge. PDFKit rejects the
input fixture that switches from a compressed cross-reference stream to a classic table;
pypdf and Pod both read its latest content, and PDFKit reads Pod's normalized saved copy.

Reproduce the independent compatibility check with:

```sh
uv run --with pikepdf python tools/xref_fixtures.py zig-out/bin/pod \
  --pikepdf-check --pdfkit-check .build/pdfkit-stream-check
```

The PDFKit helper is built from `tools/pdfkit_check.swift`. pikepdf/qpdf and PDFKit are
validation tools, with no production engine dependency.

### Ordinary web links

- Standard URI link annotations have a separate engine model and C bridge enumeration;
  they no longer make annotation listing or page rendering fail solely for being links.
- No-border, solid rectangular and underline borders; RGB, grayscale and basic CMYK colors;
  hidden/no-view flags; bounded quad regions; indirect action dictionaries; and relative
  targets with a catalog URI base. Reversed rectangles normalize; empty areas stay inactive.
- Native canvas clicks open HTTP(S) links. Drags and active annotation tools do not activate
  links. Other URI schemes remain preserved but inactive. PDF actions never execute in Zig.
- Original link dictionaries and metadata survive text/markup edits and save/reopen.
  Page extraction remaps annotation owner references into the selected page tree.
- Indexed page views retain the catalog context needed for relative URI resolution and own
  their link data for the lifetime of each view.

`script/test_links.sh` generates independent byte-level fixtures, exercises the library/C
bridge through Swift, and checks native clicks with an intercepted callback (no website is
opened). It verifies quads, relative URLs, hidden links, inactive schemes, repeated indexed
reads, text and annotation edits, extraction, and foreign PDFKit-generated annotations.
Saved files are inspected and rendered independently by PDFKit. Artifacts are under
`test-out/links`. PDFKit paints the fixture's `/BS /S /U` border as a rectangle; Pod follows
the underline style. This check establishes preservation/readability, not pixel equivalence.

Remaining link work includes creation/editing UI, action chains,
IsMap, custom appearances, dashed/rounded borders and view-dependent flags. Extraction/merge
of documents carrying a catalog URI base remains explicitly unsupported until document-level
URI context can be preserved across combined documents. These are still part of the overall goal.

### Internal page destinations

- Direct `/Dest` entries and `/GoTo` actions resolve explicit page references, legacy
  catalog `/Dests` names, and byte-string names in destination name trees.
- All eight destination modes are represented: XYZ, Fit, FitH, FitV, FitR, FitB, FitBH
  and FitBV. Null coordinates and zero XYZ zoom retain the viewer's current values.
- The native viewer applies destination zoom/position to cropped and rotated pages within
  its existing 10–300% zoom range. FitB variants compute painted content bounds through
  the engine renderer, excluding annotations and intersecting the visible page box.
- Indexed page views expose full-document destination page numbers. They borrow the
  immutable page lookup map while owning the named-destination objects they resolve.
- Name trees are bounded to 64 levels and 100,000 visited nodes/entries, with cycle,
  duplicate-key, ordering, target identity and mode-arity checks.
- Save retains the original explicit/named destination representation and metadata.
  Direct destinations remap correctly when selected pages are reordered or documents merged.
  Extraction that would remove a referenced target still fails explicitly; named-destination
  catalogs remain outside the current page assembly policy rather than being silently dropped.

`script/test_links.sh` now also checks all destination modes, legacy/name-tree lookup,
null coordinates, cropped/rotated targets, content fitting, repeated indexed reads, save,
reorder/merge and actual canvas click-to-navigation. The application controller smoke is:

```sh
./script/build_and_run.sh --build
POD_DESTINATION_SMOKE="$PWD/test-out/links/destinations.pdf" ./script/test_react_editor.sh --built
uv run --with pikepdf python tools/destination_check.py test-out/links --generate
./script/test_links.sh --built
```

The qpdf check verifies every target page, mode and annotation name in original and edited
fixtures. `--generate` also produces object-stream and linearized versions for the native
link suite to check, including their edit/save/reopen path. PDFKit independently resolves ten of the eleven fixture destinations; it cannot
resolve the legacy dictionary-wrapped destination in either the original or edited file.
That case is independently checked with qpdf, rather than counting a nil PDFKit result as
success. `destinations-edited.pdf` and `destinations-reordered.pdf` are retained in `test-out/links`.

## Standard font families and encoded text

The engine now resolves all 14 standard Type 1 faces and uses Adobe AFM widths and
bounds instead of a universal Courier cell. It decodes built-in Standard, Symbol and
ZapfDingbats encodings, WinAnsi and PDF MacRoman, plus encoding Differences. Explicit
font Widths and MissingWidth override AFM advances. Replacement encodes UTF-8 back
through the selected font and writes TJ compensation to preserve following text.
The font cache is invalidated when document dictionaries change.

Backward-compatible C APIs accept up to 14 borrowed host font sources for CPU rendering,
Metal paint collection and content bounds. Duplicate IDs, null bytes, excessive lengths
and invalid IDs fail explicitly. The native app retains immutable installed font data,
uses matching font styles, and displays the actual PDF font name for selected text.
Pod's own Zig TrueType reader interprets the outlines. No system font outlines are
bundled, and PDFKit is used only as an independent oracle in the font integration test.
The existing reading-selection layer remains separate.

`script/test_fonts.sh` checks every built-in encoded glyph in all 14 faces through
CPU rendering, indexed page rendering, Metal paint collection and content bounds.
WinAnsi, MacRoman, StandardEncoding, Differences and explicit Widths fixtures exercise
UTF-8 extraction, replacement, save/reopen, and following-text position preservation;
PDFKit independently checks saved text and positions. Invalid encoding/width fixtures
and malformed font-source arrays fail explicitly. `zig build test` includes proportional
advance, encoding, unrepresentable replacement and cache-invalidation regressions.

MacRoman's currency mapping and undefined codes were checked against Adobe PDF 1.7
Appendix D, rather than assuming the modern macOS codec is identical. Licensed source
metrics and generated-table notices live in `assets/font-metrics`; regeneration uses
`tools/generate_font_metrics.py`. The build installs the notices into both CLI data and
app resources.

Verified in this milestone: 66 Zig tests; all 14 native font grids with CPU/Metal
pixel comparisons; five encoded-text edit fixtures with independent PDFKit checks;
CLI validation with 128 malformed-input mutations; native engine/page-operation and
imported-markup regressions; full application build and React/native editor smoke.
The installed app and CLI font-data notices match the source NOTICE. Build warnings
remain for existing deprecated AppKit accessibility calls and the web bundle size.

This does not finish font compatibility: embedded programs, composite fonts, arbitrary
font names, complex shaping and wider annotation text support remain incomplete.
Substitute outlines also do not establish pixel-identical rendering to another viewer.

## ToUnicode maps and text semantics

`src/to_unicode.zig` reads declarative CMap syntax without executing PostScript. It
supports codespaces, bfchar, both bfrange forms, UTF-16BE surrogate pairs and sequences,
compressed streams, and recursive embedded UseCMap inheritance with child overrides.
Codes retain their source length. The parser can represent one- through four-byte codes;
current simple-font integration requires a one-byte codespace. This does not implement
Type 0 composite font decoding or a predefined external CMap collection.

Extraction follows ToUnicode when a code is mapped, and falls back to the existing
font encoding for unmapped codes. Glyph selection and widths remain independent of
Unicode metadata. Reverse encoding uses a bounded backwards search, so ligatures and
ambiguous prefixes do not cause a greedy-match failure. It prefers the fewest encoded
codes and preserves following text positions through the existing TJ compensation.
CLI JSON now escapes control characters that Unicode maps can legitimately produce.
Stream replacement invalidates font and inspected-page caches.

Limits include eight levels of inheritance, 4 MiB of CMap program data per stream,
65,536 mapping definitions per stream, 256 codespaces, 512 bytes per UTF-16 destination,
4 MiB of decoded mapping text across an inheritance chain, and 16 MiB of extracted text
per page. Reverse encoding accepts at most 1 MiB of UTF-8 and bounds candidate comparison
work. Invalid UTF-16, mismatched codespaces/counts, overflow, inheritance cycles and
unsupported operators fail explicitly.

`script/test_unicode.sh` exercises plain, compressed and inherited maps through CLI,
C bridge and native indexed reads, CPU/Metal rendering, text replacement, annotation
save and reopen. It checks JSON control escaping and 128 reproducible parser mutations.
PDFKit independently checks ordinary/compressed Unicode and subsequent text positions.
CoreGraphics explicitly reports that embedded UseCMap is unsupported; the inherited
fixture is therefore checked with MuPDF 1.26.5 via `tools/unicode_check.py`. MuPDF also
verifies exact original Unicode text, unchanged original glyph pixels, both CLI/native
edited text and preserved tail bounds for all three variants. This dependency is for
validation only and is not linked into or imported by the engine/application.

The implementation follows Adobe PDF 1.7 sections 5.6 and 5.9.2 (including the last-byte
increment rule for string-valued bfrange destinations):
https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf

Verification after this change: 72 Zig tests passed, including malformed UTF-16,
codespace/count/overflow checks, inherited overrides, reverse-encoding ambiguity,
stream-cache invalidation and decoded-text limits. Standard-font regressions, CLI
validation (another 128 malformed-input mutations), native text/markup/page operations,
the full app build and React/native editor smoke also passed.

A current safety-optimized, stripped CLI benchmark is retained in
`test-out/unicode/benchmark.json`: Zig 0.17.1, aarch64-macos.14.0, Apple M1 Pro,
macOS 27.0.1; executable 519,504 bytes. On the one-page, six-object, 20,656-byte
1,000-run fixture, 30 warm process invocations measured inspect median/p95 6.29/11.27 ms
and replace+save 5.64/8.63 ms, including process spawn and I/O. Peak RSS was 2,785,280
and 2,768,896 bytes respectively. Usage/startup median/p95 was 5.99/14.24 ms; its first
invocation was 318.67 ms. Other validation ran concurrently, so these are recorded
observations, not an isolated regression comparison or a Unicode-heavy workload claim.
The JSON retains the fixture hash and all first-invocation timings.

## Embedded simple TrueType fonts

Implemented `FontFile2` programs for simple `/TrueType` fonts, including subset
font names and compressed embedded streams. The PDF font model keeps source bytes,
Unicode extraction, embedded glyph IDs and PDF widths separate. The engine's own
TrueType reader supplies the outlines for both CPU and Metal rendering; no installed
font is needed for these documents. Existing C entry points support this path with
zero host font sources, including content bounds. Native font discovery no longer
rejects embedded-only documents solely because the Courier substitute is absent.

The reader supports cmap formats 0, 4, 6 and 12; Windows Unicode, Windows Symbol
and Macintosh mappings; simple contours and compound outlines with transforms,
point attachment and scaled offsets. It validates table versions, header magic,
units, horizontal metrics, monotonic loca offsets, subtable ranges and glyph IDs.
Compound decoding has bounds on recursion depth, total work, component count and
output points. Hints are not executed.

Simple font encodings select the embedded glyphs independently of ToUnicode text
extraction. The loader supports the implemented WinAnsi/MacRoman/glyph-name mappings
for nonsymbolic fonts and the documented Windows Symbol or Macintosh source-byte
mappings for symbolic fonts. Symbolic extraction requires ToUnicode in this release.
Replacing text only uses glyphs already present in the font's encoding/subset; it
preserves the font program and exact PDF widths, including fractional values.

`script/test_truetype.sh --built` passed ten fixture variants through native eager
and indexed reads, CPU/Metal rendering, C calls with zero host fonts, text replacement,
annotation saves, and independent PDFKit reopening. The fixtures include a compressed
ReportLab subset, Mac and Windows symbolic fonts, full-Unicode and byte cmaps,
point-attached/scaled compound glyphs, and extraction without ToUnicode for a
nonsymbolic font. CLI inspect/replace/reopen passes on every variant. MuPDF independently
checks text, following-text geometry, annotation persistence and byte-for-byte embedded
font preservation in native and CLI outputs. Thresholded raster overlap is 0.968–0.970
for the synthetic fonts and 0.960 for ReportLab; these fixtures do not establish general
pixel equivalence. The native ReportLab raster was also visually inspected.

PDFKit confirms exact following-text positions after replacement. MuPDF 1.26.5 rounds
individual fractional PDF widths, producing a small differing advance after replacement
in the ReportLab fixture. The independent test predicts that drift from the original
PDF widths and checks it explicitly instead of altering the engine's correct metrics
or accepting an arbitrary tolerance.

Eight targeted malformed programs (headers, metrics, loca and truncation) fail explicitly
through native and CLI reads. Another 64 deterministic font mutations reach native
extraction/rasterization without crashes. All 73 Zig tests pass. Regressions passed for
all standard fonts, ToUnicode (including 128 map mutations), links/destinations, native
text/annotation/page operations, the full app build and React/native editor smoke.
These are bounded regression checks, not a completed external-document fuzzing campaign.

Fixture production uses test-only FontTools 4.68.0 and ReportLab 5.1.0 on Python 3.12;
independent validation uses PDFKit, MuPDF 1.26.5 and pypdf 6.21.4. None are engine
dependencies. Generated fonts and PDFs stay in ignored `test-out/truetype`.

At this milestone, remaining work included Type0/CID fonts and multibyte source codes
(extended below), Type1/CFF/OpenType
`FontFile3` programs, arbitrary unembedded fonts, custom glyph-name decoding and
`post`-table fallback, remaining Macintosh mappings and cmap formats, symbolic
extraction without ToUnicode, hinting, shaping and adding glyphs to existing subsets.
The mapping follows PDF 1.7 section 5.5.5; outline handling follows the OpenType
`cmap`, `glyf`, `loca`, `head`, `hhea`, `hmtx` and `maxp` table specifications.

## Horizontal composite TrueType fonts

Implemented Type0 fonts using the Identity-H encoding and embedded CIDFontType2
programs. Source strings now iterate font character codes, rather than assuming
one glyph per byte. The change reaches extraction, character/word spacing, text-run
bounds, CPU/Metal outline callbacks and replacement serialization. Two-byte code
`0020` correctly receives character spacing but not PDF word spacing. Odd-length
strings, including a code split across TJ strings, fail explicitly.

The CID loader reads identity mappings (direct, indirect or omitted), compressed
CIDToGIDMap streams, default widths and both W-array forms. Width ranges are stored
sparsely, sorted for lookup and checked for overlap/overflow. Glyph IDs and map
lengths are checked before use. Font programs can omit their cmap table when CID
mapping supplies glyph IDs. ToUnicode maps provide text independently of the glyph
program, including supplementary Unicode and multi-character ligatures. Shared
reverse encoding handles ambiguous prefixes, uses deterministic code selection,
and limits candidate matching work; replacements retain the existing font subset.

Independent producer verification exposed a separate renderer gap: fpdf2 starts
its content with square line caps (`2 J`). Square caps now extend open path endpoints
by half the stroke width, follow transforms, handle repeated endpoints, leave closed
paths unchanged and participate in graphics-state save/restore. A raster test compares
these strokes with their explicit filled outlines. The fpdf2 document is tested as
produced, without rewriting its content to fit Pod's existing subset.

`script/test_cid_fonts.sh --built` passed ten cases: identity, remapped, absent font
cmap, indirect/default identity maps, spacing/TJ adjustments, default widths, CID
65535, supplementary Unicode/ligature mapping, and a real Inter subset produced by
fpdf2 2.9.0. Each case passes native eager/indexed reads, CPU/Metal rendering, zero-host-
font C calls, content bounds, text/annotation saves and PDFKit reopening. CLI edits
preserve following runs. MuPDF independently verifies extracted text, following-text
geometry, annotation persistence and exact embedded font bytes after saving.
Thresholded raster overlap was 0.968–0.993 for synthetic cases and 0.959 for fpdf2;
the native fpdf2 raster was also visually inspected.

Ten malformed/unsupported fixtures fail explicitly; another 64 deterministic CID-map
mutations reach native extraction and rendering without crashes. All 74 Zig tests pass.
Standard fonts, simple embedded fonts, Unicode maps, links/destinations, native page
and annotation operations, full app build and React/native editor smoke pass. The CLI
contract validator also passes its 128 malformed-input mutations. FontTools 4.68.0 and
fpdf2 2.9.0 produce ignored test fixtures only; independent checks use PDFKit and
MuPDF 1.26.5. No external PDF or font interpreter is added to the engine.

At this milestone, remaining work included Identity-V/vertical metrics, embedded
Encoding CMaps (extended below), other predefined CMaps, CIDFontType0/CFF, extraction for CID fonts lacking ToUnicode, new
subset glyph insertion and shaping. Existing ToUnicode stream inheritance is reused;
it does not imply support for embedded character-to-CID Encoding CMaps. Remaining
engine completion requirements below are unchanged.

An additional exploratory CoreGraphics-produced file was rejected for an unused
xref entry marked in-use at offset zero. It also used a named color-space resource
and a simple TrueType font, so it did not exercise the new CID path. This is a retained
corpus finding, not evidence of general CoreGraphics PDF compatibility or of a CID
regression. Its raw sample is in ignored `test-out/cid-fonts/coregraphics.pdf`.

Implementation reference: PDF 1.7 sections 5.2.2 and 5.6 (source codes, spacing,
CID widths and CIDToGIDMap), and section 4.3.2 for line caps:
https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf

## Embedded horizontal Encoding CMaps

Implemented declarative character-to-CID CMaps for horizontal composite TrueType
fonts. Character codes carry their value and byte length throughout extraction,
spacing, bounds, CPU/Metal rendering and reverse encoding. This distinguishes equal
numeric values expressed with different byte lengths and applies word spacing to
one-byte code 32, including in a composite font, without applying it to multibyte
codes. Replacements serialize the selected original source codes and preserve the
following text's position.

The bounded parser supports one- through four-byte codespaces, cidchar/cidrange,
ordered mapping overrides, embedded UseCMap inheritance and Identity-H bases. It
also handles explicit notdef mappings for otherwise unmapped valid codes. Codespace
prefix ambiguities, invalid ranges, invalid CID values, expansion overflow, cyclic
inheritance and unknown executable operators fail explicitly. No PostScript code is
executed. CMap stream decoding reuses the engine's filters. Mapping tables are bounded
at 65,536 entries, codespaces and notdef ranges at 256 each, programs at 4 MiB and
inheritance at eight levels. Large notdef ranges are stored without expansion.

A cross-byte range fixture caught an incorrect dense CID increment. CID offsets
must retain numeric character-code gaps across codespace rows. The corrected code
has a direct regression and matches independent glyph rendering; text extraction
alone would not have caught the incorrect glyph selection.

`script/test_encoding_cmaps.sh --built` passed nine cases: mixed one-/two-/three-/
four-byte codes, two-byte custom maps, cross-byte ranges, mapping overrides, embedded
inheritance, an Identity-H base, notdef fallback and character/word spacing. Each goes
through native eager/indexed reads, CPU/Metal rendering, C calls with no host fonts,
content bounds, replacement, annotation save and CLI inspect/replace/reopen. Independent
checks verify Unicode, following-text geometry, glyph-program byte preservation and
saved annotations. Raster overlap is 0.968 for most fixtures, 0.990 for spacing and
0.965 for the Ghostscript-rendered notdef fixture. Sixty-four deterministic CMap
mutations reach native extraction/rendering without crashes; nine targeted malformed
or unsupported inputs fail explicitly.

The independent-reader boundary is explicit:

- PDFKit reads the two-byte custom map. For the tested mixed-length maps, it returns
  empty, partial or missing text even on the original document. It extracts the
  cross-byte range's text but uses incorrect widths. Those fixtures retain their
  native checks and use MuPDF for independent geometry and raster verification.
- MuPDF 1.26.5 verifies the mapped glyphs and saved geometry, but fails to inherit
  omitted codespaces in the tested embedded child map. The independent inheritance
  fixture repeats the codespaces while inheriting/overriding the mappings. A direct
  engine regression separately verifies inherited codespaces without repetition.
- MuPDF ignores the tested notdef mapping. Ghostscript 10.02.1 independently verifies
  that original and its native/CLI saves with PNG rendering and structured text
  coordinates. Ghostscript emits a device-finalization diagnostic for its text device;
  the successful output, text, coordinates and rasters are checked, and diagnostics
  are retained alongside the artifacts. No external reader is an engine dependency.

The 79 Zig tests pass, including code-length identity, inherited spaces/overrides,
notdef bounds, malformed maps and the cross-byte CID regression. Standard, simple
embedded, Identity-H and ToUnicode regressions also pass. The generated artifacts
remain in ignored `test-out/encoding-cmaps`.
The full app build, React/native editor smoke, link/destination checks and native
text/annotation/page-operation regressions pass. CLI contract validation passes its
128 malformed-input mutations. The mixed-length native raster was visually inspected.

At this milestone, remaining font work included vertical writing/metrics (completed
below for supported TrueType composites), other predefined CMaps,
additional CMap syntax, complete undefined-glyph behavior, Type1/CFF programs,
composite text without ToUnicode, adding glyphs to subsets and shaping. This change
does not close the remaining graphics, image, annotation, editing or corpus work.

References: [Adobe CMap and CIDFont specification, sections 5 and 7](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5014.CIDFont_Spec.pdf),
[PDF 1.7, sections 5.2 and 5.6](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf),
and [Ghostscript output devices](https://ghostscript.readthedocs.io/en/latest/Devices.html).

### Vertical composite text (2026-11-06)

Implemented Identity-V and embedded Encoding CMaps with WMode 1 for supported
CIDFontType2 TrueType fonts. The same Zig interpreter supplies extraction, glyph
transforms, CPU rendering, Metal paint collection and native/CLI replacement.

- DW2 defaults to origin-y 880 and displacement-y -1000; default origin-x is half
  the PDF horizontal width. W2 accepts per-CID triples and constant CID ranges,
  sorted for bounded lookup. Signed metrics, array boundaries, overlapping ranges,
  maximum CID values and finite numeric limits are validated.
- Vertical glyph placement subtracts the vertical origin before text/CTM transforms.
  Horizontal scaling applies to glyph shapes and horizontal origin offsets, while
  vertical advances and TJ adjustments remain unscaled. Tc/Tw follow the writing
  direction; Tw only applies to the single-byte character code 0x20.
- Replacement accepts shorter signed advances, including upward writing, and
  compensates along the selected writing axis. Empty replacement and overflow
  checks retain the next run's full bounds. Embedded font bytes remain unchanged.
- UseCMap inherits codespaces, CID mappings and notdefs, but **not writing mode**.
  The using CMap chooses WMode, defaulting to horizontal. A regression test catches
  accidental mode inheritance. Conflicting explicit stream/program modes fail.

`script/test_vertical_fonts.sh --built` passes 13 fixtures: defaults, both W2 forms,
character/TJ spacing with scale/rise, rotated text, upward writing, negative origin
coordinates and multi-CID ranges, CID 65535, default horizontal width, mixed-length
source codes, inherited mappings, dictionary-only mode, an Identity-V base and
single-byte word spacing. The native harness covers eager/indexed reads, CPU/Metal,
zero host fonts, text/annotation saves, empty replacement and oversized replacement.
It also exercises 64 deterministic metric mutations and rejects nine malformed
metric/mode cases. CLI checks confirm exact following-run preservation.

Independent MuPDF 1.26.5 traces compare Unicode, following glyph origins/bounds and
embedded font bytes before/after native, annotation and CLI saves. Ghostscript
10.02.1 independently checks text, unchanged following glyph boxes and original/
edited rasters at 288 dpi; the dictionary-only mode case uses MuPDF rasterization.
Full PNG/XML/log artifacts are retained under `test-out/vertical-fonts/`.

Reader differences are explicit rather than hidden by relaxed geometry checks:
MuPDF 1.26.5 does not scale the horizontal vertical-origin offset with Tz in these
fixtures, so Ghostscript verifies those rasters. Ghostscript 10.02.1 ignores a
WMode supplied only in the PDF stream dictionary; MuPDF verifies that fixture.
PDFKit cannot fully extract the custom mixed/inherited maps and produces unreliable
selection boxes after an upward-writing edit. PDFKit remains the native reading
selection provider, so engine support does not establish correct selection UI for
all vertical documents. These are fixture-specific observations, not claims about
all versions or all vertical PDFs. Font hinting differences are reduced by comparing
4x rasters; all applicable original/edited overlaps exceed 0.93.

All 80 engine unit tests pass, along with the standard-font, simple TrueType,
Identity-H, embedded CMap, ToUnicode and link regressions. Native text/markup/page
operations, independent PDFKit exports and CLI validation with 128 mutations pass.
The full application builds. An existing duplicate phase number in the app smoke
harness blocked the reading test at phase -27; disjoint destination-test phases fix
it. `script/test_react_editor.sh --built` now runs generic editor, reading/highlight/
note and internal-destination flows so the collision stays covered.

The broad engine objective remains open: this adds vertical layout for already
supported embedded TrueType composites, not predefined CJK maps, CFF fonts,
font shaping, subset expansion, paragraph editing or the remaining annotation and
graphics compatibility work.

References: [ISO 32000-1, sections 9.4.4 and 9.7.4.3](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf),
[Adobe CMap and CIDFont specification, section 5](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5014.CIDFont_Spec.pdf).

### Unicode comments and foreign comment model (2026-11-06)

Pod-created sticky-note comments now accept UTF-8 Unicode and serialize Contents as
UTF-16BE PDF text strings. Reopening decodes both the new representation and older
ASCII comments. Comment text remains metadata, so changing it does not alter the
icon appearance or require new embedded glyphs. Free-text annotation bodies remain
ASCII; this change does not claim Unicode free-text rendering.

The Zig annotation library also reads standard Text annotations with PDFDocEncoding,
UTF-16BE or BOM-marked UTF-8 contents, RGB/gray colors, ordinary Print/NoZoom/NoRotate
flags and conservative read-only/lock protection. It preserves original dictionaries,
normal appearances, icon names, author/subject/review metadata and popup references.
Text-only edits replace Contents and invalidate PDFKit's private stale annotation
archive, while keeping the external appearance stream/resources unchanged. No-op
updates do not change locked annotations. Rich-text content edits, appearance/geometry
changes and unsupported visibility flags remain explicit errors.

Associated Popup dictionaries are validated against their owning annotation and do
not become a second editable annotation. Deleting a comment removes its paired popup
from the page's annotation array. A comment with incoming reply references cannot be
deleted yet; the engine checks every page to avoid leaving a broken reply target.
Malformed/self-linked/orphan popup relationships fail rather than being dropped.

**Native-app boundary:** `pod_open` still requires render validation. External Text
annotations currently return `UnsupportedAnnotationAppearance`, including those with
no AP, until correct icon appearance and fixed-screen-size behavior are implemented.
The library model is exercised directly through `tools/comment_roundtrip.zig`; the
native/C bridge is exercised for Pod-created Unicode comments. No render-validation
bypass or alternate unchecked native-open API was introduced. The native error now
names an unsupported annotation appearance instead of incorrectly calling it ink.

`script/test_comments.sh --built` generates independent PDFKit and MuPDF comments,
reads/edits/saves/reopens/removes them through the Zig library, then checks results
with both readers. It verifies Unicode contents, author metadata, popup removal,
byte-identical appearance streams/resources and identical full-page MuPDF pixels
before/after a note-only edit. Native Engine checks cover Unicode comment creation,
replacement, save/reopen, unchanged CPU icon pixels and Metal page creation.
Three new unit tests cover Unicode creation, imported metadata preservation, locks,
no-op updates, rejected restyling/rich-text edits, reply protection and malformed
popup handling. All 83 engine unit tests pass. Native text/markup/page operations,
independent PDFKit annotation/page exports and the CLI contract with 128 mutations
also pass. The app builds, and the editor, reading/highlight/note and internal-link
UI smoke flows pass in the separate test app.

The independent fixtures expose the next rendering work: PDFKit's comment appearance
uses an explicit clip and ICCBased colors; MuPDF's uses a Form matrix, a local BBox and
a paired popup. The preserved artifacts are under `test-out/comments/`. Rendering
those forms, standard icon fallbacks, NoZoom/NoRotate behavior, popup/reply UI, richer
annotation text and remaining annotation types are still required for full support.

Reference: [ISO 32000-1, sections 12.5.5 and 12.5.6.4](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf).

## Path clipping and shared CPU/Metal geometry — 6 November 2026

The renderer now implements `W` and `W*` with nonzero and even-odd clipping.
The pending clip takes effect after the path-ending paint or `n` operation,
matching the [PDF clipping operator semantics](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.5_v6.pdf).
Strokes/fills on that same path still use the previous clip. Open subpaths are
implicitly closed for clipping, and `q`/`Q` save and restore the clipping region.
An empty path creates an empty region. An unterminated clipping operation fails
explicitly instead of silently disappearing.

`src/clip.zig` intersects flattened path edges by splitting horizontal slabs at
vertices and edge crossings, applying each input's winding rule and emitting
trapezoids. This handles holes, concavity, self-intersections, transformed paths
and successive clips. Both CPU rasterization and the Metal collector consume the
same resulting edges, including for strokes and glyph outlines. Content-bound
collection uses clipped geometry. Annotation rendering starts with an independent
clip; a page's final clip cannot hide subsequently painted annotations.

Intersection input/output edge counts are limited to 65,536, event storage to
65,536, and pair/scan work to 8,388,608 steps per intersection. Retained clip
geometry is limited to 1,048,576 edges per renderer. Exceeding these limits returns
`ClippingLimit`; the engine does not silently render an unclipped substitute.
These are explicit compatibility limits, not comprehensive hostile-file or
performance guarantees. Existing curve flattening remains approximate. Floating
point intersection vertices also retain normal coordinate-rounding limits.

Validation:

- The first integration test failed on the previously unsupported `W` operator.
  An additional regression caught and corrected acceptance of an unterminated `W`.
- All 87 engine unit tests pass, including 128 seeded pairs of crossing polygons
  checked against independent ray/winding membership at 131,072 sample points.
  The cases span small/large scales and translations. A sample within coordinate
  roundoff of an input boundary may differ after intersection vertices are stored
  as f64; the oracle bounds this tolerance to two relative machine epsilons.
  Invalid coordinates and adversarial edge-work limits have explicit tests.
- Glyph clipping preserves text-run positions and matches the unclipped glyph
  raster inside the clip, with white pixels outside it. Fill/stroke ordering,
  holes, transforms, nested/restored/empty clips and content bounds are checked.
- `script/test_clipping.sh` exercises 17 fixtures through native full/indexed
  opening and CPU/Metal rendering, at widths 612 and 1224. Each fixture is checked
  as original, saved, annotated and cropped/rotated: 136 independent MuPDF raster
  comparisons. Minimum foreground overlap is 0.996826; maximum mean channel
  error is 0.565611 out of 255. Independent original/saved renders are identical.
- Native text/annotation/page-operation checks, independent PDFKit annotation/page
  exports, font/TrueType/CID/Encoding-CMap/vertical-font suites, comments and links
  pass. The CLI contract passes 128 mutations. The full app build and generic,
  reading and destination editor smoke checks pass.

This completes path clipping within the stated geometry limits, not general PDF
appearance support. Text rendering modes that clip, form/image XObjects,
resource-driven color/graphics state and foreign comment appearance rendering
remain unfinished. Imported sticky notes still deliberately fail native opening
until their appearances and fixed-size/rotation behavior can be rendered correctly.

## Named color spaces and ICC matrix profiles — 6 November 2026

`src/color.zig` adds `CS`/`cs`, `SC`/`sc` and the solid-color variants of
`SCN`/`scn`. The content interpreter owns independent fill/stroke color selections,
including `q`/`Q` restoration, the initial color after selecting a space, component
arity and finite-value checks. Existing `g`/`G` and `rg`/`RG` now use the same
resolution and conversion path. DefaultGray/DefaultRGB overrides and ICC Range
entries are honored. Text-only inspection of CMYK operators remains available;
rendering them still fails explicitly.

`src/icc.zig` parses v2/v4 RGB matrix/TRC and gray TRC profiles with XYZ PCS. It
supports identity, single-gamma and sampled curves, plus all five ICC parametric
curve forms. Profiles are evaluated in Zig and converted from the D50 PCS to
sRGB. The parser validates header size/signatures, tag offsets and overlap, shared
tag payloads, curve bounds, required colorants and profile/channel agreement.
LUT transform tags take precedence in ICC; a profile containing such a transform
is rejected instead of silently using its matrix fallback. Profile objects are
cached within each document/page view, with invalidation on dictionary/stream
changes. Limits include 4 MiB per profile, 256 tags/profile, 65,536 sampled curve
entries, 256 cached profiles and 16 color-resource resolution levels. Existing
stream and document decode budgets still apply.

These transforms follow the [ICC profile specification](https://www.color.org/specifications/ICC.1-2022-05.pdf)
and [ICC's sRGB description](https://registry.color.org/rgb-registry/srgb).
Production code has no LittleCMS, Pillow, MuPDF or host ICC-parser dependency.
Native CGImages, view-rotation contexts and the Metal display view now explicitly
declare sRGB so their display interpretation matches the engine's output values.
A native regression first demonstrated the missing image tag before the change.

Validation:

- All 92 engine tests pass, including named fill/stroke state, all parametric curve
  forms, sampled curves, malformed/truncated tag data, ranges/default spaces,
  cached-profile invalidation and preserved CMYK text-inspection behavior.
- `script/test_colors.sh` checks 22 fixtures: system sRGB, Display P3, Adobe RGB,
  ROMM RGB and gray gamma profiles, plus five synthetic parametric-curve profiles,
  each selected explicitly and through a default-space override. All use native
  full/indexed loading, CPU/Metal painting, save/reopen and shorter text edits.
  Following-run bounds and exact embedded profile bytes remain unchanged. Glyph
  colors and explicit sRGB image tags are also checked.
- The 66 original/saved/edited outputs are compared to unoptimized relative
  colorimetric LittleCMS conversion without black-point compensation. Maximum
  measured channel difference is 1/255. Thirteen malformed fixtures are rejected,
  and 64 seeded ICC mutations reach native parsing/rendering without crashes.
- MuPDF independently checks saved appearance and extraction. Original/saved
  MuPDF renders are identical. For color probes, its in-memory reference disables
  optional black-point compensation, without changing any saved test PDF.
  MuPDF 1.26.5's wide-gamut grid conversion uses a 16-bit low-resolution LittleCMS
  transform; reproducing that configuration explains observed differences up to
  19/255 from the unoptimized reference. Those wide-gamut probes use that separate
  reference, while Pod continues to be checked against the accurate transform.
  The pinned reader's [conversion configuration](https://github.com/ArtifexSoftware/mupdf/blob/1.26.5/source/fitz/color-lcms.c)
  and [default compensation setting](https://mupdf.readthedocs.io/en/1.28.0/reference/c/fitz/colors.html)
  explain why a default reader screenshot is not an exact colorimetric oracle.

The full app build, generic/reading/destination editor smoke, native annotation and
page-operation suites, comments/links, standard and embedded-font suites, and all
136 clipping raster comparisons pass after this change. The CLI contract passes
128 mutations. No user app was relaunched and no changes were committed or pushed.

This is a color-resource prerequisite for foreign annotation appearance rendering.
Imported sticky notes still fail native opening until their AP form transforms,
resources, graphics state and fixed-size/rotation behavior are implemented.
General LUT/CMYK ICC profiles, Lab/CalRGB/CalGray, spot colors and patterns,
rendering-intent selection, black-point compensation and transparent color-space
blending remain unfinished. This does not establish full color management or
complete PDF support.

## Graphics-state resources and implicit transparency groups

The content interpreter now reads `gs` ExtGState resources, including indirect
resource dictionaries and parameter values. Supported entries are `LW`, `LC`,
`LJ`, `ML`, `ca`, `CA`, `BM` (all standard RGB modes; see below), `TK` and `Font`.
The same saved content state owns direct line operators, resource settings and
colors, so `q`/`Q` and content-array boundaries preserve them consistently.
Default-only entries accept `/SMask /None`, false `AIS`/`OP`/`op`/`SA`, zero
`OPM`, a solid `D` reset and RelativeColorimetric `RI`; `ri` also accepts that
intent. Unsupported fields and malformed values fail explicitly.
Setting `TK` inside `BT`/`ET`, malformed resources and path operations inside
text objects are rejected. Font selection shares the existing font loader/cache.

Separate fill/stroke alpha reaches both CPU and Metal. The interpreter's text
knockout setting creates one implicit group per text object; `TK false` instead
composites each glyph independently. Combined `B`, `B*`, `b` and `b*` operations
also use an implicit knockout group. Each member blends against the group's
initial backdrop, so overlap does not incorrectly accumulate opacity. A
zero-opacity member can erase an earlier member's contribution. Page graphics
state does not leak into annotation appearances.

Scene callbacks now include a unique, nonzero group id for knockout members.
The new `pod_collect_paints_with_state` C entry point exposes it without changing
the old callback ABI. Legacy collectors reject translucent/blended knockout
scenes rather than silently compositing them incorrectly. Metal keeps the
backdrop in per-pixel kernel state. CPU backdrop rows allocate lazily and are
reused across groups; worst-case pixel storage adds 128 MiB to the existing
64 MiB bitmap limit, plus a row table and geometry allocations. This is not a
total engine memory cap.

`script/test_graphics_state.sh` covers 21 independently generated fixtures and
15 malformed/unsupported inputs through full and indexed native opening.
Original, saved, annotated and cropped/rotated variants run at 1x and 2x on
CPU and Metal. The 168 independent raster comparisons have a maximum mean
channel error of 0.301659/255, with separate interior color probes to catch
small overlap errors. Tests also verify C group boundaries and legacy callback
rejection, font selection through ExtGState, indirect parameters and state
continuation across content streams.

Reference behavior follows PDF 1.7 sections 5.2.7 and 7.6.2:
<https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf>.
MuPDF 1.26.5 does not consistently retain implicit text knockout boundaries and
skips zero-alpha paint. Ghostscript 10.02.1 matches ordinary text knockout and
transparent borders, but flushes text groups at some state changes and skips
zero-alpha glyphs. For those two text cases, the test-only reference expands
the specified implicit group into an equivalent explicit knockout Form group;
the zero-alpha glyph case uses the fixture font's identical rectangular glyph
outlines. Reference rewrites stay under `test-out/graphics-state/references`;
source and saved PDFs remain untouched and are compared independently for
appearance preservation. Neither reader is a production dependency.

Initial graphics-state verification also passed all 93 engine unit tests, the full app build, native
editor/reading/destination smoke tests, clipping/color/comment suites, standard
and embedded font suites, link/page-operation checks, independent PDFKit
annotation exports and 128 CLI mutation cases. The smoke tests ran in the
separate Pod UI Test app.

Remaining transparency work includes alpha-as-shape, soft masks,
isolated/non-isolated Form groups and overprinting. General
dash patterns, stroke adjustment, rendering intents and transfer functions are
also unfinished. This work does not yet enable arbitrary foreign annotation
appearances or complete the overall engine goal.

## Standard RGB blend modes

`src/blend.zig` implements all 16 standard PDF blend modes: Normal, Multiply,
Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight,
Difference, Exclusion, Hue, Saturation, Color and Luminosity. The nonseparable
modes preserve the specified luminosity and saturation, including grayscale
inputs and gamut clipping. ColorDodge and ColorBurn include the corrected
black/white endpoint behavior published by Adobe in 2009. The formulas come
from PDF 1.7 section 7.2.4, with those corrections described by the PDF
Association:
<https://github.com/pdf-association/pdf-differences/tree/main/ColorBurn-ColorDodge>.

The saved graphics state carries the selected mode. `Compatible` aliases
Normal; a `BM` array selects the first recognized name, including indirect
names, and falls back to Normal when no name is recognized. An unrecognized
single name remains an explicit unsupported error. Malformed array members
are rejected. Source colors blend in the renderer's RGB output space; this
does not enable CMYK, spot colors or explicitly declared page/Form blending
spaces that the engine still rejects.

CPU and Metal evaluate the same formulas before applying opacity and coverage,
including the existing implicit text and fill/stroke knockout groups.
`pod_collect_compositing_paints` exposes stable mode ids defined in
`PodBlendMode`. Earlier C callback signatures are preserved, with adapters
rejecting modes their ABI cannot represent rather than treating them as
Normal or Multiply.

`script/test_blends.sh` covers 38 fixtures: each mode at opacity 1 and 0.37,
five alias/fallback cases and a ReportLab-produced mixed-mode PDF. Each targeted
fixture includes a 16-by-16 color-pair grid, clipped fill/stroke and overlapping
embedded glyphs. Original, saved, annotated and cropped/rotated variants are
checked at 1x and 2x on CPU and Metal. The 304 independent raster comparisons
have maximum mean channel error 1.158409/255 and maximum interior probe error
4/255. Fallback output must also match the equivalent named-mode output
exactly. Saved appearances and embedded font bytes are preserved, and tests
verify every C mode id and older callback rejection.

The independent reference uses MuPDF 1.26.5 and Ghostscript 10.02.1. MuPDF's
8-bit premultiplied source conversion can amplify byte loss in ColorDodge and
ColorBurn at partial alpha; Hue also differs for partially transparent gray
sources. Ghostscript matches the analytic blend results for these cases and
is used for those modes and the mixed ReportLab fixture. Saturation, Color
and Luminosity use MuPDF: a saturated-yellow Saturation probe matched Pod and
Core Graphics at `[255,255,2]`, while Ghostscript gave `[254,254,11]`.
Non-endpoint fixture colors are kept away from byte-rounding thresholds;
exact zero and one remain explicit endpoint tests. No comparison tolerances
were increased to hide these reader differences.

As in the graphics-state tests, the test-only reference expands the implicit
text knockout group into equivalent rectangular glyph outlines inside an
explicit Form group. Reference copies also resolve fallback arrays according
to section 7.5.2 because the reader does not handle every array form. These
rewrites never change native inputs or saved outputs. Targeted unit tests
check the corrected endpoints, both SoftLight branches, nonseparable expected
values, bounded results, and rendered Screen/Difference state restoration.

Final verification passed all 97 engine unit tests, the app build, native
editor/reading/destination smoke tests, graphics-state/clipping/color/comment
suites, standard and embedded font suites, link/page-operation checks,
independent PDFKit annotation exports and 128 CLI mutation cases. Native UI
smoke tests used the separate Pod UI Test app. The reader precision analysis
also consulted MuPDF's pinned source without using it in production:
<https://github.com/ArtifexSoftware/mupdf/blob/1.26.5/source/fitz/draw-blend.c>.

The engine still lacks general transparency groups, masks, alpha-as-shape and
overprinting. This completes RGB blend-function coverage, not the complete
transparency implementation or the overall engine goal.

### Ordinary Form XObjects and affine strokes (2026-11-06)

The content interpreter now executes `Do` for ordinary Form XObjects. These are
reusable PDF artwork/content streams, not interactive form fields. Each invocation
inherits the caller's graphics state, concatenates its Matrix, clips to its BBox,
uses its own resource dictionary when supplied, and restores the invoking state.
Absent resource dictionaries inherit the invoking scope; an explicitly empty local
dictionary does not fall back to individual parent resources. Forms can nest, use
compressed streams, and execute within page content arrays. Degenerate BBoxes clip
to an empty region; reversed rectangle corners are normalized.

Extracted text retains the actual Form stream ID, operator span, transformed position
and page execution order. A unique Form text run supports a shorter replacement
without moving the following text. The writer keeps the Form dictionary and resource
graph. Repeated or cross-page stream executions reject editing rather than changing
other instances. Streams reachable from annotation appearance resources are also
protected. Indexed page views now reject text replacement because a single-page view
cannot establish whether another page shares that stream. Editing a shared occurrence
by cloning its resource graph remains future work.

Rendering uses the same nested BBox clips on CPU and Metal. Nonuniformly scaled and
skewed strokes are expanded in normalized stroke space and transformed back into
device coordinates. Device hairlines stay one pixel wide. A new pixel check exposed
and fixed a pre-existing missing bevel triangle, including miter-limit fallback.
Clipping now emits only inside/outside boundaries and merges contiguous pieces of
the same original edge. This removes redundant interior edges without approximating
the boundary. The ReportLab circle at 2x dropped from 26,690 clipped edges to 671,
bringing its scene under the existing Metal work limit instead of falling back to CPU.

`script/test_forms.sh --built` covers 19 fixtures and 192 independent rasters, including
an unmodified ReportLab-produced file, nested/resource-scoped text, original and saved
files, shorter edits, annotation isolation, crop/rotation, merge/reorder/extraction,
nonuniform stroke caps/joins, reflected strokes, and hairlines. Full and indexed native
opening share CPU/Metal pixel checks. Unsupported and malformed Form dictionaries,
missing local resources, cycles, unfinished paths and escaped graphics state are
rejected. Unit checks also cover recursive depth/expansion limits, shared page and
annotation use, BBox clipping and inherited/restored graphics state.

Independent checks use MuPDF 1.26.5 and Ghostscript 10.02.1, with test-only FontTools
embedded glyph fixtures to avoid comparing different standard-font substitutions.
Ghostscript is used for affine round-join cases because MuPDF's result differs from
transformed circular outlines; analytic pixel checks and Ghostscript agree with Pod.
The indirect-to-indirect alias fixture needs test-only reference normalization: MuPDF
resolves its dictionary but does not load its stream through the alias, and pypdf
cannot read that alias object. Native input/saved files are not normalized. Other saved
Form streams are checked byte-for-byte through pypdf. The alias still receives native
save/organization and normalized independent raster comparisons.

Maximum whole-image mean channel error is 0.632353/255; maximum solid interior error
is 1/255. Minimum solid mask overlap is 0.969444. Device-dependent hairlines use a
trace-neighborhood check and an independent one-pixel ink-area check instead of exact
coverage equality; their minimum mask overlap with Ghostscript is 0.748739. The
ReportLab file's PageMode/Info metadata still blocks page assembly explicitly; its
ordinary save, annotation and crop/rotation checks pass without dropping metadata.

All 110 engine tests pass. The app builds. Native annotation/page operations, PDFKit
exports, 128 CLI mutations, clipping/graphics-state/blend/color suites, standard and
embedded fonts, CID/Encoding-CMap/vertical fonts, comments/links, and the separate
React editor/reading/destination smoke app pass. The user's running app was not
replaced or relaunched. Evidence logs are under `/tmp/pod-forms-*.log`; fixture and
render artifacts are under `test-out/forms/`.

Form execution is bounded to 64 nested calls, 16,384 invocations, one million parsed
syntax nodes/operators and 256 MiB of processed stream bytes per page, including
repeated execution. Nearly singular nonuniform stroke transforms return an explicit
error. Transparency groups, optional-content Forms, external references/OPI, images,
and general imported annotation appearance placement/icons remain unfinished. This
milestone does not enable arbitrary external sticky-note appearance rendering or
complete the engine goal.

## Normal annotation appearance previews

The engine now loads an annotation's normal appearance (`AP/N`), resolving its
selected named state (`AS`) when necessary. The annotation must belong to the
requested page, and its reference generation is checked. The shared Form interpreter
handles its resources, nested Forms, graphics state and BBox clipping. Placement
transforms all four BBox corners by the Form Matrix, then maps that enclosing box to
the annotation Rect. Degenerate Form bounds clip to an empty preview. Annotation
`CA` is not applied a second time: an existing appearance controls its own opacity.

The library exposes CPU rendering and geometry collection. The C bridge and
`Engine.annotationAppearance` expose the same path to native callers, using Metal
when available. Output is an opaque preview on white, cropped to the unrotated
annotation Rect; it is not an overlay for compositing onto a page. Invalid annotation
IDs clear C output buffers, and preview dimensions retain the renderer's bitmap
limits. Transparency groups, images and other unsupported Form content still fail
explicitly rather than producing incomplete previews.

Six unit tests cover placement, named-state selection (including a state named
`Subtype`), invalid references/states, degenerate geometry and display transforms.
The transform helper preserves the PDF upper-left anchor for NoZoom/NoRotate across
four page rotations, four zoom levels and two pixel densities. Text annotations
implicitly receive both flags. At this milestone that helper was not yet integrated with the viewer.

`script/test_comments.sh --built` checks actual CPU and Metal previews at widths
24, 48 and 96. Inputs include PDFKit and MuPDF sticky notes plus controlled offset,
scale, rotation, skew, reflection, named-state, nested-Form and opacity fixtures.
Note-only edits preserve the original preview pixels and appearance bytes/resources.
Independent MuPDF comparisons cover 36 previews. Reference-only copies expose the
unchanged appearance streams as Stamp annotations on blank local pages, removing
reader-specific sticky-icon substitution and screen flags from this placement test.
Maximum mean channel error is 4.001736/255 at small antialiased edges; all checked
uniform interiors match exactly. This does not establish whole-page comment display.

Verification includes all 116 engine unit tests, the complete app build, standard
font rendering, comments, links, native annotation/page operations, independent
PDFKit exports and 128 CLI mutations. Shared renderer regressions pass 192 Form,
136 clipping, 168 graphics-state and 304 blend-mode independent rasters. The separate
React smoke app also passes reading/highlighting, saved Unicode notes, erasing,
undo/redo and destination navigation. Formatting, Python compilation and shell
syntax checks pass. Logs are `/tmp/pod-appearance-{app-build,verified,graphics,editor,engine}.log`;
appearance fixtures and PNGs are in `test-out/comments/`. The user's running Pod
app was not relaunched.

At this milestone, native opening of foreign sticky notes remained guarded. Finishing that
path required a viewer layer that keeps icons upright and fixed in size while their
page anchors move, plus matching hit regions, popup/reply behavior and fallback
icons for comments without appearance streams. This remains part of the active
engine goal, alongside the other requirements below.

## Page-view comment compositing

The renderer now accepts explicit magnification and an additional clockwise view
rotation through `renderPageViewWithFonts` and `collectPageViewWithFonts`. Raster
width determines output resolution; magnification excludes backing pixel density.
The C bridge (`pod_render_page_view` / `pod_collect_page_view`), Metal collector and
`Engine.pageViewPixels` expose the same behavior on indexed page handles. Rotation
must be 0/90/180/270 and is added to the PDF page rotation without modifying it.

This path paints supported imported and Pod-created sticky-note appearances over
page content in annotation order. Each appearance starts with independent graphics
state, uses its Form BBox clip, and composites directly against the page and earlier
annotations. The page content's final clip does not clip annotations. The PDF-space
upper-left anchor follows the page; implicit NoZoom/NoRotate keeps the icon upright
and physically constant across magnification. Existing AP opacity and blend modes
are honored without multiplying the annotation's `CA` again. Normal appearance
previews remain available separately.

A new analytic unit test checks every output pixel over four rotations, three zoom
levels and two pixel densities, including transparent regions, alpha blending and
page-clip isolation. Native tests require actual Metal collection, compare all
CPU/Metal bytes, check invalid view inputs clear C output buffers, and confirm that
view rotation does not change the source page geometry. Independent MuPDF checks
cover 24 cropped/rotated page views with two overlapping appearances, skewed Form
geometry, alpha and Multiply blending. Maximum mean error is 0.236607/255 and maximum
uniform-interior error is 2/255. For this oracle, reference-only copies use Stamp
semantics to preserve the AP, resized Rects to represent NoZoom, and MuPDF's NoRotate
handling. The independent reader performs AP placement, clipping and compositing;
the analytic test separately verifies fixed size and anchor geometry.

All 117 engine tests pass, and the full app builds. The comment suite retains its
36 independent preview checks and existing Unicode/preservation checks; Pod-created
comments also match canonical rendering at 100%. Shared Form and blend regressions
pass 192 and 304 independent rasters respectively. The separate editor/reading
smoke app and URI/internal-link suites pass. Formatting, Python compilation and
shell syntax checks pass. Logs are `/tmp/pod-comment-view-*.log`; page-view PNGs and
independent reference PNGs are in `test-out/comments/`. The user's app was not relaunched.

At this milestone the cached-scene editor was not connected to this API. Its zoom shortcut
scales the existing scene, and view rotation rotates its bitmap; either would also
scale or rotate a baked-in sticky icon. Callers must regenerate these page-view
results when zoom/rotation changes. At that stage native opening remained guarded until
scene refresh, matching hit regions and comment interaction were integrated; the
next milestone below completes that integration for supported appearances. Comments
without an AP, unsupported appearance content, popup/reply behavior and broader
annotation types remain unfinished. This is progress toward the full engine goal,
not completion of imported-comment support.

## Imported comments in the native editor

Supported foreign Text annotations with normal appearance streams now open in the
native editor. Full-document validation and ordinary raster/collector APIs use 100%
magnification at their requested output resolution; native editing therefore works
without bypassing appearance validation. A C metadata flag identifies imported
comments so the UI can preserve their original geometry and styling while allowing
unlocked plain-text note edits and deletion. Locked annotations remain read-only.

The native engine records the magnification and view rotation used for pages with
sticky notes. The controller passes that state through opening, navigation, edits,
undo/redo, page operations, shared-document loading, eraser previews and destination
navigation. Zooming cannot reuse a scene containing fixed-size comments, and view
rotation regenerates those scenes. The canvas avoids applying view rotation twice.
Both CPU images and Metal scenes use the same page geometry and fixed icon hit
regions. Selection outlines and resize handles follow those regions; imported notes
cannot be dragged or restyled. Pod-created comments retain movement/resizing, with
appearance padding accounted for during resizing.

Select an imported note on the page or in the existing comments pane to read or
edit it. The React and native inspectors expose its note text and deletion while
hiding appearance controls; the native command handler also rejects style changes
for these selections. Note-only edits preserve appearance streams/resources,
author/review metadata and popup references. The comments pane provides current
interaction; floating popup windows, initially open popup state, reply threads,
rich-text editing and fallback icons for comments without AP streams remain unfinished.

Native comment tests open PDFKit/MuPDF and controlled normal-appearance fixtures,
edit Unicode note text, save/reopen and verify unchanged pixels. The separate editor
smoke app checks actual mouse selection at 200% and 50%, view rotation on a PDF with
an existing rotation/crop, unchanged source rotation, protected geometry/styles,
sidebar text availability, editing, deletion and undo/redo. It runs against both
Metal and CPU. A new animation assertion caught a delete-fade mask still using the
scaled PDF Rect; the mask now follows the displayed fixed-size icon. The assertion
passes with intermediate opacity on both renderers and respects reduced motion.
UI fixtures use `test-out/comment-ui/` separately from the engine's
`test-out/comments/` so concurrent suites do not overwrite each other's inputs.

Verification: all 117 engine unit tests, 51 Playwright tests, the full app build,
CPU/Metal editor smoke tests, native annotation/page operations, PDFKit exports,
128 CLI mutations, comment/link suites and 496 independent Form/blend rasters pass.
Comment rendering retains 36 independent isolated previews and 24 whole-page views.
Formatting, Python compilation and shell syntax checks pass. Evidence logs are
`/tmp/pod-comment-editor-*.log`; the final build/editor/link run is
`/tmp/pod-comment-editor-complete.log`. The failed animation check is retained in
`/tmp/pod-comment-fade-red.log`. The user's running app was not relaunched.

## Sticky notes without appearance streams

Text annotations with absent or null AP entries now use Pod-owned vector icons for
Note, Comment, Key, Help, NewParagraph, Paragraph and Insert. Missing and unknown
icon names use Note without rewriting the original Name. This follows the standard
icon names and AP precedence in [PDF 32000-1, Text annotations](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf).
A present but malformed AP dictionary, missing normal state, unsupported Form content
or invalid color/opacity still reports an explicit error; those failures do not
silently select a fallback icon. Non-Text annotations do not gain fallback support.

The engine draws the icons using its existing paths, curve flattening, stroke
expansion and CPU/Metal compositing. It uses no host font or external renderer.
RGB/grayscale colors and annotation opacity are supported, with contrasting details
for dark colors. Overlapping details use one initial backdrop so opacity applies
once to the icon as a whole. The existing fixed-size/upright page transform, hit
regions, selection, delete fade and comments pane apply to fallback icons too.
Rendering never creates an AP stream or changes the original document objects.

Two unit tests add distinct-icon, default-name, grayscale, zero-opacity, AP precedence,
malformed-data and exact before/after-save checks. `script/test_comment_icons.sh`
checks nine inputs through native opening, CPU/Metal rendering at three zoom levels,
fixed painted pixel counts, Unicode note editing, save/reopen and independent PDFKit
reading. MuPDF separately verifies unchanged Name/color/opacity/flags/author/popup
metadata, continued absence of AP, and identical independent page rendering before
and after each note edit. Icon artwork is reader-defined, so these tests do not
claim pixel equality between Pod's icons and another reader's icon designs.

The separate editor smoke app now runs both appearance-backed and missing-appearance
notes on CPU and Metal. It exercises mouse selection, 200%/50% zoom, view rotation,
appearance protection, note editing, delete fade and undo/redo. Fallback fixtures and
preview PNGs are in `test-out/comment-icons/`; UI inputs remain isolated under
`test-out/comment-ui/`. Floating popup windows, initial Open state, reply threads,
rich-text editing and broader annotation coverage remain part of the active goal.

Verification: all 119 engine unit tests and the full app build pass, alongside the
new fallback suite, existing comment/link suites, all editor smoke runs, 192 Form
and 304 blend-mode independent rasters. Existing AP checks retain 36 isolated
preview and 24 whole-page independent comparisons. Representative Help, Key and
NewParagraph previews were visually inspected. Formatting, Python compilation and
shell syntax checks pass. Logs are `/tmp/pod-note-icons-*.log`; the initial failing
missing-appearance test is in `/tmp/pod-note-icons-red.log`. The user's running app
was not relaunched.

## Sticky-note popup metadata and native interaction

Supported Text comments now expose Unicode author and subject, saved initial Open
state, optional popup bounds, and the presence of rich-text contents. The cached
annotation model supplies these through `pod_comment_info` and `Engine.pageInfo`,
including indexed page handles. Repeated metadata reads reuse the cached strings
and leave serialized PDF bytes unchanged; C output is zeroed on failure.

An associated Popup's Open flag takes precedence, defaulting to closed. Without a
Popup, the Text annotation's Open flag is used. The owner may identify its Popup
without a reverse Parent entry, which is optional in the
[PDF specification](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf).
The open-state distinction is also described in Adobe's
[Text annotation API](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdflsdk/apireference/PD_Layer/PDTextAnnot.html).
If Parent exists it must identify the owner. Shared, orphaned, self-linked and
malformed associations still fail explicitly, including a shared popup omitted
from the page's annotation array. Optional null fields act as absent entries.

The native canvas opens saved-open comments as fixed-size cards showing author,
subject and selectable plain text. Double-clicking an icon opens its card; Close
Note hides it. Cards use saved popup position when available, stay within the
viewport, and update across zoom, view rotation, edits and undo. Open/closed choices
persist during the current document session and reset when another document is
opened or pages are reorganized. These viewing choices do not modify saved Open
flags. Edit Note uses the existing guarded sheet and annotation mutation path.
Locked and rich-text notes are read-only; the native and React inspectors also
prevent unsupported rich-text edits. Rich text is never interpreted as HTML.

`script/test_comment_popups.sh` covers independent MuPDF-produced open, closed,
parentless, unpaired and rich-text fixtures, full/indexed native metadata, C string
lifetime/error behavior, Unicode edits, and independent metadata/appearance
preservation. The editor smoke suite covers initial opening, close/reopen, zoom,
rotation, editing, undo and document-session reset on CPU and Metal, plus rich-text
popup/sidebar protection. Artifacts are in `test-out/comment-popups/`; the CPU popup
and Metal captures were visually inspected in dark and light appearances. The initial missing-metadata and missing-popup
failures are in `/tmp/pod-popup-red.log` and `/tmp/pod-popup-ui-red.log`; shared-popup
validation has its own failing regression in `/tmp/pod-popup-shared-red.log`.

Verification: all 120 engine tests and 52 Playwright tests pass. The full app builds;
popup, existing comment, fallback-icon and link suites pass, as does the full native
editor smoke suite on the relevant CPU/Metal paths. A startup timing issue in the
new smoke test was traced with debug symbols to WKWebView reporting a zero-sized
viewport before its first layout; the test now waits for that viewport and then
asserts the popup has a visible layout. Engine/native results are in
`/tmp/pod-popup-final.log`; the final successful editor/link run is in
`/tmp/pod-popup-editor-final.log`, and web results are in `/tmp/pod-popup-web.log`.
Formatting, Python compilation, shell syntax and whitespace checks pass.

Reply threads, rich-text editing, standalone Popup annotations, popup support for
other markup types, user-resized/repositioned popup persistence and broader foreign
annotation support remain unfinished. This is an additional engine milestone;
the full completion goal remains active.

## Comment reply threads and consistent notes navigation

The engine now reads same-page `IRT` relationships with default or explicit
`RT /R`, resolves nested roots, and rejects cycles, missing parents, cross-page
parents and stale generations. `RT /Group` remains explicitly unsupported because
annotation grouping has different semantics. Text replies may have empty rectangles
and the NoView flag; they remain visible within their thread without independent
page icons. Existing author, subject, review State/StateModel and popup metadata are
preserved. Rich-text contents and locked annotations retain their edit protections.

`addReply` and `pod_comment_reply` create standard Text replies with Unicode contents
and author names without modifying parent dictionaries or synthesizing appearance
streams. Creation validates the parent, UTF-8, limits and read-only indexed handles.
Updates preserve the parent relationship, and deletion rejects annotations with
incoming replies, including shape parents. Removing leaf replies and extracting
pages retain valid thread relationships. C metadata reads and mutations share the
existing annotation cache and invalidate it after successful changes.

Native popups display nested reply rows with selectable text and per-row Reply,
Edit and Delete actions. The existing sheet, mutation, save and undo paths handle
creation and editing. Parent deletion is disabled in native and React inspectors,
keyboard shortcuts and popup actions; the engine enforces the same rule. Selecting
a reply restores its root selection. Comments are grouped in the sidebar, and
saved-open children open their root popup. Existing review states are displayed;
a review-state editing or resolution workflow has not been implemented.

The notes navigator now uses engine annotation IDs and relationships instead of
PDFKit annotation ordinals. PDFKit does not reliably expose IRT through its public
annotation key lookup. It remains the system reading-order and passage-snippet
helper. Blank pages skip passage selection when engine text runs are empty,
avoiding a CoreGraphics diagnostic for an absent Contents entry while retaining
their annotations. The asynchronous navigator surfaces engine failures and keeps
its existing cancellation and result limits.

`script/test_replies.sh` uses independent MuPDF-produced Text, Highlight, review-state
and zero-rectangle/NoView fixtures. It checks native/full/indexed metadata, grouped
navigation, Unicode creation and editing, parent protection, C failure outputs and
cache invalidation, identical page pixels after adding a reply, CPU/Metal agreement,
PDFKit reopening, and remapped relationships after page extraction. MuPDF verifies
unchanged original annotation dictionaries and the newly saved reply links. Invalid
cycles, orphaned and cross-page parents, grouping and stale generations are rejected.

The editor smoke suite exercises nested reply creation, leaf editing/deletion,
parent protection, undo/redo and independent reopening on CPU and Metal, including
a Highlight root and a nonvisual reply. The web suite has 53 passing tests, including
parent deletion protection with text editing still available. Artifacts are under
`test-out/replies/`. Initial failing checks are recorded in
`/tmp/pod-replies-red.log`, `/tmp/pod-replies-create-red.log`,
`/tmp/pod-replies-empty-rect-red.log`, `/tmp/pod-replies-reading-red.log`,
`/tmp/pod-replies-ui-red.log` and `/tmp/pod-replies-web-red.log`.

The completed build/editor/comment/popup/icon/link regression run is recorded in
`/tmp/pod-replies-editor-final.log`. The native reply suite after the blank-page
snippet fix is in `/tmp/pod-replies-native-clean.log`. The engine unit suite, C and
Swift bridges, independent 18-tool PDFKit check, page operations and 128 CLI mutation
cases pass in `/tmp/pod-replies-core-final.log`. A final app rebuild and complete
editor/link rerun after the snippet fix pass in `/tmp/pod-replies-app-clean.log`.
The CPU thread popup was visually inspected, and Zig formatting, Python compilation,
shell syntax and whitespace checks pass. This is an annotation milestone,
not completion of the full PDF engine. Grouped annotations, review-state editing,
rich-text editing and the broader engine requirements below remain open.

## Sampled image XObjects on CPU and Metal

The content interpreter now dispatches Image XObjects alongside Forms, with the
same bounded indirect-reference resolution and per-execution work accounting.
`src/images.zig` owns image dictionary validation and sample interpretation. It
reuses document stream decoding and caches, plus the existing color conversion;
no production image or PDF decoding is delegated to a third-party reader.

Supported samples include 1, 2, 4, 8 and 16 bits per component, byte-aligned rows,
grayscale/RGB and supported ICC spaces, default color-space substitutions, decode
arrays, and the existing lossless stream filters/predictors. Image masks use the
current fill color; color-key masks compare original samples before Decode. Nearest
sampling follows the first-row-at-top PDF convention. Interpolation uses bilinear
premultiplied-alpha sampling to avoid transparent-edge color fringes. The image
attributes follow Adobe's [image documentation](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdflsdk/apireference/PD_Layer/PDImage.html).

CPU rendering maps device coordinates back into the image unit square and shares
vector coverage, clipping, opacity and RGB blending. Images inside nested Forms
and supported normal annotation appearances follow the same path. Transparent
stencils contribute no content bounds; masked bounds use the outer extent of
visible samples, including interpolation support. These are conservative bounds
for masks with disconnected visible regions.

The new `pod_collect_image_scene` ABI emits ordered vector and image callbacks.
Image callbacks borrow clipped edges, RGBA8 samples, inverse placement and sampling
mode for their duration only. The native Metal collector copies samples into a
bounded shared buffer and includes image commands in the existing tile bins. Both
page-view and isolated appearance collection use this API. Older paint-only
collectors return UnsupportedImageCollection instead of omitting images. Very
large/distant scenes retain the existing explicit collection failure and native
CPU fallback; the image test requires a real Metal scene for every supported fixture.

Image checks cover transformed and reflected placement, clipping, transparency,
interpolation, nested Forms, comment appearances, packed grayscale depths, decode
reversal, stencil polarity, color keys, Flate/ASCIIHex and PNG predictors, ICC/default
RGB colors and an independently MuPDF-produced document. Native checks use both
full and indexed handles, save/reopen, rotation and page assembly. PDFKit verifies
independent document opening. MuPDF separately compares raster output and exact
preservation of image dictionaries and encoded stream bytes.

CPU doubles and Metal floats can select adjacent texels at exact sharp boundaries.
The comparison permits only sparse one-pixel-neighborhood differences, and rejects
incorrect interior colors. The independent appearance fixture explicitly sets the
Text annotation NoZoom/NoRotate flags: MuPDF requires those flags to keep its custom
AP upright, whereas Pod follows the implicit Text behavior required by the
[PDF reference](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.6.pdf).
This is a documented reader difference, not a change to Pod's display semantics.

Initial missing-image, missing-Metal and transparent-bound regressions are in
`/tmp/pod-images-red.log`, `/tmp/pod-images-metal-red.log` and
`/tmp/pod-images-bounds-red.log`. Unit and expanded native checks are in
`/tmp/pod-images-expanded.log`; the complete final image run is in
`/tmp/pod-images-verified.log`, with independent comparison detail also in
`/tmp/pod-images-independent-final.log`.
Fixtures and raster artifacts are under `test-out/images/`.

Verification: 126 engine tests pass. The 23 image fixtures produce 184 independent
raster comparisons across originals, saved/rotated/assembled copies and two output
sizes. Maximum mean channel error is 0.810/255, with maximum solid-interior error
1/255 after excluding a three-pixel independent raster edge-filter margin. Isolated
image appearances use a required Metal scene and match the CPU preview exactly;
legacy-collector failure and invalid appearance-view parameters are also checked.

The full app builds and its complete editor/link smoke run passes, including image
opening, zoom, annotation creation, undo and view rotation on CPU and Metal.
An existing ink smoke assertion could run after metadata completion but before
Metal presentation; it now waits for the replacement scene before checking that
the draft overlay has cleared. The initial failure and separate diagnostic run are
in `/tmp/pod-images-app-regression.log` and `/tmp/pod-images-ui-diagnostic.log`;
the successful final run is `/tmp/pod-images-app-final.log`. The user's running app
was not restarted. Form/blend regressions add 496 independent raster comparisons
in `/tmp/pod-images-graphics-regression.log`. Bridge, 18-tool annotation, page-operation
and 128 CLI mutation checks pass in `/tmp/pod-images-core-regression.log`.
The transformed image preview was visually inspected; formatting, Python compilation,
shell syntax and whitespace checks pass. The overall engine goal remains active.

The decoder rejects unsupported codecs and image masks, malformed sample lengths,
invalid bit depths, dimensions, Decode/mask arrays and optional-field types.
Limits are 65,536 per dimension, 16 million pixels, 64 MiB decoded samples and
256 MiB expanded RGBA work per content execution, including repeated images. JPEG,
JPEG 2000, CCITT/JBIG2, inline images, indexed/CMYK/other color spaces, explicit and
soft-mask images, image editing and broader corpus/performance work remain open.

## Sequential JPEG images

`src/jpeg.zig` adds owned Zig decoding of DCTDecode streams. The decoder reads
8-bit SOF0 baseline and SOF1 extended sequential Huffman frames, quantization and
canonical Huffman tables, byte-stuffed entropy, signed coefficients, restart
intervals and EOI completion. It supports grayscale and three-component images,
interleaved or separate/mixed component scans, DC reset at scan/restart boundaries,
16-bit quantization in extended frames, separable inverse DCT and bilinear chroma
upsampling. PDF ColorTransform is applied unless an Adobe APP14 marker overrides
it. The stream filter validates image dimensions and bit depth against the JPEG;
the image loader validates channel/sample counts against the PDF color space.
No host JPEG codec is used in production.

`script/test_jpeg.sh` covers 19 valid cases and ten invalid or unsupported PDFs,
using Pillow 11.3.0/libjpeg-turbo and local `cjpeg` 3.2.0 as independent producers.
The fixtures include odd dimensions, optimized tables, restart wraparound,
separate and mixed scans, 16-bit quantization, raw YCbCr ColorTransform=0,
Adobe override, filter chains and a 480 by 640 page for native UI checks.
Native full/indexed handles render through CPU and required Metal scenes with
exact sample equality. Save/reopen and merge/extract retain the decoded image;
all original encoded JPEG streams and dictionaries remain unchanged.

Independent libjpeg sample comparisons pass with maximum channel error 3/255
and maximum mean error 0.2/255. MuPDF and libjpeg-turbo differ in reconstructing
subsampled chroma: the original 4:2:2 fixture differed between the two reference
decoders by mean 4.983/255 before any Pod processing. The verifier therefore
keeps a strict libjpeg sample check, verifies placement against MuPDF rendering
of those independently decoded samples, and requires exact MuPDF original/saved
JPEG page equality. It does not increase a tolerance to conceal that difference.
The initial discrepancy is recorded in `/tmp/pod-jpeg-native.log`; the expanded
passing native/oracle run is `/tmp/pod-jpeg-final.log`.

129 engine tests pass, including the analytic constant-block JPEG, every truncated
prefix and three single-byte mutations at each position of that stream, bounded
output allocation and allocation-failure cleanup. The test allocator reports no
leaks. The log is `/tmp/pod-jpeg-safety.log`.

The app build and full React/native editor smoke suite pass, including JPEG page
opening, zoom, annotation creation, undo and view rotation on CPU and Metal.
The link/destination suite passes after UI fixture generation. Existing sampled
images pass all 23 fixtures and 184 independent raster comparisons
(`/tmp/pod-jpeg-image-regression.log`). The C bridge, 18 annotation tools,
independent PDFKit annotations/page operations and 128 CLI mutation cases also
pass. The 480 by 640 native JPEG raster was visually inspected. Zig formatting,
Python compilation, shell syntax and whitespace checks pass. The user app was
not restarted; UI checks ran in the separate test bundle.

The implementation follows [ITU-T T.81](https://www.w3.org/Graphics/JPEG/itu-t81.pdf)
and the [PDF reference DCTDecode rules](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf).
At that milestone, progressive, arithmetic, lossless, hierarchical, 12-bit and
four-component JPEGs remained explicit unsupported cases. Limits are 16 million output pixels, 64 MiB
component planes, the stream output budget and 10,000 markers. This milestone
does not close the remaining codec, image/color, annotation or overall engine work.

## Progressive JPEG images

The Zig decoder now accepts 8-bit SOF2 progressive Huffman frames. It retains
coefficients across DC and AC scans, tracks the approximation bit for every
component/band, handles first and refinement scans, and reconstructs pixels after
EOI. Signed DC refinement uses appended two's-complement bits; AC refinement
increases the signed magnitude, including newly nonzero values, zero runs and
end-of-band runs. Restart markers reset DC prediction and EOB state. EOB runs
cannot cross restart or scan boundaries. Quantization tables are retained per
component when that component starts, so later table definitions cannot alter
already-decoded components.

Malformed bands, refinement without an initial scan, duplicate initial scans,
interleaved AC scans, skipped approximation levels, missing tables, truncated
entropy and bad restart sequences fail explicitly. Work is bounded to
256 * 1024 * 1024 coefficient visits, in addition to the existing pixel, stream
and marker limits. Progressive coefficient storage adds at most 256 MiB to the
64 MiB component-plane budget, with cleanup on every failure path.

Verification: 132 engine tests pass, including analytic initial/refinement
streams, negative DC refinement, EOB overrun rejection, every truncated prefix
and three mutations per byte of both minimal sequential/progressive streams,
and injected allocation failures. The log is `/tmp/pod-progressive-safety.log`.
The initial independent suite failed at `UnsupportedJPEGProcess`, as recorded
in `/tmp/pod-progressive-red.log`, before the implementation was added.

The expanded JPEG suite passes 33 valid cases and 16 malformed/unsupported PDFs.
Progressive cases cover grayscale, 4:4:4/4:2:2/4:2:0 chroma, odd/tiny/narrow
images, flat color and deterministic noise, restart markers, reordered spectral
bands, deeper refinement, DC-only images and late quantization redefinitions.
Native full/indexed CPU and required Metal output match exactly. Save/reopen and
page assembly preserve samples, while independent MuPDF reads confirm exact
original/saved JPEG rendering and encoded-stream/dictionary preservation.
Maximum error against independent libjpeg reconstruction remains 3/255 per
channel and 0.2/255 mean. The log is `/tmp/pod-progressive-final.log`.

The DC-only fixture initially differed from Pillow because libjpeg applies
optional smoothing to estimate missing coefficients in incomplete progressions.
A lossless `jpegtran` conversion of that fixture's coefficients to sequential
JPEG removes that estimation without changing the coefficients. Pod matches
that independent reconstruction within 2/255 per channel and mean 0.017/255.
The test uses this oracle for DC-only images and keeps the original strict
sample threshold. Pod reconstructs the coefficients actually supplied; it does
not estimate missing image detail or expose intermediate scan previews.

The full app build, complete React/native smoke suite and subsequent link suite
pass in `/tmp/pod-progressive-app.log`. Both baseline and progressive JPEG pages
open, zoom, annotate, undo and rotate on CPU and Metal. The sampled-image suite
still passes its 23 fixtures and 184 independent raster comparisons
(`/tmp/pod-progressive-image-regression.log`). C-bridge and 18-tool annotation
checks, independent PDFKit page/annotation checks and 128 CLI mutations pass in
`/tmp/pod-progressive-core-regression.log`. Formatting, Python compilation, shell
syntax and whitespace checks pass. All test processes completed; the user app
was not restarted.

Arithmetic, lossless, hierarchical, 12-bit and CMYK/four-component JPEGs remain
unsupported. The overall engine goal remains active.

## CCITT monochrome scans

`src/fax.zig` implements owned Zig T.4/T.6 decoding through CCITTFaxDecode.
It handles Group 3 one-dimensional, mixed Group 3 and Group 4 two-dimensional
coding, terminating/makeup Huffman codes, repeated makeup codes, horizontal,
vertical and pass modes, EOL fill, RTC/EOFB and PDF byte alignment. Reference
transitions are scanned monotonically rather than rescanning a line for every
mode. The code assignments are the factual T.4/T.6 tables also published in
[RFC 804](https://www.rfc-editor.org/rfc/rfc804.txt); framing and recovery follow
[the PDF reference](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.3.pdf).

Rows is ignored when EndOfBlock is true, as required by the PDF filter. Missing
row counts can terminate at the marker or, with EndOfBlock false, exhausted data.
BlackIs1 controls decoded polarity before normal image Decode arrays/stencil
painting. Image dimensions/depth must agree with decoded data. The filter uses
shared numeric/boolean parameter handling; null optional parameters use defaults
instead of being treated as invalid values. DamagedRowsBeforeError resynchronizes
Group 3 rows at EOL and substitutes the preceding undamaged row, or white after
consecutive damage. The default remains strict rejection. Uncompressed fax
extension modes report UnsupportedFaxExtension.

Limits are 65,536 columns/rows, 16 million pixels, the stream output budget,
256 * 1024 * 1024 consumed/probed bits and a bounded number of row operations.
Two packed row buffers and one transition array serve all rows. Intermediate
storage and output are released on errors. The Huffman lookup tables are built
at compile time; production uses no TIFF/PDF library dependency.

The initial analytic Group 4 test failed at UnsupportedFilter in
`/tmp/pod-ccitt-red.log`. Independent libtiff fixtures then exposed a byte-aligned
MH bug: padding plus a run prefix could look like EOL. Alignment now happens
before optional-EOL recognition for that mode, with an analytic regression test.
A separate null-parameter test failed before fixing the shared parameter default
handling (`/tmp/pod-ccitt-null-red.log`).

139 engine tests pass in `/tmp/pod-ccitt-safety.log`. Checks include 6,000-pixel
white/black runs with repeated makeup codes, malformed run bounds, unsupported
extensions, output limits, every truncated prefix and 1,024 byte mutations of
a minimal Group 4 stream, and allocation-failure cleanup. The renderer's existing
4,096-pixel output-width limit remains unchanged; the longest run is checked
directly through the decoder and rendered long-run fixtures use width 4,093.

`script/test_ccitt.sh` passes 26 valid cases and 11 malformed/unsupported PDFs
in `/tmp/pod-ccitt-final.log`. Pillow/libtiff produces Group 3/4, mixed, fill-aligned,
MH, narrow, long-run, checkerboard and scanned-notes images. Hand-built fixtures
cover RTC, byte-aligned Group 4, unknown row counts and recovery. Full/indexed
native reads require exact CPU/Metal sample equality; save/reopen and merge/extract
preserve samples and original encoded streams/dictionaries. Twenty-five cases
also match MuPDF rasters exactly. The shared native codec harness now lives in
`macos/codec_image_test.swift` and serves both JPEG and CCITT suites.

The damaged-row fixture matches the PDF-specified previous/white substitutions.
MuPDF reports a malformed code and renders it differently; its filter parameter
loader does not apply DamagedRowsBeforeError. Ghostscript also gives a white
replacement for the first damaged row in this fixture. These are recorded as
independent-reader differences, not pixel-equivalence passes. Exact original/saved
MuPDF rendering and byte preservation are still checked for this case.

The app build and full React/native smoke suite pass in `/tmp/pod-ccitt-app.log`,
including the scanned-notes fixture on CPU and Metal and the subsequent links suite.
JPEG and sampled-image regressions pass in `/tmp/pod-ccitt-codec-regression.log`.
The C bridge, all 18 annotation tools, independent PDFKit annotation/page checks,
and 128 CLI mutation cases pass in `/tmp/pod-ccitt-core-regression.log`. The processes
were confirmed terminal before starting the next engine change.

## Explicit and soft image masks

`src/images.zig` now loads explicit image-mask streams and DeviceGray SMask image
streams. The base image and mask keep independent dimensions, Decode arrays and
interpolation flags through CPU rendering and Metal scene collection. Soft masks
override Mask, bypass DefaultGray color conversion and retain 1/2/4/8/16-bit alpha
decoding. Masks use the existing stream filters, including JPEG. Nested masks,
cycles, wrong subtypes, malformed samples, invalid color/depth and oversized
dimensions fail explicitly. Mask streams and dictionaries remain unchanged on save.

Matte components are validated against the parent color space and require matching
dimensions. Preblending is undone before color conversion; interpolation uses
alpha weights to avoid colors from fully transparent samples. The behavior follows
the image-mask and Matte definitions in sections 4.8.5 and 7.5.4 of the
[PDF reference](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.4.pdf).
Mask bounds participate in content bounds, including completely transparent images.
Both planes count toward the existing 256 MiB image-execution/scene budget;
each plane remains limited to 16 million samples. Metal commands now carry an
independent float alpha plane with its own dimensions and interpolation flag.
The C callback borrows both arrays only for its duration.

Initial native tests failed at UnsupportedImageMask (`/tmp/pod-mask-red.log`).
The first Metal run failed on the explicit-mask fixture before the separate plane
was added (`/tmp/pod-mask-native-red.log`). A Matte test first showed the unwanted
background color before unblending (`/tmp/pod-mask-matte-red.log`). All 146 engine
tests now pass in `/tmp/pod-mask-safety.log`, including independent-resolution masks,
Decode reversal, soft-mask precedence, transparent bounds, analytic blend pixels,
malformed child/matte validation, and allocation failures through CPU rendering
and image-scene collection.

`script/test_images.sh --built` passes 47 valid fixtures and 18 malformed/unsupported
fixtures in `/tmp/pod-mask-expanded.log`. Each valid fixture is opened through full
and indexed native paths, rendered on CPU and Metal at two scales, and saved,
rotated, merged and extracted. The 376 independent raster comparisons use MuPDF
for 45 cases and Ghostscript for two cases, retaining a mean difference below
2/255 and flat-interior difference below 3/255. Observed maxima are 0.80970625/255
mean and 2/255 interior. Tests also compare raw image/mask dictionaries and encoded
bytes and exact original/saved MuPDF rasters. Fixtures include a MuPDF-produced
transparent image, masks within Forms and comment appearances, JPEG alpha,
ICC-color Matte, varying mask resolution/depth/polarity, clipping and interpolation.

MuPDF 1.26.5 differs on the soft-mask + Multiply + constant-alpha case and on
interpolated Matte. The former matches analytic compositing and Ghostscript to
rounding; the latter uses premultiplied interpolation and matches Ghostscript
within the unchanged raster thresholds. These cases use Ghostscript as their
raster oracle, while still checking unchanged MuPDF output after save. They are
not reported as MuPDF pixel-equivalence passes. General graphics-state soft masks
and transparency groups remain separate unfinished work.

The app builds and the complete React/native smoke suite passes in
`/tmp/pod-mask-app.log`, including masked-image opening, zoom, annotation, undo and
rotation on both CPU and Metal, followed by the links/destinations suite. JPEG and
CCITT regressions pass in `/tmp/pod-mask-codec-regression.log`. The C bridge,
18 annotation tools, native page operations, independent PDFKit exports and 128
CLI mutation cases pass in `/tmp/pod-mask-core-regression.log`. The mask gradient
artifact was visually inspected. Python/shell syntax, Zig formatting and diff
whitespace checks pass. These results complete this mask milestone, not the full
PDF-engine goal.

## Indexed palettes and producer compatibility

Indexed color spaces now resolve gray, RGB and supported ICC base spaces, direct
and indirect lookup strings, and filtered lookup streams. Packed 1/2/4/8-bit image
indices retain the PDF default Decode mapping, clip to the declared palette, and
use nearest-integer selection after non-default mappings. Vector SC/SCN/sc/scn
colors share conversion, initialize at index zero and restore through q/Q.
The palette borrows document-owned lookup bytes instead of allocating a color
conversion cache. Tables require the exact declared length, at most 256 entries;
nested Indexed spaces, invalid indices/table sizes and 16-bit indexed images fail
explicitly. Existing stream, reference, image and scene budgets still apply.

Indexed images support interpolation, color-key masking on raw indices, explicit
and soft masks, nested Forms and ICC/default-space conversion. Matte is supplied
as a color in the Indexed space: a single palette index. It is expanded to base
components before undoing preblending, rather than unblending index values.
An initial RGB-array assumption failed the corrected unit fixture and was fixed.
The source for these rules is the [PDF reference, sections 4.5.5, 4.8.4 and 7.5.4](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.4.pdf).

Independent-reader differences are kept explicit. For the fractional Decode
fixture (samples 0, 26, 76, 128, 204, 255 with Decode [0 5]), Pod selects palette
entries 0, 1, 1, 3, 4, 5. PDFBox 3.0.5 renders the same pixels; MuPDF 1.26.5 selects
0, 0, 1, 2, 3, 4 using its quantized fixed-point multiplier, and Ghostscript
10.02.1 selects 0, 0, 1, 2, 4, 5. The [PDFBox sample decoder](https://github.com/apache/pdfbox/blob/3.0.5/pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/image/SampledImageReader.java)
uses nearest-integer rounding after Decode. Indexed Matte also matches PDFBox
exactly at the diagnostic scale, while the other two readers differ. Those two
fixtures use PDFBox for independent raster comparisons without relaxing the
thresholds. Original/saved MuPDF appearance equality is still checked for every
fixture. PDFBox is checksum-pinned in the test script and never linked or bundled
into the production engine; Java is required only for this test reader.

A Pillow 11.3 palette PDF exercises two narrowly scoped compatibility cases:
free object zero with offset zero and generation 65536 normalizes to 65535, while
live-object overflow and other invalid generations remain rejected. Complete
ASCIIHex image streams can end at their declared boundary without `>`; sample
length validation still rejects truncated images, and non-image ASCIIHex remains
strict.

That producer also exposed page assembly's rejection of document Info metadata.
Assembly now preserves Unicode string and scalar custom fields, resolves indirect
values and combines compatible fields across sources. Explicit null fields survive
extraction; a populated value takes precedence over null when combining sources.
Conflicting values and
structured custom fields still fail rather than choosing a source silently.
Info streams, cycles and oversized dictionaries are rejected; the merge has a
1,024-field limit and a one-million-entry work limit. Allocation-failure checks
cover metadata assembly and indexed image collection. XMP and general document
catalog preservation remain separate unfinished work.

Validation now covers 158 passing Zig tests, 69 valid image fixtures and 31 invalid
image fixtures. All 552 image comparisons (four round-trip/page-operation variants
at two sizes) pass through CPU/Metal, full/indexed reads and independent readers.
Encoded image dictionaries/streams and the filtered palette stream survive saves;
Pillow and Unicode metadata fields are also checked after save, rotation and page
assembly. The native image harness rejects invalid input on both loading paths.
The ICC suite passes its 22 profiles, 13 invalid fixtures and 64 mutations; JPEG
and CCITT regressions also pass. The C bridge, all 18 annotation tools, independent
PDFKit exports/page operations and the 128-case CLI mutation contract pass.
The final image run has a maximum mean channel difference of 1.6870125/255 and
maximum flat-interior difference of 2/255. The app builds, and the copied native
UI-test bundle passes its reading, comment, popup, reply and image interactions,
including the Pillow palette PDF on CPU and Metal. Links pass again after the
UI suite regenerates their fixtures. Final unit/build/image/UI/link evidence is
in `/tmp/pod-indexed-completion.log`; the core contract evidence is in
`/tmp/pod-indexed-core-regression.log`. No running user app was restarted.
These checks establish the supported palette/metadata subset, not complete PDF
compatibility. The overall engine goal remains active.

## CalGray, CalRGB and Lab conversion

The shared color path now handles all three calibrated PDF families in owned Zig
code. CalGray applies its gamma and white point; CalRGB applies component gammas
and the declared column-major XYZ matrix; Lab uses its piecewise XYZ conversion
and declared component ranges. A precomputed Bradford adaptation maps the source
white point to D65 before the sRGB transfer function. Vector fills/strokes, text,
image samples, Indexed palettes and default-space substitutions share this path.
The source definitions follow [PDF reference sections 4.5.4 and 4.8.4](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.4.pdf).

Lab image default Decode uses [0 100 amin amax bmin bmax]. Palette bytes scale to
those same base ranges. Explicit Decode, color-key and soft masks continue through
the existing image pipeline. A dedicated test verifies that Matte is removed in
Lab before conversion to RGB; doing it after conversion gives different colors.
WhitePoint, Gamma, Matrix, Range and BlackPoint parameters are validated, including
indirect parameters and optional null entries. Invalid dimensions/types/ranges,
nonfinite or oversized numbers and singular white-point adaptation fail explicitly.
The new color descriptors need no heap allocation. Rendering remains relative
colorimetric without optional black-point compensation, as with the ICC path;
BlackPoint remains preserved in the original PDF rather than rewriting its colors.

The new `script/test_calibrated_colors.sh` runs 17 calibrated vector/text cases,
12 malformed cases and 64 bounded mutations through the native color harness.
It uses LittleCMS's independent illuminant adaptation and XYZ-to-sRGB transform
as the accurate color oracle, including clipping, unequal gammas, D50/D65/equal-
energy whites, Lab range restrictions and device defaults. Normal cases also
agree with MuPDF; wide-gamut identity-matrix cases use Ghostscript. Native colors
differ from LittleCMS by at most 1/255 in these cases, and verified PDF-reader
comparisons differ by at most 2/255. Saved and edited calibration dictionaries
remain unchanged, and shorter text replacements retain neighboring text positions.

Lab reader discrepancies are explicit: MuPDF 1.26.5 returns its built-in Lab space
without loading the dictionary's WhitePoint or Range in
[`pdf-colorspace.c`](https://github.com/ArtifexSoftware/mupdf/blob/1.26.5/source/pdf/pdf-colorspace.c).
Its Lab results are recorded diagnostically, not counted as equivalent colors.
Lab image oracles expand samples with LittleCMS into an RGB PDF, then use an
independent reader for page placement, rotation and soft-mask compositing. The
original Lab PDF's appearance is still independently compared before/after save.
No production engine code calls LittleCMS, MuPDF, Ghostscript or PDFBox.

A PyMuPDF rewrite of a calibrated image adds compressed object/xref coverage. It
exposed MuPDF's one-byte object-zero generation sentinel of 255. The parser now
normalizes that unused free entry only when the generation field is one byte and
its next-free field is zero; live object zero, other malformed sentinel values and
ordinary object generations retain their checks. A focused regression failed
before the change and verifies canonical save/reopen and preserved live generations.

Validation passes 164 Zig tests and 79 image fixtures (632 CPU/Metal and independent
comparisons), plus 31 malformed image fixtures. The image suite's maximum mean
channel difference is 1.6870125/255 and maximum flat-interior difference is 2/255.
The existing 22-case ICC suite, native C bridge, all 18 annotation tools, independent
PDFKit page/annotation checks and 128 CLI mutation cases pass. CLI inspection also
reads the calibrated Lab document's text correctly. The app builds and its copied
UI-test bundle opens, zooms, annotates, undoes and rotates Lab and independently
rewritten CalRGB documents on CPU and Metal. User app sessions are not restarted.

The calibrated/ICC passes and the initial producer failure are recorded in
`/tmp/pod-cie-final.log`. The repaired unit/build/image/UI/link run is recorded in
`/tmp/pod-cie-completion.log`, and the final core checks in
`/tmp/pod-cie-core-final.log`. UI image fixtures now use `test-out/image-ui`, avoiding
changes to the independently verified source/save files in `test-out/images`.
The isolated-fixture rerun is recorded in `/tmp/pod-cie-isolated-ui.log`.
Python/shell syntax, Zig formatting and diff whitespace checks pass. This closes
the calibrated-color milestone; the broader engine requirements below remain open.

## Inline images in content streams

Inline `BI` / `ID` / `EI` images now execute through the existing image sink in
`content.zig`, sharing CPU/Metal geometry, clipping, color conversion, opacity and
blend behavior. This includes images inside nested Forms and supported comment
appearances. `inline_image.zig` normalizes the standard dictionary and filter
abbreviations, validates direct dictionary values and supported color declarations,
and applies the existing dimension, sample and execution limits before rendering.
Unknown dictionary keys are ignored as specified; indirect inline values and
ambiguous duplicate keys are rejected. The format follows
[Adobe PDF Reference 1.4, section 4.8.6](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.4.pdf).

Raw data length comes from padded sample rows. Each first-stage filter reports
its exact consumed input: zlib footer, ASCII terminator, RunLength/LZW EOD,
JPEG EOI parsed by the decoder, or CCITT row/end framing. No binary `EI` search
or repeated candidate decompression is used. Flate, LZW, ASCIIHex, ASCII85,
RunLength, baseline/progressive JPEG and supported CCITT modes work with chains
and predictors. Inline CCITT with no EOB marker and no Rows uses image Height.
JPEG comments containing fake EOI and `EI` bytes do not terminate images early.
The ID separator consumes one whitespace character, treating CRLF as one line
ending; additional whitespace remains sample data.

Dictionary and decoded sample storage is scoped to the synchronous image
callback. Inline decoding does not enter the document stream cache. Allocation
failure checks cover parsing, filtered palettes, rasterization and scene collection;
100 repeated renders retain the same document arena capacity. Save preserves
original inline-containing streams, and text replacement on both sides keeps the
inline bytes and the following text position. Existing unsupported codecs and
color spaces remain unsupported; this adds no host rendering fallback.

A real ReportLab inline-image fixture also exposed catalog `PageMode /UseNone`
and page `Trans <<>>` preservation gaps during assembly. Assembly now preserves
compatible standard PageMode/PageLayout names and clones page-local transition
dictionaries. Invalid or conflicting viewing settings fail explicitly. This does
not enable presentation transitions in the UI or general catalog graph assembly.
The fixture is tested without stripping its metadata.

`script/test_inline_images.sh` generates 44 valid and 23 malformed fixtures plus
64 deterministic mutations. Coverage includes every supported first-stage filter,
filter arrays, predictors, packed 1/2/4/8/16-bit samples, Indexed/resource/calibrated
colors, default color spaces, stencils, interpolation, false delimiters, JPEG
comments, nested/compressed content, appearances, blending, text edits, and
ReportLab/Pillow/libtiff output. Native full/indexed reads and CPU/Metal images
pass across save, rotation and merge/extract variants at two sizes. Independent
checks cover 354 raster comparisons, with maximum mean difference 0.699/255 and
maximum flat-interior difference 1/255. MuPDF 1.26.5 reports a post-image syntax
error for the mixed T.4 inline fixture; Ghostscript 10.02.1 is its strict oracle
and agrees with native output (mean 0.000834/255 at 200 pixels). All other inline
fixtures use MuPDF. No tolerance was relaxed for the discrepant reader.

All 170 Zig tests pass (`/tmp/pod-inline-unit-final.log`); the inline native and
independent checks pass in `/tmp/pod-inline-completion.log`. Existing JPEG,
CCITT and 79-image regressions pass in `/tmp/pod-inline-jpeg-regression.log`,
`/tmp/pod-inline-fax-regression.log` and `/tmp/pod-inline-image-regression.log`.
The native C bridge, all 18 annotation tools, Swift page operations, independent
PDFKit annotations/page exports and 128 CLI mutations also pass.

The app builds (`/tmp/pod-inline-app.log`). The full React/native smoke suite
passes (`/tmp/pod-inline-ui.log`), including opening original ReportLab and
progressive-JPEG inline pages, zooming, annotating, undoing and rotating on both
CPU and Metal. Inline UI fixtures use `test-out/inline-ui`, separate from
independent round-trip artifacts in `test-out/inline-images`. Link/destination
checks pass afterward in `/tmp/pod-inline-links.log`. The rendered ReportLab
fixture was also visually inspected. Python/shell syntax, Zig formatting and
whitespace checks pass. This completes the inline-image milestone; the engine
requirements below remain open.

## Dashed strokes and bounded Metal edge filtering

Page and Form graphics now accept line dash patterns through `d` and ExtGState
`/D`. The owned Zig parser validates finite, nonnegative lengths, rejects a nonempty
all-zero pattern and bounds the array to 128 entries. Odd arrays repeat twice;
phases normalize over the full cycle. Empty arrays restore solid strokes.

Stroke generation measures lengths in user space, including nonuniform/reflected
transforms and hairlines, and restarts the pattern for each subpath. It retains
corners inside a dash, joins fragments across closed seams and preserves the
selected cap on open fragments and zero-length dots. Square dots follow the path
direction. A dash starting exactly after the path endpoint is not painted. A
single dash covering a closed contour retains all its joins. All fragments use
one paint operation, avoiding accumulated opacity in overlapping caps. Annotation
rendering resets page dash state. Changes to the CTM inside an unfinished path
are rejected as malformed path syntax.

Dense curves exposed the old 2,048-edge-per-paint Metal limit. Large paints now
filter edges by tile row while retaining one command per original draw in each
bin. Forward tile halos cover preview sample footprints up to 32 source pixels.
The existing 300-million edge/pixel work budget remains; expanded edge storage
is bounded to two million, commands to 100,000 and bin entries to two million.
Small paints retain their original path. Preview scaling now uses a uniform
factor on both axes, avoiding vertical stretching from rounded bitmap heights.

Verification:

- All 174 Zig tests pass, including phase equivalence, odd arrays, square-dot and
  closed-corner pixel probes, annotation isolation and allocation-failure cleanup.
- `script/test_dashes.sh --built` passes 38 valid and 11 invalid fixtures through
  full/indexed native reads and CPU/Metal rendering at 612 and 1,224 pixels.
  Original, saved, annotated, cropped/rotated and assembled variants produce 380
  independent raster comparisons. Maximum mean difference is 0.926401/255 and
  maximum uniform-interior difference is 1/255. Short dashes use bidirectional
  one-pixel trace containment, strict interior checks and mean error below 1/255;
  perimeter-sensitive mask overlap is not the acceptance criterion.
- A 4,000-edge grid exercises the expanded Metal path and checks a 61-pixel
  preview against CPU output, including tile-boundary sample footprints.
  At the app's 2,400-pixel render width it exceeds the retained work budget and
  uses the owned CPU renderer. The smoke test requires Metal on initial opening,
  then requires that fallback at 2x zoom and compares its pixels with a direct
  CPU render after annotation/undo and view rotation. No host PDF renderer is
  used as a fallback.
- Page content bytes, XObject streams and viewing settings survive saves. The
  fixture producer includes an unmodified compressed ReportLab document.
- Shared-renderer regressions pass for Forms (194 independent rasters), graphics
  state (168), blend modes/knockout (304), external and inline images. Native C/Swift
  checks, all 18 annotation tools, independent PDFKit annotation/page exports and
  128 CLI mutation cases also pass.
- The native app builds and the full React/WKWebView editor smoke passes in the
  isolated `PodReactUITest.app`, including ReportLab dashes on CPU/Metal and the
  dense-grid work-budget fallback. Test launches ignore saved application state
  so a failed assertion cannot block later runs behind macOS's recovery dialog.
  The user's running Pod instance is not restarted.

Reader differences are explicit: MuPDF loses precision for the very large phase
and differs on negative phase wrapping, so oracle-only copies reduce those two
phases to their equivalent positive values. Native/saved inputs remain unchanged.
PDFBox checks the dashed closed seam; Ghostscript checks the fully covered closed
rectangle because PDFBox and MuPDF leave caps at that seam. Analytic corner tests
independently require the miter joins. These readers are test-only dependencies.

Dashing remains bounded by existing path geometry limits (65,536 points and
16,384 contours) and one million splitting steps. Tiny patterns and singular
transforms fail explicitly. This milestone does not enable dashed link borders,
annotation border-style UI, transparency groups, soft masks or general graphics
support. The complete engine goal remains active.

## Foreign vector shape annotations

Standard Square, Circle, Line, PolyLine and Polygon annotations with supported
normal appearances now open in full/indexed native paths. Rendering uses the
existing owned Form/image/graphics pipeline on both CPU and Metal. AP takes
precedence over the annotation's border metadata, including named normal states,
transformed BBoxes, shared streams, dashed borders, line endings and custom
content. The AP's own opacity is not multiplied by annotation CA again.

The native model exposes a separate imported-shape capability without extending
the existing public C annotation struct. Unlocked shapes can be selected, dragged,
noted in Unicode and deleted. Translation updates Rect and L/Vertices together;
the original AP dictionary and streams remain unchanged. Relative rectangle
insets, caption offsets, line endings, border effects, author, dates, subject and
custom metadata survive. Text edits invalidate only PDFKit's private stale cache
in addition to Contents. Edits stage a private dictionary before committing.

Imported-shape styling and resize handles are protected, while moving remains
available. Nonuniform point edits and style changes fail explicitly rather than
replacing an arbitrary appearance with a simpler one. Locked annotations reject
move, note and delete changes; rich-text notes remain readable but protected.
Shape notes join the existing comments pane and notes navigator. The new native
smoke exercises selection, drag, protected styling, Unicode note edits, independent
PDFKit reopening, deletion/undo/redo and zoom/rotation on CPU and Metal.

Validation covers 14 valid PDFs from MuPDF, PDFKit and controlled byte-level
fixtures, plus 12 invalid/unsupported inputs. Original, saved, noted, moved,
removed, cropped/rotated and assembled variants produce 188 independent raster
comparisons (maximum mean error 0.981138/255; maximum uniform-interior error
1/255). Appearance dictionaries, decoded/encoded streams and metadata are checked
across saves and page assembly; shared appearances remain untouched when one
annotation moves. MuPDF incorrectly caps a dashed polygon's closed seam; that
fixture uses Ghostscript, matching the analytic closed-dash tests. Other shape
fixtures use MuPDF. These readers/producers remain test-only dependencies.

All 176 Zig tests pass, including exact translation, Unicode notes, AP preservation,
rejected resize, locked mutations, missing-AP rejection and allocation-failure
cleanup through parse, update, render and save. Native integration additionally
checks the C capability bridge, full/indexed CPU/Metal output and independent
PDFKit note reopening.

The rebuilt app and full React/WKWebView smoke suite pass in the isolated test
bundle, including all four new shape runs (arrow-ended line and named-state
appearance, each on CPU and Metal). Existing comment/reply suites, 380 dashed
stroke comparisons, all 18 native annotation tools, PDFKit annotation/page
exports, 128 CLI mutations and the post-smoke link suite pass. The user's running
Pod instance was not restarted. Evidence is in `/tmp/pod-shape-final.log`,
`/tmp/pod-shape-unit-2.log`, `/tmp/pod-shape-comments.log`,
`/tmp/pod-shape-replies.log`, `/tmp/pod-shape-dashes.log`,
`/tmp/pod-shape-core.log`, `/tmp/pod-shape-ui.log` and `/tmp/pod-shape-links.log`.

This is a compatibility milestone toward the full engine, not full shape support.
Missing-AP synthesis, restyling/resizing, CMYK metadata colors, hidden/fixed-screen
flags, grouped annotations and the other annotation families remain unfinished.
Existing geometry limits apply: 4,096 vertices, 1,000 annotations per page,
coordinates bounded to one million, and the shared AP execution/render budgets.

## Rectangles and ellipses without appearance streams

Standard Square and Circle annotations now render without AP streams through
owned vector geometry on both CPU and Metal. Existing normal appearances remain
authoritative; an invalid or incomplete AP dictionary still fails explicitly.
The fallback supports RGB/grayscale or transparent stroke/fill, annotation opacity,
zero-width invisible borders, solid/dashed BS dictionaries, legacy Border arrays,
BS precedence, rectangle insets and cubic ellipse outlines. Fill and stroke share
one opacity group. No PDF objects or appearance streams are created during display;
notes, movement, save/reopen and page assembly retain the original metadata and
absence of AP. Imported-shape resize/restyle protection remains in place.

Border parsing validates finite bounded values, dash limits and nonnegative RD
insets whose opposing sums are smaller than the annotation rectangle. Cloudy
border effects, nonzero legacy corner radii, unsupported border styles, CMYK
metadata colors and collapsed inset geometry fail explicitly. Existing APs can
still carry supported drawings for those metadata cases.

Reader behavior is recorded rather than hidden by wider tolerances. RD components
are applied to the corresponding Rect coordinates (left, lower, right, upper),
matching asymmetric MuPDF/PDFBox probes; the older reference describes them as
left/top/right/bottom. Zero/absent RD uses half the border width. The default dashed
BS pattern is [3], as specified in [ISO 32000-1 table 166](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf).
MuPDF and PDFBox omit that default during fallback, so oracle-only copies make
it explicit. MuPDF also caps the seam of the dashed square. Those two square
fixtures use PDFBox with an analytic standard appearance and a single opacity
group; fourfold supersampling avoids Java2D's whole-pixel placement of fractional
transparency-group bounds. Original and saved inputs are unchanged. All other
fallback fixtures compare directly with MuPDF. These remain test-only readers.

The shape suite now covers 34 valid fixtures (including 20 missing-AP cases) and
18 invalid/unsupported fixtures. Native full/indexed rendering, CPU/Metal agreement,
translation, Unicode note editing, deletion, protected edits and round trips pass.
Independent save/assembly metadata checks and 468 raster comparisons pass, with
maximum mean difference 0.981138/255 and maximum uniform-interior difference 2/255.
The 178 Zig tests pass, including exact no-mutation saves, border defaults and
precedence, opacity-overlap probes and allocation-failure cleanup through fallback
parsing, rendering, moving, noting and saving. Evidence: `/tmp/pod-shape-fallback-unit.log`,
`/tmp/pod-shape-fallback-native.log` (native checks), and
`/tmp/pod-shape-fallback-oracle.log` (final independent checks).

The native app builds (`/tmp/pod-shape-fallback-app.log`) and the complete isolated
React/native smoke suite passes (`/tmp/pod-shape-fallback-ui.log`), including four
new missing-AP runs (dashed rectangle and inset ellipse, each on CPU and Metal).
Selection, drag, Unicode note editing, deletion/undo/redo, independent PDFKit note
reopening, zoom and rotation pass. The post-smoke link/destination suite passes
(`/tmp/pod-shape-fallback-links.log`). Core C/Swift bridges, all 18 annotation tools,
independent PDFKit annotation/page exports and 128 CLI mutations pass
(`/tmp/pod-shape-fallback-core.log`). Both new fallback shapes were visually
inspected. Formatting, Python/shell syntax and whitespace checks pass. The user's
running app was not restarted.

Other shapes without APs, resizing/restyling and the remaining full-engine
requirements remain open; this is progress toward the existing goal.

## Editing imported rectangles and ellipses

Supported Square/Circle annotations without APs now expose resize and appearance
editing through the C bridge, Swift model, native inspector and React inspector.
Corner dragging changes the rectangle while retaining its relative insets; color,
fill, opacity and border-width changes retain dash patterns and other metadata.
An appearance change writes a fresh Form with local coordinates and its own
opacity resources. Translation and note-only edits preserve existing AP bytes.
Old/shared appearance objects are never rewritten. Metadata edits and appearance
allocation are staged before committing the annotation; allocation failure leaves
the original object and object count unchanged.

A saved shape remains editable only when its Pod marker, normal appearance,
resources, BBox, numeric operands and painting operators agree with the supported
metadata-driven geometry. Verification accepts ordinary numeric round-trip noise,
not arbitrary artwork. Extra appearance states, transforms, changed streams or
resources, and illegal indirect operands in a content stream disable regeneration.
Custom foreign appearances remain movable/notable but protected from resizing
and restyling. Locks and rich-text-note restrictions remain enforced. This adds
an independent capability getter without changing the existing public C structs.

Inset probes exposed two rendering gaps. Each RD component is now at least half
the stroke width, keeping the complete border inside its rectangle; fallback
painting also uses the normal rectangle clip. A closed curve whose last point
repeated its first point lost the join across its zero-length closing segment.
The shared stroker now removes redundant adjacent/closing points for every join
style. An exact-image regression checks implicit versus explicit closure for
miter, round and bevel joins with both solid and dashed strokes.

The expanded shape suite includes 22 fallback cases, including partial insets with
wide borders. It exercises independent resizing, restyling, further editing after
saving/reopening and fractional translation, metadata/dash retention and fresh
appearance allocation. Unit checks additionally cover shared APs, stale markers,
custom drawing commands, illegal references, transforms, locks, and allocation
failures before and after the first regeneration. The application smoke exercises
actual resize-handle drags, inspector styling, React color buttons, undo/redo,
Unicode notes, deletion, zoom and rotation on both CPU and Metal. Shape selection
no longer offers the unrelated font-size control in the React inspector.

All 182 Zig tests pass (`/tmp/pod-shape-edit-unit.log`). The native shape suite
passes 36 valid and 18 invalid/unsupported fixtures, full/indexed opening and
CPU/Metal comparisons. Independent metadata checks and 628 shape rasters pass
with maximum mean error 0.981138/255 and flat-interior error 2/255
(`/tmp/pod-shape-edit-final.log`). Dashed-square oracles use PDFBox with a single
opacity group and supersampling, including regenerated appearances; input and
saved files remain unchanged. Existing dash and Form regressions pass 380 and
194 independent rasters respectively (`/tmp/pod-shape-edit-dashes.log`,
`/tmp/pod-shape-edit-forms.log`). No raster tolerance was relaxed.

The final app builds (`/tmp/pod-shape-edit-app-final.log`) and its complete isolated
React/native smoke suite passes (`/tmp/pod-shape-edit-ui.log`), including four
resize/restyle runs on CPU/Metal with actual corner dragging, React color edits
and undo/redo. Link/destination checks pass afterward
(`/tmp/pod-shape-edit-links.log`). Core C/Swift bridges, all 18 annotation tools,
independent PDFKit annotation/page exports and 128 CLI mutation cases pass
(`/tmp/pod-shape-edit-core.log`). The restyled ellipse was visually inspected.
Formatting, Python/shell syntax, TypeScript/Vite build and whitespace checks pass.
The user's running app was not restarted.

The full-engine goal remains active: arbitrary foreign AP regeneration, other
missing-AP shape families, richer annotation families and the engine requirements
below are still unfinished.

## Missing-appearance lines, polylines and polygons

Standard Line, PolyLine and Polygon annotations without APs now render from their
metadata on both CPU and Metal. The same geometry builder writes their editable
appearances. Line endings cover None, Square, Circle, Diamond, OpenArrow,
ClosedArrow, Butt, ROpenArrow, RClosedArrow and Slash, with the border's dash
pattern and optional interior color. Only polygons fill the main path; line and
polyline IC colors fill closed endpoint markers. Duplicate endpoint vertices use
the nearest distinct segment to determine marker direction. Lines also support
positive/negative LL, LLE and LLO. Existing arbitrary APs continue to take
precedence and remain protected from regeneration.

Resize/restyle updates retain L/Vertices, LE, leader metadata, border patterns and
notes. Bounds include endpoint geometry, leader lines and miter joins instead of
using the vertices alone; horizontal, vertical and coincident paths remain valid.
Translation/note-only edits retain original AP bytes. Appearance generation keeps
the existing staged update/allocation-failure guarantees. The canonical-program
budget is now 1 MiB, accommodating the supported 4,096 vertices; a regression
checks that a generated stream larger than 64 KiB remains editable after saving.
Rectangle and ellipse program serialization remains unchanged.

Independent-reader work exposed several oracle differences. MuPDF's native
appearance writer is used for no-AP references: PyMuPDF's higher-level update
helper adds duplicate polyline endpoint artwork and changes line endpoint dashes.
Duplicate zero-length endpoint segments are compacted only in reference copies
because MuPDF's tangent calculation otherwise produces a marker pointing at the
origin. Its generated reference Form retains the original annotation rectangle
as its clip because the native writer otherwise omits acute miter extents from
its bounds. Source and saved files preserve their vertices and rectangles.
Ghostscript renders the new path references with 4x supersampling, avoiding whole-pixel device-height
placement on fractional crop/rotation sizes. Square endpoints at an exact
dash/corner boundary use PDFBox with a separate opacity group per paint operation; Ghostscript/MuPDF's
floating-point placement introduces a tiny outgoing dash that produces a miter.
An independent analytic-contour unit check establishes the correct cap at that
boundary and joins for dashes that cross a corner. Comparison thresholds remain
unchanged.

All 186 engine tests pass (`/tmp/pod-path-unit.log`). Native full/indexed loading,
CPU/Metal comparisons and editing pass for 59 valid fixtures, with 22 malformed
or unsupported fixtures rejected (`/tmp/pod-path-final.log`, native-check section).
Independent metadata and 1,088 raster checks pass at the existing thresholds:
maximum mean 0.981138/255 and maximum flat-interior error 2/255
(`/tmp/pod-path-oracle-final.log`). Tests cover all endpoint styles, leader signs,
acute joins, duplicate/degenerate points, resizing/restyling, further edits after
save/reopen, translation, notes, page operations and original AP preservation.
A final 460-raster path rerun uses the actual saved files directly whenever APs
already exist, avoiding numeric reserialization by the reference reader; it passes
with maximum mean 0.464866/255 and interior error 2/255
(`/tmp/pod-path-direct-oracle.log`). Only missing-AP references are synthesized.
The existing MuPDF polygon reference also passes against its original file
(`/tmp/pod-path-original-oracle.log`).

The app builds (`/tmp/pod-path-app.log`) and the complete isolated native/React
smoke suite passes (`/tmp/pod-path-ui.log`), including six new line/polyline/polygon
resize/style runs across CPU and Metal and all eight earlier shape runs. The
harness checks transformed vertices for path resizes; recomputed paint bounds
may differ from the requested drag rectangle. Translation-size comparisons use
the existing coordinate tolerance rather than exact floating-point equality.
Post-smoke links/destinations pass (`/tmp/pod-path-links.log`). Core C/Swift bridges,
all 18 existing annotation tools, independent PDFKit annotation/page exports and
128 CLI mutations pass (`/tmp/pod-path-core.log`). Formatting, Python/shell syntax
and whitespace checks pass. The restyled polyline and leader geometry were
visually inspected. The user's running app was not restarted.

Captioned missing-AP lines still fail explicitly: implementing Cap/CO/CP requires
text layout and font handling. Cloudy borders, CMYK metadata colors, arbitrary
foreign appearance regeneration and the broader engine completion work remain
open. Endpoint/leader metadata is preserved through existing resize/style edits;
this change does not add dedicated UI controls for those metadata fields.

## Plain-text line captions and caption editing

Line annotations with `Cap true` and no saved appearance now render their plain
Contents on CPU and Metal. A shared caption layout handles Inline/Top placement,
along-line and perpendicular CO offsets, positive/negative leader displacement,
reversed and vertical lines, coincident endpoints and multiline labels. The
inline stroke leaves a gap only where the caption overlaps it. Labels wider than
the line use top placement. CRLF/CR line endings and tabs normalize for display;
source Contents bytes remain unchanged until editing.

Captions use measured Helvetica metrics at 12 pt with WinAnsi encoding. Saved
appearances include their font resource and use the same layout as direct
rendering. This includes accented Latin, euro signs and dashes, not arbitrary
Unicode or rich text. Unsupported text and malformed CP/CO/Cap values fail
explicitly. At most 64 lines are accepted. Original annotation rectangles clip
the fallback; resizing, restyling or caption edits recompute bounds around the
line, markers, leaders and label.

Changing a caption now regenerates the visible text, inline gap, bounds and AP.
It retains the staged-update guarantee: invalid text or an allocation failure
cannot change the annotation or add a dangling appearance. Translation alone
retains the original AP. Canonical appearance validation compares text operands
and font resources, so editing an externally customized caption is prohibited.
The native model, C bridge and React inspector expose that distinction: custom
captions can still display, move and delete, but text editing is disabled with a
specific explanation. Ordinary non-caption shape notes retain Unicode editing.

All 191 engine tests pass (`/tmp/pod-caption-unit3.log`), including analytic
placement, text decoding, invalid metadata, save/reopen, custom-font/appearance
protection and exhaustive allocation-failure checks for caption edits. The new
`script/test_captions.sh` passes 12 valid native fixtures and four invalid ones,
with CPU/Metal comparisons, exact fallback/generated-AP raster identity, repeated
text/style/geometry edits, removal, crop/rotation and independent PDFKit text
checks. Its 166 independent raster comparisons pass with maximum mean error
0.524932/255 and flat-interior error 2/255 (`/tmp/pod-caption-final.log`).

The test-only oracle embeds the same host Arial outlines with Helvetica PDF
advances to eliminate font-substitution differences while checking saved AP
operators, placement and compositing in another reader. MuPDF is the default
reader. Vertical closed-arrow cases use Ghostscript: MuPDF caps their closed
dashed seam, while Ghostscript agrees with the analytic closed-dash regression.
The oracle leaves production/saved PDFs unchanged and does not relax the existing
mean/interior thresholds. FontTools and ReportLab are test-only dependencies.
The multiline and accented-text outputs were visually inspected.

The app builds (`/tmp/pod-caption-app-final.log`). The complete isolated
native/React smoke suite passes (`/tmp/pod-caption-ui-final.log`), including six
new editable-caption runs and two protected-caption runs across CPU and Metal.
It checks actual dragging/resizing, React color edits, caption editing,
undo/redo, deletion, zoom/rotation and the protected-text explanation. Large
caption fixtures move inward and shrink in this test so the pointer stays
inside the canvas's page-coordinate clamp. The user's running app was not
restarted.

Existing shape regressions pass 59 native cases, 22 invalid cases and 1,086
independent rasters with maximum mean 0.981138/255 and interior 2/255
(`/tmp/pod-caption-shapes.log`). The two removed comparisons were note edits on
an arbitrary custom caption AP; such edits are now correctly rejected instead
of leaving stale visible text. Core C/Swift bridges, all 18 annotation tools,
independent PDFKit exports and 128 CLI mutation cases pass
(`/tmp/pod-caption-core.log`). Post-smoke link/destination regressions pass
(`/tmp/pod-caption-links.log`). Formatting, syntax, TypeScript/Vite and whitespace
checks pass.

The full engine remains unfinished. Rich/Unicode caption typography, arbitrary
foreign AP regeneration, FreeText coverage and the requirements below remain
open. This change does not introduce caption creation or dedicated CP/CO controls.

## Imported FreeText appearances and callout preservation

Standard FreeText annotations with normal appearances now use the owned content
interpreter and CPU/Metal renderer. The saved AP takes precedence over DA/RC
formatting. Import preserves alignment, default/rich styles, text, author and
review metadata, font resources, transformed/shared appearances and named states.
Existing embedded-font, color, transparency and content-operator limits still
apply. Unicode Contents remain readable even when their rendering is supplied by
an appearance stream.

Translation retains original appearance bytes and resources and shifts both Rect
and four-/six-number CL callout coordinates. RD insets and other formatting remain
unchanged. Updates stage dictionary changes privately; invalid geometry,
overflow or allocation failure cannot partially move the annotation. Locked
annotations remain protected. Text changes, restyling and resizing are disabled
until FreeText appearance regeneration is implemented; the native and React
inspectors explain that the original formatting is being preserved. Moving,
deleting, undo/redo, page operations and save/reopen use the existing native path.
Missing-AP FreeText still returns an explicit unsupported error.

PDFKit interoperability exposed two separate issues. Its generated FontFile2
streams omitted the required Length entry, while their Length1 and actual font
bytes were consistent. The test harness retains raw files as rejection fixtures
and rewrites test copies with explicit stream lengths, excluding the newline
separator. Production parsing stays strict. Those corrected files then exposed
the valid Apple `true` sfnt scaler header, which the owned TrueType reader now
accepts alongside 0x00010000. All existing table, metric, loca, cmap and glyph
checks remain in force; PostScript/CFF and collection headers remain unsupported.
The font program itself is not normalized or replaced.

References: [Adobe PDF 1.6, FreeText table 8.21](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.6.pdf)
and [Apple TrueType font directory](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6.html).
The implementation uses the specifications and independently produced test files,
not external reader source code.

All 195 engine tests pass (`/tmp/pod-freetext-boundary-green.log`), including FreeText
movement/protected edits, two-/three-point callouts, overflow, shared APs, rich
metadata, exhaustive allocation failures and the Apple scaler regression. The
new `script/test_freetext.sh` exercises 15 valid inputs and 10 invalid/unsupported
inputs, including the two raw PDFKit files. It checks full/indexed native opening,
CPU/Metal raster agreement, protected edits, movement/removal, page operations,
unchanged appearances/metadata and independent PDFKit reopen.

The callout fixtures paint their actual two-/three-point geometry, so these
checks cover visible placement as well as CL metadata. The rotated three-point
callout exposed a CPU sample-boundary bug: transform/intersection roundoff put
an exact diagonal end cap a few double-precision units beyond sample centers,
changing coverage by three of sixteen samples. CPU span boundaries now snap only
within a small machine-precision envelope before applying the half-open fill
rule. A failing-then-passing regression checks both winding directions and fill
rules, positive/negative roundoff, and real offsets that must still change
coverage. No raster comparison tolerance was relaxed.

The native suite and all 176 independent FreeText rasters pass, with maximum
mean error 0.835116/255 and flat-interior error 2/255
(`/tmp/pod-freetext-boundary-native.log`). The regression failure and original
two-pixel CPU/Metal discrepancy are recorded in
`/tmp/pod-freetext-boundary-red.log` and `/tmp/pod-freetext-delta.log`.

Independent raster checking shares a test-only standard-font substitution helper
with the caption suite. It embeds matching host outlines with original PDF
advances only in oracle copies, so font substitution does not obscure geometry
or compositing errors. Embedded source fonts remain untouched. All 166 caption
raster regressions pass with maximum mean 0.524932/255 and flat-interior error
2/255 (`/tmp/pod-freetext-caption-oracle.log`).

The app build and full isolated React/native smoke suite pass
(`/tmp/pod-freetext-app-final.log`, `/tmp/pod-freetext-ui-final.log`). Its 28
shape/caption/FreeText runs include six new FreeText checks for a MuPDF text box,
a painted callout and rich metadata on CPU and Metal. These exercise selection,
movement, protected text/style controls, deletion, undo/redo, zoom/rotation and
independent PDFKit reopen. The user app was not restarted. Link regressions pass
after the UI suite regenerates their fixtures (`/tmp/pod-freetext-links-final.log`).

The embedded TrueType regression suite passes (`/tmp/pod-freetext-fonts.log`).
The sample-boundary fix also passes dashed-path checks with 380 independent
rasters, clipping with 136 and graphics state with 168
(`/tmp/pod-freetext-dashes.log`, `/tmp/pod-freetext-clipping.log`,
`/tmp/pod-freetext-graphics.log`). C/Swift bridge checks, all 18 existing annotation
tools, independent PDFKit annotation/page-operation checks and all 128 CLI
mutation cases pass. Python/shell syntax, Zig formatting and whitespace checks
are clean. The web build retains its existing large-chunk advisory.

The full-engine objective remains active. FreeText layout without APs, appearance
regeneration, richer text editing and the requirements below are still incomplete.

## FreeText layout without saved appearances

FreeText annotations with no AP now render from their plain text and default
appearance properties. The owned layout code uses standard-font metrics and the
existing glyph, border, callout and clipping renderers; it adds no host PDF renderer
or production dependency. All 14 standard faces and recognized aliases retain
their distinct font metrics. Fixed positive font sizes, grayscale/RGB text,
left/center/right quadding, word wrapping, normalized line breaks, quarter-turn
text rotation, background colors, opacity, border styles, RD insets and two-/three-
point callouts are supported. Closed arrowheads use the background fill color.
Rendering alone does not add AP objects or change the saved annotation dictionary.
Moving/deleting, undo/redo, crop/rotation, page assembly and save/reopen retain the
original formatting properties and the existing protection against unsupported
text/style/resize edits.

The long-word fixture was checked in MuPDF and PDFBox: both keep an unbreakable
word on one clipped line. The owned layout now does the same. Trailing separators
remain in the laid-out text but do not shift center/right quadding. Ordinary words
wrap at spaces; vertical overflow is clipped to the text rectangle. These choices
are rendering/layout behavior, not modifications to Contents.

Validation currently includes 201 engine tests, including a failing-then-passing
missing-AP integration case, read-only rendering, line layout/rotation, all standard
font names, strict rejection and exhaustive allocation-failure cleanup
(`/tmp/pod-freetext-layout-unit-final.log`). The expanded native FreeText suite
passes 34 valid fixtures and 15 malformed/unsupported cases, plus 404 independent
rasters with maximum mean error 0.959355/255 and flat-interior error 2/255
(`/tmp/pod-freetext-layout-native-final.log`). It covers serif/monospace/sans text,
all alignments, explicit/wrapped lines, long words, clipped overflow, empty text,
WinAnsi Unicode, all quarter-turn rotations, callout geometry/arrowheads, protected
edits, full/indexed loading, CPU/Metal agreement and unchanged metadata on saves.

Oracle copies materialize missing appearances with MuPDF, then use the existing
test-only font matching helper. MuPDF tightens callout Rect to line-center
endpoints and consequently clips stroke ends. For those reference copies only,
the harness checks that CL and the RD-derived text rectangle did not move, verifies
an identity appearance Matrix and matching BBox, and restores the original Rect
and appearance clipping box around MuPDF's generated drawing. Production files
and source metadata remain unchanged. No raster tolerances were relaxed. The
166 independent caption raster regressions also pass
(`/tmp/pod-freetext-layout-captions.log`).

The final app build and isolated React/native smoke suite pass
(`/tmp/pod-freetext-layout-app-final.log`, `/tmp/pod-freetext-layout-ui-final.log`).
All 12 FreeText runs pass on CPU/Metal, including six missing-appearance runs for
plain/wrapped text and callouts. They verify selection, movement, protected
inspector controls, deletion, undo/redo, zoom/rotation and PDFKit reopen. The
harness now distinguishes protected FreeText from editable geometric fallback
fixtures and names each fixture in its result. Link regressions pass after the UI
suite regenerates their inputs (`/tmp/pod-freetext-layout-links-final.log`).
C/Swift bridge checks, all 18 annotation tools, independent PDFKit annotation/page
checks and 128 CLI mutations pass (`/tmp/pod-freetext-layout-core.log`). Zig
formatting, Python/shell syntax and whitespace checks are clean. The build keeps
the existing web-chunk size advisory; no user app was restarted.

The [PDF reference, FreeText table 8.25 and variable-text rules](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf)
provide the metadata contract; independent producer/reader outputs establish the
interoperability checks. RD uses left/bottom/right/top order, matching the tested
readers and the existing shape renderer. The printed left/top/right/bottom order
is a [documented specification/implementation discrepancy](https://github.com/pdf-association/pdf-issues/issues/592),
not a resolved erratum. No external reader implementation was copied.

This does not finish FreeText or the engine. Auto-sized fonts, custom font
resources, additional DA text/graphics state, rich text/default styles, broader
Unicode shaping and editing/regenerating imported appearances remain unfinished.
Unsupported cases still fail explicitly. Plain layout is bounded to 65,536 UTF-8
bytes, 4,096 lines and the existing annotation/geometry limits.

## Editing plain imported FreeText

Plain imported FreeText without a saved appearance now supports text, font size,
text/background color, opacity, border-width and rectangle edits. Regeneration
uses the owned layout and appearance serializer, with standard font resources,
clipped text, borders and callout markers. Resizing scales CL points and RD insets
relative to the original rectangle. Pure translation retains existing appearance
objects, including shared appearances. Other annotation metadata is preserved;
Apple's stale private appearance cache is invalidated on edits.

Generated appearances carry a version marker, but that marker alone never grants
editing. Pod compares the decoded drawing and resources against the current
annotation properties before allowing regeneration. Externally altered artwork
or fonts become protected. Unsupported text, invalid styles and allocation
failures leave the annotation dictionary and object count unchanged. The C bridge
exposes the editing capability to Swift, and the inspector uses it to enable text,
style and resize controls while retaining custom-appearance and lock protection.

The native checks exposed a wrapping boundary bug: a separator after a word could
exceed the available width and eject that already-fitting word onto the next
line. A failing-then-passing unit regression now covers trailing spaces, including
multiple separators. The layout preserves those spaces while using visible text
width for the line break and alignment.

All 203 unit tests pass in debug and safety-enabled builds
(`/tmp/pod-freetext-edit-unit-final.log`, `/tmp/pod-freetext-edit-unit-safe.log`).
Tests include exhaustive allocation failures before and after appearance
creation, shared appearances, modified drawing/font resources, lock protection,
unsupported Unicode, invalid style, repeated edits and callout/inset scaling.
The native FreeText suite passes 34 valid fixtures and 15 invalid/unsupported
inputs. Its 692 independent raster comparisons cover both Pod's saved appearances
and independently regenerated MuPDF appearances at two resolutions, with maximum
mean error 0.959355/255 and flat-interior error 2/255
(`/tmp/pod-freetext-edit-native-final.log`). CPU/Metal comparisons, PDFKit text
reopening and exact unrelated-metadata checks pass. Raster tolerances are unchanged.

The shared appearance validator and border-width update also pass the shape and
caption regressions: 1,086 shape rasters with maximum mean error 0.981138/255 and
166 caption rasters with maximum mean error 0.524932/255; both retain the 2/255
flat-interior bound (`/tmp/pod-freetext-edit-shapes.log`,
`/tmp/pod-freetext-edit-captions.log`). The C/Swift bridge, all 18 annotation tools,
independent PDFKit annotation/page checks and 128 CLI mutation cases pass
(`/tmp/pod-freetext-edit-core.log`).

The safety-enabled app build and full isolated React/native smoke suite pass
(`/tmp/pod-freetext-edit-app-final.log`, `/tmp/pod-freetext-edit-ui-final.log`).
All 12 FreeText runs pass on CPU/Metal. Six plain/wrapped/callout runs now verify
resize/restyle, React color controls, text editing and undo/redo; six custom-
appearance runs retain protected typography. Selection, movement, deletion,
zoom/rotation and PDFKit reopening remain covered. The smoke app uses its own
bundle identity and ignores persisted application state; the user's Pod was not
restarted. The build retains the existing web-chunk size advisory. Zig formatting,
Python/shell syntax and whitespace checks pass. Link regressions also pass after
the UI suite regenerated their fixtures (`/tmp/pod-freetext-edit-links-final.log`).

This extends the earlier layout milestone's editing boundary; it does not make
arbitrary imported appearances regenerable. Rich/default-style text, auto-sizing,
custom font resources, additional DA state and complex-script shaping remain
unfinished. Newly created Pod text boxes retain their existing printable-ASCII
restriction. The broader engine completion requirements below remain open.

## Creating text boxes with the standard FreeText layout

New Pod text boxes now use the same owned layout and standard appearance writer
as editable imported FreeText. Their Contents use PDF Unicode strings; visible
text uses Courier with WinAnsi encoding, including accented Latin, euro signs
and typographic punctuation. Words wrap within the box, explicit line breaks are
honored, unbreakable words stay intact and overflow is clipped. Fill, border,
opacity and text color are represented by standard annotation properties. New
boxes remain editable after saving, including resizing and subsequent text/style
changes. Unsupported characters fail explicitly instead of producing replacement
glyphs. This remains bounded to the font repertoire; it does not claim arbitrary
Unicode shaping or font selection.

Creation stages the page's annotation array before publishing the new annotation
and appearance. If either object append fails, the object count and trailer Size
are restored and the page dictionary remains unchanged. Exhaustive allocation-
failure tests cover the complete operation. A separate compatibility test builds
the legacy PodKind form, saves/reopens it, checks unchanged appearance bytes and
checks its existing ASCII edit behavior. Existing files are not silently migrated
or visually restyled. Geometry validation is shared; the legacy writer remains
available for previously saved boxes.

The Add Text sheet now uses a plain multiline editor with a vertical scrollbar.
The isolated app checks create an accented multiline box through the sheet,
verify the inspector's editing capability, undo/redo its creation, update text
through the React command bridge and reopen the result in PDFKit, on both CPU
and Metal. The full existing React/native smoke suite also passes
(`/tmp/pod-created-freetext-ui.log`). The user's app was not restarted.

All 205 engine tests pass in debug and safety-enabled builds
(`/tmp/pod-created-freetext-unit-final.log`,
`/tmp/pod-created-freetext-unit-safe.log`). The app build passes with the existing
web-chunk size advisory (`/tmp/pod-created-freetext-app.log`). C/Swift bridge checks,
all 18 annotation tools, independent PDFKit annotation/page checks and 128 CLI
mutation cases pass (`/tmp/pod-created-freetext-core.log`). Link regressions pass
after the UI suite regenerates their fixtures (`/tmp/pod-created-freetext-links.log`).
Zig formatting, Python/shell syntax and whitespace checks are clean.

Seven Pod-created fixtures expand the FreeText cases to 41: accented text,
wrapping, clipped overflow, long words, empty text, escaped characters and mixed
line endings. Full/indexed loading, CPU/Metal comparison, translation, deletion,
text/style/resize edits, repeated editing, page operations and metadata
preservation pass. The independent checks compare both saved appearances and
new MuPDF-generated appearances at two resolutions; 958 raster comparisons pass
with maximum mean error 0.959355/255 and flat-interior error 2/255
(`/tmp/pod-created-freetext-native-final.log`). The complete
`script/test_freetext.sh --built` command passes, including all 15 malformed or
unsupported inputs. No tolerances were relaxed.

MuPDF's regenerated appearance treats CRLF as two line breaks. Pod's layout
normalizes CRLF to one break and tabs to spaces; an independent PDFBox rendering
of the same appearance-less input agrees on those three lines
(`/tmp/pod-created-lines-noap.pdf`, `/tmp/pod-created-lines-pdfbox.png`). The MuPDF
regeneration copy for that exact fixture normalizes only those characters. The
original saved Contents remain unchanged, and the separate saved-appearance
comparison renders the original PDF. This is an observed layout difference,
not a claim that the PDF specification fully defines plaintext paragraph layout.

This milestone supersedes the earlier new-box ASCII limitation. Legacy Pod boxes
retain that limitation, while rich text, arbitrary fonts, additional scripts,
auto-sizing and the broader engine requirements below remain open.

## Automatic font sizing for plain FreeText

Plain FreeText now accepts a zero font size in its default appearance. The owned
layout selects a positive size that fits both the wrapped lines and the longest
unbreakable word inside the usable text area. It accounts for border padding,
rectangle insets, explicit line breaks and quarter-turn text rotation. The search
is bounded to 32 allocation-free trial layouts after encoding the paragraphs
once; only the final lines are retained. The maximum computed size is 200 pt;
empty text is capped at 12 pt. An interior with no usable space returns
`TextOverflow`. Negative and nonfinite sizes remain invalid.

The saved DA retains size zero while the normal appearance contains the computed
positive size. Subsequent text edits and resizing recompute the layout, including
after save/reopen. Fixed-size layout retains its existing wrapping and clipping
behavior. New standard text boxes can also use automatic sizing; legacy PodKind
boxes and protected foreign appearances keep their existing editing restrictions.
Creation and edit allocation-failure checks cover the automatic path.

The React inspector offers **Auto fit** only for new or editable standard text
boxes. The native style field accepts `Auto` or zero for the same supported
kind. The bridge retains zero only for supported text boxes; other tools retain
their existing font-size validation. The isolated UI suite passes on both CPU and
Metal, including multiline creation, selecting Auto fit through the real select
control, text changes, undo/redo, switching back to a fixed size and PDFKit
reopen (`/tmp/pod-auto-freetext-ui-verified.log`). The user's Pod was not restarted.

All 207 engine tests pass in debug and safe builds
(`/tmp/pod-auto-freetext-unit-final.log`,
`/tmp/pod-auto-freetext-unit-safe.log`); rerunning both targets after the checker
fixes also succeeds. The app build and core C/Swift, 18-tool, PDFKit and 128 CLI
mutation checks passed before the test-only fixes
(`/tmp/pod-auto-freetext-app.log`, `/tmp/pod-auto-freetext-core.log`).

Eight imported automatic-size fixtures and one Pod-created fixture extend the
suite to 50 valid inputs and 16 malformed/unsupported inputs. Native checks cover
full/indexed reads, edits, resizing, saving, page operations, CPU/Metal parity and
metadata preservation. For missing appearances, materializing an appearance by
editing and restoring the same text must leave every rendered channel within 1.
Independent font metrics also check emitted line advances and total line height.
The independent checker passes 1,156 raster comparisons with maximum mean error
0.959355/255 and flat-interior error 2/255
(`/tmp/pod-auto-freetext-oracle-verified.log`).

The complete `script/test_freetext.sh --built` rerun passes after both checker
corrections (`/tmp/pod-auto-freetext-final.log`). Link regressions pass after the
UI fixture regeneration (`/tmp/pod-auto-freetext-links.log`). Zig formatting,
Python/shell syntax and whitespace checks are clean.

Automatic-size layout is not unique across readers. MuPDF regeneration rewrites
zero to 12 pt in the probe, so automatic fixtures compare Pod's saved appearance
in the independent renderer, alongside the independent fitting constraints.
Large fitted glyphs expose sampling differences at native resolution; these
reference rasters are rendered at eight times the target resolution and averaged
down. Mean and flat-interior thresholds remain unchanged, as do all fixed-size
reference paths and CPU/Metal tolerances. This does not claim that different
readers choose identical automatic font sizes.

Two test-oracle assumptions were corrected. MuPDF can tighten a plain inset
text box as well as a callout; the checker restores the original clipping box
only after asserting that text-body bounds, callout coordinates and intent are
unchanged. PDFKit's protected saved appearances can contain a DA without a
parseable Tf; these remain saved-appearance checks rather than automatic-layout
cases. Neither exception changes production parsing or editing permissions.

The [PDF 1.7 variable-text rules, printed page 679](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf)
define zero as automatic sizing; FreeText's DA entry references those rules.
This supersedes the earlier auto-sizing limitation. Custom font resources,
additional text state, rich text/default styles, complex-script shaping and the
broader engine requirements below remain unfinished.

## FreeText using document font resources

FreeText now resolves its DA font resource name through the catalog AcroForm's
DR/Font dictionary before trying the existing standard-font aliases. Direct and
indirect dictionaries and font objects are supported. A declared font that is
malformed or unsupported fails explicitly instead of falling back to a different
face. Resource-only AcroForm dictionaries containing DR and an optional empty
Fields array can pass page validation; nonempty fields, XFA and other form
features remain outside the supported subset.

The layout reuses the owned font loader for standard fonts, supported embedded
TrueType and horizontal CID fonts, including supported custom Encoding CMaps.
Each encoded paragraph is decoded once into glyph boundaries, advances and word
separator flags. Wrapping and auto fitting operate on those boundaries rather
than raw bytes. This prevents splitting a multibyte character or treating a
non-space glyph encoded at byte 32 as a word separator. The direct appearance
renderer also iterates complete character codes. Vertical FreeText writing,
complex-script shaping, fonts outside the existing reader's repertoire and
characters absent from the original font remain explicit limitations.

Generated appearances retain the original font value, including embedded
programs, encodings, Unicode maps and PDF widths. Restyling preserves the DA
resource name with proper PDF name escaping. Canonical appearance checks require
the original indirect font reference, or a matching direct font dictionary;
substituted resources are protected. The comparator now handles retained null
and boolean metadata as well. Unit regressions demonstrate failures before the
resource lookup, reference preservation and direct-metadata fixes, followed by
209 passing tests in debug and safe builds
(`/tmp/pod-freetext-font-unit-final.log`,
`/tmp/pod-freetext-font-safe-final.log`). Allocation-failure checks exercise
editing and reopening resource-backed appearances.

Nine test fixtures use document font resources: standard Courier, embedded
TrueType, remapped spaces, direct font dictionaries with null/boolean metadata,
CID codes containing space-valued bytes, mixed-length CMaps, rotated CID text,
and automatic TrueType/CID fitting. Five additional malformed/unsupported cases
cover missing font resources, malformed DR, vertical writing, nonempty fields
and XFA. Source fonts come from existing test-only FontTools producers; the
production engine has no new dependency.

Resource-backed fixtures check full/indexed rendering, text edits, repeated
edits, restyling, resizing, translation, deletion, save/reopen and CPU/Metal
parity. The reference checker asserts that the complete AcroForm resource graph
is unchanged and the saved appearance uses the original selected font. It
compares the saved drawing with MuPDF; missing appearances are first materialized
by changing and restoring the same text, which must leave each native rendered
channel within 1. This checks font decoding and drawing independently, without
assuming that other readers regenerate identical paragraph layout.

The complete `script/test_freetext.sh --built` run passes all 59 valid fixtures
and 21 malformed/unsupported inputs, including 1,318 independent rasters with
maximum mean error 0.959355/255 and flat-interior error 2/255
(`/tmp/pod-freetext-font-native-final.log`). CPU/Metal and independent-raster
thresholds are unchanged. The app build passes with the existing web-chunk size
advisory (`/tmp/pod-freetext-font-app-final.log`). Core C/Swift bridge checks,
all 18 annotation tools, independent PDFKit annotation/page checks and 128 CLI
mutation cases pass (`/tmp/pod-freetext-font-core-final.log`,
`/tmp/pod-freetext-font-cli.log`).

The full isolated React/native UI suite passes
(`/tmp/pod-freetext-font-ui-final.log`). Eight new CPU/Metal runs exercise embedded
TrueType, direct TrueType resources, mixed-length CMaps and auto-sized CID text
through selection, dragging, resizing, styling, React color changes, text editing,
delete/undo/redo, zoom/rotation and PDFKit reopen. The user's running Pod was not
restarted. Zig formatting, Python/shell syntax and whitespace checks are clean.
Link regressions pass after the UI suite regenerates their inputs
(`/tmp/pod-freetext-font-links-final.log`).

A separate PDFBox 3.0.5 probe renders the original appearance-less embedded-font
fixtures with the expected glyphs, but left-aligns text requested with Q=2. It is
not used as a pixel-equivalence oracle for that regenerated layout
(`/tmp/pod-resource-truetype-pdfbox.png`,
`/tmp/pod-resource-cid-pdfbox.png`,
`/tmp/pod-resource-mixed-cmap-pdfbox.png`,
`/tmp/pod-resource-remapped-space-pdfbox.png`). Pod retains the requested quadding.

The [PDF 1.7 FreeText and variable-text rules, printed pages 624 and 678–679](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf)
connect the DA font name to default font resources and require copying resources
into the generated appearance. These specification rules, the existing owned
font model and independent output checks guide this change; external engine
implementations are not production dependencies.

This supersedes the blanket custom-font-resource limitation for supported
horizontal fonts. Extraction and merging still reject documents with AcroForm
catalog resources, rather than dropping or incorrectly combining those
resources. Rich text, additional DA state, vertical layout, interactive forms,
font creation/selection UI and the remaining engine requirements below are open.

## Page assembly with document font resources

Extraction, reordering and merging now preserve resource-only AcroForm font
dictionaries. A single selection retains the original AcroForm graph and resource
names. Multi-source assembly gives each source font a distinct target name and
rewrites only the corresponding Tf name operands in copied FreeText default
appearances. Names already present in selected annotations are reserved, including
unbound names in protected appearances, so a merge cannot accidentally bind an
old name to a newly imported font. Standard fallback names remain unbound unless
they were explicitly defined by that source document.

Font programs, encodings, Unicode maps, PDF widths and existing appearance
streams use the same object-cloning map. The DA rewrite preserves comments,
non-font operands, other operators, literal strings and unrelated resource names.
It also handles escaped resource names and is idempotent for shared annotations.
Appearance resources retain their font relationships, allowing supported text
boxes to remain editable after merge, extraction and save/reopen. Sources are
unchanged. Documents with interactive fields, XFA or non-font default-resource
categories still fail explicitly during assembly. Existing document-information
conflicts and other catalog restrictions also remain; this does not claim general
AcroForm or catalog merging.

A regression failed at the old catalog rejection, then passed with two PDFs that
both name different fonts Cour and a third PDF using the standard fallback.
Further assertions cover a protected appearance whose unbound name resembles a
generated name, source-byte preservation, extraction/reordering, escaped DA names,
non-font token preservation and allocation failures. A further failing regression
found that duplicate font names within one source could silently select the wrong
definition; multi-source assembly now rejects that ambiguity explicitly. All 211
engine tests pass
in debug and safe builds (`/tmp/pod-font-assembly-unit-final.log`,
`/tmp/pod-font-assembly-safe-final.log`).

The complete `script/test_freetext.sh --built` run passes
(`/tmp/pod-font-assembly-native-final.log`). All nine document-font fixtures now exercise
merge followed by extraction. Additional two-document checks merge standard
Courier with an embedded CID font under the same original resource name, both
without and with saved appearances, then edit both merged pages. Native before/
after rendering is byte-identical for unchanged pages; CPU/Metal comparison
thresholds are unchanged. Independent metadata checks verify the selected font
graph and unchanged appearance data. All 1,344 independent rasters pass with
maximum mean error 0.959355/255 and flat-interior error 2/255. No tolerances were
relaxed.

The full isolated React/native suite passes (`/tmp/pod-font-assembly-ui.log`).
The final build additionally repeats eight resource-font flows on CPU/Metal
(`/tmp/pod-font-assembly-ui-final.log`): merge through the app's page-change path,
undo/redo, moving a page, extracting it, subsequent text editing and PDFKit
reopen. These checks bypass the file-picker/save-panel prompts while exercising
the normal document/history/rendering operations. The user's Pod was not
restarted. The app build passes with the existing web-chunk advisory
(`/tmp/pod-font-assembly-build-final.log`). Core C/Swift bridge checks, all 18
annotation tools, PDFKit annotation/page checks and 128 CLI mutations passed
(`/tmp/pod-font-assembly-core.log`). Zig formatting, Python/shell syntax and
whitespace checks are clean. Link regressions pass after UI fixture generation
(`/tmp/pod-font-assembly-links.log`).

This supersedes the earlier blanket rejection of page assembly for document
font resources. Other catalog structures, non-font default resources, interactive
forms and the full engine requirements below remain unfinished.

## FreeText horizontal scaling

FreeText default appearances now accept positive Tz percentages. Glyph outlines
and horizontal advances use the same scale in native fallback rendering and
saved appearances. Wrapping and automatic fitting work in the corresponding
unscaled text width; quadding uses the resulting scaled line advances. Rotation,
vertical line spacing, font size and annotation geometry retain their existing
semantics. The original percentage is retained without a divide/multiply rewrite
when text or style changes, including fractional percentages. Default 100 percent
does not add an operator to existing canonical programs.

Two regressions first failed because the DA parser rejected Tz. They now cover
narrow/wide text, all quadding modes, repeated Tz operators, rotated automatic
fitting, malformed and nonpositive values, edits, save/reopen and allocation
failures during regeneration. All 213 engine tests pass in debug and safe builds
(`/tmp/pod-freetext-scale-unit-final.log`, `/tmp/pod-freetext-scale-safe.log`).

The native FreeText suite passes 67 valid fixtures and rejects 24 invalid or
unsupported fixtures (`/tmp/pod-freetext-scale-native.log`, native portion).
Eight new fixtures exercise compressed, stretched and fractional widths,
rotation, automatic fitting, embedded CID fonts and mixed-length CMaps.
They run through full/indexed reads, CPU/Metal comparison, text/style/size
changes, deletion, page operations and save/reopen. Materializing a missing
appearance retains the original native pixels within the existing one-channel
tolerance. Independent checks compare DA and saved-appearance scaling and
verify automatic line extents against external standard-font metrics.

All 1,504 independent rasters pass (`/tmp/pod-freetext-scale-oracle-final.log`):
maximum mean error 0.963450/255 and flat-interior error 2/255. A stretched-text
case initially exceeded the mean threshold at the independent renderer's native
resolution (1.129213/255 at 300 pixels). Rendering the same reference at 2x, 4x
and 8x reduced that error to 0.806262, 0.646809 and 0.563256 respectively,
identifying raster edge sampling rather than changed layout. Scaled-text cases
now use the existing 8x averaging path used for auto-fit text. Error tolerances
and CPU/Metal comparisons are unchanged. The final independent checker passed
against the same saved files and native pixels; the native suite was not rerun
after this oracle-only change.

Eight isolated editor flows pass on CPU/Metal for fixed and automatically sized
scaled boxes and two embedded-font cases (`/tmp/pod-freetext-scale-ui.log`).
These include selection, dragging, resizing, inspector styling, text edits,
undo/redo, zoom/rotation and PDFKit reopening. Embedded-font cases additionally
exercise merge, reordering, extraction and editing afterward. The app build
passes with the existing web-chunk advisory (`/tmp/pod-freetext-scale-build.log`).
The user's Pod was not restarted.

The implementation follows PDF Reference 1.7, sections 5.2.3 and 8.6.2. It does
not add an inspector control for scaling. Character and word spacing, leading,
rise, arbitrary text matrices, nonpositive scaling, vertical FreeText layout
and the other full-engine requirements below remain unfinished.

## Character and word spacing in FreeText

FreeText default appearances now accept signed `Tc` and `Tw` in addition to
positive `Tz`. The same text state is used for native fallback drawing and
saved appearances, including after text changes, restyling, resizing and page
assembly. Word spacing applies to single-byte code 32, independently of its
Unicode mapping. A byte equal to 32 within a multibyte code does not receive it.
Wrapping still identifies word breaks from decoded spaces. These rules follow
PDF Reference 1.7 sections 5.2.1–5.2.3.

Spaced lines measure the leftmost and rightmost nominal glyph positions. This
keeps right/center alignment meaningful when spacing reverses the direction
of successive advances. Trailing separator advances and spacing after the last
visible glyph do not shift alignment. Glyph shapes and vertical line spacing
are unchanged. The zero-spacing layout path retains its previous behavior.

With negative spacing, shrinking the font can make a line wider. Automatic
fitting therefore tracks positions as affine functions of font size and checks
the intervals where glyph extrema and wrap decisions remain unchanged. It
searches from the largest candidate down, including boundary sizes, and checks
the resulting layout before accepting it. No feasible size reports `TextOverflow`;
the search has a budget of one million boundary checks (`TextLimit`).

Regressions first failed at the unsupported DA operators. The tests cover
positive and negative spacing, reversed positions, wrapping, quadding,
remapped code 32, scale/rotation, finite fitting intervals, impossible fits,
save/reopen/restyle and allocation failures. An exhaustive quarter-point sweep
of 800 sizes across 216 text/spacing/box combinations exposed a rounding bug
at a wrapping boundary. Layout and interval traversal now use the same crossing
comparison; all 172,800 size checks pass. The engine passes all 217 tests in both
debug and safe builds (`/tmp/pod-freetext-spacing-unit-final.log`,
`/tmp/pod-freetext-spacing-safe-final.log`).

The independent renderer exposed a seam inside overlapping glyphs with negative
word spacing. Antialiasing each glyph separately lost coverage where their edges
met. For clipped knockout text with negative spacing in annotation appearances,
the engine now rasterizes the union of a string's normalized glyph interiors.
Clipping gives the contours consistent winding before combining them; CPU and
Metal consume the same geometry, bounded to 65,536 edges per combined string.
Separate colors, non-knockout paints and ordinary page text retain their previous
paths. A one-pixel regression covers opposite-winding overlapping shapes and
half opacity. The previously failing 600-pixel independent raster's flat-interior
error fell from 35/255 to 1/255 without changing the reference or thresholds.

The native suite checks 79 valid and 27 invalid/unsupported fixtures. The twelve
new valid cases include a narrow box with an impossible replacement, remapped
simple-font codes, multibyte CID codes and mixed-length CMaps. Independent checks
read the saved DA and appearance text state and measure auto-fit extents using
external standard-font metrics. Ten isolated editor flows pass on CPU/Metal
(`/tmp/pod-freetext-spacing-ui-final.log`), including inspector changes, text editing,
undo/redo and PDFKit reopen. Resource-font cases also exercise merge, page
reordering and extraction. The app build passes with its existing chunk-size
advisory (`/tmp/pod-freetext-spacing-build-final.log`). The user's Pod was not restarted.

The final complete `script/test_freetext.sh --built` run passes, including all
1,744 independent rasters, with maximum mean error 0.963450/255 and flat-interior
error 2/255 (`/tmp/pod-freetext-spacing-native-final.log`). Error thresholds were
unchanged. Work stops at this milestone at the user's request.

This is import/edit preservation; there are no new spacing controls. Leading,
rise, arbitrary text matrices, vertical FreeText layout, richer paint and
the broader engine requirements remain open.

## Remaining completion work

- Broader annotation import, appearance handling, editing, and preservation, including
  link editing and document-level navigation preservation, comments, free text, shapes, stamps, attachments, forms, and signatures.
  Redaction must remove the underlying content. A visual overlay cannot establish that.
- Remaining embedded and arbitrary font coverage, composite/predefined CMaps, broader Unicode text extraction,
  and the additional font formats and shaping described in the engine design.
- Remaining image codecs and variants, CMYK/spot colors, patterns/shadings,
  remaining graphics-state parameters, text clipping modes,
  general transparency groups and masks, color spaces, and specialized Form groups.
- Text-region reconstruction and paragraph editing with serialization back into the PDF.
- Encryption support and preservation of document-level structures during page operations.
- A representative external-document corpus, malformed-input fuzzing, independent
  visual and round-trip checks, and updated performance/memory measurements.

Each subsystem needs checks through the library, C bridge, and native application where
applicable. The engine remains incomplete until these requirements have implementation
and verification evidence.
