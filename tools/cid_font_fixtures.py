#!/usr/bin/env python3
"""Composite-font fixtures; FontTools is a test producer, never an engine dependency."""
from io import BytesIO
from pathlib import Path
import json, random, sys
from fontTools.ttLib import TTFont
from truetype_fixtures import program, stream
from link_fixtures import serialize


def fixture(font, remap=False, content=None, widths=None, encoding=b'/Identity-H', gid_override=None, unicode_override=None, codes_override=None, indirect_identity=False, extra_objects=(), cid_extra=b''):
    codes=codes_override or ([256,257,258,32] if remap else [2,3,6,1])
    a,b,e,space=codes
    if content is None:content=f'BT /F1 24 Tf 1 0 0 1 72 700 Tm <{a:04x}{b:04x}{e:04x}> Tj <{space:04x}{a:04x}{b:04x}> Tj ET'.encode()
    if widths is None:widths=f'[{e} {e} 500 {a} [600 700] {space} [250]]'.encode()
    unicode_map=b'begincmap 1 begincodespacerange <0000> <ffff> endcodespacerange 4 beginbfchar '+b' '.join(f'<{code:04x}> <{cp:04x}>'.encode() for code,cp in zip(codes,[65,66,233,32]))+b' endbfchar endcmap'
    if unicode_override is not None:unicode_map=unicode_override
    gidmap=bytearray((max(codes)+1)*2)
    for code,gid in zip(codes,[2,3,6,1]):gidmap[code*2:code*2+2]=gid.to_bytes(2,'big')
    if gid_override is not None:gidmap=gid_override
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type0 /BaseFont /AAAAAA+PodFixture-Regular /Encoding '+encoding+b' /DescendantFonts [9 0 R] /ToUnicode 8 0 R >>',
        stream(content),
        b'<< /Type /FontDescriptor /FontName /AAAAAA+PodFixture-Regular /Flags 4 /FontBBox [0 -200 700 800] /Ascent 800 /Descent -200 /CapHeight 700 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>',
        stream(font),stream(unicode_map),
        b'<< /Type /Font /Subtype /CIDFontType2 /BaseFont /AAAAAA+PodFixture-Regular /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 6 0 R /DW 1000 /W '+widths+b' /CIDToGIDMap '+(b'10 0 R' if remap or indirect_identity else b'/Identity')+b' '+cid_extra+b' >>',
        b'/Identity' if indirect_identity else stream(bytes(gidmap)),
    ]+list(extra_objects))


def main(root):
    root.mkdir(parents=True,exist_ok=True)
    font=program()
    cases={'cid-identity':fixture(font),'cid-remap':fixture(font,True)}
    parsed=TTFont(BytesIO(font));del parsed['cmap'];out=BytesIO();parsed.save(out)
    cases['cid-no-cmap']=fixture(out.getvalue())
    cases['cid-indirect-identity']=fixture(font,indirect_identity=True)
    cases['cid-default-map']=fixture(font).replace(b'/CIDToGIDMap /Identity',b' '*len(b'/CIDToGIDMap /Identity'))
    # Multibyte code 0x0020 is NOT a one-byte space for the Tw operator.
    cases['cid-spacing']=fixture(font,True,content=b'BT /F1 24 Tf 3 Tc 80 Tw 75 Tz 1 0 0 1 72 700 Tm [<0100> -125 <01010102>] TJ <002001000101> Tj ET')
    cases['cid-default-width']=fixture(font,widths=b'[]')
    cases['cid-highest']=fixture(font,True,codes_override=[65533,65534,65535,32])
    cases['cid-unicode']=fixture(font,True,unicode_override=b'begincmap 1 begincodespacerange <0000> <ffff> endcodespacerange 4 beginbfchar <0100> <4e2d> <0101> <d83dde00> <0102> <00660069> <0020> <0020> endbfchar endcmap')
    for name,data in cases.items():(root/(name+'.pdf')).write_bytes(data)
    manifest=[{'name':n,'text':'ABé','replacement':'é','tail':'AB'} for n in cases if n!='cid-unicode']
    manifest.append({'name':'cid-unicode','text':'中😀fi','replacement':'fi','tail':'中😀'})
    from fpdf import FPDF
    pdf=FPDF(unit='pt',format=(612,792))
    pdf.add_font('Inter',fname=str(Path(__file__).resolve().parents[1]/'macos/Resources/Lumin/Inter-Medium.ttf'))
    pdf.add_page();pdf.set_font('Inter',size=20)
    original='Students café — résumé'
    pdf.text(72,92,original);pdf.text(72+pdf.get_string_width(original),92,' tail')
    pdf.output(root/'fpdf2.pdf')
    manifest.append({'name':'fpdf2','text':original,'replacement':'café','tail':'tail'})
    (root/'cases.json').write_text(json.dumps(manifest))
    rng=random.Random(5015)
    for i in range(64):
        mapping=bytearray(518)
        for code in [32,256,257,258]:mapping[2*code:2*code+2]=rng.randrange(10).to_bytes(2,'big')
        (root/f'mutation-{i}.pdf').write_bytes(fixture(font,True,gid_override=mapping))
    malformed={
        'odd-code':fixture(font,content=b'BT /F1 24 Tf <0002ff> Tj ET'),
        'split-code':fixture(font,content=b'BT /F1 24 Tf [<00> <02>] TJ ET'),
        'unicode-code-width':fixture(font,unicode_override=b'begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <02> <0041> endbfchar endcmap'),
        'gid-length':fixture(font,True,gid_override=b'\0'),
        'gid-range':fixture(font,True,gid_override=b'\xff\xff'*259),
        'width-range':fixture(font,widths=b'[65535 [400 500]]'),
        'width-order':fixture(font,widths=b'[4 3 500]'),
        'width-negative':fixture(font,widths=b'[2 [-1]]'),
        'width-overlap':fixture(font,widths=b'[2 [500 600] 3 4 400]'),
    }
    for name,data in malformed.items():(root/('invalid-'+name+'.pdf')).write_bytes(data)
    (root/'unsupported-vertical.pdf').unlink(missing_ok=True)
    (root/'unsupported-predefined.pdf').write_bytes(fixture(font,encoding=b'/UniJIS-UTF16-V'))
    print(root.resolve())

if __name__=='__main__':main(Path(sys.argv[1]))
