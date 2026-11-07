#!/usr/bin/env python3
"""Pillow/libjpeg-produced JPEGs and independent sample/PDF preservation checks."""
import base64
import io
import json
from pathlib import Path
import sys
import subprocess
import random
import zlib
from PIL import Image
from link_fixtures import serialize

root=Path(sys.argv[1])
def stream(data,entries=b''):
    return b'<< /Length '+str(len(data)).encode()+b' '+entries+b' >>\nstream\n'+data+b'\nendstream'
def pdf(data,w,h,mode='RGB',filter=b'/DCTDecode',params=b''):
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {w} {h}] /Resources << /XObject << /Im 5 0 R >> >> /Contents 4 0 R >>'.encode(),
        stream(f'q {w} 0 0 {h} 0 0 cm /Im Do Q'.encode()),
        stream(data,f'/Subtype /Image /Width {w} /Height {h} /BitsPerComponent 8 /ColorSpace /Device{mode if mode=="RGB" else "Gray"} /Filter '.encode()+filter+params)])

def pattern(mode,w,h):
    data=bytearray()
    for y in range(h):
        for x in range(w):
            if mode=='RGB':data.extend(((x*7+y*3)%256,(y*9+x*2)%256,220 if (x//5+y//7)%2 else 30))
            else:data.append((x*11+y*7)%256)
    return Image.frombytes(mode,(w,h),bytes(data))

if '--fixtures' in sys.argv:
    root.mkdir(parents=True,exist_ok=True);(root/'invalid').mkdir(exist_ok=True)
    cases={}
    specs=[('gray','L',17,19,{}),('rgb-444','RGB',33,25,{'subsampling':0}),('rgb-422','RGB',33,25,{'subsampling':1}),('rgb-420','RGB',33,25,{'subsampling':2}),('optimized','RGB',43,35,{'subsampling':2,'optimize':True}),('restart','RGB',43,35,{'subsampling':2,'restart_marker_blocks':2}),('adobe-rgb','RGB',33,25,{'keep_rgb':True}),('tiny','RGB',1,1,{}),('odd-gray','L',1,31,{}),('restart-cycle','RGB',83,67,{'subsampling':2,'restart_marker_blocks':1}),('ui','RGB',480,640,{'subsampling':2})]
    specs += [('progressive-gray','L',17,19,{'progressive':True}),
              ('progressive-444','RGB',33,25,{'progressive':True,'subsampling':0}),
              ('progressive-422','RGB',33,25,{'progressive':True,'subsampling':1}),
              ('progressive-420','RGB',83,67,{'progressive':True,'subsampling':2}),
              ('progressive-restart','RGB',83,67,{'progressive':True,'restart_marker_blocks':2}),
              ('progressive-ui','RGB',480,640,{'progressive':True}),
              ('progressive-flat','RGB',129,97,{'progressive':True}),
              ('progressive-noise','RGB',83,67,{'progressive':True}),
              ('progressive-tiny','RGB',1,1,{'progressive':True}),
              ('progressive-narrow','L',1,31,{'progressive':True})]
    for name,mode,w,h,options in specs:
        source=pattern(mode,w,h)
        if name=='progressive-flat':source=Image.new('RGB',(w,h),(20,40,60))
        if name=='progressive-noise':
            rng=random.Random(17);source=Image.frombytes('RGB',(w,h),bytes(rng.randrange(256) for _ in range(w*h*3)))
        output=io.BytesIO();source.save(output,format='JPEG',quality=87,**options);data=output.getvalue()
        if name=='restart':assert b'\xff\xdd' in data and b'\xff\xd0' in data
        if name=='adobe-rgb':assert b'Adobe' in data
        (root/(name+'.jpg')).write_bytes(data)
        Image.open(io.BytesIO(data)).convert('RGB').save(root/(name+'-expected.png'))
        (root/(name+'.pdf')).write_bytes(pdf(data,w,h,mode))
        cases[name]={'width':w,'height':h}
    # Independent libjpeg encoder scripts exercise separate and mixed scans,
    # including restart counters that reset per scan and wrap after RST7.
    pattern('RGB',83,67).save(root/'source.ppm')
    for name,script in [('separate','0; 1; 2;'),('mixed','0; 1 2;')]:
        (root/'scans.txt').write_text(script)
        data=subprocess.check_output(['cjpeg','-quality','87','-sample','2x2,1x1,1x1','-restart','2B','-scans',str(root/'scans.txt'),str(root/'source.ppm')])
        assert data.count(b'\xff\xda') == (3 if name=='separate' else 2)
        (root/(name+'.jpg')).write_bytes(data)
        Image.open(io.BytesIO(data)).convert('RGB').save(root/(name+'-expected.png'))
        (root/(name+'.pdf')).write_bytes(pdf(data,83,67))
        cases[name]={'width':83,'height':67}
    progressive_scripts={
        'progressive-spectral':'0 1 2: 0 0 0 0; '+''.join(f'{c}: {lo} {hi} 0 0; ' for lo,hi in [(33,63),(1,32)] for c in range(3)),
        'progressive-refine':'0 1 2: 0 0 0 3; '+''.join(f'{c}: 1 63 0 3; ' for c in range(3))+''.join('0 1 2: 0 0 '+f'{high} {high-1}; '+''.join(f'{c}: 1 63 {high} {high-1}; ' for c in range(3)) for high in [3,2,1]),
        'progressive-dc-only':'0 1 2: 0 0 0 0;'
    }
    for name,script in progressive_scripts.items():
        (root/'scans.txt').write_text(script)
        data=subprocess.check_output(['cjpeg','-quality','87','-sample','2x2,1x1,1x1','-restart','2B','-scans',str(root/'scans.txt'),str(root/'source.ppm')])
        assert b'\xff\xc2' in data
        (root/(name+'.jpg')).write_bytes(data)
        # libjpeg estimates missing AC values for a DC-only progressive preview.
        # Lossless coefficient transcoding disables that optional block smoothing.
        reference=subprocess.check_output(['jpegtran'],input=data) if name=='progressive-dc-only' else data
        Image.open(io.BytesIO(reference)).convert('RGB').save(root/(name+'-expected.png'))
        (root/(name+'.pdf')).write_bytes(pdf(data,83,67))
        cases[name]={'width':83,'height':67}
    data=(root/'progressive-444.jpg').read_bytes()
    # A later table definition must not change an already-started component.
    changed_quant=b'\xff\xdb\x00\x43\x00'+bytes([7]*64)
    data=data[:-2]+changed_quant+data[-2:]
    Image.open(io.BytesIO(data)).convert('RGB').save(root/'progressive-quant-redefined-expected.png')
    (root/'progressive-quant-redefined.pdf').write_bytes(pdf(data,33,25))
    cases['progressive-quant-redefined']={'width':33,'height':25}
    data=subprocess.check_output(['cjpeg','-quality','1','-sample','1x1,1x1,1x1',str(root/'source.ppm')])
    assert b'\xff\xc1' in data and b'\xff\xdb\x00\x83\x10' in data
    (root/'wide-quant.jpg').write_bytes(data)
    Image.open(io.BytesIO(data)).convert('RGB').save(root/'wide-quant-expected.png')
    (root/'wide-quant.pdf').write_bytes(pdf(data,83,67))
    cases['wide-quant']={'width':83,'height':67}
    data=(root/'rgb-444.jpg').read_bytes()
    raw=Image.open(io.BytesIO(data));raw.draft('YCbCr',raw.size);assert raw.mode=='YCbCr'
    Image.frombytes('RGB',raw.size,raw.tobytes()).save(root/'raw-ycbcr-expected.png')
    (root/'raw-ycbcr.pdf').write_bytes(pdf(data,33,25,params=b' /DecodeParms << /ColorTransform 0 >>'))
    cases['raw-ycbcr']={'width':33,'height':25}
    for name,encoded,filter,params in [
        ('ascii85-chain',base64.a85encode(data)+b'~>',b'[/ASCII85Decode /DCTDecode]',b''),
        ('flate-chain',zlib.compress(data),b'[/FlateDecode /DCTDecode]',b' /DecodeParms [null null]'),
        ('extended',data.replace(b'\xff\xc0',b'\xff\xc1',1),b'/DCTDecode',b''),
        ('adobe-override',(root/'adobe-rgb.jpg').read_bytes(),b'/DCTDecode',b' /DecodeParms << /ColorTransform 1 >>')]:
        (root/(name+'.pdf')).write_bytes(pdf(encoded,33,25,filter=filter,params=params))
        (root/(name+'-expected.png')).write_bytes((root/('adobe-rgb-expected.png' if name=='adobe-override' else 'rgb-444-expected.png')).read_bytes())
        cases[name]={'width':33,'height':25}
    bad={'truncated':pdf(data[:-2],33,25),'wrong-width':pdf(data,32,25),'transform':pdf(data,33,25,params=b' /DecodeParms << /ColorTransform 2 >>'),'arithmetic':pdf(data.replace(b'\xff\xc0',b'\xff\xc9',1),33,25)}
    restart=(root/'restart.jpg').read_bytes();bad['restart-sequence']=pdf(restart.replace(b'\xff\xd0',b'\xff\xd3',1),43,35)
    zero=bytearray(data);zero[data.index(b'\xff\xdb')+5]=0;bad['zero-quantization']=pdf(zero,33,25)
    bad['wrong-height']=pdf(data,33,24)
    bad['wrong-channels']=pdf(data,33,25,mode='L')
    bad['bad-depth']=pdf(data,33,25).replace(b'/BitsPerComponent 8',b'/BitsPerComponent 4')
    progressive=(root/'progressive-420.jpg').read_bytes()
    first=progressive.index(b'\xff\xda');second=progressive.index(b'\xff\xda',first+2)
    header_end=first+2+int.from_bytes(progressive[first+2:first+4],'big')
    for name,offset,value in [('refinement-before-first',header_end-1,0x21),('invalid-band',header_end-2,64),('interleaved-ac',header_end-3,1)]:
        invalid=bytearray(progressive);invalid[offset]=value
        bad['progressive-'+name]=pdf(invalid,83,67)
    bad['progressive-duplicate-dc']=pdf(progressive[:second]+progressive[first:second]+progressive[second:],83,67)
    bad['progressive-truncated']=pdf(progressive[:-4],83,67)
    restart=(root/'progressive-restart.jpg').read_bytes()
    bad['progressive-restart']=pdf(restart.replace(b'\xff\xd0',b'\xff\xd7',1),83,67)
    invalid=bytearray(progressive);invalid[progressive.index(b'\xff\xc2')+4]=12
    bad['progressive-12bit']=pdf(invalid,83,67)
    for name,encoded in bad.items():(root/'invalid'/(name+'.pdf')).write_bytes(encoded)
    (root/'invalid.json').write_text(json.dumps(list(bad)))
    (root/'cases.json').write_text(json.dumps(cases))
    print('PASS:',len(cases),'JPEG cases;',len(bad),'malformed or unsupported cases')
    sys.exit(0)

import numpy as np
import pymupdf
maximum=mean_max=pdf_max=0
for name,info in json.loads((root/'cases.json').read_text()).items():
    expected=np.asarray(Image.open(root/(name+'-expected.png')).convert('RGB')).astype(int)
    actual=np.asarray(Image.open(root/(name+'-samples.png')).convert('RGB')).astype(int)
    assert actual.shape==expected.shape,(name,actual.shape,expected.shape)
    delta=abs(actual-expected);worst=int(delta.max());mean=float(delta.mean());maximum=max(maximum,worst);mean_max=max(mean_max,mean)
    assert worst<=4 and mean<=1,(name,'libjpeg sample error',worst,mean)
    with pymupdf.open(root/(name+'.pdf')) as original,pymupdf.open(root/(name+'-saved.pdf')) as saved:
        assert original.xref_stream_raw(5)==saved.xref_stream_raw(5),(name,'encoded JPEG changed')
        assert original.xref_object(5)==saved.xref_object(5),(name,'image dictionary changed')
        # MuPDF/IJG and libjpeg-turbo reconstruct subsampled chroma differently.
        # Check exact original/saved MuPDF rasters; compare Pod's PDF placement
        # against a MuPDF raster of independently decoded libjpeg samples.
        reference=original[0].get_pixmap(alpha=False)
        assert reference.samples==saved[0].get_pixmap(alpha=False).samples,(name,'MuPDF saved appearance changed')
        oracle=pdf(zlib.compress(expected.astype(np.uint8).tobytes()),info['width'],info['height'],filter=b'/FlateDecode')
        with pymupdf.open(stream=oracle,filetype='pdf') as reference_pdf:
            reference=reference_pdf[0].get_pixmap(alpha=False)
            pixels=np.frombuffer(reference.samples,np.uint8).reshape(reference.height,reference.width,3).astype(int)
            error=float(abs(pixels-actual).mean());pdf_max=max(pdf_max,error)
            assert error<=1,(name,'MuPDF placement error',error)
    print('PASS:',name,'libjpeg samples',worst,round(mean,4),'and preserved PDF JPEG stream')
print('Maximum sample difference:',maximum,'mean:',mean_max,'MuPDF mean:',pdf_max)
