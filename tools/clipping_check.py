#!/usr/bin/env python3
"""Independent PDF clipping fixtures and raster checks; MuPDF is test-only."""
import sys
from pathlib import Path
from validate import fixture

ROOT = Path(sys.argv[1])
CASES = {
    "rectangle": "100 100 220 340 re W n 0 0 612 792 re f",
    "evenodd-hole": "100 100 400 500 re 170 200 230 200 re W* n 0 0 612 792 re f",
    "nonzero-overlap": "100 100 400 500 re 170 200 230 200 re W n 0 0 612 792 re f",
    "nonzero-hole": "100 100 400 500 re 170 400 230 -200 re W n 0 0 612 792 re f",
    "bowtie": "100 100 m 500 600 l 100 600 l 500 100 l h W* n 0 0 612 792 re f",
    "concave": "100 100 m 500 100 l 270 250 l 500 600 l 100 600 l 200 350 l h W n 0 0 612 792 re f",
    "curve": "300 150 m 465 150 520 400 300 600 c 80 400 135 150 300 150 c h W n 0 0 612 792 re f",
    "restore": "100 100 400 500 re W n q 170 200 230 200 re W n 0.8 g 0 0 612 792 re f Q 0 g 100 100 100 500 re f",
    "nested-crossings": "100 100 m 500 600 l 100 600 l 500 100 l h W* n 50 200 m 550 400 l 50 500 l h W n 0 0 612 792 re f",
    "stroke-before-clip": "20 w 100 100 400 500 re W S 0.5 g 0 0 612 792 re f",
    "fill-stroke-before-clip": "20 w 0.5 g 100 100 400 500 re W B 0 g 250 0 50 792 re f",
    "empty": "100 100 0 0 re W n 0 0 612 792 re f",
    "disjoint": "100 100 100 100 re W n 300 300 100 100 re W n 0 0 612 792 re f",
    "transform": "q 0.8 0.3 -0.3 0.8 200 50 cm 0 0 300 500 re W n -500 -500 1500 1500 re f Q",
    "crossing-paint": "100 100 m 500 600 l 100 600 l 500 100 l h W* n 50 200 m 550 400 l 50 500 l h f*",
    "open-subpath": "100 100 m 500 600 l 100 600 l W n 0 0 612 792 re f",
    "clipped-stroke": "100 100 220 340 re W n 40 w 0 0 m 612 792 l S",
}
if "--fixtures" in sys.argv:
    ROOT.mkdir(parents=True, exist_ok=True)
    for name, stream in CASES.items():
        (ROOT / (name + ".pdf")).write_bytes(fixture(stream.encode() + b"\n"))
    raise SystemExit(0)

import numpy as np
import pymupdf
minimum_overlap, maximum_error = 1.0, 0.0
for name in CASES:
    for suffix in ["", "-saved", "-annotated", "-rotated"]:
        with pymupdf.open(ROOT / (name + suffix + ".pdf")) as doc:
            for width in [612, 1224]:
                page = doc[0]
                scale = width / page.rect.width
                reference = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
                actual = pymupdf.Pixmap(str(ROOT / f"{name}{suffix}-{width}.png"))
                assert (actual.width, actual.height) == (reference.width, reference.height)
                expected = np.frombuffer(reference.samples, np.uint8).reshape(-1, 3).astype(np.int16)
                observed = np.frombuffer(actual.samples, np.uint8).reshape(-1, actual.n)[:, :3].astype(np.int16)
                mask_a = np.min(observed, axis=1) < 240
                mask_b = np.min(expected, axis=1) < 240
                union = np.count_nonzero(mask_a | mask_b)
                overlap = np.count_nonzero(mask_a & mask_b) / max(1, union) if union else 1
                error = np.abs(expected - observed).mean()
                minimum_overlap = min(minimum_overlap, overlap)
                maximum_error = max(maximum_error, float(error))
                assert overlap > 0.99 and error < 1, (name, suffix, width, overlap, error)
            if suffix == "-saved":
                with pymupdf.open(ROOT / (name + ".pdf")) as original:
                    assert original[0].get_pixmap().samples == page.get_pixmap().samples, (name, "save changed appearance")
    print("PASS:", name, "native/Metal, save/reopen, annotation isolation, crop/rotation and independent rasters")

print(f"136 independent rasters: minimum mask overlap {minimum_overlap:.6f}, maximum mean channel error {maximum_error:.6f}/255")
