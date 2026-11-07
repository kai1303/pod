#!/usr/bin/env python3
"""Independent byte-level web-link PDFs for the native integration check."""
from pathlib import Path
import sys


def fixture(base=False):
    content = b"BT /F1 12 Tf 1 0 0 1 72 720 Tm (Lesson reference) Tj ET\n"
    bodies = [
        b"<< /Type /Catalog /Pages 2 0 R" + (b" /URI << /Base (https://example.com/course/) >>" if base else b"") + b" >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /Annots [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R] >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"endstream",
        b"<< /Type /Annot /Subtype /Link /P 3 0 R /Rect [70 710 220 740] /Border [0 0 2] /C [0 0 1] /A 12 0 R /NM (lesson-link) /Contents (Keep this note) >>",
        b"<< /Subtype /Link /Rect [70 650 220 680] /BS << /W 2 /S /U >> /C [0.3] /A << /S /URI /URI (https://example.com/underline) >> >>",
        b"<< /Subtype /Link /Rect [70 570 220 640] /Border [0 0 0] /QuadPoints [70 640 220 640 70 620 220 620 70 590 220 590 70 570 220 570] /A << /S /URI /URI (https://example.com/quads) >> >>",
        b"<< /Subtype /Link /Rect [70 500 220 530] /F 32 /Border [0 0 6] /C [1 0 0] /A << /S /URI /URI (https://example.com/hidden) >> >>",
        b"<< /Subtype /Link /Rect [70 440 220 470] /Border [0 0 0] /A << /S /URI /URI (javascript:alert%281%29) >> >>",
        b"<< /Subtype /Link /Rect [70 380 220 410] /Border [0 0 0] /A << /S /URI /URI (chapter.html) >> >>",
        b"<< /S /URI /URI (https://example.com/lesson) >>",
    ]
    return serialize(bodies)


def serialize(bodies):
    output = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for number, body in enumerate(bodies, 1):
        offsets.append(len(output))
        output += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    start = len(output)
    output += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    for offset in offsets[1:]:
        output += f"{offset:010d} 00000 n \n".encode()
    output += f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode()
    return output


def destinations(direct_only=False):
    first = b"BT /F1 12 Tf 1 0 0 1 72 750 Tm (Contents) Tj ET\n"
    second = b"0.2 0.4 0.8 rg 72 100 200 300 re f 0 g BT /F1 12 Tf 1 0 0 1 72 700 Tm (Chapter page) Tj ET\n"
    def stream(data):
        return b"<< /Length " + str(len(data)).encode() + b" >>\nstream\n" + data + b"endstream"
    bodies = [
        b"<< /Type /Catalog /Pages 2 0 R /Dests << /legacy << /D [6 0 R /FitH 720] >> >> /Names << /Dests 9 0 R >> >>",
        b"<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 /Resources << /Font << /F1 4 0 R >> >> >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R /Annots [10 0 R 11 0 R 12 0 R 13 0 R 14 0 R 15 0 R 16 0 R 17 0 R 18 0 R 19 0 R 20 0 R] >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
        stream(first),
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /CropBox [10 20 600 780] /Rotate 90 /Contents 7 0 R /Annots [21 0 R] >>",
        stream(second),
        b"<< /Limits [(chapter) (fitbox)] /Names [(chapter) << /D [6 0 R /XYZ 72 700 1.5] >> (fitbox) [6 0 R /FitB]] >>",
        b"<< /Kids [8 0 R] >>",
    ]
    targets = ["[6 0 R /XYZ 72 700 1.5]", "[6 0 R /Fit]", "[6 0 R /FitH 700]", "[6 0 R /FitV 72]", "[6 0 R /FitR 72 100 272 400]", "[6 0 R /FitB]", "[6 0 R /FitBH 700]", "[6 0 R /FitBV 72]", "/legacy", "(chapter)", "(fitbox)"]
    for i, target in enumerate(targets):
        action = f"/Dest {target}" if i % 2 == 0 else f"/A << /S /GoTo /D {target} >>"
        y = 700 - 40*i
        bodies.append(f"<< /Subtype /Link /P 3 0 R /Rect [40 {y} 220 {y+25}] /Border [0 0 1] /C [0 0 1] /NM (destination-{i}) {action} >>".encode())
    bodies.append(b"<< /Subtype /Link /P 6 0 R /Rect [300 500 450 530] /Border [0 0 0] /Dest [3 0 R /Fit] >>")
    if direct_only:
        bodies[0] = b"<< /Type /Catalog /Pages 2 0 R >>"
        bodies[2] = bodies[2].replace(b" 18 0 R 19 0 R 20 0 R", b"")
    return serialize(bodies)


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "test-out/links")
    out.mkdir(parents=True, exist_ok=True)
    for name, base in [("web-links", False), ("relative-links", True)]:
        (out / f"{name}.pdf").write_bytes(fixture(base))
    (out / "destinations.pdf").write_bytes(destinations())
    (out / "direct-destinations.pdf").write_bytes(destinations(True))
    print(out.resolve())
