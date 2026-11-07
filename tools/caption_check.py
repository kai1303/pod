#!/usr/bin/env python3
"""Line-caption fixtures and independent checks of saved appearance streams."""
import json
import math
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
if '--fixtures' in sys.argv:
    from link_fixtures import serialize
    root.mkdir(parents=True, exist_ok=True)
    def stream(data):
        return b'<< /Length ' + str(len(data)).encode() + b' >>\nstream\n' + data + b'\nendstream'
    cases = {
        'inline': ('Lesson 1', '/L [40 170 260 170]'),
        'top': ('Lesson 1', '/L [40 170 260 170] /CP /Top'),
        'offset-inline': ('Lesson 1', '/L [40 170 260 170] /CO [20 0]'),
        'offset-away': ('Lesson 1', '/L [40 170 260 170] /CO [-15 25]'),
        'vertical': ('Height', '/L [150 60 150 280] /LE [/ClosedArrow /OpenArrow]'),
        'reverse': ('Distance', '/L [260 170 40 170] /CP /Top'),
        'leader': ('Measure', '/L [60 130 240 210] /LL -20 /LLE 6 /LLO 4 /LE [/Butt /Slash]'),
        'long': ('This caption is longer than its line', '/L [130 170 170 170]'),
        'multiline': ('First line\r\nSecond line\rThird', '/L [40 170 260 170]'),
        'winansi': ('Café — €25 (draft)', '/L [40 170 260 170] /CP /Top'),
        'empty': ('', '/L [40 170 260 170]'),
        'coincident': ('Point', '/L [150 170 150 170] /LE [/Circle /None]'),
    }
    for name, (text, geometry) in cases.items():
        encoded = ('feff' + text.encode('utf-16-be').hex()).encode()
        annotation = b'<< /Type /Annot /Subtype /Line /Rect [10 20 290 340] /Cap true /Contents <' + encoded + b'> /T (Teacher) /NM (caption-1) /Subj (Preserve metadata) /C [.1 .3 .7] /CA .6 /F 4 /BS << /W 2 /S /D /D [7 3] >> /IC [.8 .7 .2] ' + geometry.encode() + b' >>'
        (root / (name + '.pdf')).write_bytes(serialize([
            b'<< /Type /Catalog /Pages 2 0 R >>',
            b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 360] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>',
            stream(b'.8 .9 1 rg 0 0 300 360 re f'), annotation,
        ]))
    invalid = root / 'invalid'; invalid.mkdir(exist_ok=True)
    baseline = (root / 'inline.pdf').read_bytes()
    # Re-serialize mutations so rejection tests have valid cross-reference offsets.
    source = baseline.split(b'5 0 obj\n', 1)[1].split(b'\nendobj', 1)[0]
    for name, extra in {
        'position': b'/CP /Side', 'offset': b'/CO [1]', 'rich': b'/RC (<p>Rich</p>)',
        'offset-range': b'/CO [0 1000001]',
    }.items():
        (invalid / (name + '.pdf')).write_bytes(serialize([
            b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 360] /Resources << >> /Contents 4 0 R /Annots [5 0 R] >>',
            stream(b''), source[:-2] + b' ' + extra + b' >>',
        ]))
    (root / 'cases.json').write_text(json.dumps(list(cases)))
    print(f'PASS: {len(cases)} caption fixtures')
    raise SystemExit

import numpy as np
import pymupdf
from PIL import Image
from pypdf import PdfReader
from reference_fonts import embed_reference_fonts

worst = 0.0
interior_worst = 0
count = 0
for name in json.loads((root / 'cases.json').read_text()):
    original = PdfReader(root / (name + '.pdf')).pages[0]['/Annots'][0].get_object()
    for suffix in ('-saved', '-moved', '-regenerated', '-resized', '-restyled', '-noted', '-again', '-empty', '-rotated'):
        path = root / (name + suffix + '.pdf')
        annotation = PdfReader(path).pages[0]['/Annots'][0].get_object()
        for key in ('/Cap', '/CP', '/CO', '/LL', '/LLE', '/LLO', '/LE', '/NM', '/T', '/Subj'):
            assert annotation.get(key) == original.get(key), (name, suffix, key)
        if suffix in ('-saved', '-moved') or (name == 'coincident' and suffix == '-resized'):
            # A zero-length line's scaled vertices remain coincident: this is
            # a translation, which deliberately preserves its missing AP.
            assert '/AP' not in annotation
            assert annotation['/Contents'] == original['/Contents']
            continue
        ap = annotation['/AP']['/N'].get_object()
        assert ap['/Resources']['/Font']['/Caption']['/BaseFont'] == '/Helvetica'
        assert ap['/Resources']['/Font']['/Caption']['/Encoding'] == '/WinAnsiEncoding'
        if suffix == '-noted': assert annotation['/Contents'] == 'Updated café — €30'
        if suffix == '-again': assert annotation['/Contents'] == 'Final label'
        if suffix == '-empty': assert annotation['/Contents'] == ''
        reference_path = root / (name + suffix + '-reference.pdf')
        embed_reference_fonts(path, reference_path)
        reference = pymupdf.open(reference_path)
        for width in (300, 600):
            expected = np.array(Image.open(root / f'{name}{suffix}-{width}.png').convert('RGB'), dtype=np.int16)
            pix = reference[0].get_pixmap(matrix=pymupdf.Matrix(width/reference[0].rect.width, width/reference[0].rect.width), alpha=False)
            actual = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, 3).astype(np.int16)
            if name == 'vertical':
                # MuPDF caps the closed arrow's dashed seam. Ghostscript agrees
                # with the analytic closed-dash regression and the joined outline.
                png = root / f'{name}{suffix}-{width}-gs.png'
                resolution = width / reference[0].rect.width * 72 * 4
                subprocess.run(['gs', '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-dUseCropBox', '-sDEVICE=png16m', '-dGraphicsAlphaBits=4', '-dTextAlphaBits=4', f'-r{resolution}', '-sOutputFile='+str(png), str(reference_path)], check=True)
                image = Image.open(png).convert('RGB')
                image = image.resize((width, math.ceil(width*reference[0].rect.height/reference[0].rect.width)), Image.Resampling.BOX)
                actual = np.array(image, dtype=np.int16)
            assert actual.shape == expected.shape, (name, suffix, actual.shape, expected.shape)
            difference = np.abs(actual-expected)
            mean = float(difference.mean())
            # Exclude only edge neighborhoods; flat ink interiors must agree.
            flat = np.ones(expected.shape[:2], dtype=bool)
            for y in (-1, 0, 1):
                for x in (-1, 0, 1):
                    flat &= np.all(actual == np.roll(actual, (y,x), (0,1)), axis=2)
            interior = int(difference[flat].max()) if flat.any() else 0
            assert mean < 1 and interior <= 2, (name, suffix, width, mean, interior)
            worst = max(worst, mean); interior_worst = max(interior_worst, interior); count += 1
        reference.close()
    print(f'PASS: {name} metadata, saved caption appearance and independent rasters')
print(f'PASS: {count} caption rasters; maximum mean {worst:.6f}/255, flat interior {interior_worst}/255')
