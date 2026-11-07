#!/usr/bin/env python3
"""Independent ICC/PDF fixtures and LittleCMS/MuPDF validation (test-only)."""
import ctypes, ctypes.util, io, itertools, json, random, struct, sys, zlib
from pathlib import Path
from link_fixtures import serialize
from PIL import Image, ImageCms

ROOT = Path(sys.argv[1])
PROFILES = Path('/System/Library/ColorSync/Profiles')

def stream(data, extra=b''):
    encoded = zlib.compress(data)
    return b'<< /Length ' + str(len(encoded)).encode() + b' /Filter /FlateDecode ' + extra + b' >>\nstream\n' + encoded + b'\nendstream'

def pdf(profile, channels, content, default=False, extra=b'', resources=None):
    spaces = b'/CS0 [/ICCBased 6 0 R]'
    if default: spaces += (b' /DefaultGray' if channels == 1 else b' /DefaultRGB') + b' [/ICCBased 6 0 R]'
    if resources is not None: spaces = resources
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> /ColorSpace << ' + spaces + b' >> >> /Contents 5 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
        stream(content), stream(profile, b'/N ' + str(channels).encode() + extra),
    ])

def parametric(source, kind, params):
    result = bytearray(source[:128]);result[8] = 4
    tags = []
    for i in range(struct.unpack_from('>I', source, 128)[0]):
        tag, offset, size = struct.unpack_from('>4sII', source, 132+i*12)
        body = source[offset:offset+size]
        if tag in [b'rTRC', b'gTRC', b'bTRC']:
            body = b'para\0\0\0\0' + struct.pack('>HH',kind,0) + b''.join(struct.pack('>i',round(x*65536)) for x in params)
        tags.append((tag, body))
    result += struct.pack('>I',len(tags)) + bytes(12*len(tags))
    for i,(tag,body) in enumerate(tags):
        while len(result)%4: result += b'\0'
        struct.pack_into('>4sII', result, 132+i*12, tag, len(result), len(body))
        result += body
    while len(result)%4: result += b'\0'
    struct.pack_into('>I',result,0,len(result))
    return bytes(result)

def low_resolution_colors(profile, n, values):
    # MuPDF 1.26.5 uses a 16-bit LittleCMS transform with LOWRESPRECALC.
    # Keep this separate from the accurate, unoptimized reference used for Pod.
    library = ctypes.util.find_library('lcms2') or next((str(p) for p in [Path('/opt/homebrew/lib/liblcms2.dylib'),Path('/usr/local/lib/liblcms2.dylib')] if p.exists()), None)
    if not library: raise RuntimeError('Color tests require LittleCMS 2 (liblcms2)')
    lib = ctypes.CDLL(library)
    pointer, uint = ctypes.c_void_p, ctypes.c_uint32
    signatures = {
        'cmsOpenProfileFromMem': ([pointer,uint],pointer),
        'cmsCreate_sRGBProfile': ([],pointer),
        'cmsCreateTransform': ([pointer,uint,pointer,uint,uint,uint],pointer),
        'cmsDoTransform': ([pointer,pointer,pointer,uint],None),
        'cmsDeleteTransform': ([pointer],None),
        'cmsCloseProfile': ([pointer],ctypes.c_int),
    }
    for name,(args,result) in signatures.items():
        function=getattr(lib,name);function.argtypes=args;function.restype=result
    data=ctypes.create_string_buffer(profile)
    source=lib.cmsOpenProfileFromMem(data,len(profile));target=lib.cmsCreate_sRGBProfile()
    assert source and target
    # Public lcms2.h format bits: color model, channel count, bytes per channel.
    source_format=((3 if n==1 else 4)<<16)|(n<<3)|2
    transform=lib.cmsCreateTransform(source,source_format,target,(4<<16)|(3<<3)|2,1,0x0800)
    assert transform
    try:
        output=[]
        for value in values:
            raw=(ctypes.c_uint16*n)(*[v*257 for v in value]);converted=(ctypes.c_uint16*3)()
            lib.cmsDoTransform(transform,raw,converted,1)
            output.append([round(v/257) for v in converted])
        return output
    finally:
        lib.cmsDeleteTransform(transform);lib.cmsCloseProfile(source);lib.cmsCloseProfile(target)

if '--fixtures' in sys.argv:
    ROOT.mkdir(parents=True, exist_ok=True)
    profiles = {
        'srgb': ('sRGB Profile.icc',3), 'display-p3': ('Display P3.icc',3),
        'adobe-rgb': ('AdobeRGB1998.icc',3), 'romm-rgb': ('ROMM RGB.icc',3),
        'gray-22': ('Generic Gray Gamma 2.2 Profile.icc',1), 'gray-18': ('Generic Gray Profile.icc',1),
    }
    data = {name:(PROFILES/file).read_bytes() for name,(file,_) in profiles.items()}
    channels = {name:n for name,(_,n) in profiles.items()}
    for kind,params in enumerate([[2],[2,1,-.25],[2,1,-.25,.1],[2,1,0,.25,.25],[2,1,0,.25,.25,.1,.1]]):
        name=f'parametric-{kind}'
        data[name]=parametric(data['srgb'],kind,params);channels[name]=3
    cases=[]
    for name,profile in data.items():
        n=channels[name]
        values = list(itertools.product(range(0,256,51),repeat=3)) if n==3 else [(x,) for x in list(range(0,255,5))+[255]]
        mode='RGB' if n==3 else 'L'
        image=Image.frombytes(mode,(len(values),1),bytes(c for v in values for c in v))
        transform=ImageCms.buildTransformFromOpenProfiles(ImageCms.ImageCmsProfile(io.BytesIO(profile)),ImageCms.createProfile('sRGB'),mode,'RGB',renderingIntent=1,flags=ImageCms.Flags.NOOPTIMIZE)
        expected=list(ImageCms.applyTransform(image,transform).getdata())
        mupdf_expected=low_resolution_colors(profile,n,values) if name in ['display-p3','adobe-rgb','romm-rgb'] else expected
        for default in [False,True]:
            filename=name+('-default' if default else '')
            content=bytearray(b'' if default else b'/CS0 cs\n')
            samples=[]
            for i,(value,rgb,lowres) in enumerate(zip(values,expected,mupdf_expected)):
                x,y=60+(i%12)*40,80+(i//12)*34
                op='g' if default and n==1 else 'rg' if default else 'scn'
                content+=(' '.join(f'{v/255:.9f}' for v in value)+f' {op} {x} {y} 36 30 re f\n').encode()
                samples.append({'x':x+18,'y':y+15,'rgb':rgb,'mupdf_rgb':lowres})
            text_value=(51,128,204) if n==3 else (128,)
            text_image=Image.frombytes(mode,(1,1),bytes(text_value))
            text_rgb=list(ImageCms.applyTransform(text_image,transform).getdata())[0]
            text_op='g' if default and n==1 else 'rg' if default else 'scn'
            content+=(' '.join(f'{v/255:.9f}' for v in text_value)+' '+text_op+'\n').encode()
            content+=b'BT /F1 18 Tf 1 0 0 1 60 740 Tm (Color) Tj ( tail) Tj ET\n'
            (ROOT/(filename+'.pdf')).write_bytes(pdf(profile,n,bytes(content),default))
            (ROOT/(filename+'.icc')).write_bytes(profile)
            cases.append({'name':filename,'samples':samples,'text_rgb':text_rgb})
    source=data['srgb']
    invalid={
        'truncated':source[:120], 'empty-tags':source[:128]+bytes(4),
        'bad-magic':source[:36]+b'nope'+source[40:],
        'bad-version':source[:8]+b'\x05'+source[9:],
    }
    for field,value in [(128,257),(136,1),(140,len(source)+1)]:
        b=bytearray(source);struct.pack_into('>I',b,field,value);invalid[f'field-{field}']=bytes(b)
    for name,profile in invalid.items(): (ROOT/('invalid-'+name+'.pdf')).write_bytes(pdf(profile,3,b'/CS0 cs 1 0 0 sc 0 0 100 100 re f'))
    for name,n,content,extra,resources in [
        ('channels',1,b'/CS0 cs',b'',None),
        ('range',3,b'/CS0 cs',b' /Range [1 0 0 1 0 1]',None),
        ('operand-count',3,b'/CS0 cs 1 0 sc',b'',None),
        ('operand-name',3,b'/CS0 cs /Pattern scn',b'',None),
        ('cycle',3,b'/CS0 cs',b'',b'/CS0 /CS1 /CS1 /CS0'),
        ('missing',3,b'/Unknown cs',b'',None),
    ]: (ROOT/('invalid-'+name+'.pdf')).write_bytes(pdf(source,n,content,extra=extra,resources=resources))
    randomizer=random.Random(77421)
    for i in range(64):
        b=bytearray(source)
        at=randomizer.randrange(len(b));b[at]^=1<<randomizer.randrange(8)
        (ROOT/f'mutation-{i}.pdf').write_bytes(pdf(bytes(b),3,b'/CS0 cs .2 .5 .8 sc 0 0 100 100 re f'))
    (ROOT/'cases.json').write_text(json.dumps(cases))
    print('Generated',len(cases),'ICC fixtures,',len(list(ROOT.glob('invalid-*.pdf'))),'invalid and 64 mutated profiles')
    raise SystemExit(0)

import pymupdf
worst=0
for case in json.loads((ROOT/'cases.json').read_text()):
    name=case['name']
    for suffix in ['', '-saved', '-edited']:
        with pymupdf.open(ROOT/(name+suffix+'.pdf')) as doc:
            original_profile=ROOT/(name+'.icc')
            assert any(doc.xref_stream(i)==original_profile.read_bytes() for i in range(1,doc.xref_length()) if doc.xref_is_stream(i)),(name,'profile changed')
            unmodified=doc[0].get_pixmap(alpha=False)
            if suffix=='-saved':
                with pymupdf.open(ROOT/(name+'.pdf')) as original:
                    assert original[0].get_pixmap().samples==unmodified.samples
            # Match Pod's relative colorimetric conversion without optional BPC.
            # Only the independent in-memory reference is configured; saved PDFs
            # and the source/edited profile bytes above remain untouched.
            off=doc.get_new_xref();doc.update_object(off,'<< /Type /ExtGState /UseBlackPtComp /OFF >>')
            doc.xref_set_key(doc[0].xref,'Resources/ExtGState',f'<< /Off {off} 0 R >>')
            content=doc[0].get_contents()[0]
            doc.update_stream(content,b'/Off gs\n'+doc.xref_stream(content))
            independent=doc[0].get_pixmap(alpha=False)
            native=pymupdf.Pixmap(str(ROOT/(name+suffix+'.png')))
            for sample in case['samples']:
                x,y=sample['x'],791-sample['y']
                actual=native.pixel(x,y)[:3]
                difference=max(abs(a-b) for a,b in zip(actual,sample['rgb']))
                worst=max(worst,difference)
                assert difference<=2,(name,suffix,actual,sample['rgb'],'LittleCMS')
                reference=independent.pixel(x,y)
                assert max(abs(a-b) for a,b in zip(sample['mupdf_rgb'],reference))<=2,(name,suffix,sample['mupdf_rgb'],reference,'MuPDF low-resolution transform')
            text_pixels=[native.pixel(x,y)[:3] for y in range(30,60) for x in range(60,240) if min(native.pixel(x,y)[:3])<240]
            assert len(text_pixels)>50 and min(max(abs(a-b) for a,b in zip(pixel,case['text_rgb'])) for pixel in text_pixels)<=2,(name,'glyph color')
            if suffix=='-edited':assert doc[0].get_text().split()==['Ink','tail']
    print('PASS:',name,'LittleCMS/MuPDF colors, CPU/Metal, text edit and exact ICC preservation')
print('Maximum channel difference versus LittleCMS:',worst,'out of 255')
