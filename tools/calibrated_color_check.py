#!/usr/bin/env python3
"""Calibrated color fixtures; independent LittleCMS adaptation and sRGB mapping."""
from cie_reference import reference
import itertools
import json
import random
import subprocess
import sys
from pathlib import Path
from link_fixtures import serialize
import pymupdf

root=Path(sys.argv[1])
def array(values): return '['+' '.join(f'{v:.12g}' for v in values)+']'
def space(kind,params):
    return '['+kind+' << '+' '.join('/'+key+' '+(array(value) if isinstance(value,list) else str(value)) for key,value in params.items())+' >>]'
def pdf(spec,content,default=None):
    data=content.encode()
    return serialize([
        b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> /ColorSpace << /CS0 6 0 R '+('/'+default+' 6 0 R' if default else '')+' >> >> /Contents 5 0 R >>').encode(),
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
        b'<< /Length '+str(len(data)).encode()+b' >>\nstream\n'+data+b'\nendstream',spec.encode()])

if '--fixtures' in sys.argv:
    root.mkdir(parents=True,exist_ok=True)
    d65=[.95047,1,1.08883];d50=[.9642,1,.8249]
    rgb_matrix=[.4124564,.2126729,.0193339,.3575761,.7151522,.1191920,.1804375,.0721750,.9503041]
    definitions={
        'gray-d65':('/CalGray',dict(WhitePoint=d65)),
        'gray-d50':('/CalGray',dict(WhitePoint=d50,Gamma=2.2)),
        'gray-e':('/CalGray',dict(WhitePoint=[1,1,1],Gamma=.5)),
        'rgb-d65':('/CalRGB',dict(WhitePoint=d65,Gamma=[2.2]*3,Matrix=rgb_matrix)),
        'rgb-gammas':('/CalRGB',dict(WhitePoint=d65,Gamma=[1,1.8,2.4],Matrix=rgb_matrix)),
        'rgb-identity':('/CalRGB',dict(WhitePoint=d50)),
        'rgb-black':('/CalRGB',dict(WhitePoint=d65,BlackPoint=[.01,.01,.01],Gamma=[2.2]*3,Matrix=rgb_matrix)),
        'lab-d50':('/Lab',dict(WhitePoint=d50)),
        'lab-d65':('/Lab',dict(WhitePoint=d65)),
        'lab-range':('/Lab',dict(WhitePoint=d65,Range=[-20,40,-60,10])),
    }
    cases=[]
    for name,(kind,params) in definitions.items():
        values=[(i/20,) for i in range(21)] if kind=='/CalGray' else list(itertools.product([0,.2,.4,.6,.8,1],repeat=3)) if kind=='/CalRGB' else list(itertools.product([0,8,25,50,75,100],[-80,-20,0,60],[-60,0,50]))
        values+=[(-1,),(2,)] if kind=='/CalGray' else [(-1,2,.5)] if kind=='/CalRGB' else [(-10,-200,200),(110,200,-200)]
        expected=reference(kind,params,values)
        for default in [False,True] if kind!='/Lab' else [False]:
            filename=name+('-default' if default else '')
            op=('g' if kind=='/CalGray' else 'rg') if default else 'scn'
            content='' if default else '/CS0 cs\n'; samples=[]
            for i,(value,rgb) in enumerate(zip(values,expected)):
                x,y=60+i%12*40,80+i//12*34
                content+=' '.join(map(str,value))+f' {op} {x} {y} 36 30 re f\n'
                samples.append(dict(x=x+18,y=y+15,rgb=rgb))
            text=[.5] if kind=='/CalGray' else [50,10,-20] if kind=='/Lab' else [.2,.5,.8]
            content+=' '.join(map(str,text))+f' {op} BT /F1 18 Tf 1 0 0 1 60 740 Tm (Color) Tj ( tail) Tj ET\n'
            spec=space(kind,params)
            (root/(filename+'.pdf')).write_bytes(pdf(spec,content,('DefaultGray' if kind=='/CalGray' else 'DefaultRGB') if default else None))
            cases.append(dict(name=filename,samples=samples,text_rgb=reference(kind,params,[text])[0]))
    bad={
        'missing-white':'[/CalGray << >>]', 'white-y':'[/Lab << /WhitePoint [1 0 1] >>]',
        'white-z':'[/CalRGB << /WhitePoint [1 1 -1] >>]', 'white-arity':'[/Lab << /WhitePoint [1 1] >>]',
        'gamma-zero':'[/CalGray << /WhitePoint [1 1 1] /Gamma 0 >>]',
        'gamma-arity':'[/CalRGB << /WhitePoint [1 1 1] /Gamma [1 1] >>]',
        'gamma-type':'[/CalGray << /WhitePoint [1 1 1] /Gamma /Bad >>]',
        'matrix':'[/CalRGB << /WhitePoint [1 1 1] /Matrix [1 0 0] >>]',
        'range':'[/Lab << /WhitePoint [1 1 1] /Range [1 -1 0 1] >>]',
        'black':'[/Lab << /WhitePoint [1 1 1] /BlackPoint [0 -1 0] >>]',
        'dictionary':'[/CalGray false]', 'arity':'[/CalRGB << /WhitePoint [1 1 1] >> false]',
    }
    for name,spec in bad.items():(root/('invalid-'+name+'.pdf')).write_bytes(pdf(spec,'/CS0 cs'))
    rng=random.Random(5149)
    for i in range(64):
        params=dict(WhitePoint=d65,Gamma=[rng.uniform(-2,4) for _ in range(3)],Matrix=[rng.uniform(-2,2) for _ in range(9)])
        (root/f'mutation-{i}.pdf').write_bytes(pdf(space('/CalRGB',params),'/CS0 cs .2 .5 .8 scn 0 0 100 100 re f'))
    (root/'cases.json').write_text(json.dumps(cases))
    print(f'PASS: {len(cases)} calibrated color fixtures, {len(bad)} invalid and 64 mutations')
    sys.exit(0)

worst=0;reader_worst=0;lab_reader_difference=0
for case in json.loads((root/'cases.json').read_text()):
    name=case['name']
    with pymupdf.open(root/(name+'.pdf')) as before:
        for suffix in ['', '-saved', '-edited']:
            with pymupdf.open(root/(name+suffix+'.pdf')) as doc:
                assert doc.xref_object(6)==before.xref_object(6),(name,'calibration dictionary changed')
                if suffix=='-saved':assert doc[0].get_pixmap().samples==before[0].get_pixmap().samples,(name,'saved appearance changed')
                native=pymupdf.Pixmap(str(root/(name+suffix+'.png')))
                # Disable optional black-point compensation in the independent reader.
                off=doc.get_new_xref();doc.update_object(off,'<< /Type /ExtGState /UseBlackPtComp /OFF >>')
                doc.xref_set_key(doc[0].xref,'Resources/ExtGState',f'<< /Off {off} 0 R >>')
                at=doc[0].get_contents()[0];doc.update_stream(at,b'/Off gs\n'+doc.xref_stream(at))
                reader=doc[0].get_pixmap(alpha=False)
                if name.startswith('rgb-identity'):
                    # MuPDF differs for this wide XYZ gamut; Ghostscript agrees
                    # with the unoptimized LittleCMS transform.
                    path=root/(name+suffix+'-gs.png')
                    subprocess.run(['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=png16m','-r72',f'-sOutputFile={path}',str(root/(name+suffix+'.pdf'))],check=True)
                    reader=pymupdf.Pixmap(str(path))
                for sample in case['samples']:
                    x,y=sample['x'],791-sample['y']
                    actual=native.pixel(x,y)[:3];expected=sample['rgb']
                    delta=max(abs(a-b) for a,b in zip(actual,expected));worst=max(worst,delta)
                    assert delta<=2,(name,suffix,actual,expected,'LittleCMS')
                    delta=max(abs(a-b) for a,b in zip(reader.pixel(x,y),expected))
                    # MuPDF uses a fixed Lab space, ignoring WhitePoint/Range,
                    # and a coarse transform. For Lab the independent oracle is
                    # LittleCMS above; source/save appearance equality still applies.
                    if not name.startswith('lab-'):
                        reader_worst=max(reader_worst,delta)
                        assert delta<=3,(name,suffix,reader.pixel(x,y),expected,'PDF reader')
                    else:
                        lab_reader_difference=max(lab_reader_difference,delta)
                text_pixels=[native.pixel(x,y)[:3] for y in range(30,60) for x in range(60,240) if min(native.pixel(x,y)[:3])<240]
                assert len(text_pixels)>50 and min(max(abs(a-b) for a,b in zip(pixel,case['text_rgb'])) for pixel in text_pixels)<=2,(name,'glyph color')
                if suffix=='-edited':assert doc[0].get_text().split()==['Ink','tail']
    print('PASS:',name,'LittleCMS colors and exact calibration preservation'+(' (MuPDF Lab differs)' if name.startswith('lab-') else ' and PDF reader'))
print('Maximum channel differences: Pod/LittleCMS',worst,'verified PDF-reader cases',reader_worst)
print('Diagnostic only: fixed-space MuPDF Lab differs by up to',lab_reader_difference,'(not a Lab equivalence pass)')
