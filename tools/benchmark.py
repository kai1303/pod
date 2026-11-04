#!/usr/bin/env python3
"""Small reproducible CLI benchmark; process wall time includes spawn and I/O."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import re
import statistics
import subprocess
import time
from validate import fixture


def distribution(values):
    ordered = sorted(values)
    return {"median_ms": statistics.median(ordered), "p95_ms": ordered[min(len(ordered) - 1, int(len(ordered) * .95))], "min_ms": ordered[0]}


def benchmark(binary, out, iterations):
    out.mkdir(parents=True, exist_ok=True)
    # Independent input stresses object/content parsing, not font or image decoding.
    data = fixture(b"BT /F1 12 Tf 1 0 0 1 72 720 Tm\n" + b"(Hello) Tj 0 -14 Td\n" * 1000 + b"ET\n")
    source = out / "1000-runs.pdf"
    source.write_bytes(data)
    target = out / "edited.pdf"
    result = {"binary": str(binary), "binary_bytes": binary.stat().st_size,
              "system": platform.platform(), "machine": platform.machine(),
              "iterations": iterations, "fixture_bytes": len(data),
              "fixture_sha256": hashlib.sha256(data).hexdigest(), "runs": 1000}
    for name, command in {
        "usage_startup": [str(binary)],
        "inspect": [str(binary), "inspect", str(source)],
        "replace_save": [str(binary), "replace", str(source), str(target), "1", "0", "Hi"],
    }.items():
        elapsed = []
        for i in range(iterations + 1):
            target.unlink(missing_ok=True)
            start = time.perf_counter_ns()
            process = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            assert process.returncode >= 0 and (name == "usage_startup" or process.returncode == 0), process.stderr
            duration = (time.perf_counter_ns() - start) / 1e6
            if i == 0:
                first = duration
            else:
                elapsed.append(duration)
        target.unlink(missing_ok=True)
        rss = subprocess.run(["/usr/bin/time", "-l", *command], capture_output=True)
        assert name == "usage_startup" or rss.returncode == 0, rss.stderr
        match = re.search(rb"(\d+)\s+maximum resident set size", rss.stderr)
        result[name] = {"first_invocation_ms": first, **distribution(elapsed), "peak_rss_bytes": int(match[1]) if match else None}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--out", type=Path, default=Path("test-out/benchmark"))
    parser.add_argument("--iterations", type=int, default=30)
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("iterations must be positive")
    benchmark(args.binary.resolve(), args.out.resolve(), args.iterations)
