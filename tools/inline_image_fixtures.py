#!/usr/bin/env python3
"""Inline-image producers, adversarial framing, and malformed dictionaries; test only."""
import base64
import io
import json
from pathlib import Path
import sys
import zlib
from PIL import Image
from link_fixtures import serialize

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
(root/'invalid').mkdir(exist_ok=True)

def stream(data, entries=b''):
    return b'<< /Length '+str(len(data)).encode()+b' '+entries+b' >>\nstream\n'+data+b'\nendstream'

def pdf(content, resources=b'', extra=(), nested=False, compressed=False, appearance=False):
    fonts=b'/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Courier >> >> '
    local=fonts+resources
    page_content=b'/Fm Do' if nested else b'' if appearance else content
    page_resources=b'/XObject << /Fm 5 0 R >>' if nested else local
    objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
             b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << '+page_resources+b' >> /Contents 4 0 R '+(b'/Annots [6 0 R]' if appearance else b'')+b' >>',
             stream(zlib.compress(page_content) if compressed else page_content,b'/Filter /FlateDecode' if compressed else b'')]
    if nested or appearance:
        objects.append(stream(content,b'/Subtype /Form /BBox [0 0 200 200] /Resources << '+local+b' >>'))
    if appearance:
        objects.append(b'<< /Subtype /Text /Rect [0 0 200 200] /F 28 /Contents (Inline note) /AP << /N 5 0 R >> >>')
    objects.extend(extra)
    return serialize(objects)

def inline(entries, data, separator=b'\n', end=b'\nEI'):
    return b'BI '+entries+b' ID'+separator+data+end

def place(image):
    return b'q 120 0 0 100 40 50 cm '+image+b' Q 0 .5 0 rg 175 20 10 10 re f'

def lzw_literal(data):
    # Clear between small blocks keeps this independent producer at 9-bit codes.
    codes=[]
    for pos in range(0,len(data),200):codes += [256]+list(data[pos:pos+200])
    codes += [257]
    bits=''.join(f'{code:09b}' for code in codes)
    bits+='0'*(-len(bits)%8)
    return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))

rgb=bytes([255,0,0,0,255,0,0,0,255,255,255,0,0,255,255,255,0,255])
base=b'/W 3 /H 2 /BPC 8 /CS /RGB'
cases={}
def add(name,entries=base,data=rgb,**kwargs):
    cases['inline-'+name]=pdf(place(inline(entries,data)),**kwargs)
add('rgb')
add('full-names',b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceRGB')
add('flate',base+b' /F /Fl',zlib.compress(rgb))
add('hex',base+b' /F /AHx',rgb.hex().encode()+b'>')
add('a85',base+b' /F /A85',base64.a85encode(rgb)+b'~>')
add('lzw',base+b' /F /LZW',lzw_literal(rgb))
add('lzw-early0',base+b' /F /LZW /DP << /EarlyChange 0 >>',lzw_literal(rgb))
add('runlength',base+b' /F /RL',bytes([len(rgb)-1])+rgb+b'\x80')
add('filter-chain',base+b' /F [/A85 /Fl] /DP [null null]',base64.a85encode(zlib.compress(rgb))+b'~>')
add('predictor',base+b' /F /Fl /DP << /Predictor 15 /Colors 3 /Columns 3 /BitsPerComponent 8 >>',zlib.compress(b'\0'+rgb[:9]+b'\0'+rgb[9:]))
add('decode',base+b' /D [1 0 0 1 1 0]')
add('interpolate',base+b' /I true')
add('unknown-keys',base+b' /Length 1 /Subtype /Form /Custom << /Comment (EI) >>')
for depth,data in [(1,b'\x40\xa0'),(2,b'\x18\xe4'),(4,b'\x08\xf0\xf8\x00'),(8,b'\x00\x80\xff\xff\x80\x00'),(16,b'\x00\x00\x80\x00\xff\xff\xff\xff\x80\x00\x00\x00')]:
    add(f'gray-{depth}',f'/W 3 /H 2 /BPC {depth} /CS /G'.encode(),data)
add('indexed',b'/W 3 /H 2 /BPC 8 /CS [/I /RGB 5 <ff000000ff000000ffffff0000ffffff00ff>]',bytes(range(6)))
add('resource',base.replace(b'/RGB',b'/Palette'),bytes([0,1,2,3,4,5]),resources=b'/ColorSpace << /Palette [/Indexed /DeviceRGB 5 <ff000000ff000000ffffff0000ffffff00ff>] >>')
add('calibrated',base.replace(b'/RGB',b'/Cal'),resources=b'/ColorSpace << /Cal [/CalRGB << /WhitePoint [.9505 1 1.089] /Gamma [2.2 2.2 2.2] /Matrix [.4124 .2126 .0193 .3576 .7152 .1192 .1805 .0722 .9505] >>] >>')
add('default-gray',b'/W 3 /H 2 /BPC 8 /CS /G',b'\x00\x80\xff\xff\x80\x00',resources=b'/ColorSpace << /DefaultGray [/CalGray << /WhitePoint [.9505 1 1.089] /Gamma 2.2 >>] >>')
for reverse in [False,True]:
    name='inline-stencil'+('-reverse' if reverse else '')
    entries=b'/W 3 /H 2 /IM true'+(b' /D [1 0]' if reverse else b'')
    cases[name]=pdf(b'0 .4 .8 rg 0 0 200 200 re f 1 .2 .4 rg '+place(inline(entries,b'\x40\xa0')))
for label,separator in [('space',b' '),('crlf',b'\r\n'),('tab',b'\t')]:
    cases['inline-separator-'+label]=pdf(place(inline(b'/W 4 /H 1 /BPC 8 /CS /G',b' EI ',separator)))
for name,filter,data in [('raw',b'',b' EI '),('flate',b' /F /Fl',zlib.compress(b' EI ',level=0)),('runlength',b' /F /RL',b'\x03 EI \x80')]:
    add('false-end-'+name,b'/W 4 /H 1 /BPC 8 /CS /G'+filter,data)
add('nested',nested=True)
add('compressed-content',compressed=True)
add('appearance',appearance=True)
cases['inline-multiple']=pdf(place(inline(base,rgb))+b' q 20 0 0 20 10 10 cm '+inline(b'/W 1 /H 1 /BPC 8 /CS /G',b'\x80')+b' Q')
cases['inline-clip-blend']=pdf(b'.2 .4 .8 rg 0 0 200 200 re f /A gs 80 100 65 70 re W n '+place(inline(base,rgb)),b'/ExtGState << /A << /ca .5 /BM /Multiply >> >>')
cases['inline-text']=pdf(b'BT /F1 10 Tf 10 175 Td (Before) Tj ET '+place(inline(base,rgb))+b' BT /F1 10 Tf 10 10 Td (After) Tj ET')
for progressive in [False,True]:
    output=io.BytesIO();Image.frombytes('RGB',(3,2),rgb).resize((48,32),Image.Resampling.NEAREST).save(output,format='JPEG',quality=95,subsampling=0,progressive=progressive)
    jpeg=output.getvalue()
    # Marker-like bytes inside a length-delimited comment must not end the image.
    comment=b' EI \xff\xd9 fake end'
    jpeg=jpeg[:2]+b'\xff\xfe'+(len(comment)+2).to_bytes(2,'big')+comment+jpeg[2:]
    add('jpeg'+('-progressive' if progressive else ''),b'/W 48 /H 32 /BPC 8 /CS /RGB /F /DCT',jpeg)
# Independent libtiff produces MH and T.4/T.6 bitstreams.
for name,compression,options in [('g4','group4',0),('g3','group3',0),('mixed','group3',1),('mh','tiff_ccitt',0)]:
    image=Image.new('1',(24,16),255)
    for y in range(16):
        for x in range(24):image.putpixel((x,y),255*((x//8+y//4)%2))
    output=io.BytesIO();tags={262:0,278:16}
    if compression=='group3':tags[292]=options
    image.save(output,format='TIFF',compression=compression,tiffinfo=tags)
    tiff=output.getvalue();opened=Image.open(io.BytesIO(tiff))
    offset=opened.tag_v2[273][0];length=opened.tag_v2[279][0];data=tiff[offset:offset+length]
    params=f'/K {-1 if name=="g4" else 4 if name=="mixed" else 0} /Columns 24 /Rows 16'.encode()
    if name!='g4':params+=b' /EndOfBlock false'
    if compression=='group3':params+=b' /EndOfLine true'
    if name=='mh':params+=b' /EncodedByteAlign true'
    add('fax-'+name,b'/W 24 /H 16 /BPC 1 /CS /G /F /CCF /DP << '+params+b' >>',data)
    if name=='g3':add('fax-no-rows',b'/W 24 /H 16 /BPC 1 /CS /G /F /CCF /DP << '+params.replace(b' /Rows 16',b'')+b' >>',data)
# Real ReportLab inline image production exercises A85+Flate and compressed pages.
from reportlab.pdfgen import canvas
out=io.BytesIO();c=canvas.Canvas(out,pagesize=(200,200),pageCompression=1)
c.drawInlineImage(Image.frombytes('RGB',(3,2),rgb),40,50,width=120,height=100)
c.showPage();c.save();cases['inline-reportlab']=out.getvalue()

bad={}
def invalid(name,content):bad['inline-'+name]=pdf(content)
valid=inline(base,rgb)
invalid('no-ei',valid[:-3]);invalid('no-id',b'BI '+base+b' '+rgb+b' EI')
invalid('short',inline(base,rgb[:-1]));invalid('long',inline(base,rgb+b'x'))
invalid('nested',b'BI '+base+b' BI '+valid)
invalid('inside-text',b'BT '+valid+b' ET')
invalid('operands',b'1 '+valid)
invalid('ei-prefix',valid+b'bad')
invalid('missing-separator',inline(base,rgb,separator=b''))
invalid('duplicate',inline(base+b' /Width 3',rgb))
invalid('reference',inline(base.replace(b'/W 3',b'/W 3 0 R'),rgb))
invalid('nested-reference',inline(base+b' /Custom [4 0 R]',rgb))
invalid('huge',inline(base.replace(b'/W 3',b'/W 65536').replace(b'/H 2',b'/H 65536'),rgb))
invalid('hex-end',inline(base+b' /F /AHx',rgb.hex().encode()))
invalid('a85-end',inline(base+b' /F /A85',base64.a85encode(rgb)))
invalid('runlength-end',inline(base+b' /F /RL',bytes([17])+rgb))
invalid('flate-truncated',inline(base+b' /F /Fl',zlib.compress(rgb)[:-2]))
invalid('flate-checksum',inline(base+b' /F /Fl',zlib.compress(rgb)[:-1]+b'\0'))
invalid('lzw-end',inline(base+b' /F /LZW',lzw_literal(rgb)[:-2]))
invalid('filter',inline(base+b' /F /JBIG2Decode',rgb))
invalid('params',inline(base+b' /F [/Fl] /DP << >>',zlib.compress(rgb)))
invalid('cal-direct',inline(base.replace(b'/RGB',b'[/CalRGB << /WhitePoint [1 1 1] >>]'),rgb))
invalid('indexed-base',inline(base.replace(b'/RGB',b'[/I /Other 0 <000000>]'),rgb))
# Deterministic damaged streams exercise the full native boundary without assuming
# every mutation is invalid (sample changes can remain valid images).
import random
randomizer=random.Random(6408)
(root/'mutations').mkdir(exist_ok=True)
seed=place(inline(base+b' /F /Fl',zlib.compress(rgb)))
for index in range(64):
    changed=bytearray(seed)
    if index%3==0:changed=changed[:randomizer.randrange(len(changed))]
    else:
        offset=randomizer.randrange(len(changed));changed[offset]^=1<<randomizer.randrange(8)
    (root/'mutations'/f'{index:02d}.pdf').write_bytes(pdf(bytes(changed)))
for name,data in cases.items():(root/(name+'.pdf')).write_bytes(data)
for name,data in bad.items():(root/'invalid'/(name+'.pdf')).write_bytes(data)
(root/'cases.json').write_text(json.dumps(list(cases)))
print(f'PASS: {len(cases)} inline image fixtures and {len(bad)} malformed fixtures produced')
