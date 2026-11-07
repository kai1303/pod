#!/usr/bin/env python3
"""Independent vertical text/geometry, font-preservation and raster checks."""
from pathlib import Path
import json, subprocess, sys
import xml.etree.ElementTree as ET
import pymupdf
root=Path(sys.argv[1]);binary=str(Path(sys.argv[2]).resolve())
def inspect(path):
    return json.loads(subprocess.check_output([binary,'inspect',str(path)],timeout=10))['pages'][0]['runs']
def fonts(doc):
    return {f[3]:doc.extract_font(f[0])[3] for f in doc.get_page_fonts(0) if f[1]=='ttf'}
def chars(page):
    spans=page.get_texttrace()
    assert spans and all(s['wmode']==1 for s in spans),spans
    return [c for s in spans for c in s['chars']]
def mask(path):
    pix=pymupdf.Pixmap(str(path))
    assert (pix.width,pix.height)==(2448,3168)
    return bytearray(v<128 for v in pix.samples[::pix.n])
def gs(path,raster=True):
    # At 4x resolution, font hinting/rasterizer edge differences do not dominate
    # these deliberately tiny glyphs. Retain full images, text XML and logs.
    outputs=[('txtwrite',path.with_suffix('.gs.xml'),['-dTextFormat=0'])]
    if raster:outputs.append(('png16m',path.with_suffix('.gs-4x.png'),['-r288','-dTextAlphaBits=4']))
    logs=[]
    for device,out,flags in outputs:
        r=subprocess.run(['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE='+device,'-sOutputFile='+str(out),*flags,str(path)],capture_output=True,check=True,timeout=30)
        logs.append(r.stdout+r.stderr)
    path.with_suffix('.gs.log').write_bytes(b''.join(logs))
    return [(c.attrib['c'],tuple(map(float,c.attrib['bbox'].split()))) for c in ET.parse(path.with_suffix('.gs.xml')).getroot().iter('char')]
def close(a,b,tolerance=1e-4):
    return len(a)==len(b) and all(abs(x-y)<tolerance for x,y in zip(a,b))
for case in json.loads((root/'cases.json').read_text()):
    name=case['name'];source=root/(name+'.pdf');cli=root/(name+'-cli.pdf')
    before=inspect(source)
    assert [r['text'] for r in before]==['ABé',' AB']
    advances={'range':(-76.8,-79.2),'metrics':(-75.6,-79.2),'spacing':(-66,-63),'word-spacing':(-63,-55),'upward':(72,72)}.get(name,(-72,-72))
    assert close([r['advance'] for r in before],advances,1e-7),(name,before)
    if name=='rotated':assert close([before[1]['x'],before[1]['y']],[172,72])
    else:assert close([before[1]['x'],before[1]['y']],[72,before[0]['y']+advances[0]])
    cli.unlink(missing_ok=True)
    subprocess.run([binary,'replace',str(source),str(cli),'1','0','é'],check=True,capture_output=True,timeout=10)
    after=inspect(cli)
    assert after[0]['text']=='é' and before[1:]==after[1:],(name,before,after)
    with pymupdf.open(source) as doc:
        original=chars(doc[0]);assert ''.join(chr(c[0]) for c in original)=='ABé AB'
        embedded=fonts(doc);assert embedded
        use_gs=name!='dictionary-mode'
        gs_before=gs(source)
        assert ''.join(c[0] for c in gs_before).replace(' ','')=='ABéAB',gs_before
        if not use_gs:
            # GS 10.02.1 reads only the program WMode here; MuPDF honors the
            # PDF stream dictionary and independently checks this fixture.
            assert len({box[1] for _,box in gs_before})==1
            doc[0].get_pixmap(matrix=pymupdf.Matrix(4,4)).save(root/(name+'.mupdf-4x.png'))
        for suffix in ['-edited','-annotated','-cli']:
            path=root/(name+suffix+'.pdf')
            with pymupdf.open(path) as saved:
                edited=chars(saved[0]);assert ''.join(chr(c[0]) for c in edited)=='é AB'
                for old,new in zip(original[3:],edited[1:]):
                    assert old[:2]==new[:2] and close(old[2],new[2]) and close(old[3],new[3]),(name,old,new)
                assert fonts(saved)==embedded,'Embedded font bytes changed'
                if suffix=='-annotated':assert any(a.type[1]=='Square' for a in saved[0].annots())
                if not use_gs and suffix=='-edited':saved[0].get_pixmap(matrix=pymupdf.Matrix(4,4)).save(root/(name+suffix+'.mupdf-4x.png'))
            if not use_gs:continue
            gs_after=gs(path,raster=suffix=='-edited')
            assert ''.join(c[0] for c in gs_after).replace(' ','')=='éAB',gs_after
            # txtwrite rounds bounds to integer points; unchanged glyphs must
            # nevertheless produce exactly identical boxes across the save.
            assert gs_before[-2:]==gs_after[-2:],(name,gs_before,gs_after)
        overlaps=[]
        for suffix in ['', '-edited']:
            a=mask(root/(name+suffix+'-native-4x.png'));b=mask(root/(name+suffix+('.gs-4x.png' if use_gs else '.mupdf-4x.png')))
            union=sum(x or y for x,y in zip(a,b));assert union>0
            iou=sum(x and y for x,y in zip(a,b))/union
            assert iou>0.93,(name,suffix,iou)
            overlaps.append(round(iou,3))
        print(f"PASS: {name}: signed advances, origins, CLI/native edits, following glyphs, embedded bytes, {'Ghostscript' if use_gs else 'MuPDF'} original/edited raster IoU {overlaps}",flush=True)
for path in sorted(root.glob('invalid-*.pdf')):
    r=subprocess.run([binary,'inspect',str(path)],capture_output=True,timeout=5)
    assert r.returncode==1,(path,r.returncode,r.stderr)
print('PASS: all malformed vertical metrics and writing modes rejected')
print('Independent readers: MuPDF',pymupdf.VersionBind,'Ghostscript',subprocess.check_output(['gs','--version'],text=True).strip())
