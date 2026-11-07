#!/usr/bin/env python3
"""Verify CID-font raster and save semantics with an independent reader."""
from pathlib import Path
import json, subprocess, sys
import xml.etree.ElementTree as ET
import pymupdf
root=Path(sys.argv[1]);binary=str(Path(sys.argv[2]).resolve())
def fonts(doc):return {f[3]:doc.extract_font(f[0])[3] for f in doc.get_page_fonts(0) if f[1]=='ttf'}
def mask(pix):return bytearray(v<128 for v in pix.samples[::pix.n])
def ghostscript(path,tail):
    png=path.with_suffix('.gs.png');xml=path.with_suffix('.gs.xml')
    logs=[]
    for device,output,extra in [('png16m',png,['-r72','-dTextAlphaBits=4']),('txtwrite',xml,['-dTextFormat=0'])]:
        result=subprocess.run(['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE='+device,'-sOutputFile='+str(output),*extra,str(path)],check=True,capture_output=True,timeout=30)
        logs.append(result.stdout+result.stderr)
    path.with_suffix('.gs.log').write_bytes(b''.join(logs))
    chars=list(ET.parse(xml).getroot().iter('char'))
    text=''.join(c.attrib['c'] for c in chars)
    at=text.rfind(tail);assert at>=0,(path,text)
    boxes=[list(map(float,c.attrib['bbox'].split())) for c in chars[at:at+len(tail)]]
    bounds=(min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes))
    return text,bounds,mask(pymupdf.Pixmap(str(png)))

for case in json.loads((root/'cases.json').read_text()):
    name=case['name'];source=root/(name+'.pdf');cli=root/(name+'-cli.pdf')
    before=json.loads(subprocess.check_output([binary,'inspect',str(source)]))['pages'][0]['runs']
    assert before[0]['text']==case['text']
    if name=='cid-spacing':
        # Tc applies per CID; Tw does not apply to two-byte 0x0020.
        assert abs(before[0]['advance']-41.4)<1e-7,before
        assert abs(before[1]['advance']-34.65)<1e-7,before
    if name=='word-spacing':
        assert abs(before[0]['advance']-39.15)<1e-7,before
        assert abs(before[1]['advance']-40.65)<1e-7,before
    cli.unlink(missing_ok=True)
    subprocess.run([binary,'replace',str(source),str(cli),'1','0',case['replacement']],check=True,capture_output=True)
    after=json.loads(subprocess.check_output([binary,'inspect',str(cli)]))['pages'][0]['runs']
    assert after[0]['text']==case['replacement'] and before[1:]==after[1:]
    with pymupdf.open(source) as doc:
        page=doc[0];embedded=fonts(doc);assert embedded
        use_gs=case.get('oracle')=='ghostscript'
        if use_gs:
            text,before_box,original=ghostscript(source,case['tail'])
        else:
            text=page.get_text();before_box=page.search_for(case['tail'])[-1];original=mask(page.get_pixmap())
        assert ''.join(text.split())==''.join((case['text']+case['tail']).split()),repr(text)
        native=mask(pymupdf.Pixmap(str(root/(name+'-native.png'))))
        assert len(original)==len(native)==612*792
        iou=sum(a and b for a,b in zip(original,native))/sum(a or b for a,b in zip(original,native))
        assert iou>0.90,(name,iou)
        for suffix in ['-edited','-annotated','-cli']:
            with pymupdf.open(root/(name+suffix+'.pdf')) as saved:
                if use_gs:
                    text,after_box,_=ghostscript(root/(name+suffix+'.pdf'),case['tail'])
                else:
                    text=saved[0].get_text();after_box=saved[0].search_for(case['tail'])[-1]
                assert text.startswith(case['replacement'])
                assert all(abs(a-b)<0.001 for a,b in zip(before_box,after_box)),(name,before_box,after_box)
                assert fonts(saved)==embedded,'Embedded bytes changed'
                if suffix=='-annotated':assert any(a.type[1]=='Square' for a in saved[0].annots())
        if not use_gs:page.get_pixmap().save(str(root/(name+'-independent.png')))
        print(f'PASS: {name} CLI/native round trips, Unicode, glyph programs, following text and independent raster overlap {iou:.3f}')
for path in sorted(root.glob('invalid-*.pdf'))+sorted(root.glob('unsupported-*.pdf')):
    result=subprocess.run([binary,'inspect',str(path)],capture_output=True,timeout=5)
    assert result.returncode==1,(path,result.returncode,result.stderr)
print('PASS: malformed CID programs and unsupported encodings fail explicitly')
if any(c.get('oracle')=='ghostscript' for c in json.loads((root/'cases.json').read_text())):
    print('Ghostscript validation version:',subprocess.check_output(['gs','--version'],text=True).strip())
