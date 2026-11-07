#!/usr/bin/env python3
"""Independent libtiff CCITT producers and exact native/PDF raster checks."""
import io
import json
from pathlib import Path
import sys
import zlib
from PIL import Image, ImageDraw
from link_fixtures import serialize

root=Path(sys.argv[1])
def stream(data,entries=b''):
    return b'<< /Length '+str(len(data)).encode()+b' '+entries+b' >>\nstream\n'+data+b'\nendstream'
def pdf(data,w,h,params,stencil=False,chain=False):
    parms=b'<< '+params+b' >>'
    filter=b'[/FlateDecode /CCITTFaxDecode]' if chain else b'/CCITTFaxDecode'
    if chain:data=zlib.compress(data);parms=b'[null '+parms+b']'
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {w} {h}] /Resources << /XObject << /Im 5 0 R >> >> /Contents 4 0 R >>'.encode(),
        stream(f'0 0.4 0.8 rg q {w} 0 0 {h} 0 0 cm /Im Do Q'.encode()),
        stream(data,f'/Subtype /Image /Width {w} /Height {h} /BitsPerComponent 1 '.encode()+(b'/ImageMask true ' if stencil else b'/ColorSpace /DeviceGray ')+b'/Filter '+filter+b' /DecodeParms '+parms)])
def pack(bits):
    bits+='0'*(-len(bits)%8)
    return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))
def pattern(w,h,kind):
    image=Image.new('1',(w,h),255)
    draw=ImageDraw.Draw(image)
    if kind=='ui':
        draw.rectangle((18,18,w-19,h-19),outline=0,width=2)
        draw.text((35,35),'POD / SCANNED CLASS NOTES',fill=0)
        for y in range(80,h-40,32):
            draw.text((35,y),f'Lesson {y//32}: read, highlight and discuss.',fill=0)
            draw.line((35,y+20,w-40,y+20),fill=0)
    elif kind=='checker':
        for y in range(h):
            for x in range(w):image.putpixel((x,y),255*((x+y)%2))
    else:
        for y in range(h):
            if y%7==0:continue
            if y%7==1:draw.line((0,y,w-1,y),fill=0);continue
            start=(y*3)%(max(1,w//3));end=min(w-1,start+max(1,w//4)+y%4)
            draw.line((start,y,end,y),fill=0)
            if y%3==0:draw.line((max(0,w-8-y%5),y,w-1,y),fill=0)
    return image

if '--fixtures' in sys.argv:
    root.mkdir(parents=True,exist_ok=True);(root/'invalid').mkdir(exist_ok=True)
    cases={};encoded={}
    specs=[('g4','group4',137,41,0,0,'pattern'),('g3','group3',137,41,0,0,'pattern'),('mixed','group3',137,41,0,1,'pattern'),
           ('mh-aligned','tiff_ccitt',137,41,0,0,'pattern'),('g3-fill','group3',137,41,0,4,'pattern'),('mixed-fill','group3',137,41,0,5,'pattern'),
           ('black-is-one','group4',137,41,1,0,'pattern'),('narrow','group4',1,31,0,0,'pattern'),('long-g4','group4',4093,7,0,0,'pattern'),
           ('long-g3','group3',4093,7,0,0,'pattern'),('long-mixed','group3',4093,7,0,1,'pattern'),('checker','group4',128,64,0,0,'checker'),
           ('ui','group4',480,640,0,0,'ui')]
    for name,compression,w,h,photo,options,kind in specs:
        image=pattern(w,h,kind);out=io.BytesIO();tags={262:photo,278:h}
        if compression=='group3':tags[292]=options
        image.save(out,format='TIFF',compression=compression,tiffinfo=tags)
        tiff=out.getvalue();opened=Image.open(io.BytesIO(tiff))
        assert opened.convert('RGB').tobytes()==image.convert('RGB').tobytes()
        offsets=opened.tag_v2[273];counts=opened.tag_v2[279]
        assert len(offsets)==len(counts)==1
        data=tiff[offsets[0]:offsets[0]+counts[0]]
        k=-1 if compression=='group4' else 4 if options&1 else 0
        params=f'/K {k} /Columns {w} /Rows {h} /BlackIs1 {str(bool(photo)).lower()}'.encode()
        if compression!='group4':params+=b' /EndOfBlock false'
        if compression=='group3':
            assert opened.tag_v2.get(292,0)==options
            params+=b' /EndOfLine true'
        if compression=='tiff_ccitt':params+=b' /EncodedByteAlign true'
        (root/(name+'.tif')).write_bytes(tiff)
        (root/(name+'.pdf')).write_bytes(pdf(data,w,h,params))
        image.convert('RGB').save(root/(name+'-expected.png'))
        cases[name]={'width':w,'height':h};encoded[name]=(data,w,h,params)
    data,w,h,params=encoded['g4']
    for name,extra,stencil,chain in [('rows-overridden',params.replace(b'/Rows 41',b'/Rows 1'),False,False),('flate-chain',params,False,True),('stencil',params,True,False)]:
        (root/(name+'.pdf')).write_bytes(pdf(data,w,h,extra,stencil,chain))
        reference=Image.open(root/'g4-expected.png').convert('RGB')
        if stencil:reference.putdata([(0,102,204) if pixel==(0,0,0) else pixel for pixel in reference.getdata()])
        reference.save(root/(name+'-expected.png'));cases[name]={'width':w,'height':h}
    for name,source,modify in [('auto-eol','g3',lambda p:p.replace(b' /EndOfLine true',b'')),
                               ('auto-mixed-eol','mixed',lambda p:p.replace(b' /EndOfLine true',b'')),
                               ('fill-aligned','g3-fill',lambda p:p+b' /EncodedByteAlign true'),
                               ('default-rows','g4',lambda p:p.replace(b' /Rows 41',b''))]:
        data,w,h,params=encoded[source]
        (root/(name+'.pdf')).write_bytes(pdf(data,w,h,modify(params)))
        (root/(name+'-expected.png')).write_bytes((root/(source+'-expected.png')).read_bytes())
        cases[name]={'width':w,'height':h}
    eol='000000000001';white='10011';black='00110101'+'000101';badrow='000000000010'
    handmade=[('g4-aligned','10000000'*2+eol*2,b'/K -1 /EncodedByteAlign true',[255,255]),
              ('rtc',eol+white+eol+black+eol*6,b'/K 0 /EndOfLine true', [255,0]),
              ('mixed-rtc',eol+'1'+white+eol+'1'+black+(eol+'1')*6,b'/K 4 /EndOfLine true',[255,0]),
              ('no-eol',white+black,b'/K 0 /Rows 2 /EndOfBlock false',[255,0]),
              ('unknown-rows',white+black,b'/K 0 /EndOfBlock false',[255,0]),
              ('damaged',eol+black+eol+badrow+eol+badrow+eol+white+eol*6,b'/K 0 /EndOfLine true /DamagedRowsBeforeError 2',[0,0,255,255])]
    for name,bits,params,values in handmade:
        params+=b' /Columns 8';data=pack(bits);h=len(values)
        (root/(name+'.pdf')).write_bytes(pdf(data,8,h,params))
        Image.frombytes('L',(8,h),bytes(v for v in values for _ in range(8))).convert('RGB').save(root/(name+'-expected.png'))
        cases[name]={'width':8,'height':h};encoded[name]=(data,8,h,params)
    data,w,h,params=encoded['g4']
    bad={'missing-end':pdf(data[:-2],w,h,params),'columns':pdf(data,w,h,params.replace(b'/Columns 137',b'/Columns 0')),
         'wrong-width':pdf(data,w-1,h,params),'wrong-height':pdf(data,w,h+1,params),'wrong-depth':pdf(data,w,h,params).replace(b'/BitsPerComponent 1',b'/BitsPerComponent 8'),
         'flag-type':pdf(data,w,h,params+b' /EndOfLine 1'),'rows-negative':pdf(data,w,h,params.replace(b'/Rows 41',b'/Rows -1')),
         'extension':pdf(pack('0000001111'),8,1,b'/K -1 /Columns 8 /Rows 1 /EndOfBlock false'),
         'run-overflow':pdf(pack(white),7,1,b'/K 0 /Columns 7 /Rows 1 /EndOfBlock false'),
         'missing-eol':pdf(pack(white),8,1,b'/K 0 /Columns 8 /Rows 1 /EndOfLine true /EndOfBlock false')}
    data,w,h,params=encoded['damaged'];bad['damage-budget']=pdf(data,w,h,params.replace(b'/DamagedRowsBeforeError 2',b'/DamagedRowsBeforeError 1'))
    for name,data in bad.items():(root/'invalid'/(name+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps(cases));(root/'invalid.json').write_text(json.dumps(list(bad)))
    print('PASS:',len(cases),'CCITT fixtures;',len(bad),'invalid/unsupported fixtures')
    sys.exit(0)

import pymupdf
for name,info in json.loads((root/'cases.json').read_text()).items():
    expected=Image.open(root/(name+'-expected.png')).convert('RGB').tobytes()
    actual=Image.open(root/(name+'-samples.png')).convert('RGB').tobytes()
    assert actual==expected,(name,'native sample mismatch')
    with pymupdf.open(root/(name+'.pdf')) as original,pymupdf.open(root/(name+'-saved.pdf')) as saved:
        assert original.xref_stream_raw(5)==saved.xref_stream_raw(5),(name,'fax stream changed')
        assert original.xref_object(5)==saved.xref_object(5),(name,'image dictionary changed')
        before=original[0].get_pixmap(alpha=False).samples
        after=saved[0].get_pixmap(alpha=False).samples
        assert before==after,(name,'saved raster changed')
        # MuPDF reports a malformed code and does not apply this recovery option.
        # The hand-built fixture above checks the PDF-specified substitutions.
        if name!='damaged':assert actual==before,(name,'MuPDF raster mismatch')
    print('PASS:',name,'exact decoded samples, native/PDF round trip and preservation'+(' (specification recovery; MuPDF differs)' if name=='damaged' else ''))
