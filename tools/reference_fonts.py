"""Test-only font matching for independent raster readers; never used by Pod."""
from pathlib import Path
from fontTools.ttLib import TTFont
from pypdf import PdfWriter
from pypdf.generic import NameObject, NumberObject, FloatObject, DictionaryObject, ArrayObject, DecodedStreamObject
from reportlab.pdfbase import _fontdata

# Match Pod's host outlines while retaining the source PDF's standard metrics.
FACES = {'Helvetica': 'Arial.ttf', 'Courier': 'Courier New.ttf', 'Times-Roman': 'Times New Roman.ttf'}
FONT_ROOT = Path('/System/Library/Fonts/Supplemental')

def embed_reference_fonts(source, output):
    writer = PdfWriter(clone_from=source)
    visited = set()
    def resources(value):
        if value is None: return
        value = value.get_object()
        if id(value) in visited: return
        visited.add(id(value))
        for key, ref in list(value.get('/Font', {}).items()):
            original = ref.get_object()
            face = str(original.get('/BaseFont', '')).lstrip('/')
            if face not in FACES or original.get('/Subtype') != '/Type1' or '/FontDescriptor' in original: continue
            encoding = str(original.get('/Encoding', '/StandardEncoding')).lstrip('/')
            assert encoding in ('WinAnsiEncoding', 'StandardEncoding', 'MacRomanEncoding'), encoding
            path = FONT_ROOT / FACES[face]
            font = TTFont(path)
            units = font['head'].unitsPerEm
            scale = lambda x: FloatObject(x * 1000 / units)
            data = DecodedStreamObject(); data.set_data(path.read_bytes())
            data[NameObject('/Length1')] = NumberObject(len(data.get_data()))
            head = font['head']; hhea = font['hhea']
            descriptor = DictionaryObject({
                NameObject('/Type'): NameObject('/FontDescriptor'), NameObject('/FontName'): NameObject('/PodReference'),
                NameObject('/Flags'): NumberObject(32), NameObject('/FontBBox'): ArrayObject([scale(x) for x in (head.xMin, head.yMin, head.xMax, head.yMax)]),
                NameObject('/ItalicAngle'): NumberObject(0), NameObject('/Ascent'): scale(hhea.ascent), NameObject('/Descent'): scale(hhea.descent),
                NameObject('/CapHeight'): scale(font['OS/2'].sCapHeight), NameObject('/StemV'): NumberObject(80),
                NameObject('/FontFile2'): writer._add_object(data),
            })
            widths = _fontdata.widthsByFontGlyph[face]
            replacement = DictionaryObject({
                NameObject('/Type'): NameObject('/Font'), NameObject('/Subtype'): NameObject('/TrueType'), NameObject('/BaseFont'): NameObject('/PodReference'),
                NameObject('/FirstChar'): NumberObject(0), NameObject('/LastChar'): NumberObject(255), NameObject('/Encoding'): NameObject('/'+encoding),
                NameObject('/Widths'): ArrayObject([NumberObject(widths.get(glyph, 0)) for glyph in _fontdata.encodings[encoding]]),
                NameObject('/FontDescriptor'): writer._add_object(descriptor),
            })
            if '/Widths' in original:
                for field in ('/Widths', '/FirstChar', '/LastChar'): replacement[NameObject(field)] = original[field]
            value['/Font'][key] = writer._add_object(replacement)
            font.close()
        for ref in value.get('/XObject', {}).values():
            resources(ref.get_object().get('/Resources'))
    for page in writer.pages:
        resources(page.get('/Resources'))
        for ref in page.get('/Annots', []):
            annotation = ref.get_object()
            normal = annotation.get('/AP', {}).get('/N')
            if normal is None: continue
            normal = normal.get_object()
            if '/Subtype' in normal: resources(normal.get('/Resources'))
            else:
                for form in normal.values(): resources(form.get_object().get('/Resources'))
    writer.write(output)
