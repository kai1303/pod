#!/usr/bin/env python3
"""Independent MuPDF verification of embedded fonts and saved geometry."""
import json, subprocess, sys
from pathlib import Path
import pymupdf
from pypdf import PdfReader
from pypdf.generic import ContentStream

root=Path(sys.argv[1])
binary=str(Path(sys.argv[2]).resolve())
names=['unicode','mac-symbolic','mac-nonsymbolic','windows-symbolic','unicode-full','mac-format-zero','attached','scaled','without-unicode','reportlab']

def fonts(doc):
    return {font[3]:doc.extract_font(font[0])[3] for font in doc.get_page_fonts(0) if font[1]=='ttf'}

def rounded_advance_error(path):
    reader=PdfReader(path)
    page=reader.pages[0]
    font=None; size=0
    for values,op in ContentStream(page.get_contents(),reader).operations:
        if op==b'Tf':font=page['/Resources']['/Font'][values[0]].get_object();size=float(values[1])
        elif op in (b'Tj',b'TJ'):
            strings=[values[0]] if op==b'Tj' else [v for v in values[0] if isinstance(v,(bytes,str))]
            raw=b''.join(v.original_bytes if hasattr(v,'original_bytes') else bytes(v) for v in strings)
            widths=font['/Widths'];first=int(font['/FirstChar'])
            return sum(int(float(widths[c-first])+0.5)-float(widths[c-first]) for c in raw)*size/1000
    raise AssertionError('Missing text-showing operator')

def mask(pix):
    return bytearray(value<128 for value in pix.samples[::pix.n])

for name in names:
    source=root/(name+'.pdf')
    saved=root/(name+'-cli.pdf')
    saved.unlink(missing_ok=True)
    before_runs=json.loads(subprocess.check_output([binary,'inspect',str(source)]))['pages'][0]['runs']
    replacement='café' if name=='reportlab' else 'é'
    subprocess.run([binary,'replace',str(source),str(saved),'1','0',replacement],check=True,capture_output=True)
    after_runs=json.loads(subprocess.check_output([binary,'inspect',str(saved)]))['pages'][0]['runs']
    assert after_runs[0]['text']==replacement
    assert after_runs[1:]==before_runs[1:],'CLI changed following text runs'
    with pymupdf.open(root/(name+'.pdf')) as doc:
        page=doc[0]
        expected='Students café — résumé tail' if name=='reportlab' else 'ABé AB'
        assert page.get_text().strip()==expected,(name,repr(page.get_text()))
        embedded=fonts(doc);assert embedded and all(embedded.values())
        original=mask(page.get_pixmap())
        native=mask(pymupdf.Pixmap(str(root/(name+'-native.png'))))
        assert len(original)==len(native)==612*792
        intersection=sum(a and b for a,b in zip(original,native))
        union=sum(a or b for a,b in zip(original,native))
        iou=intersection/union
        assert iou>= (0.80 if name=='reportlab' else 0.90),(name,iou)
        tail='tail' if name=='reportlab' else 'AB'
        before=page.search_for(tail)[-1]
        for suffix in ['-edited','-annotated','-cli']:
            with pymupdf.open(root/(name+suffix+'.pdf')) as changed:
                target=changed[0]
                replacement='café' if name=='reportlab' else 'é'
                assert target.get_text().startswith(replacement),(name,target.get_text())
                after=target.search_for(tail)[-1]
                # MuPDF rounds each PDF Widths entry to an integer. Predict the
                # resulting advance drift; PDFKit checks exact fractional positions.
                drift=rounded_advance_error(root/(name+suffix+'.pdf'))-rounded_advance_error(root/(name+'.pdf'))
                assert abs((after.x0-before.x0)-drift)<0.001,(name,before,after,drift)
                assert abs((after.x1-before.x1)-drift)<0.001
                assert abs(after.y0-before.y0)<0.001 and abs(after.y1-before.y1)<0.001
                assert fonts(changed)==embedded,'Embedded font bytes changed'
                if suffix=='-annotated':assert any(a.type[1]=='Square' for a in target.annots())
        page.get_pixmap().save(str(root/(name+'-independent.png')))
        print(f'PASS: {name} CLI/native edits, MuPDF text, embedded-byte preservation, edit geometry and raster overlap {iou:.3f}')

for path in sorted(root.glob('invalid-*.pdf')):
    result=subprocess.run([binary,'inspect',str(path)],capture_output=True,timeout=5)
    assert result.returncode==1,(path,result.returncode,result.stderr)
print('PASS: CLI rejects malformed embedded font fixtures without crashes')
