#!/usr/bin/env python3
"""Independent comment producer/preservation checks; MuPDF is test-only."""
from pathlib import Path
import subprocess,sys,json
import pymupdf
root=Path(sys.argv[1])
if '--fixtures' in sys.argv:
    doc=pymupdf.open(root/'sample.pdf')
    note=doc[0].add_text_annot((100,100),'Bài học ✓ 😀')
    note.set_info(title='Teacher',subject='Lesson',creationDate='D:20261106000000Z')
    note.update()
    doc.save(root/'mupdf.pdf')
    cases = {
        'ap-offset': '[1 0 0 1 70 -30]',
        'ap-scale': '[2 0 0 .5 0 0]',
        'ap-rotate': '[0 2 -3 0 200 100]',
        'ap-skew': '[1 .4 -.3 1 20 40]',
        'ap-reflect': '[-1 .2 .3 1 100 50]',
        'ap-state': '[1 0 0 1 0 0]',
        'ap-nested': '[1 .2 .3 1 0 0]',
        'ap-opacity': '[1 0 0 1 0 0]',
    }
    for name,matrix in cases.items():
        fixture=pymupdf.open(root/'sample.pdf')
        page=fixture[0]
        mark=page.add_text_annot((100,100),'Bài học ✓ 😀')
        mark.update()
        ap=int(fixture.xref_get_key(mark.xref,'AP/N')[1].split()[0])
        resources='<< /ColorSpace << /CS /DeviceRGB >> /ExtGState << /Half << /ca .5 >> >> >>'
        body=b'/CS cs 1 0 0 sc -100 -100 300 300 re f 0 0 1 sc 10 20 20 40 re f'
        if name=='ap-nested':
            child=fixture.get_new_xref()
            fixture.update_object(child,'<< /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 10 20] /Resources << >> >>')
            fixture.update_stream(child,b'0 0 1 rg 0 0 20 40 re f')
            resources=f'<< /XObject << /Child {child} 0 R >> >>'
            body=b'1 0 0 rg -100 -100 300 300 re f /Child Do'
        if name=='ap-opacity':
            body=b'/Half gs 1 0 0 rg -100 -100 300 300 re f'
            fixture.xref_set_key(mark.xref,'CA','.1')
        fixture.update_object(ap,f'<< /Type /XObject /Subtype /Form /BBox [10 20 50 60] /Matrix {matrix} /Resources {resources} >>')
        fixture.update_stream(ap,body)
        fixture.xref_set_key(mark.xref,'Rect','[100 500 160 540]')
        if name=='ap-state':
            fixture.xref_set_key(mark.xref,'AP',f'<< /N << /Subtype {ap} 0 R >> >>')
            fixture.xref_set_key(mark.xref,'AS','/Subtype')
        fixture.save(root/(name+'.pdf'))
        fixture.close()
    (root/'appearance-cases.json').write_text(json.dumps(['pdfkit','mupdf',*cases]))
    sys.exit(0)
for name in ['pod','pdfkit','mupdf']:
    with pymupdf.open(root/(name+'.pdf')) as before,pymupdf.open(root/(name+'-edited.pdf')) as after:
        old=next(before[0].annots());new=next(after[0].annots())
        assert old.info['content']=='Bài học ✓ 😀'
        assert new.info['content']=='Cần dẫn chứng — 已阅'
        for key in ['T','NM','Subj','CreationDate','M','State','StateModel','Name','Popup','IRT','Rect','F','C']:
            assert before.xref_get_key(old.xref,key)==after.xref_get_key(new.xref,key),(name,key)
        old_ap=int(before.xref_get_key(old.xref,'AP/N')[1].split()[0])
        new_ap=int(after.xref_get_key(new.xref,'AP/N')[1].split()[0])
        assert before.xref_stream(old_ap)==after.xref_stream(new_ap),(name,'appearance stream changed')
        assert before.xref_object(old_ap)==after.xref_object(new_ap),(name,'appearance resources changed')
        # Identical full independent renders verify saved icon/profile/clip
        # preservation independently of Pod's rasterizer.
        assert before[0].get_pixmap().samples==after[0].get_pixmap().samples,(name,'visible appearance changed')
        if name!='pod':
            for key in ['AP','Popup']:
                assert before.xref_get_key(old.xref,key)==after.xref_get_key(new.xref,key)
            with pymupdf.open(root/(name+'-removed.pdf')) as removed:
                assert not list(removed[0].annots() or [])
                assert removed.xref_get_key(removed[0].xref,'Annots')[1]=='[]'
        print('PASS:',name,'Unicode, metadata, appearance bytes/resources and unchanged independent rendering')

# Compare normal AP previews independently. Move only the annotation rectangle
# into a blank local page and use Stamp semantics to avoid viewer-specific Text
# icon substitution/NoZoom behavior; the AP stream/resources remain unchanged.
maximum_preview_error = 0.0
maximum_interior_error = 0
preview_count = 0
for name in json.loads((root/'appearance-cases.json').read_text()):
    for suffix in (['', '-edited'] if name in ['pdfkit','mupdf'] else ['']):
        doc = pymupdf.open(root/(name+suffix+'.pdf'))
        page = doc[0]
        note = next(page.annots())
        w,h = note.rect.width,note.rect.height
        ann_xref,page_xref = note.xref,page.xref
        doc.xref_set_key(ann_xref,'Subtype','/Stamp')
        doc.xref_set_key(ann_xref,'F','4')
        doc.xref_set_key(ann_xref,'Rect',f'[0 0 {w} {h}]')
        doc.xref_set_key(page_xref,'MediaBox',f'[0 0 {w} {h}]')
        doc.xref_set_key(page_xref,'CropBox','null')
        doc.xref_set_key(page_xref,'Rotate','0')
        empty=doc.get_new_xref();doc.update_object(empty,'<<>>');doc.update_stream(empty,b'')
        doc.xref_set_key(page_xref,'Contents',f'{empty} 0 R')
        reference=pymupdf.open(stream=doc.tobytes(),filetype='pdf')
        for width in [24,48,96]:
            expected=reference[0].get_pixmap(matrix=pymupdf.Matrix(width/w,width/w),alpha=False)
            actual=pymupdf.Pixmap(str(root/f'{name}{suffix}-appearance-{width}.png'))
            assert (actual.width,actual.height)==(expected.width,expected.height)
            observed=bytes(channel for i,channel in enumerate(actual.samples) if i%actual.n<3)
            reference_bytes=expected.samples
            delta=[abs(x-y) for x,y in zip(observed,reference_bytes)]
            mean=sum(delta)/len(delta)
            maximum_preview_error=max(maximum_preview_error,mean)
            interior_error=0
            def rgb(raw,x,y):
                at=(y*expected.width+x)*3
                return raw[at:at+3]
            for y in range(1,expected.height-1):
                for x in range(1,expected.width-1):
                    center=rgb(reference_bytes,x,y)
                    if all(rgb(reference_bytes,x+dx,y+dy)==center for dx in [-1,0,1] for dy in [-1,0,1]):
                        interior_error=max(interior_error,max(abs(u-v) for u,v in zip(center,rgb(observed,x,y))))
            maximum_interior_error=max(maximum_interior_error,interior_error)
            assert interior_error<=2,(name,suffix,width,'interior',interior_error)
            # Edge antialias error scales with perimeter / area; interiors must match.
            assert mean<5*24/width,(name,suffix,width,mean)
            preview_count+=1
        reference.close();doc.close()
        print('PASS:',name+suffix,'independent normal AP preview placement and color')
print(f'{preview_count} independent appearance previews; maximum mean channel error {maximum_preview_error:.6f}/255; maximum interior error {maximum_interior_error}/255')
