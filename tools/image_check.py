#!/usr/bin/env python3
"""Independent image fixtures and MuPDF raster/preservation checks; test-only."""
from pathlib import Path
import json
import sys
import subprocess
import zlib

root = Path(sys.argv[1])

def stream(data, entries=b''):
    return b'<< /Length ' + str(len(data)).encode() + b' ' + entries + b' >>\nstream\n' + data + b'\nendstream'

def pdf(entries, data, content=b'q 120 0 0 100 40 50 cm /Im Do Q', resources=b'', nested=False, extra=None, page_entries=b''):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '+page_entries+b' /Resources << /XObject << /Im 5 0 R ' + (b'/Fm 6 0 R' if nested else b'') + b' >> ' + resources + b' >> /Contents 4 0 R >>',
        stream(b'/Fm Do' if nested else content), stream(data,b'/Subtype /Image '+entries)]
    if nested:
        objects.append(stream(content,b'/Subtype /Form /BBox [10 10 180 180] /Matrix [.9 .1 -.1 .9 20 10] /Resources << /XObject << /Im 5 0 R >> >>'))
    if extra: objects.extend(extra)
    out = bytearray(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offsets=[0]
    for i,obj in enumerate(objects,1):
        offsets.append(len(out));out += f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
    start=len(out);out += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    for offset in offsets[1:]:out += f'{offset:010d} 00000 n \n'.encode()
    out += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode()
    return out

if '--fixtures' in sys.argv:
    root.mkdir(parents=True,exist_ok=True)
    rgb=bytes([255,0,0, 0,255,0, 0,0,255, 255,255,0, 0,255,255, 255,0,255])
    base=b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceRGB'
    cases={'rgb':pdf(base,rgb),'flate':pdf(base+b' /Filter /FlateDecode',zlib.compress(rgb)),
           'hex':pdf(base+b' /Filter /ASCIIHexDecode',rgb.hex().encode()+b'>'),
           'decode':pdf(base+b' /Decode [1 0 0 1 1 0]',rgb),
           'interpolate':pdf(base+b' /Interpolate true',rgb),
           'nested':pdf(base,rgb,nested=True),
           'skew':pdf(base,rgb,b'q 110 25 -15 100 45 35 cm /Im Do Q'),
           'reflect':pdf(base,rgb,b'q -120 0 0 100 160 50 cm /Im Do Q'),
           'clip':pdf(base,rgb,b'80 100 65 70 re W n q 120 0 0 100 40 50 cm /Im Do Q'),
           'opacity':pdf(base,rgb,b'.2 .4 .8 rg 0 0 200 200 re f /A gs q 120 0 0 100 40 50 cm /Im Do Q',b'/ExtGState << /A << /ca .5 /BM /Multiply >> >>'),
           'key-mask':pdf(base+b' /Mask [255 255 0 0 0 0]',rgb),
           'png-predictor':pdf(base+b' /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 /Columns 3 /BitsPerComponent 8 >>',zlib.compress(b'\0'+rgb[:9]+b'\0'+rgb[9:]))}
    for bits,data in [(1,b'\x40\xa0'),(2,b'\x18\xe4'),(4,b'\x08\xf0\xf8\x00'),(8,b'\x00\x80\xff\xff\x80\x00'),(16,b'\x00\x00\x80\x00\xff\xff\xff\xff\x80\x00\x00\x00')]:
        cases[f'gray-{bits}']=pdf(f'/Width 3 /Height 2 /BitsPerComponent {bits} /ColorSpace /DeviceGray'.encode(),data)
    for reverse in [False,True]:
        cases['stencil'+('-reverse' if reverse else '')]=pdf(b'/Width 3 /Height 2 /ImageMask true /BitsPerComponent 1'+(b' /Decode [1 0]' if reverse else b''),b'\x40\xa0',b'0 .4 .8 rg 0 0 200 200 re f 1 .2 .4 rg q 120 0 0 100 40 50 cm /Im Do Q')
    background=b'.2 .4 .8 rg 0 0 200 200 re f q 120 0 0 100 40 50 cm /Im Do Q'
    for reverse in [False,True]:
        cases['explicit-mask'+('-reverse' if reverse else '')]=pdf(base+b' /Mask 6 0 R',rgb,background,extra=[
            stream(b'\x50\xa0\xf0',b'/Subtype /Image /Width 4 /Height 3 /ImageMask true'+(b' /Decode [1 0]' if reverse else b''))])
    for bits,data in [(1,b'\x40\xa0'),(2,b'\x18\xe4'),(4,b'\x08\xf0\xf8\x00'),(8,b'\x00\x80\xff\xff\x80\x00'),(16,b'\x00\x00\x80\x00\xff\xff\xff\xff\x80\x00\x00\x00')]:
        cases[f'soft-mask-{bits}']=pdf(base+b' /SMask 6 0 R',rgb,background,extra=[
            stream(zlib.compress(data),f'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent {bits} /ColorSpace /DeviceGray /Filter /FlateDecode'.encode())])
    for name,entries,mask_entries in [('soft-different',b'',b''),('soft-reverse',b'',b' /Decode [1 0]'),('soft-interpolate',b'',b' /Interpolate true'),('soft-base-interpolate',b' /Interpolate true',b''),('soft-both-interpolate',b' /Interpolate true',b' /Interpolate true'),('soft-override',b' /Mask [0 255 0 255 0 255]',b'')]:
        cases[name]=pdf(base+b' /SMask 6 0 R'+entries,rgb,background,extra=[
            stream(bytes([0,64,128,255,255,128,64,0,0,128,255,64]),b'/Subtype /Image /Width 4 /Height 3 /BitsPerComponent 8 /ColorSpace /DeviceGray'+mask_entries)])
    soft=stream(bytes([0,128,255,255,128,0]),b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray')
    cases['soft-skew']=pdf(base+b' /SMask 6 0 R',rgb,b'q 110 25 -15 100 45 35 cm /Im Do Q',extra=[soft])
    cases['soft-clip-blend']=pdf(base+b' /SMask 6 0 R',rgb,b'.2 .4 .8 rg 0 0 200 200 re f /A gs 80 100 65 70 re W n q 120 0 0 100 40 50 cm /Im Do Q',b'/ExtGState << /A << /ca .5 /BM /Multiply >> >>',extra=[soft])
    cases['soft-nested']=pdf(base+b' /SMask 7 0 R',rgb,nested=True,extra=[soft])
    cases['soft-transparent']=pdf(base+b' /SMask 6 0 R',rgb,extra=[stream(b'\0',b'/Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray')])
    cases['explicit-interpolate']=pdf(base+b' /Mask 6 0 R',rgb,background,extra=[stream(b'\x50\xa0',b'/Subtype /Image /Width 4 /Height 2 /ImageMask true /Interpolate true')])
    for interpolate in [False,True]:
        cases['soft-matte'+('-interpolate' if interpolate else '')]=pdf(base+b' /SMask 6 0 R'+(b' /Interpolate true' if interpolate else b''),bytes([255,255,255,127,255,127,0,0,255,255,255,0,127,255,255,255,255,255]),background,extra=[stream(bytes([0,128,255,255,128,0]),b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 1 1]'+(b' /Interpolate true' if interpolate else b''))])
    # Explicit Text display flags make MuPDF retain the required upright AP on rotated pages.
    cases['appearance']=pdf(base,rgb,content=b'',page_entries=b'/Annots [7 0 R]',extra=[
        stream(b'/Im Do',b'/Subtype /Form /BBox [0 0 1 1] /Resources << /XObject << /Im 5 0 R >> >>'),
        b'<< /Type /Annot /Subtype /Text /Rect [40 50 160 150] /F 28 /Contents (Image note) /AP << /N 6 0 R >> >>'])
    cases['soft-appearance']=pdf(base+b' /SMask 8 0 R',rgb,content=b'',page_entries=b'/Annots [7 0 R]',extra=[
        stream(b'/Im Do',b'/Subtype /Form /BBox [0 0 1 1] /Resources << /XObject << /Im 5 0 R >> >>'),
        b'<< /Type /Annot /Subtype /Text /Rect [40 50 160 150] /F 28 /Contents (Masked image note) /AP << /N 6 0 R >> >>',soft])
    import pymupdf
    producer=pymupdf.open()
    page=producer.new_page(width=200,height=200)
    pixmap=pymupdf.Pixmap(pymupdf.csRGB,3,2,rgb,False)
    page.insert_image(pymupdf.Rect(40,50,160,150),pixmap=pixmap)
    cases['mupdf']=producer.tobytes(deflate=True)
    producer.close()
    producer=pymupdf.open();page=producer.new_page(width=200,height=200)
    transparent=pymupdf.Pixmap(pymupdf.csRGB,3,2,bytes([0,0,0,0, 0,128,0,128, 0,0,255,255, 255,255,0,255, 0,128,128,128, 0,0,0,0]),True)
    page.insert_image(pymupdf.Rect(40,50,160,150),pixmap=transparent)
    cases['mupdf-soft']=producer.tobytes(deflate=True);producer.close()
    jpeg_mask=pymupdf.Pixmap(pymupdf.csGRAY,3,2,bytes([0,128,255,255,128,0]),False).tobytes('jpeg')
    cases['jpeg-soft']=pdf(base+b' /SMask 6 0 R',rgb,background,extra=[stream(jpeg_mask,b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter /DCTDecode')])
    profile=(Path('/System/Library/ColorSync/Profiles')/'Display P3.icc').read_bytes()
    cases['icc']=pdf(base.replace(b'/DeviceRGB',b'[/ICCBased 6 0 R]'),rgb,extra=[stream(profile,b'/N 3')])
    cases['default-rgb']=pdf(base,rgb,resources=b'/ColorSpace << /DefaultRGB [/ICCBased 6 0 R] >>',extra=[stream(profile,b'/N 3')])
    cases['icc-matte']=pdf(base.replace(b'/DeviceRGB',b'[/ICCBased 6 0 R]')+b' /SMask 7 0 R',bytes([255,127,127,127,255,127,127,127,255,255,255,127,127,255,255,255,127,255]),background,extra=[stream(profile,b'/N 3'),stream(bytes([128]*6),b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 1 1]')])
    palette=b'[/Indexed /DeviceRGB 5 <'+rgb.hex().encode()+b'>]'
    indexed=b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace '+palette
    indices=bytes(range(6))
    cases['indexed-1']=pdf(b'/Width 3 /Height 2 /BitsPerComponent 1 /ColorSpace [/Indexed /DeviceRGB 1 <ff00000000ff>]',b'\x40\xa0')
    cases['indexed-2']=pdf(b'/Width 3 /Height 2 /BitsPerComponent 2 /ColorSpace [/Indexed /DeviceRGB 3 <ff000000ff000000ffffff00>]',b'\x18\xe4')
    cases['indexed-4']=pdf(indexed.replace(b'/BitsPerComponent 8',b'/BitsPerComponent 4'),b'\x01\x20\x34\x50')
    cases['indexed-8']=pdf(indexed,indices)
    cases['indexed-clamp']=pdf(indexed,bytes([0,1,5,6,128,255]))
    cases['indexed-zero']=pdf(b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceGray 0 <80>]',bytes([0,1,5,6,128,255]))
    cases['indexed-decode']=pdf(indexed+b' /Decode [5 0]',bytes([0,51,102,153,204,255]))
    cases['indexed-round']=pdf(indexed+b' /Decode [0 5]',bytes([0,26,76,128,204,255]))
    cases['indexed-gray']=pdf(indexed.replace(palette,b'[/Indexed /DeviceGray 5 (\000\063\146\231\314\377)]'),indices)
    cases['indexed-stream']=pdf(indexed.replace(palette,b'[/Indexed /DeviceRGB 5 6 0 R]'),indices,extra=[stream(zlib.compress(rgb),b'/Filter /FlateDecode')])
    cases['indexed-indirect']=pdf(indexed.replace(palette,b'[/Indexed /DeviceRGB 5 6 0 R]'),indices,extra=[b'7 0 R',b'<'+rgb.hex().encode()+b'>'])
    cases['indexed-icc']=pdf(indexed.replace(b'/Indexed /DeviceRGB',b'/Indexed [/ICCBased 6 0 R]'),indices,extra=[stream(profile,b'/N 3')])
    cases['indexed-default']=pdf(indexed,indices,resources=b'/ColorSpace << /DefaultRGB [/ICCBased 6 0 R] >>',extra=[stream(profile,b'/N 3')])
    cases['indexed-interpolate']=pdf(indexed+b' /Interpolate true',indices)
    cases['indexed-key']=pdf(indexed+b' /Mask [1 1]',indices,background)
    cases['indexed-soft']=pdf(indexed+b' /SMask 6 0 R',indices,background,extra=[soft])
    cases['indexed-explicit']=pdf(indexed+b' /Mask 6 0 R',indices,background,extra=[stream(b'\x50\xa0',b'/Subtype /Image /Width 4 /Height 2 /ImageMask true')])
    matte_palette=bytes(round(v*128/255+127) for v in rgb)
    matte_indexed=indexed.replace(palette,b'[/Indexed /DeviceRGB 6 <'+matte_palette.hex().encode()+b'ffffff>]')
    cases['indexed-matte']=pdf(matte_indexed+b' /SMask 6 0 R',indices,background,extra=[stream(bytes([128]*6),b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [6]')])
    cases['indexed-nested']=pdf(indexed,indices,nested=True)
    cases['indexed-vectors']=pdf(indexed,indices,content=b'/Palette cs 20 20 30 60 re f q .6 scn 60 20 30 60 re f 100 sc 100 20 30 60 re f Q 140 20 30 60 re f /Palette CS 2 SCN 8 w 20 120 m 180 120 l S',resources=b'/ColorSpace << /Palette '+palette+b' >>')
    from PIL import Image,ImageDraw
    import io
    producer=Image.new('P',(200,200));producer.putpalette(list(rgb)+[0]*(768-len(rgb)))
    draw=ImageDraw.Draw(producer)
    for y in range(5):
        for x in range(5):draw.rectangle((x*40,y*40,x*40+39,y*40+39),fill=(x+y)%6)
    output=io.BytesIO();producer.save(output,format='PDF',resolution=72)
    cases['pillow-indexed']=output.getvalue()
    with pymupdf.open(stream=cases['pillow-indexed'],filetype='pdf') as document:
        assert any('/Indexed' in document.xref_get_key(xref,'ColorSpace')[1] for xref in range(1,document.xref_length())), 'Independent producer must retain its palette'
        document.set_metadata(dict(document.metadata,title='Study notes – Sinh học',author='Giáo viên',subject='Palette preservation'))
        info_ref=int(document.xref_get_key(-1,'Info')[1].split()[0])
        document.xref_set_key(info_ref,'Course',pymupdf.get_pdf_str('Biology'))
        cases['indexed-metadata']=document.tobytes()
    calgray=b'[/CalGray << /WhitePoint [.9642 1 .8249] /Gamma 2.2 >>]'
    calrgb=b'[/CalRGB << /WhitePoint [.95047 1 1.08883] /Gamma [2.2 2.2 2.2] /Matrix [.4124564 .2126729 .0193339 .3575761 .7151522 .1191920 .1804375 .0721750 .9503041] >>]'
    lab=b'[/Lab << /WhitePoint [.9642 1 .8249] >>]'
    lab_samples=bytes([0,128,128,128,128,128,255,128,128,128,200,80,180,80,180,200,150,190])
    cases['cie-gray']=pdf(b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace '+calgray,bytes([0,32,128,192,224,255]))
    cases['cie-rgb']=pdf(base.replace(b'/DeviceRGB',calrgb),bytes([20,60,180,80,180,60,200,90,20,180,180,60,60,180,180,180,60,180]))
    cases['cie-lab']=pdf(base.replace(b'/DeviceRGB',lab),lab_samples)
    cases['cie-lab-range']=pdf(base.replace(b'/DeviceRGB',lab.replace(b'>>',b'/Range [-40 40 -20 20] >>')),lab_samples)
    cases['cie-lab-decode']=pdf(base.replace(b'/DeviceRGB',lab)+b' /Decode [0 100 -128 127 -128 127]',lab_samples)
    cases['cie-lab-indexed']=pdf(indexed.replace(palette,b'[/Indexed '+lab+b' 5 <'+lab_samples.hex().encode()+b'>]'),indices)
    cases['cie-lab-soft']=pdf(base.replace(b'/DeviceRGB',lab)+b' /SMask 6 0 R',lab_samples,background,extra=[soft])
    cases['cie-rgb-nested']=pdf(base.replace(b'/DeviceRGB',calrgb),rgb,nested=True)
    cases['cie-rgb-default']=pdf(base,rgb,resources=b'/ColorSpace << /DefaultRGB '+calrgb+b' >>')
    with pymupdf.open(stream=cases['cie-rgb'],filetype='pdf') as document:
        # An independent writer produces compressed objects and an xref stream.
        cases['cie-rgb-object-stream']=document.tobytes(garbage=4,deflate=True,use_objstms=1)
    # MuPDF fixes Lab to its built-in D50 space and disregards PDF Range. Expand
    # samples through an independent LittleCMS transform for these raster oracles.
    # The original Lab PDFs are still independently compared before/after save.
    from cie_reference import reference as cie_reference
    (root/'oracles').mkdir(exist_ok=True)
    for name,ranges,decode in [
        ('cie-lab',[-100,100,-100,100],[0,100,-100,100,-100,100]),
        ('cie-lab-range',[-40,40,-20,20],[0,100,-40,40,-20,20]),
        ('cie-lab-decode',[-100,100,-100,100],[0,100,-128,127,-128,127]),
        ('cie-lab-indexed',[-100,100,-100,100],[0,100,-100,100,-100,100]),
        ('cie-lab-soft',[-100,100,-100,100],[0,100,-100,100,-100,100])]:
        values=[[decode[j*2]+lab_samples[i+j]/255*(decode[j*2+1]-decode[j*2]) for j in range(3)] for i in range(0,len(lab_samples),3)]
        pixels=bytes(v for color in cie_reference('/Lab',dict(WhitePoint=[.9642,1,.8249],Range=ranges),values) for v in color)
        expected=pdf(base+b' /SMask 6 0 R',pixels,background,extra=[soft]) if name=='cie-lab-soft' else pdf(base,pixels)
        (root/'oracles'/(name+'.pdf')).write_bytes(expected)
    for name,data in cases.items():(root/(name+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps(list(cases)))
    bad={'short':pdf(base,rgb[:-1]),'long':pdf(base,rgb+b'\0'),'dimensions':pdf(base.replace(b'/Width 3',b'/Width -1'),rgb),'soft-mask':pdf(base+b' /SMask 5 0 R',rgb),'mask-type':pdf(base+b' /Mask false',rgb),'decode-arity':pdf(base+b' /Decode [0 1]',rgb),'depth':pdf(base.replace(b'/BitsPerComponent 8',b'/BitsPerComponent 3'),rgb)}
    for name,entries,data in [
        ('mask-cycle',b'/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /SMask 5 0 R',b'\0'),
        ('mask-nested',b'/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Mask [0 0]',b'\0'),
        ('mask-color',b'/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB',b'\0\0\0'),
        ('mask-stencil',b'/Width 1 /Height 1 /ImageMask true',b'\0'),
        ('mask-short',b'/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray',b'\0'),
        ('mask-size',b'/Width 65536 /Height 65536 /BitsPerComponent 8 /ColorSpace /DeviceGray',b'\0'),
        ('matte-size',b'/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 1 1]',b'\0'),
        ('matte-arity',b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1]',b'\0'*6),
        ('matte-range',b'/Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 2 1]',b'\0'*6),
        ('mask-subtype',b'/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Subtype /Form',b'\0')]:
        bad[name]=pdf(base+b' /SMask 6 0 R',rgb,extra=[stream(data,(b'' if name=='mask-subtype' else b'/Subtype /Image ')+entries)])
    bad['explicit-not-stencil']=pdf(base+b' /Mask 6 0 R',rgb,extra=[soft])
    for name,space in [('arity',b'[/Indexed /DeviceRGB 5]'),('negative',b'[/Indexed /DeviceRGB -1 <>]'),('huge',b'[/Indexed /DeviceRGB 256 <>]'),('real',b'[/Indexed /DeviceRGB 1.5 <000000ffffff>]'),('short',b'[/Indexed /DeviceRGB 5 <ff0000>]'),('long',b'[/Indexed /DeviceGray 0 <0000>]'),('type',b'[/Indexed /DeviceGray 0 false]'),('nested',b'[/Indexed [/Indexed /DeviceGray 0 <00>] 0 <00>]')]:
        bad['indexed-'+name]=pdf(indexed.replace(palette,space),indices)
    bad['indexed-16']=pdf(indexed.replace(b'/BitsPerComponent 8',b'/BitsPerComponent 16'),indices*2)
    bad['indexed-cycle']=pdf(indexed.replace(palette,b'[/Indexed /DeviceRGB 5 6 0 R]'),indices,extra=[b'6 0 R'])
    for label,matte in [('arity',b'[1 1 1]'),('negative',b'[-1]'),('high',b'[7]')]:
        bad['indexed-matte-'+label]=pdf(matte_indexed+b' /SMask 6 0 R',indices,extra=[stream(bytes([128]*6),b'/Subtype /Image /Width 3 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte '+matte)])
    (root/'invalid').mkdir(exist_ok=True)
    for name,data in bad.items():(root/'invalid'/(name+'.pdf')).write_bytes(data)
    print(f'PASS: {len(cases)} image fixtures and {len(bad)} malformed/unsupported fixtures produced')
    sys.exit(0)

import pymupdf
import numpy as np
from PIL import Image
worst=0
maximum_interior=0
for name in json.loads((root/'cases.json').read_text()):
    for suffix in ['', '-saved', '-rotated', '-organized']+(['-edited'] if name=='inline-text' else []):
        with pymupdf.open(root/(name+suffix+'.pdf')) as doc:
            for width in [200,400]:
                pix=doc[0].get_pixmap(matrix=pymupdf.Matrix(width/doc[0].rect.width,width/doc[0].rect.width),alpha=False)
                ref=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width,3).astype(float)
                if name.startswith('cie-lab'):
                    with pymupdf.open(root/'oracles'/(name+'.pdf')) as oracle:
                        oracle[0].set_rotation(doc[0].rotation)
                        mapped=oracle[0].get_pixmap(matrix=pymupdf.Matrix(width/200,width/200),alpha=False)
                        ref=np.frombuffer(mapped.samples,np.uint8).reshape(mapped.height,mapped.width,3).astype(float)
                if name in ('indexed-round','indexed-matte'):
                    # PDFBox 3.0.5 SampledImageReader rounds decoded palette indices
                    # to nearest, matching the Indexed color-space rule. MuPDF
                    # 1.26.5 truncates via a quantized fixed-point multiplier;
                    # Ghostscript 10.02.1 truncates differently. For Indexed Matte,
                    # PDFBox also agrees with palette expansion followed by the
                    # specified unblending equation; the other readers differ.
                    # Keep all thresholds.
                    prefix=root/f'{name}{suffix}-pdfbox-{width}'
                    subprocess.run(['java','-jar','.tools/pdfbox-app-3.0.5.jar','render','-i',str(root/(name+suffix+'.pdf')),'-outputPrefix',str(prefix),'-dpi',str(72*width//200),'-format','png'],check=True)
                    ref=np.asarray(Image.open(str(prefix)+'-1.png').convert('RGB')).astype(float)
                if name in ('soft-clip-blend','soft-matte-interpolate','inline-fax-mixed'):
                    # MuPDF 1.26.5 differs on mask+Multiply+constant-alpha and on
                    # interpolated Matte; Ghostscript agrees with the analytic result.
                    # MuPDF also reports a post-image syntax error for mixed T.4
                    # inline framing, where Ghostscript matches native output.
                    output=root/f'{name}{suffix}-gs-{width}.png'
                    subprocess.run(['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=png16m',f'-r{72*width/200}',f'-sOutputFile={output}',str(root/(name+suffix+'.pdf'))],check=True)
                    ref=np.asarray(Image.open(output).convert('RGB')).astype(float)
                actual=np.asarray(Image.open(root/f'{name}{suffix}-{width}.png').convert('RGB')).astype(float)
                assert actual.shape==ref.shape,(name,suffix,actual.shape,ref.shape)
                delta=np.abs(ref-actual);mean=float(delta.mean());worst=max(worst,mean)
                assert mean<2,(name,suffix,width,mean)
                # Readers use different edge filters for transformed images. Exclude
                # a three-pixel boundary margin, then compare solid interiors tightly.
                stable=np.ones(ref.shape[:2],dtype=bool)
                stable[:3,:]=False;stable[-3:,:]=False;stable[:,:3]=False;stable[:,-3:]=False
                for dy in range(-3,4):
                    for dx in range(-3,4):
                        stable &= np.max(np.abs(ref-np.roll(ref,(dy,dx),(0,1))),axis=2)<0.5
                interior=float(delta[stable].max()) if stable.any() else 0
                maximum_interior=max(maximum_interior,interior)
                assert interior<=3,(name,suffix,width,'interior',interior)
    with pymupdf.open(root/(name+'.pdf')) as before,pymupdf.open(root/(name+'-saved.pdf')) as after:
        if name=='inline-fax-mixed':
            assert Image.open(root/f'{name}-gs-200.png').tobytes()==Image.open(root/f'{name}-saved-gs-200.png').tobytes(),(name,'saved appearance changed')
        else:
            assert before[0].get_pixmap(alpha=False).samples==after[0].get_pixmap(alpha=False).samples,(name,'saved appearance changed')
        for xref in range(1,before.xref_length()):
            if before.xref_get_key(xref,'Subtype')!=('name','/Image'):continue
            assert before.xref_stream_raw(xref)==after.xref_stream_raw(xref),(name,'encoded image changed')
            assert before.xref_object(xref)==after.xref_object(xref),(name,'image dictionary changed')
        if name.startswith('inline-'):
            for xref in range(1,before.xref_length()):
                if before.xref_is_stream(xref):
                    assert before.xref_stream_raw(xref)==after.xref_stream_raw(xref),(name,'inline containing stream changed')
            if name=='inline-reportlab':
                for suffix in ['-saved','-rotated','-organized']:
                    with pymupdf.open(root/(name+suffix+'.pdf')) as output:
                        assert output.xref_get_key(output.pdf_catalog(),'PageMode')==before.xref_get_key(before.pdf_catalog(),'PageMode')
                        assert output.xref_get_key(output[0].xref,'Trans')==before.xref_get_key(before[0].xref,'Trans')
            if name=='inline-text':
                source=before[0].read_contents()
                with pymupdf.open(root/(name+'-edited.pdf')) as edited:
                    changed=edited[0].read_contents()
                    assert source.split(b'BI ',1)[1].split(b'\nEI',1)[0]==changed.split(b'BI ',1)[1].split(b'\nEI',1)[0]
                    assert edited[0].get_text().split()==['Ink','Tail']
        if name == 'indexed-stream':
            assert before.xref_stream_raw(6)==after.xref_stream_raw(6),'encoded palette changed'
            assert before.xref_object(6)==after.xref_object(6),'palette dictionary changed'
        if name in ('pillow-indexed','indexed-metadata'):
            source_info=int(before.xref_get_key(-1,'Info')[1].split()[0])
            for suffix in ['-saved','-rotated','-organized']:
                with pymupdf.open(root/(name+suffix+'.pdf')) as output:
                    target_info=int(output.xref_get_key(-1,'Info')[1].split()[0])
                    assert set(before.xref_get_keys(source_info))==set(output.xref_get_keys(target_info)),(name,suffix,'metadata keys changed')
                    for key in before.xref_get_keys(source_info):
                        assert before.xref_get_key(source_info,key)==output.xref_get_key(target_info,key),(name,suffix,key,'metadata changed')
    print('PASS:',name,'independent image rasters and unchanged image stream/dictionary')
print('Maximum mean channel difference:',worst,'/255; maximum flat-interior difference:',maximum_interior,'/255')
