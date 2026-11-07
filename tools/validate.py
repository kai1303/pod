#!/usr/bin/env python3
"""Independent fixture producer and CLI contract checks (Python stdlib only)."""
import argparse
import base64
import zlib
import hashlib
import json
from pathlib import Path
import random
import subprocess


def fixture(content=None, font=b"Courier", extra=b"", trailer=b"", indirect=True, length_override=None):
    content = content or b"BT /F1 12 Tf 1 0 0 1 72 720 Tm (Hello) Tj (World) Tj 0 -20 Td [(ABC) 100 (DEF)] TJ ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /" + font + b" /Encoding /WinAnsiEncoding >>",
        b"<< /Length " + (b"6 0 R" if indirect else str(len(content)).encode()) + b" " + extra + b" >>\nstream\n" + content + b"endstream",
        str(len(content) if length_override is None else length_override).encode(),
    ]
    data = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += str(i).encode() + b" 0 obj\n" + obj + b"\nendobj\n"
    xref = len(data)
    data += b"xref\n0 7\n0000000000 65535 f \n"
    for offset in offsets[1:]:
        data += f"{offset:010d} 00000 n \n".encode()
    data += b"trailer\n<< /Size 7 /Root 1 0 R " + trailer + b" >>\nstartxref\n" + str(xref).encode() + b"\n%%EOF\n"
    return bytes(data)


def lzw_literals(data, early_change):
    """Pack literal codes with PDF LZW width transitions, including a table reset."""
    encoded = []
    width, next_code, previous = 9, 258, False
    encoded.append(f"{256:09b}")
    for char in data:
        encoded.append(f"{char:0{width}b}")
        if previous:
            next_code += 1
            if width < 12 and next_code + early_change == 1 << width:
                width += 1
        previous = True
        if next_code == 4096:
            encoded.append(f"{256:0{width}b}")
            width, next_code, previous = 9, 258, False
    encoded.append(f"{257:0{width}b}")
    bits = "".join(encoded)
    bits += "0" * (-len(bits) % 8)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))


def run(binary, *args, success=True):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, timeout=10)
    assert (result.returncode == 0) == success, (args, result.returncode, result.stdout, result.stderr)
    return result


def inspect(binary, path):
    return json.loads(run(binary, "inspect", path).stdout)


def validate(binary, out, pdfkit=None, mutations=128):
    out.mkdir(parents=True, exist_ok=True)
    # Stable, regenerated outputs: never touch files outside this test directory.
    for path in out.glob("*.pdf"):
        path.unlink()
    source = out / "independent.pdf"
    source.write_bytes(fixture())
    original = hashlib.sha256(source.read_bytes()).digest()
    pages = inspect(binary, source)["pages"]
    assert len(pages) == 1 and pages[0]["number"] == 1, pages
    runs = pages[0]["runs"]
    hello = next(r for r in runs if r["text"] == "Hello")
    world = next(r for r in runs if r["text"] == "World")
    assert abs(hello["x"] - 72) < 1e-6 and abs(hello["advance"] - 36) < 1e-6, hello
    assert abs(world["x"] - 108) < 1e-6, world
    assert "ABCDEF" in "".join(r["text"] for r in runs), runs
    edited = out / "edited.pdf"
    run(binary, "replace", source, edited, 1, hello["id"], "Hi")
    changed = inspect(binary, edited)["pages"][0]["runs"]
    assert any(r["text"] == "Hi" for r in changed), changed
    after = next(r for r in changed if r["text"] == "World")
    assert abs(after["x"] - world["x"]) < 1e-6 and abs(after["y"] - world["y"]) < 1e-6, after
    assert b"Hello" not in edited.read_bytes(), "Original operand must actually be replaced"
    deleted = out / "deleted.pdf"
    run(binary, "replace", source, deleted, 1, hello["id"], "")
    deleted_runs = inspect(binary, deleted)["pages"][0]["runs"]
    assert all(r["text"] != "Hello" for r in deleted_runs)
    assert abs(next(r for r in deleted_runs if r["text"] == "World")["x"] - world["x"]) < 1e-6
    escaped = out / "escaped.pdf"
    run(binary, "replace", source, escaped, 1, hello["id"], "(\\)")
    assert any(r["text"] == "(\\)" for r in inspect(binary, escaped)["pages"][0]["runs"])
    transformed = out / "transformed.pdf"
    transformed.write_bytes(fixture(b"q 1 .2 .1 1 10 15 cm BT /F1 12 Tf 2 Tc 3 Tw 80 Tz 4 Ts 1 .1 .2 1 72 600 Tm (A B) Tj (NEXT) Tj ET Q\n"))
    transformed_edit = out / "transformed-edited.pdf"
    transformed_runs = inspect(binary, transformed)["pages"][0]["runs"]
    run(binary, "replace", transformed, transformed_edit, 1, transformed_runs[0]["id"], "X")
    transformed_after = inspect(binary, transformed_edit)["pages"][0]["runs"]
    assert transformed_after[0]["text"] == "X"
    for coordinate in ["x", "y"]:
        assert abs(transformed_runs[1][coordinate] - transformed_after[1][coordinate]) < 1e-5
    run(binary, "replace", source, out / "overflow.pdf", 1, hello["id"], "Too long to fit", success=False)
    assert not (out / "overflow.pdf").exists()
    for page, run_id in [(0, 0), (2, 0), (1, 999)]:
        target = out / f"invalid-selection-{page}-{run_id}.pdf"
        run(binary, "replace", source, target, page, run_id, "Hi", success=False)
        assert not target.exists()
    run(binary, "replace", source, source, 1, hello["id"], "Hi", success=False)
    protected = out / "protected.pdf"
    protected.write_bytes(b"do not overwrite")
    run(binary, "replace", source, protected, 1, hello["id"], "Hi", success=False)
    assert protected.read_bytes() == b"do not overwrite"
    assert hashlib.sha256(source.read_bytes()).digest() == original
    for name, data in {
        "font": fixture(font=b"UnrecognizedFont"),
        "filter": fixture(extra=b"/Filter /FlateDecode"),
        "revision": fixture(trailer=b"/Prev 0"),
        "truncated": fixture()[:120],
        "xref": fixture().replace(b"startxref\n", b"startxref\n999999 %"),
        "length": fixture(length_override=99999),
    }.items():
        path = out / f"bad-{name}.pdf"
        path.write_bytes(data)
        target = out / f"rejected-{name}.pdf"
        run(binary, "replace", path, target, 1, 0, "Hi", success=False)
        assert not target.exists(), name
    content = b"BT /F1 12 Tf 1 0 0 1 72 720 Tm (Hello) Tj (World) Tj ET\n"
    compressed = zlib.compress(content)
    compressed_paths = []
    # The comment drives LZW through 9/10/11/12-bit codes and dictionary resets.
    lzw_content = content + b"%" + b"dictionary-width-check " * 300 + b"\n"
    for name, encoded, metadata in [
        ("flate", compressed, b"/Filter /FlateDecode"),
        ("flate-array", compressed, b"/Filter [/FlateDecode] /DecodeParms [null]"),
        ("flate-params", compressed, b"/Filter /FlateDecode /DecodeParms << /Predictor 1 >>"),
        ("ascii85-flate", base64.a85encode(compressed) + b"~>", b"/Filter [/ASCII85Decode /FlateDecode] /DecodeParms [null null]"),
        ("hex-flate", compressed.hex().encode() + b">", b"/Filter [/ASCIIHexDecode /FlateDecode]"),
        ("run-length", bytes([len(content) - 1]) + content + b"\x80", b"/Filter /RunLengthDecode"),
        ("lzw-early", lzw_literals(lzw_content, 1), b"/Filter /LZWDecode"),
        ("lzw-late", lzw_literals(lzw_content, 0), b"/Filter /LZWDecode /DecodeParms << /EarlyChange 0 >>"),
    ]:
        compressed_source = out / f"{name}.pdf"
        compressed_source.write_bytes(fixture(content=encoded, extra=metadata))
        before_bytes = compressed_source.read_bytes()
        decoded_runs = inspect(binary, compressed_source)["pages"][0]["runs"]
        assert [r["text"] for r in decoded_runs] == ["Hello", "World"], decoded_runs
        compressed_edit = out / f"{name}-edited.pdf"
        run(binary, "replace", compressed_source, compressed_edit, 1, 0, "Hi")
        edited_runs = inspect(binary, compressed_edit)["pages"][0]["runs"]
        assert [r["text"] for r in edited_runs] == ["Hi", "World"], edited_runs
        assert abs(decoded_runs[1]["x"] - edited_runs[1]["x"]) < 1e-6
        assert b"/Filter" not in compressed_edit.read_bytes()
        assert b"/DecodeParms" not in compressed_edit.read_bytes()
        assert compressed_source.read_bytes() == before_bytes
        compressed_paths.extend([compressed_source, compressed_edit])
    created = out / "created.pdf"
    run(binary, "create", created, "Native PDF engine")
    assert "Native PDF engine" in "".join(r["text"] for r in inspect(binary, created)["pages"][0]["runs"])
    run(binary, "create", created, "overwrite", success=False)
    if pdfkit:
        decoded = {}
        for path in [source, edited, created, escaped, transformed, transformed_edit, *compressed_paths]:
            result = subprocess.run([str(pdfkit), str(path), str(path.with_suffix(".png"))], capture_output=True, check=True)
            decoded[path.stem] = json.loads(result.stdout)
            assert decoded[path.stem]["pages"] == 1
        for path in compressed_paths:
            expected = "Hi" if path.stem.endswith("-edited") else "Hello"
            assert expected in decoded[path.stem]["text"] and "World" in decoded[path.stem]["text"]
        assert "Hi" in decoded["edited"]["text"] and "Hello" not in decoded["edited"]["text"]
        assert "Native PDF engine" in decoded["created"]["text"]
        assert "(\\)" in decoded["escaped"]["text"]
        before_w = next(c for c in decoded["independent"]["characters"] if c["text"] == "W")
        after_w = next(c for c in decoded["edited"]["characters"] if c["text"] == "W")
        assert abs(before_w["x"] - after_w["x"]) < 1e-5 and abs(before_w["y"] - after_w["y"]) < 1e-5
        # PDFKit extends a word-leading selection into inferred whitespace.
        # An interior glyph gives a stable independent position measurement.
        before_e = next(c for c in decoded["transformed"]["characters"] if c["text"] == "E")
        after_e = next(c for c in decoded["transformed-edited"]["characters"] if c["text"] == "E")
        assert abs(before_e["x"] - after_e["x"]) < 1e-5 and abs(before_e["y"] - after_e["y"]) < 1e-5
        (out / "pdfkit-results.json").write_text(json.dumps(decoded, indent=2))
    # A reproducible crash smoke test, not coverage-guided fuzzing or a security audit.
    rng = random.Random(0x504446)
    seed = fixture()
    mutant = out / "mutant.pdf"
    for index in range(mutations):
        data = bytearray(seed)
        if index % 3 == 0:
            data = data[:rng.randrange(len(data))]
        else:
            for _ in range(1 + index % 8):
                data[rng.randrange(len(data))] = rng.randrange(256)
        mutant.write_bytes(data)
        result = subprocess.run([str(binary), "inspect", str(mutant)], capture_output=True, timeout=3)
        assert result.returncode >= 0, ("crash", index, result.stderr)
        if result.returncode == 0:
            json.loads(result.stdout)
    mutant.unlink(missing_ok=True)
    print(json.dumps({"result": "passed", "mutation_cases": mutations, "fixture_bytes": source.stat().st_size, "artifacts": str(out.resolve())}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("--out", type=Path, default=Path("test-out/validation"))
    parser.add_argument("--pdfkit-check", type=Path, help="compiled tools/pdfkit_check.swift helper (macOS)")
    parser.add_argument("--mutations", type=int, default=128)
    args = parser.parse_args()
    validate(args.binary.resolve(), args.out.resolve(), args.pdfkit_check.resolve() if args.pdfkit_check else None, args.mutations)
