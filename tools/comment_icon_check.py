#!/usr/bin/env python3
"""Test-only producer and independent preservation checks for missing-AP notes."""
from pathlib import Path
import sys
import pymupdf

root=Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
names=['Note','Comment','Key','Help','NewParagraph','Paragraph','Insert','Unknown','Default']
if '--fixtures' in sys.argv:
    for name in names:
        doc=pymupdf.open();page=doc.new_page(width=160,height=160)
        body=doc.get_new_xref();doc.update_object(body,'<<>>')
        doc.update_stream(body,b'.2 .4 .8 rg 0 0 160 160 re f')
        doc.xref_set_key(page.xref,'Contents',f'{body} 0 R')
        note=page.add_text_annot((40,60),'Fixed comment')
        note.set_info(title='Teacher',subject='Fallback icon')
        note.update()
        doc.xref_set_key(note.xref,'Rect','[40 60 64 84]')
        doc.xref_set_key(note.xref,'Name','null' if name=='Default' else '/'+name)
        # Omit optional Name entirely for the default icon.
        if name=='Default':
            doc.update_object(note.xref,doc.xref_object(note.xref).replace('/Name null',''))
        doc.xref_set_key(note.xref,'AP','null')
        doc.xref_set_key(note.xref,'C','[.2 .8 .4]')
        doc.xref_set_key(note.xref,'CA','.5')
        page.set_rotation(90)
        doc.save(root/(name+'.pdf'));doc.close()
    sys.exit(0)
for name in names:
    with pymupdf.open(root/(name+'.pdf')) as before,pymupdf.open(root/(name+'-edited.pdf')) as after:
        old=next(before[0].annots());new=next(after[0].annots())
        assert old.info['content']=='Fixed comment'
        assert new.info['content']=='Fallback note ✓'
        for key in ['AP','Name','Rect','C','CA','F','T','Subj','Popup','NM']:
            assert before.xref_get_key(old.xref,key)==after.xref_get_key(new.xref,key),(name,key)
        assert after.xref_get_key(new.xref,'AP')[0]=='null'
        assert before[0].rotation==after[0].rotation==90
        # MuPDF is free to draw different icon artwork, but a note-only edit must
        # not change its independently rendered page or icon.
        assert before[0].get_pixmap().samples==after[0].get_pixmap().samples,name
        print('PASS:',name,'independent Unicode note, metadata, absent AP and rendered preservation')
