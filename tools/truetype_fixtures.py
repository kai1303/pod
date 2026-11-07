#!/usr/bin/env python3
"""Independent embedded TrueType fixtures. FontTools/ReportLab are test-only."""
from pathlib import Path
from io import BytesIO
import sys, zlib, random
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
from link_fixtures import serialize

def program(platform=3, encoding=1, form=4, compound=None):
    order=['.notdef','space','A','B','e','acute','eacute','fi']
    fb=FontBuilder(1000,isTTF=True)
    fb.setupGlyphOrder(order)
    chars={32:'space',65:'A',66:'B',101:'e',233:'eacute',64257:'fi'}
    fb.setupCharacterMap(chars)
    glyphs={}
    for name,points in {
        '.notdef':[(50,0),(50,650),(450,650),(450,0)], 'space':[],
        'A':[(40,0),(300,700),(560,0)], 'B':[(40,0),(40,700),(600,700),(600,0)],
        'e':[(30,0),(30,450),(450,450),(450,0)], 'acute':[(0,0),(100,150),(170,150),(60,0)],
        'fi':[(40,0),(40,700),(350,700),(350,0)],
    }.items():
        pen=TTGlyphPen(None)
        if points:
            pen.moveTo(points[0])
            for p in points[1:]: pen.lineTo(p)
            pen.closePath()
        glyphs[name]=pen.glyph()
    pen=TTGlyphPen(glyphs);pen.addComponent('e',(1,0,0,1,0,0));pen.addComponent('acute',(1,0,0,1,180,500));glyphs['eacute']=pen.glyph()
    if compound == 'attached':
        part=glyphs['eacute'].components[1]
        del part.x; del part.y
        part.firstPt=2; part.secondPt=0
    elif compound == 'scaled':
        part=glyphs['eacute'].components[1]
        part.transform=[[0.5,0],[0,0.5]]
        part.flags=0x0800
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n:(w,getattr(glyphs[n],'xMin',0)) for n,w in zip(order,[500,250,600,700,500,200,500,450])})
    fb.setupHorizontalHeader(ascent=800,descent=-200)
    fb.setupNameTable({'familyName':'PodFixture','styleName':'Regular','uniqueFontIdentifier':'PodFixture-Regular','fullName':'Pod Fixture Regular','psName':'PodFixture-Regular'})
    fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    fb.setupPost();fb.setupMaxp()
    sub=CmapSubtable.newSubtable(form);sub.platformID=platform;sub.platEncID=encoding;sub.language=0
    if platform==1: sub.cmap={32:'space',65:'A',66:'B',101:'e',142:'eacute',222:'fi'}
    elif encoding==0: sub.cmap={0xf000+c:n for c,n in {32:'space',65:'A',66:'B',101:'e',233:'eacute'}.items()}
    else: sub.cmap=chars
    fb.font['cmap'].tables=[sub]
    out=BytesIO();fb.font.save(out)
    return out.getvalue()

def stream(data,compressed=True):
    encoded=zlib.compress(data) if compressed else data
    return b'<< /Length '+str(len(encoded)).encode()+b' /Length1 '+str(len(data)).encode()+(b' /Filter /FlateDecode' if compressed else b'')+b' >>\nstream\n'+encoded+b'\nendstream'

def fixture(font,encoding=b'/WinAnsiEncoding',symbolic=False,code=233):
    widths=[0]*256
    for c,w in [(32,250),(65,600),(66,700),(101,500),(code,500)]:widths[c]=w
    content=f'BT /F1 24 Tf 1 0 0 1 72 700 Tm <4142{code:02x}> Tj ( AB) Tj ET'.encode()
    unicode_map=f'begincmap 1 begincodespacerange <00> <ff> endcodespacerange 4 beginbfchar <20> <0020> <41> <0041> <42> <0042> <{code:02x}> <00e9> endbfchar endcmap'.encode()
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAA+PodFixture-Regular /FirstChar 0 /LastChar 255 /Widths ['+b' '.join(str(w).encode() for w in widths)+b'] /FontDescriptor 6 0 R /ToUnicode 8 0 R'+(b' /Encoding '+encoding if encoding else b'')+b' >>',
        stream(content),
        b'<< /Type /FontDescriptor /FontName /AAAAAA+PodFixture-Regular /Flags '+(b'4' if symbolic else b'32')+b' /FontBBox [0 -200 700 800] /Ascent 800 /Descent -200 /CapHeight 700 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>',
        stream(font),stream(unicode_map),
    ])

def main(out):
    out.mkdir(parents=True,exist_ok=True)
    cases=[('unicode',3,1,4,b'/WinAnsiEncoding',False,233),
           ('mac-symbolic',1,0,6,None,True,142),
           ('mac-nonsymbolic',1,0,6,b'/WinAnsiEncoding',False,233),
           ('windows-symbolic',3,0,4,None,True,233),
           ('unicode-full',3,10,12,b'/WinAnsiEncoding',False,233),
           ('mac-format-zero',1,0,0,None,True,142)]
    for name,p,e,f,enc,sym,code in cases:
        font=program(p,e,f)
        (out/(name+'.ttf')).write_bytes(font)
        (out/(name+'.pdf')).write_bytes(fixture(font,enc,sym,code))
    for kind in ['attached','scaled']:
        (out/(kind+'.pdf')).write_bytes(fixture(program(compound=kind)))
    font=program()
    (out/'without-unicode.pdf').write_bytes(fixture(font).replace(b'/ToUnicode 8 0 R',b' '*len(b'/ToUnicode 8 0 R')))
    malformed=bytearray(font)
    parsed=TTFont(BytesIO(font));loc=parsed.reader.tables['loca'].offset
    malformed[loc+2:loc+4]=b'\xff\xff'
    (out/'invalid-loca.pdf').write_bytes(fixture(bytes(malformed)))
    (out/'invalid-truncated.pdf').write_bytes(fixture(font[:20]))
    for name,tag,offset,value in [
        ('head-version','head',0,b'\0\0\0\0'),
        ('head-magic','head',12,b'\0\0\0\0'),
        ('cmap-version','cmap',0,b'\0\1'),
        ('maxp-version','maxp',0,b'\0\0\x50\0'),
        ('hhea-version','hhea',0,b'\0\0\0\0'),
        ('metrics-count','hhea',34,b'\xff\xff'),
    ]:
        damaged=bytearray(font)
        at=parsed.reader.tables[tag].offset+offset
        damaged[at:at+len(value)]=value
        (out/('invalid-'+name+'.pdf')).write_bytes(fixture(bytes(damaged)))
    rng=random.Random(5014)
    for i in range(64):
        damaged=bytearray(font)
        for _ in range(rng.randint(1,4)):
            damaged[rng.randrange(len(damaged))]=rng.randrange(256)
        (out/f'mutation-{i}.pdf').write_bytes(fixture(bytes(damaged)))
    from reportlab.pdfgen import canvas
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont as ReportFont
    source=Path(__file__).resolve().parents[1]/'macos/Resources/Lumin/Inter-Medium.ttf'
    pdfmetrics.registerFont(ReportFont('PodInter',str(source)))
    c=canvas.Canvas(str(out/'reportlab.pdf'),pagesize=(612,792),pageCompression=1)
    text=c.beginText(72,700);text.setFont('PodInter',20);text.textOut('Students café — résumé');text.textOut(' tail');c.drawText(text);c.save()
    print(out.resolve())

if __name__=='__main__':main(Path(sys.argv[1]))
