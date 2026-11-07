#!/usr/bin/env python3
"""Independent fonts for FreeText; no production font or layout implementation."""
from io import BytesIO
import json
from pathlib import Path
import sys
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, BooleanObject, DecodedStreamObject, DictionaryObject, FloatObject, NameObject, NullObject, NumberObject, TextStringObject
from truetype_fixtures import fixture as simple, program
from cid_font_fixtures import fixture as composite
from encoding_cmap_fixtures import make as mixed

root=Path(sys.argv[1])
font=program()
def box(source, size=18, rotate=0, remap=False):
    writer=PdfWriter(clone_from=PdfReader(BytesIO(source)))
    page=writer.pages[0]
    resource=page['/Resources']['/Font'].raw_get('/F1')
    if remap:
        selected=resource.get_object()
        selected[NameObject('/Encoding')]=DictionaryObject({NameObject('/BaseEncoding'):NameObject('/WinAnsiEncoding'),NameObject('/Differences'):ArrayObject([NumberObject(32),NameObject('/A'),NumberObject(65),NameObject('/space')])})
        selected['/Widths'][32]=NumberObject(600);selected['/Widths'][65]=NumberObject(250)
        mapping=DecodedStreamObject();mapping.set_data(b'begincmap 1 begincodespacerange <00> <ff> endcodespacerange 4 beginbfchar <20> <0041> <41> <0020> <42> <0042> <e9> <00e9> endbfchar endcmap')
        selected[NameObject('/ToUnicode')]=writer._add_object(mapping)
    page[NameObject('/Resources')]=DictionaryObject()
    page[NameObject('/MediaBox')]=ArrayObject([NumberObject(n) for n in [0,0,300,360]])
    background=DecodedStreamObject();background.set_data(b'.8 .9 1 rg 0 0 300 360 re f')
    page[NameObject('/Contents')]=writer._add_object(background)
    writer.root_object[NameObject('/AcroForm')]=writer._add_object(DictionaryObject({
        NameObject('/Fields'):ArrayObject(),
        NameObject('/DR'):writer._add_object(DictionaryObject({NameObject('/Font'):writer._add_object(DictionaryObject({NameObject('/Lesson Font'):resource}))})),
    }))
    mark=DictionaryObject({
        NameObject('/Type'):NameObject('/Annot'),NameObject('/Subtype'):NameObject('/FreeText'),
        NameObject('/Rect'):ArrayObject([NumberObject(n) for n in [60,90,170,230]]),
        NameObject('/DA'):TextStringObject(f'/Lesson#20Font {size} Tf .1 .2 .4 rg'),
        NameObject('/Contents'):TextStringObject('ABé ABé ABé ABé\nA B é'),
        NameObject('/Q'):NumberObject(2),NameObject('/Rotate'):NumberObject(rotate),NameObject('/F'):NumberObject(4),
        NameObject('/C'):ArrayObject([FloatObject(n) for n in [.9,.8,.6]]),
        NameObject('/BS'):DictionaryObject({NameObject('/W'):NumberObject(1)}),
    })
    page[NameObject('/Annots')]=ArrayObject([writer._add_object(mark)])
    return writer

cases={
    'resource-truetype':box(simple(font)),
    'resource-remapped-space':box(simple(font),remap=True),
    'resource-cid':box(composite(font,True,codes_override=[0x0120,0x2020,0x0102,1])),
    'resource-mixed-cmap':box(mixed(font)),
    'resource-auto-cid':box(composite(font),size=0),
    'resource-auto-truetype':box(simple(font),size=0),
    'resource-rotated-cid':box(composite(font),rotate=270),
}
standard=box(simple(font))
standard.root_object['/AcroForm']['/DR']['/Font'][NameObject('/Lesson Font')]=DictionaryObject({NameObject('/Type'):NameObject('/Font'),NameObject('/Subtype'):NameObject('/Type1'),NameObject('/BaseFont'):NameObject('/Courier'),NameObject('/Encoding'):NameObject('/WinAnsiEncoding')})
cases['resource-standard']=standard
direct=box(simple(font))
direct_fonts=direct.root_object['/AcroForm']['/DR']['/Font']
direct_font=direct_fonts['/Lesson Font']
direct_font[NameObject('/ProducerNull')]=NullObject()
direct_font[NameObject('/ProducerFlag')]=BooleanObject(True)
direct_fonts[NameObject('/Lesson Font')]=direct_font
cases['resource-direct-truetype']=direct
for label,source,scale,size in [('cid',composite(font),65,18),('auto-mixed',mixed(font),140,0)]:
    scaled=box(source,size=size)
    mark=scaled.pages[0]['/Annots'][0].get_object()
    mark[NameObject('/DA')]=TextStringObject(str(mark['/DA'])+f' {scale} Tz')
    cases['resource-hscale-'+label]=scaled
for label,writer,state in [
    ('remapped',box(simple(font),remap=True),'1 Tc 7 Tw'),
    ('cid',box(composite(font,True,codes_override=[0x0120,0x2020,0x0102,1])),'1 Tc 7 Tw'),
    ('auto-mixed',box(mixed(font),size=0),'-1 Tc 8 Tw 140 Tz'),
]:
    mark=writer.pages[0]['/Annots'][0].get_object()
    mark[NameObject('/DA')]=TextStringObject(str(mark['/DA'])+' '+state)
    cases['resource-spacing-'+label]=writer
names=json.loads((root/'cases.json').read_text())
for name,writer in cases.items():
    writer.write(root/(name+'.pdf'))
    if name not in names:names.append(name)
(root/'cases.json').write_text(json.dumps(names))
for name in ['vertical','fields','xfa','missing-font','malformed-resources']:
    writer=box(composite(font,encoding=b'/Identity-V') if name=='vertical' else simple(font))
    form=writer.root_object['/AcroForm']
    if name=='fields':form[NameObject('/Fields')]=ArrayObject([DictionaryObject({NameObject('/FT'):NameObject('/Tx')})])
    if name=='xfa':form[NameObject('/XFA')]=TextStringObject('Unsupported')
    if name=='missing-font':form['/DR'][NameObject('/Font')]=DictionaryObject()
    if name=='malformed-resources':form[NameObject('/DR')]=NumberObject(7)
    writer.write(root/'invalid'/('resource-'+name+'.pdf'))
print(f'PASS: {len(cases)} FreeText font-resource fixtures; 5 invalid/unsupported fixtures')
