# Pod PDF core implementation plan

> For agentic workers: use superpowers:subagent-driven-development to implement the core, then independent specification and code-quality review. Follow test-driven development for nontrivial logic.

**Goal:** Deliver the approved native PDF create/inspect/replace round trip with no PDF dependencies, explicit compatibility limits and measured size/performance.

**Architecture:** One Zig library holds bounded syntax parsing, object resolution, page traversal, content interpretation, edits and serialization. A thin native CLI handles files. Validation uses an independent PDF reader and reproducible fixtures.

**Tech stack:** Zig 0.17.1, Zig standard library, native OS interfaces. Python and macOS PDFKit may be used only as external validation tools.

## Task 1 — Core library and CLI

Files: `build.zig`, `build.zig.zon`, `src/pod.zig`, `src/syntax.zig`, `src/document.zig`, `src/content.zig`, `src/main.zig`, `README.md`.

- [x] Write tests for nested/escaped strings, hex strings, numeric syntax and bounded nesting; demonstrate a failing assertion against an unimplemented parser before implementing.
- [x] Implement values and token spans with explicit allocation, checked offsets and fixed traversal limits.
- [x] Write create/read/write tests and malformed-xref, stream-length, cycle and truncation regressions; implement classic-xref resolution, stream parsing, page inheritance and serialization.
- [x] Write content-state tests and a replacement test that verifies following text does not move; implement the approved text operators, Courier ASCII metrics, source-linked run IDs and compensation for changed advances.
- [x] Reject unsupported editing features and invalid operands before output is produced. Preserve unrelated content and input files.
- [x] Add CLI operations with this contract:

```text
pod create OUTPUT.pdf [TEXT]
pod inspect INPUT.pdf
pod replace INPUT.pdf OUTPUT.pdf PAGE RUN_ID REPLACEMENT
```

`inspect` emits valid JSON containing `pages` with 1-based `number` and `runs`; each run has a zero-based page-local `id`, `text`, `x`, `y`, `font_size`, and `advance`. Errors go to stderr with nonzero exit status. The CLI must not overwrite an existing output or use the input as output. `create` defaults to a small Courier test document.

- [x] Implement and document `zig build`, `zig build test`, `zig build -Doptimize=ReleaseSafe`, `zig build -Doptimize=ReleaseFast`, and `zig build -Doptimize=ReleaseSmall`; adapt option spelling only if pinned compiler requires it, and document the exact commands.
- [x] Run format checks and all tests; commit only implementation-owned files after self-review.

## Task 2 — Independent validation and measurement

Files: `tools/validate.py`, `tools/pdfkit_check.swift`, `tools/benchmark.py`, `docs/benchmarks/initial.md`.

- [x] Generate a classic-xref PDF fixture independently of Pod with two separate text runs and a `TJ` array.
- [x] Verify JSON inspection, shorter replacement, escaped replacement, and subsequent run positions.
- [x] Verify invalid xref, invalid lengths, unsupported features, same-path output and existing-output rejection with file hashes proving no input/output data loss.
- [x] Use macOS PDFKit as an independent reader to extract text and rasterize created/edited files. Inspect the resulting image.
- [x] Build safe, speed and size variants. Record actual binary bytes, process startup and operation medians/tails, peak RSS, fixture identities, iteration counts and toolchain/hardware. Do not extrapolate the narrow benchmark to general PDFs.

Example black-box assertions:

```python
assert inspect_after['pages'][0]['runs'][0]['text'] == 'Hi'
assert inspect_after['pages'][0]['runs'][1]['x'] == inspect_before['pages'][0]['runs'][1]['x']
assert input_sha256_before == input_sha256_after
assert malformed_input_exit_code != 0
```

## Task 3 — Review and integration

- [x] Independent specification review against the approved design, including compatibility/error behavior and size measurements.
- [x] Independent code-quality review of parser arithmetic, lifetimes, traversal bounds, stream rewriting, font handling and output-file semantics.
- [x] Fix material findings and run focused regressions plus the full suite after changes.
- [x] Update the README with supported/unsupported behavior, build commands and validation evidence.
- [ ] Integrate the completed branch into the user workspace without changing the retained research artifacts. Keep the local compiler and downloaded artifacts ignored.
