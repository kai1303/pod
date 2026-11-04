# Initial PDF engine benchmark

Measured 4 November 2026 on Apple M1 Pro, 32 GiB RAM, macOS 27.0.1 arm64, Zig 0.17.1. This measures the first PDF editing milestone, not a complete PDF application.

## Workload and method

- One independently generated page, six live objects (seven xref slots), 1,000 Courier `Tj` runs, 20,656 bytes. Content intentionally extends off-page to exercise interpretation; rendering is not benchmarked.
- Fixture SHA-256: `8c19b8910c088f3353ba90e2c8ae6851daab7a56ebd57b471c7d7667cb54cfe1`.
- CLI: first invocation reported separately, then 30 fresh processes per command; stdout discarded. Timings include process launch, file I/O, JSON/serialization and exit. `usage_startup` runs the usage/error path without opening a PDF; it is a startup proxy.
- OS caches were not purged. First invocation is not a disk-cold benchmark. This was a normal developer workstation, not an isolated performance lab; scheduling noise is visible in the process tails. Do not rank compiler modes using these process times alone.
- In process: one warmup batch, then 30 batches of 50 operations. Tables report median and p95 of per-batch mean operation latency, not individual-call percentiles. A fresh document is allocated for each operation; the input bytes remain in memory.
- Open measures header/xref parsing. Inspect follows open and includes lazy object parsing/content interpretation. Replace follows inspection. Save follows an edit and returns an in-memory full-file rewrite. Setup and document cleanup are excluded from each stage timer; save includes output allocation but not disk I/O.
- Peak RSS comes from a separate `/usr/bin/time -l` run of each CLI command, in bytes on macOS. It includes the process runtime; values are not portable cross-platform memory guarantees.
- Safe retains Zig runtime checks; fast and small disable them. Explicit parser/editor validation is present in every mode. Executables are stripped and dynamically link the system libc; no PDF libraries, UI, fonts, compiler or fixtures are bundled.

## Results

| Mode | Executable bytes | KiB | Inspect peak RSS MiB |
| --- | ---: | ---: | ---: |
| safe | 306,080 | 298.9 | 2.27 |
| fast | 165,904 | 162.0 | 2.20 |
| small | 121,200 | 118.4 | 2.17 |

All three meet the provisional 1 MiB CLI target. Use safe as the initial release configuration; the small build is an available size tradeoff, not an excuse to remove validation.

### In-process stages (milliseconds, median / p95 batch mean)

| Mode | Open | Inspect | Replace | Save |
| --- | ---: | ---: | ---: | ---: |
| safe | 0.001946 / 0.002067 | 0.287929 / 0.314934 | 0.002891 / 0.003312 | 0.010971 / 0.015214 |
| fast | 0.001905 / 0.003811 | 0.219741 / 1.516855 | 0.002782 / 0.004596 | 0.020308 / 0.050411 |
| small | 0.003307 / 0.004138 | 0.389785 / 0.444982 | 0.002777 / 0.003536 | 0.010926 / 0.014142 |

### Fresh-process wall time (milliseconds, median / p95)

| Mode | Usage/startup proxy | Inspect | Replace + save |
| --- | ---: | ---: | ---: |
| safe | 4.055 / 4.869 | 4.686 / 5.235 | 4.485 / 5.020 |
| fast | 3.821 / 4.740 | 4.258 / 5.621 | 4.323 / 4.732 |
| small | 5.132 / 27.833 | 9.565 / 28.115 | 12.933 / 32.225 |

Full first-invocation measurements, RSS, checksums and measured revision are in [the raw results](initial-results.json). These numbers establish a narrow baseline; they do not predict complex documents, image decoding, arbitrary fonts, rendering or final application size.

## Reproduce

From the repository root with Zig 0.17.1 on PATH:

```sh
zig build test
swiftc tools/pdfkit_check.swift -o /tmp/pod-pdfkit-check
zig build -Doptimize=safe --prefix test-out/safe
python3 tools/validate.py test-out/safe/bin/pod --out test-out/validation-safe --pdfkit-check /tmp/pod-pdfkit-check
python3 tools/benchmark.py test-out/safe/bin/pod
zig build-exe -O safe --dep pod -Mroot=tools/bench.zig -O safe -Mpod=src/pod.zig -lc -femit-bin=test-out/bench-safe
test-out/bench-safe
```

Repeat with `fast` and `small` in both module optimization settings and output paths. The Python benchmark creates `test-out/benchmark/1000-runs.pdf`, which the in-process harness reads. The harness and PDFKit helper are macOS-only validation tools; neither is shipped in the CLI.

## Correctness evidence

All 14 engine tests pass in debug, safe, fast and small. Independent specification and code-quality reviews caught and verified fixes for repeated page-tree traversal and empty xref tables.

Independent CLI fixtures cover inherited resources, indirect stream lengths, `Tj`/`TJ`, shorter and empty replacements, escaped text, transformed text with spacing/rise, unchanged following text positions, unsupported and malformed input, invalid selections, and refusal to overwrite existing files. Each release mode passed the same fixture suite plus 128 deterministic byte-mutation/truncation cases without crashes. This is a smoke test, not coverage-guided fuzzing or a security audit.

PDFKit independently extracts text and renders created/edited documents. Saved examples and PNGs remain under `test-out/validation-safe/`; created and edited pages were visually inspected. The validation helper also compares following-character positions. Broader corpus and fuzz work remains before accepting arbitrary PDFs.
