#!/usr/bin/env python3
"""Independent Form XObject producers and visual/save checks. Readers are test-only."""
import json
import re
import math
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(sys.argv[1])


def stream(body, entries=b"", compressed=False):
    body = body.encode() if isinstance(body, str) else body
    if compressed:
        body = zlib.compress(body)
        entries += b" /Filter /FlateDecode"
    return b"<< /Length " + str(len(body)).encode() + b" " + entries + b" >>\nstream\n" + body + b"\nendstream"


def pdf(objects):
    data = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
    offset = len(data)
    data += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    data += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets[1:])
    data += f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{offset}\n%%EOF\n".encode()
    return data


def fixture(content, body, form=b"", child=None, extra=None, bbox=b"[0 0 220 240]", compressed=False, array=False, alias=False):
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 612 792] >>",
        b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> /ColorSpace << /CS /DeviceGray >> /XObject << /Fm " + (b"8" if alias else b"6") + b" 0 R /Child 7 0 R >> /ExtGState << /Alpha << /ca .4 /CA .6 /BM /Multiply >> >> >> /Contents " + (b"[5 0 R 9 0 R]" if array else b"5 0 R") + b" >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
        stream(content),
        stream(body, b"/Type /XObject /Subtype /Form /BBox " + bbox + b" " + form, compressed),
        child or stream("0 0 220 240 re f", b"/Subtype /Form /BBox [0 0 120 160] /Matrix [1 .2 -.2 1 20 30]"),
        extra or b"6 0 R",
        stream("/Fm Do Q 0 0 1 rg 440 150 80 100 re f"),
    ]
    if "(AB) Tj" in body or (child is not None and b"(AB) Tj" in child):
        objects[3] = b"<< /Type /Font /Subtype /TrueType /BaseFont /PodFixture-Regular /FirstChar 65 /LastChar 66 /Widths [600 700] /Encoding /WinAnsiEncoding /FontDescriptor 10 0 R >>"
        objects.extend([
            b"<< /Type /FontDescriptor /FontName /PodFixture-Regular /Flags 32 /FontBBox [0 -200 700 800] /Ascent 800 /Descent -200 /CapHeight 700 /ItalicAngle 0 /StemV 80 /FontFile2 11 0 R >>",
            stream(TEST_FONT, compressed=True),
        ])
    return pdf(objects)


if "--fixtures" in sys.argv:
    ROOT.mkdir(parents=True, exist_ok=True)
    from truetype_fixtures import program
    TEST_FONT = program()
    cases = {
        "transform": fixture("q .9 .3 -.2 .8 150 120 cm /Fm Do Q", ".2 .6 .9 rg -100 -100 500 500 re f", b"/Matrix [1 .2 .3 1 30 40]"),
        "nested": fixture("q 1 0 0 1 150 150 cm /Fm Do Q", "0 .4 .8 rg /Child Do 1 0 0 rg 180 0 40 240 re f", b"/Resources << /XObject << /Child 7 0 R >> >>"),
        "restore": fixture("50 50 450 600 re W n 0 0 1 rg q 1 0 0 1 120 200 cm /Fm Do Q 430 100 200 100 re f", "0 0 100 100 re W n 1 0 0 rg -50 -50 400 400 re f"),
        "inherited-paint": fixture("1 0 0 rg q 1 0 0 1 100 150 cm /Fm Do Q 420 150 80 100 re f", "0 0 200 200 re f 0 0 1 rg 50 50 50 50 re f"),
        "opacity": fixture(".5 .7 .9 rg 60 100 500 500 re f /Alpha gs q 1 0 0 1 120 200 cm /Fm Do Q", "1 0 0 rg 0 0 160 180 re f 80 60 160 180 re f"),
        "stroke": fixture("1 J 2 j 12 w .7 0 .2 RG q 1.1 .2 -.2 .8 160 200 cm /Fm Do Q", "-30 30 m 100 220 l 250 30 l S"),
        "local-color": fixture("/CS cs .5 sc q 1 0 0 1 120 200 cm /Fm Do Q 420 150 80 100 re f", "/CS cs .8 .2 .6 sc 0 0 220 240 re f", b"/Resources << /ColorSpace << /CS /DeviceRGB >> >>"),
        "compressed": fixture("q 1 0 0 1 120 200 cm /Fm Do Q", ".2 .7 .1 rg 0 0 220 240 re f", compressed=True),
        "empty-box": fixture("/Fm Do 0 0 1 rg 400 100 100 100 re f", "1 0 0 rg 0 0 600 700 re f", bbox=b"[100 100 100 200]"),
        "reversed-box": fixture("q 1 0 0 1 120 200 cm /Fm Do Q", ".2 .7 .1 rg -100 -100 500 500 re f", bbox=b"[220 240 0 0]"),
        "array": fixture("q 1 0 0 1 120 200 cm", ".8 .4 .2 rg 0 0 220 240 re f", array=True),
        "alias": fixture("q 1 0 0 1 120 200 cm /Fm Do Q", ".2 .7 .1 rg 0 0 220 240 re f", alias=True),
        "text": fixture("q 1 0 0 1 120 200 cm /Fm Do Q", "BT /Local 18 Tf 1 0 0 1 10 100 Tm (AB) Tj (BA) Tj ET", b"/Resources << /Font << /Local 4 0 R >> >>"),
        "nested-text": fixture("q 1 0 0 1 120 200 cm /Fm Do Q", "q 1 0 0 1 10 20 cm /Child Do Q", b"/Resources << /XObject << /Child 7 0 R >> >>", child=stream("BT /Local 18 Tf 1 0 0 1 10 100 Tm (AB) Tj (BA) Tj ET", b"/Subtype /Form /BBox [0 0 220 240] /Resources << /Font << /Local 4 0 R >> >>")),
        "reused-text": fixture("q 1 0 0 1 120 200 cm /Fm Do 1 0 0 1 0 280 cm /Fm Do Q", "BT /F1 18 Tf 1 0 0 1 10 100 Tm (AB) Tj (BA) Tj ET"),
    }
    gallery = []
    for cap in range(3):
        for join in range(3):
            gallery.append(f"q {cap} J {join} j 10 w 2 M .2 .3 .6 RG 1.4 .2 .4 .8 {80 + cap * 170} {100 + join * 200} cm /Fm Do Q")
    cases["affine-stroke-gallery"] = fixture(" ".join(gallery), "10 20 m 40 100 l 80 20 l S 10 60 m 80 60 l S", bbox=b"[0 0 100 120]")
    cases["reflected-stroke"] = fixture("q 2 J 1 j 16 w .1 .6 .3 RG -1.2 .2 .4 .7 420 150 cm /Fm Do Q", "20 20 m 100 220 l 200 20 l S")
    cases["affine-hairline"] = fixture("q 0 w .9 .3 .4 .7 150 150 cm /Fm Do Q", "20 20 m 100 220 l 200 20 l S")
    from reportlab.pdfgen import canvas
    from reportlab.lib.colors import Color
    c = canvas.Canvas(str(ROOT / "reportlab.pdf"), pagesize=(612, 792), pageCompression=1)
    c.beginForm("art", 0, 0, 220, 240)
    c.setFillColor(Color(.2, .4, .8))
    c.rect(-20, -20, 260, 280, fill=1, stroke=0)
    c.setStrokeColor(Color(.8, .2, .1))
    c.setLineWidth(10)
    c.circle(110, 120, 80, fill=0, stroke=1)
    c.endForm()
    c.saveState()
    c.translate(150, 250)
    c.rotate(12)
    c.doForm("art")
    c.restoreState()
    c.save()
    for name, data in cases.items():
        (ROOT / (name + ".pdf")).write_bytes(data)
    (ROOT / "cases.json").write_text(json.dumps([*cases, "reportlab"]))
    invalid = ROOT / "invalid"
    invalid.mkdir(exist_ok=True)
    for name, data in {
        "group": fixture("/Fm Do", "0 0 1 1 re f", b"/Group << /S /Transparency >>"),
        "cycle": fixture("/Fm Do", "/Fm Do"),
        "resources": fixture("/Fm Do", "BT /F1 12 Tf (A) Tj ET", b"/Resources << >>"),
        "unfinished": fixture("/Fm Do", "0 0 m"),
        "parent-path": fixture("0 0 m /Fm Do", ""),
        "escape-state": fixture("q /Fm Do Q", "Q"),
        "matrix": fixture("/Fm Do", "", b"/Matrix [1 0]"),
    }.items():
        (invalid / (name + ".pdf")).write_bytes(data)
    raise SystemExit(0)

import numpy as np
import pymupdf
from pypdf import PdfReader

def open_reference(path):
    doc = pymupdf.open(path)
    if path.stem.startswith("alias"):
        # MuPDF does not follow an indirect-to-indirect XObject alias. Resolve
        # only in the oracle; native input and saved artifact remain untouched.
        _, value = doc.xref_get_key(doc[0].xref, "Resources/XObject/Fm")
        # These are controlled, uncompressed fixture objects. xref_object itself
        # resolves aliases, but xref_stream does not, so inspect the raw alias bodies.
        aliases = {(int(i), int(g)): (int(t), int(tg)) for i, g, t, tg in re.findall(
            rb"\b(\d+) (\d+) obj\s+(\d+) (\d+) R\s+endobj", path.read_bytes())}
        match = re.fullmatch(r"(\d+) (\d+) R", value.strip())
        assert match, value
        key = (int(match[1]), int(match[2]))
        for _ in range(64):
            if key not in aliases:
                assert doc.xref_is_stream(key[0])
                doc.xref_set_key(doc[0].xref,"Resources/XObject/Fm",f"{key[0]} {key[1]} R")
                normalized = doc.tobytes()
                doc.close()
                doc = pymupdf.open(stream=normalized,filetype="pdf")
                break
            key = aliases[key]
        else:
            raise AssertionError("cyclic alias in reference")
    return doc

def reference_pixels(doc, name, suffix, width):
    page = doc[0]
    scale = width / page.rect.width
    if name in ("dash-large-phase", "dash-negative-phase"):
        # MuPDF loses large-phase precision and does not wrap negative phases.
        # Reduce only the oracle phase to the equivalent position in the cycle.
        with pymupdf.open(stream=doc.tobytes(),filetype="pdf") as normalized:
            for xref in normalized[0].get_contents():
                data=normalized.xref_stream(xref).replace(b'[30 10] 1000000012 d',b'[30 10] 12 d').replace(b'[30 10] -5 d',b'[30 10] 35 d')
                normalized.update_stream(xref,data)
            return normalized[0].get_pixmap(matrix=pymupdf.Matrix(scale,scale),alpha=False)
    if name == "dash-closed":
        # PDFBox joins dashes across closed seams, matching the analytic geometry.
        # MuPDF differs on these cases. Raster tolerances remain unchanged.
        refs=ROOT/"references";refs.mkdir(exist_ok=True)
        path=refs/f"{name}{suffix}-{width}.pdf";path.write_bytes(doc.tobytes())
        png=path.with_suffix('.png')
        subprocess.run(['java','--class-path','.tools/pdfbox-app-3.0.5.jar','tools/PdfboxRender.java',str(path),str(png),str(width)],check=True)
        return pymupdf.Pixmap(str(png))
    if name not in ("affine-stroke-gallery", "reflected-stroke", "affine-hairline", "dash-closed-solid"):
        return page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
    # MuPDF's affine round joins differ from transformed circular outlines.
    # Ghostscript agrees with the analytic stroke geometry and pixel probes.
    # It also preserves all four miter joins when one dash covers a closed
    # rectangle; PDFBox and MuPDF incorrectly leave round caps at its seam.
    gs = shutil.which("gs")
    if not gs:
        raise RuntimeError("Form tests require Ghostscript")
    refs = ROOT / "references"
    refs.mkdir(exist_ok=True)
    path = refs / f"{name}{suffix}-{width}.pdf"
    path.write_bytes(doc.tobytes())
    png = path.with_suffix(".png")
    height = math.ceil(page.rect.height * scale)
    subprocess.run([gs,"-q","-dSAFER","-dBATCH","-dNOPAUSE","-dUseCropBox","-dFIXEDMEDIA",
                    "-sDEVICE=png16m","-dGraphicsAlphaBits=4","-dTextAlphaBits=4",f"-r{scale*72}",
                    f"-g{width}x{height}","-sOutputFile="+str(png),str(path)],check=True)
    return pymupdf.Pixmap(str(png))

maximum_error = 0.0
minimum_overlap = 1.0
minimum_solid_overlap = 1.0
maximum_interior = 0
count = 0
for name in json.loads((ROOT / "cases.json").read_text()):
    for suffix in ["", "-saved", "-annotated", "-rotated"] + ["-organized"] + (["-edited"] if name in ("text", "nested-text") else []):
        file = ROOT / (name + suffix + ".pdf")
        with open_reference(file) as doc:
            page = doc[0]
            for width in (612, 1224):
                ref = reference_pixels(doc, name, suffix, width)
                actual = pymupdf.Pixmap(str(ROOT / f"{name}{suffix}-{width}.png"))
                assert (actual.width, actual.height) == (ref.width, ref.height)
                expected = np.frombuffer(ref.samples, np.uint8).reshape(ref.height, ref.width, 3).astype(np.int16)
                observed = np.frombuffer(actual.samples, np.uint8).reshape(actual.height, actual.width, actual.n)[:, :, :3].astype(np.int16)
                err = np.abs(expected - observed).mean()
                ma, mb = np.min(expected, axis=2) < 240, np.min(observed, axis=2) < 240
                overlap = np.count_nonzero(ma & mb) / np.count_nonzero(ma | mb) if np.any(ma | mb) else 1.0
                maximum_error = max(maximum_error, float(err))
                minimum_overlap = min(minimum_overlap, overlap)
                if name not in ("affine-hairline", "dash-hairline", "dash-hairline-affine"):
                    minimum_solid_overlap = min(minimum_solid_overlap, overlap)
                # Compare interiors strictly and permit only a one-pixel antialias fringe.
                interior = np.ones(expected.shape[:2], dtype=bool)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        interior &= np.all(expected == np.roll(expected, (dy, dx), (0, 1)), axis=2)
                delta = np.abs(expected - observed).max(axis=2)
                if name == "affine-hairline":
                    # Zero-width strokes are device dependent: GS uses less coverage.
                    # Check the shared trace, then independently verify Pod's one-pixel width.
                    near_a, near_b = np.zeros_like(ma), np.zeros_like(mb)
                    for dy in range(-2, 3):
                        for dx in range(-2, 3):
                            near_a |= np.roll(ma, (dy, dx), (0, 1))
                            near_b |= np.roll(mb, (dy, dx), (0, 1))
                    assert not np.any(ma & ~near_b) and not np.any(mb & ~near_a), (name, suffix, width, "trace")
                    if suffix != "-annotated":
                        # Transformed lengths of (20,20)->(100,220)->(200,20).
                        length = (math.hypot(152,164) + math.hypot(10,-110)) * width / page.rect.width
                        area = (255 - observed[:, :, 0]).sum() / 255
                        assert abs(area - length) < length * .025, (name, suffix, width, "hairline area", area, length)
                else:
                    maximum_interior = max(maximum_interior, int(delta[interior].max()))
                    assert delta[interior].max() <= 2, (name, suffix, width, "interior", delta[interior].max())
                    if name.startswith("dash-"):
                        # Short dashes have much more perimeter per painted pixel.
                        # Compare both traces within one pixel, retaining the strict
                        # interior and mean checks instead of a perimeter-sensitive IoU.
                        near_a, near_b = np.zeros_like(ma), np.zeros_like(mb)
                        for dy in (-1,0,1):
                            for dx in (-1,0,1):
                                near_a |= np.roll(ma,(dy,dx),(0,1))
                                near_b |= np.roll(mb,(dy,dx),(0,1))
                        assert not np.any(ma & ~near_b) and not np.any(mb & ~near_a),(name,suffix,width,"dash trace")
                    else:
                        assert overlap > .965, (name, suffix, width, "mask", overlap)
                assert err < 1, (name, suffix, width, "mean", err)
                count += 1
            if suffix in ("-saved", "-organized"):
                with open_reference(ROOT / (name + ".pdf")) as original:
                    assert original[0].get_pixmap().samples == page.get_pixmap().samples, (name, suffix, "appearance changed")
            if suffix == "-edited":
                assert "ABA" in "".join(page.get_text().split()) and "ABBA" not in "".join(page.get_text().split())
        if suffix == "-saved" and name != "alias":
            original = PdfReader(ROOT / (name + ".pdf"))
            saved = PdfReader(file)
            assert original.pages[0].get_contents().get_data()==saved.pages[0].get_contents().get_data(),(name,"page content changed")
            for key in ("/PageMode","/PageLayout"):
                assert original.trailer["/Root"].get(key)==saved.trailer["/Root"].get(key),(name,key,"catalog viewing setting changed")
            for key, obj in original.pages[0]["/Resources"].get("/XObject", {}).items():
                target = saved.pages[0]["/Resources"]["/XObject"][key].get_object()
                assert obj.get_object().get_data() == target.get_data(), (name, key, "stream changed")
    print("PASS:", name, "independent appearance and saved resource preservation")
print(f"{count} independent rasters; min solid mask overlap {minimum_solid_overlap:.6f}; min hairline-inclusive overlap {minimum_overlap:.6f}; max mean error {maximum_error:.6f}/255; max interior error {maximum_interior}/255")
