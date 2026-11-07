#!/usr/bin/env python3
"""Whole-page comment compositing oracle; PyMuPDF is a test-only dependency."""
from pathlib import Path
import sys
import pymupdf

root = Path(sys.argv[1])
if '--fixtures' in sys.argv:
    doc = pymupdf.open()
    page = doc.new_page(width=200, height=160)
    stream = doc.get_new_xref()
    doc.update_object(stream, '<<>>')
    doc.update_stream(stream, b'0 1 1 rg 0 0 200 160 re f .2 .4 .8 rg 60 40 80 70 re f 0 0 1 1 re W n')
    doc.xref_set_key(page.xref, 'Contents', f'{stream} 0 R')
    for rect, matrix, body in [
        ('[50 60 90 84]', '[1 .2 -.3 1 20 40]', b'/Half gs 1 0 0 rg -100 -100 300 300 re f /Full gs 0 0 1 rg 10 32 20 12 re f'),
        ('[65 54 95 74]', '[1 0 0 1 0 0]', b'/Multiply gs .8 .6 .2 rg 10 20 40 24 re f'),
    ]:
        note = page.add_text_annot((50,50), 'Fixed comment')
        note.update()
        ap = int(doc.xref_get_key(note.xref, 'AP/N')[1].split()[0])
        doc.update_object(ap, f'<< /Subtype /Form /BBox [10 20 50 44] /Matrix {matrix} /Resources << /ExtGState << /Half << /ca .5 >> /Full << /ca 1 >> /Multiply << /ca .7 /BM /Multiply >> >> >> >>')
        doc.update_stream(ap, body)
        doc.xref_set_key(note.xref, 'Rect', rect)
        doc.xref_set_key(note.xref, 'F', '4')
        doc.xref_set_key(note.xref, 'CA', '.1')
    doc.xref_set_key(page.xref, 'CropBox', '[20 10 180 150]')
    doc.xref_set_key(page.xref, 'Rotate', '90')
    doc.save(root/'page-view.pdf')
    for note, name in zip(list(page.annots()), ['Note', 'Help']):
        doc.xref_set_key(note.xref, 'AP', 'null')
        doc.xref_set_key(note.xref, 'Name', '/'+name)
        doc.xref_set_key(note.xref, 'CA', '.6')
    doc.save(root/'page-view-no-ap.pdf')
    sys.exit(0)

# Use Stamp semantics to keep the exact AP rather than a reader's Text icon.
# Rect resizing supplies NoZoom explicitly, while MuPDF handles NoRotate and AP
# mapping/compositing. Analytic Zig tests separately prove fixed size and anchors.
maximum_mean = 0.0
maximum_interior = 0
count = 0
for rotation in [0,90,180,270]:
    for zoom in [.5,1,2]:
        doc = pymupdf.open(root/'page-view.pdf')
        page = doc[0]
        page.set_rotation((90+rotation)%360)
        for note in list(page.annots()):
            x0,y0,x1,y1 = map(float,doc.xref_get_key(note.xref,'Rect')[1].strip('[]').split())
            doc.xref_set_key(note.xref,'Subtype','/Stamp')
            doc.xref_set_key(note.xref,'F','20')
            doc.xref_set_key(note.xref,'Rect',f'[{x0} {y1-(y1-y0)/zoom} {x0+(x1-x0)/zoom} {y1}]')
        reference = pymupdf.open(stream=doc.tobytes(),filetype='pdf')
        for density in [1,2]:
            expected = reference[0].get_pixmap(matrix=pymupdf.Matrix(zoom*density,zoom*density),alpha=False)
            name = f'page-view-r{rotation}-z{zoom:g}-d{density}'
            actual = pymupdf.Pixmap(str(root/(name+'.png')))
            expected.save(root/(name+'-reference.png'))
            assert (actual.width,actual.height)==(expected.width,expected.height), name
            observed = bytes(v for i,v in enumerate(actual.samples) if i%actual.n<3)
            target = expected.samples
            mean = sum(abs(x-y) for x,y in zip(observed,target))/len(target)
            interior = 0
            def rgb(data,x,y):
                at=(y*expected.width+x)*3
                return data[at:at+3]
            for y in range(1,expected.height-1):
                for x in range(1,expected.width-1):
                    value = rgb(target,x,y)
                    if all(rgb(target,x+dx,y+dy)==value for dx in [-1,0,1] for dy in [-1,0,1]):
                        interior=max(interior,max(abs(a-b) for a,b in zip(value,rgb(observed,x,y))))
            assert interior<=2,(name,'interior',interior,mean)
            assert mean<1,(name,'mean',mean)
            maximum_mean=max(maximum_mean,mean)
            maximum_interior=max(maximum_interior,interior)
            count+=1
        reference.close();doc.close()
print(f'{count} independent page views; maximum mean error {maximum_mean:.6f}/255; maximum interior error {maximum_interior}/255')
