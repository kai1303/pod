#!/usr/bin/env python3
"""Independent popup fixtures and preservation checks. MuPDF is test-only."""
from pathlib import Path
import sys
import pymupdf

root = Path(sys.argv[1])
cases = ['open', 'closed', 'parentless', 'unpaired', 'rich']
if '--fixtures' in sys.argv:
    root.mkdir(parents=True, exist_ok=True)
    for name in cases:
        doc = pymupdf.open()
        page = doc.new_page(width=400, height=400)
        note = page.add_text_annot((50, 50), 'Original note ✓')
        note.set_info(title='Cô giáo 😀', subject='Bài học — 中文')
        note.update()
        doc.xref_set_key(note.xref, 'Open', 'true')
        popup = int(doc.xref_get_key(note.xref, 'Popup')[1].split()[0])
        doc.xref_set_key(popup, 'Rect', '[90 100 290 240]')
        doc.xref_set_key(popup, 'Open', 'false' if name == 'closed' else 'true')
        if name == 'parentless':
            doc.xref_set_key(popup, 'Parent', 'null')
        if name == 'unpaired':
            doc.xref_set_key(note.xref, 'Popup', 'null')
            doc.xref_set_key(page.xref, 'Annots', f'[{note.xref} 0 R]')
        if name == 'rich':
            doc.xref_set_key(note.xref, 'RC', '(<body>Original note</body>)')
        doc.save(root / f'{name}.pdf')
        doc.close()
    print('PASS: independent popup fixtures produced')
    sys.exit(0)

for name in cases:
    with pymupdf.open(root / f'{name}.pdf') as before, pymupdf.open(root / f'{name}-saved.pdf') as after:
        old = next(before[0].annots())
        new = next(after[0].annots())
        assert new.info['content'] == ('Original note ✓' if name == 'rich' else 'Edited note — 已阅')
        for key in ['T', 'Subj', 'Popup', 'Open', 'RC', 'Rect', 'F', 'AP']:
            assert before.xref_get_key(old.xref, key) == after.xref_get_key(new.xref, key), (name, key)
        popup_ref = before.xref_get_key(old.xref, 'Popup')
        if popup_ref[0] == 'xref':
            popup = int(popup_ref[1].split()[0])
            assert before.xref_object(popup) == after.xref_object(popup), name
        assert before[0].get_pixmap().samples == after[0].get_pixmap().samples, name
        print('PASS:', name, 'independent Unicode, popup state/rectangle/parent and appearance preservation')
