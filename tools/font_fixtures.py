#!/usr/bin/env python3
"""Independent standard-font fixtures; no engine or generated-table imports."""
from pathlib import Path
import sys
from link_fixtures import serialize

ROOT = Path(__file__).resolve().parents[1]

def pdf(font, content, extra_objects=()):
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 ' + font + b' >>',
        b'<< /Length ' + str(len(content)).encode() + b' >>\nstream\n' + content + b'\nendstream',
    ] + list(extra_objects))

def main(out):
    out.mkdir(parents=True, exist_ok=True)
    for path in sorted((ROOT/'assets/font-metrics').glob('*.afm')):
        codes = []
        for line in path.read_text().splitlines():
            if line.startswith('C '):
                code = int(line.split()[1])
                if code >= 32: codes.append(code)
        content = bytearray(b'BT /F1 16 Tf\n')
        for i, code in enumerate(codes):
            content += f'1 0 0 1 {40+(i%16)*34} {740-(i//16)*38} Tm <{code:02x}> Tj\n'.encode()
        content += b'ET'
        (out/(path.stem+'.pdf')).write_bytes(pdf(b'/BaseFont /'+path.stem.encode(),content))
    cases = {
        'win-ansi': (b'/BaseFont /Helvetica /Encoding /WinAnsiEncoding', b'636166e9208020ff', 'café € ÿ'),
        'mac-roman': (b'/BaseFont /Times-Roman /Encoding /MacRomanEncoding', b'6361668e20db', 'café ¤'),
        'standard': (b'/BaseFont /Helvetica', b'60666927aeb1', '‘fi’ﬁ–'),
        'differences': (b'/BaseFont /Helvetica /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /eacute /Euro /fi] >>', b'414243', 'é€ﬁ'),
        'widths': (b'/BaseFont /Helvetica /Encoding /WinAnsiEncoding /FirstChar 65 /LastChar 66 /Widths [900 300]', b'4142', 'AB'),
    }
    for name, (font, encoded, text) in cases.items():
        (out/(name+'.pdf')).write_bytes(pdf(font,b'BT /F1 12 Tf 1 0 0 1 72 700 Tm <'+encoded+b'> Tj (tail) Tj ET'))
        (out/(name+'.txt')).write_text(text)
    for name, font in {
        'invalid-differences': b'/BaseFont /Helvetica /Encoding << /Differences [255 /A /B] >>',
        'invalid-widths': b'/BaseFont /Helvetica /FirstChar 65 /LastChar 66 /Widths [1]',
        'negative-width': b'/BaseFont /Helvetica /FirstChar 65 /LastChar 65 /Widths [-1]',
    }.items():
        (out/(name+'.pdf')).write_bytes(pdf(font,b'BT /F1 12 Tf (A) Tj ET'))
    print(out.resolve())

if __name__ == '__main__': main(Path(sys.argv[1]))
