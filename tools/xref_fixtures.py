"""Independent PDF cross-reference fixtures and end-to-end CLI checks."""
import json
from pathlib import Path
import subprocess
import zlib

CONTENT = b"BT /F1 12 Tf 1 0 0 1 72 720 Tm (Hello) Tj (World) Tj ET\n"
OBJECTS = {
    1: b"<< /Type /Catalog /Pages 2 0 R >>",
    2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> >>",
    3: b"<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>",
    4: b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
}


def add_object(data, number, body, generation=0):
    offset = len(data)
    data.extend(f"{number} {generation} obj\n".encode() + body + b"\nendobj\n")
    return offset


def stream(data, metadata=b""):
    return b"<< /Length " + str(len(data)).encode() + b" " + metadata + b" >>\nstream\n" + data + b"\nendstream"


def last_xref(data):
    return int(data.rsplit(b"startxref\n", 1)[1].splitlines()[0])


def classic():
    data = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {n: add_object(data, n, body) for n, body in OBJECTS.items()}
    offsets[5] = add_object(data, 5, stream(CONTENT))
    xref = len(data)
    data.extend(b"xref\n0 8\n0000000006 65535 f \n")
    for n in range(1, 6):
        data.extend(f"{offsets[n]:010d} 00000 n \n".encode())
    data.extend(b"0000000007 00000 f \n0000000000 00000 f \n")
    data.extend(f"trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


def incremental(original, text=b"Latest", free=False, generation=0, root=True, previous=None):
    data = bytearray(original)
    content = CONTENT.replace(b"Hello", text)
    offset = add_object(data, 5, stream(content), generation)
    xref = len(data)
    if free:
        row = b"0000000000 00001 f \n"
    else:
        row = f"{offset:010d} {generation:05d} n \n".encode()
    data.extend(b"xref\n5 1\n" + row)
    data.extend(b"trailer\n<< /Size 8 " + (b"/Root 1 0 R " if root else b""))
    data.extend(b"/Prev " + str(last_xref(original) if previous is None else previous).encode() + b" >>\n")
    data.extend(f"startxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


def reused_generation():
    original = classic()
    data = bytearray(original)
    page_offset = add_object(data, 3, b"<< /Type /Page /Parent 2 0 R /Contents 5 1 R >>")
    content_offset = add_object(data, 5, stream(CONTENT), generation=1)
    xref = len(data)
    data.extend(f"xref\n3 1\n{page_offset:010d} 00000 n \n5 1\n{content_offset:010d} 00001 n \n".encode())
    data.extend(f"trailer\n<< /Size 8 /Root 1 0 R /Prev {last_xref(original)} >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


def modern(hybrid=False, compressed=True, predictor=False, index=None, rows_override=None, member_override=None, header_override=None, first_override=None):
    data = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    members = [4] if hybrid else [1, 2, 3, 4]
    body = bytearray()
    pairs = []
    for number in members:
        pairs.extend([number, len(body)])
        body.extend(OBJECTS[number] + b"\n")
    header = " ".join(map(str, pairs)).encode() + b" " if header_override is None else header_override
    for number in OBJECTS.keys() - set(members):
        offsets[number] = add_object(data, number, OBJECTS[number])
    offsets[5] = add_object(data, 5, stream(zlib.compress(CONTENT), b"/Filter /FlateDecode"))
    first = len(header) if first_override is None else first_override
    metadata = f"/Type /ObjStm /N {len(members)} /First {first} /Filter /FlateDecode".encode()
    offsets[6] = add_object(data, 6, stream(zlib.compress(header + body), metadata))
    offsets[7] = len(data)
    records = [(0, 0, 65535)]
    for number in range(1, 8):
        records.append((2, 6, members.index(number)) if number in members else (1, offsets[number], 0))
    if member_override:
        records[member_override[0]] = member_override[1]
    selected = list(range(8)) if index is None else [n for i in range(0, len(index), 2) for n in range(index[i], index[i] + index[i + 1])]
    rows = [bytes([records[n][0]]) + records[n][1].to_bytes(4, "big") + records[n][2].to_bytes(2, "big") for n in selected]
    raw = b"".join(rows)
    metadata = b"/Type /XRef /Size 8 /Root 1 0 R /W [1 4 2]"
    if index is not None:
        metadata += b" /Index [" + " ".join(map(str, index)).encode() + b"]"
    if predictor:
        previous = bytes(7)
        filtered = []
        for row in rows:
            filtered.append(b"\x02" + bytes((x - y) % 256 for x, y in zip(row, previous)))
            previous = row
        raw = b"".join(filtered)
        metadata += b" /DecodeParms << /Predictor 12 /Columns 7 >>"
    if rows_override is not None:
        raw = rows_override
    if compressed:
        raw = zlib.compress(raw)
        metadata += b" /Filter /FlateDecode"
    add_object(data, 7, stream(raw, metadata))
    if hybrid:
        xref = len(data)
        data.extend(b"xref\n0 8\n0000000000 65535 f \n")
        for number in range(1, 8):
            data.extend(b"0000000000 00000 f \n" if number in members else f"{offsets[number]:010d} 00000 n \n".encode())
        data.extend(f"trailer\n<< /Size 8 /Root 1 0 R /XRefStm {offsets[7]} >>\n".encode())
    else:
        xref = offsets[7]
    data.extend(f"startxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


def sparse_update(original):
    data = bytearray(original)
    content = CONTENT.replace(b"Hello", b"Sparse")
    offset = add_object(data, 5, stream(content))
    xref = len(data)
    # Width zero for type and generation means uncompressed and generation zero.
    rows = offset.to_bytes(4, "big") + xref.to_bytes(4, "big")
    metadata = f"/Type /XRef /Size 9 /Root 1 0 R /W [0 4 0] /Index [5 1 8 1] /Prev {last_xref(original)}".encode()
    add_object(data, 8, stream(rows, metadata))
    data.extend(f"startxref\n{xref}\n%%EOF\n".encode())
    return bytes(data)


def validate(binary, out, pdfkit=None, pikepdf_check=False, native_check=None):
    out.mkdir(parents=True, exist_ok=True)
    base = modern()
    cases = {
        "xref-plain": (modern(compressed=False), "Hello"),
        "reused-generation": (reused_generation(), "Hello"),
        "xref-flate": (base, "Hello"),
        "xref-predictor": (modern(predictor=True), "Hello"),
        "xref-index": (modern(index=[0, 4, 4, 4]), "Hello"),
        "xref-hybrid": (modern(hybrid=True), "Hello"),
        "incremental": (incremental(classic()), "Latest"),
        "incremental-chain": (incremental(incremental(classic()), b"Newest", root=False), "Newest"),
        "incremental-hybrid": (incremental(modern(hybrid=True)), "Latest"),
        "xref-default-widths": (sparse_update(base), "Sparse"),
        "xref-stream-after-table": (sparse_update(classic()), "Sparse"),
    }
    if pikepdf_check:
        import pikepdf
        qpdf_source = out / "qpdf-source.pdf"
        qpdf_source.write_bytes(classic())
        for linearized in [False, True]:
            for mode in [pikepdf.ObjectStreamMode.disable, pikepdf.ObjectStreamMode.generate]:
                name = f"qpdf-{'linearized' if linearized else 'regular'}-{mode.name}"
                path = out / f"{name}.pdf"
                with pikepdf.open(qpdf_source) as document:
                    document.save(path, linearize=linearized, object_stream_mode=mode)
                cases[name] = (path.read_bytes(), "Hello")
    def run(*args):
        return subprocess.run([str(binary), *map(str, args)], capture_output=True, timeout=10)
    def inspect(path):
        result = run("inspect", path)
        assert result.returncode == 0, (path, result.stderr)
        return json.loads(result.stdout)["pages"][0]["runs"]
    for name, (data, text) in cases.items():
        source, edited = out / f"{name}.pdf", out / f"{name}-edited.pdf"
        source.write_bytes(data)
        if native_check:
            result = subprocess.run([str(native_check), str(source), "/System/Library/Fonts/Supplemental/Courier New.ttf"], capture_output=True, timeout=30)
            assert result.returncode == 0, (name, result.stderr)
        edited.unlink(missing_ok=True)
        before = inspect(source)
        assert [r["text"] for r in before] == [text, "World"], (name, before)
        result = run("replace", source, edited, 1, 0, "Hi")
        assert result.returncode == 0, (name, result.stderr)
        after = inspect(edited)
        assert [r["text"] for r in after] == ["Hi", "World"], (name, after)
        assert before[1]["x"] == after[1]["x"]
        assert source.read_bytes() == data
        assert b"/Prev" not in edited.read_bytes() and b"/XRefStm" not in edited.read_bytes()
        if pikepdf_check:
            with pikepdf.open(edited) as document:
                assert not document.check_pdf_syntax(), name
        if pdfkit:
            for path, expected in [(source, text), (edited, "Hi")]:
                result = subprocess.run([str(pdfkit), str(path), str(path.with_suffix(".png"))], capture_output=True, check=True)
                decoded = json.loads(result.stdout)
                assert expected in decoded["text"] and "World" in decoded["text"], (name, decoded)
    # PDFKit rejects this transition, while pypdf and Pod resolve its latest revision.
    # Keep it in the CLI regressions and validate its normalized saved copy with PDFKit.
    mixed = out / "mixed-table-after-stream.pdf"
    mixed.write_bytes(incremental(base))
    assert [r["text"] for r in inspect(mixed)] == ["Latest", "World"]
    normalized = out / "mixed-table-after-stream-edited.pdf"
    normalized.unlink(missing_ok=True)
    assert run("replace", mixed, normalized, 1, 0, "Hi").returncode == 0
    assert [r["text"] for r in inspect(normalized)] == ["Hi", "World"]
    if pdfkit:
        result = subprocess.run([str(pdfkit), str(normalized), str(normalized.with_suffix(".png"))], capture_output=True, check=True)
        assert "Hi" in json.loads(result.stdout)["text"]
    def change_xref(data, old, new):
        offset = last_xref(data)
        return data[:offset] + data[offset:].replace(old, new, 1)
    invalid = {
        "xref-wide-field": change_xref(base, b"/W [1 4 2]", b"/W [1 9 2]"),
        "xref-negative-field": change_xref(base, b"/W [1 4 2]", b"/W [1 -1 2]"),
        "xref-huge-size": change_xref(base, b"/Size 8", b"/Size 1000001"),
        "xref-indirect-filter": change_xref(base, b"/Filter /FlateDecode", b"/Filter 4 0 R"),
        "xref-indirect-length": change_xref(base, b"/Length", b"/Length 5 0 R /OtherLength"),
        "xref-short": modern(rows_override=b"\0" * 55),
        "xref-long": modern(rows_override=b"\0" * 57),
        "xref-overlap": modern(index=[0, 5, 4, 4]),
        "member-index": modern(member_override=(1, (2, 6, 1))),
        "nested-object-stream": modern(member_override=(6, (2, 6, 0))),
        "header-offset": modern(first_override=1),
        "header-duplicate": modern(header_override=b"1 0 1 35 3 170 4 225 "),
        "freed-content": incremental(base, free=True),
        "wrong-generation": incremental(base, generation=1),
        "prev-zero": incremental(base, previous=0),
    }
    # Self-referential /Prev must terminate instead of cycling forever.
    revision = incremental(base)
    previous = str(last_xref(base)).encode()
    cycle = revision.replace(b"/Prev " + previous, b"/Prev " + str(last_xref(revision)).encode())
    invalid["prev-cycle"] = cycle
    for name, data in invalid.items():
        path, target = out / f"bad-{name}.pdf", out / f"bad-{name}-output.pdf"
        path.write_bytes(data)
        target.unlink(missing_ok=True)
        result = run("replace", path, target, 1, 0, "Hi")
        assert result.returncode > 0 and not target.exists(), (name, result.stderr)
    # Mutate structure and encoded data with a reproducible seed. Rejections must not crash.
    import random
    rng = random.Random(0x58524546)
    mutant = out / "mutant.pdf"
    for index in range(128):
        data = bytearray(base if index % 2 else incremental(classic()))
        if index % 4 == 0:
            data = data[:rng.randrange(len(data))]
        else:
            for _ in range(1 + index % 8):
                data[rng.randrange(len(data))] = rng.randrange(256)
        mutant.write_bytes(data)
        result = run("inspect", mutant)
        assert result.returncode >= 0, (index, result.stderr)
        if result.returncode == 0:
            json.loads(result.stdout)
    mutant.unlink(missing_ok=True)
    print(json.dumps({"mutation_cases": 128, "xref_valid_cases": len(cases), "xref_invalid_cases": len(invalid), "artifacts": str(out)}))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--out", type=Path, default=Path("test-out/xref"))
    parser.add_argument("--pdfkit-check", type=Path)
    parser.add_argument("--pikepdf-check", action="store_true")
    parser.add_argument("--native-check", type=Path)
    args = parser.parse_args()
    validate(args.binary.resolve(), args.out.resolve(), args.pdfkit_check.resolve() if args.pdfkit_check else None, args.pikepdf_check, args.native_check.resolve() if args.native_check else None)
