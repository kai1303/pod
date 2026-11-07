#!/usr/bin/env python3
"""Independent thread producer and saved relationship verifier; MuPDF is test-only."""
from pathlib import Path
import sys
import pymupdf

root = Path(sys.argv[1])
cases = ['note', 'highlight', 'review', 'no-view']
if '--fixtures' in sys.argv:
    root.mkdir(parents=True, exist_ok=True)
    for name in cases:
        doc = pymupdf.open()
        page = doc.new_page(width=400, height=400)
        mark = page.add_highlight_annot(pymupdf.Rect(40, 40, 180, 60)) if name == 'highlight' else page.add_text_annot((40, 40), 'Question ✓')
        mark.set_info(content='Question ✓', title='Teacher', subject='Evidence')
        mark.update()
        popup = doc.xref_get_key(mark.xref, 'Popup')
        if popup[0] == 'xref':
            doc.xref_set_key(int(popup[1].split()[0]), 'Open', 'true')
        child = page.add_text_annot((80, 100), 'First answer 中文')
        child.set_info(title='Student')
        child.update()
        doc.xref_set_key(child.xref, 'IRT', f'{mark.xref} 0 R')
        grandchild = page.add_text_annot((120, 160), 'Follow-up 😀')
        grandchild.set_info(title='Teacher')
        grandchild.update()
        doc.xref_set_key(grandchild.xref, 'IRT', f'{child.xref} 0 R')
        doc.xref_set_key(grandchild.xref, 'RT', '/R')
        if name == 'review':
            doc.xref_set_key(grandchild.xref, 'State', '(Accepted)')
            doc.xref_set_key(grandchild.xref, 'StateModel', '(Review)')
        if name == 'no-view':
            doc.xref_set_key(child.xref, 'F', '32')
            doc.xref_set_key(child.xref, 'Rect', '[0 0 0 0]')
        doc.save(root / f'{name}.pdf')
        doc.close()
    # Malformed parent relationships must fail instead of becoming independent notes.
    for name in ['cycle', 'orphan', 'cross-page', 'group', 'wrong-generation']:
        doc = pymupdf.open(root / 'note.pdf')
        marks = list(doc[0].annots())
        if name == 'cycle':
            doc.xref_set_key(marks[0].xref, 'IRT', f'{marks[2].xref} 0 R')
        elif name == 'group':
            doc.xref_set_key(marks[1].xref, 'RT', '/Group')
        elif name == 'wrong-generation':
            doc.xref_set_key(marks[1].xref, 'IRT', f'{marks[0].xref} 1 R')
        else:
            page = doc.new_page(width=400, height=400)
            foreign = page.add_text_annot((40, 40), 'Another page')
            doc.xref_set_key(marks[1].xref, 'IRT', f'{foreign.xref} 0 R')
            if name == 'orphan':
                doc.xref_set_key(page.xref, 'Annots', '[]')
        doc.save(root / f'{name}.pdf')
        doc.close()
    print('PASS: independent threaded comment and malformed relationship fixtures produced')
    sys.exit(0)

for name in cases:
    with pymupdf.open(root / f'{name}.pdf') as before, pymupdf.open(root / f'{name}-replied.pdf') as after:
        old = list(before[0].annots())
        marks = list(after[0].annots())
        assert len(marks) == 4
        for original, current in zip(old, marks):
            assert before.xref_object(original.xref) == after.xref_object(current.xref), (name, 'existing note changed')
        reply = marks[-1]
        assert reply.info['content'] == 'New reply — 已阅'
        assert reply.info['title'] == 'Học sinh 😀'
        assert after.xref_get_key(reply.xref, 'IRT')[1] == f'{marks[1].xref} 0 R'
        assert after.xref_get_key(reply.xref, 'RT')[1] == '/R'
        assert after.xref_get_key(reply.xref, 'AP')[0] == 'null'
    with pymupdf.open(root / f'{name}-extracted.pdf') as extracted:
        marks = list(extracted[0].annots())
        assert len(marks) == 4
        assert extracted.xref_get_key(marks[1].xref, 'IRT')[1] == f'{marks[0].xref} 0 R'
        assert extracted.xref_get_key(marks[2].xref, 'IRT')[1] == f'{marks[1].xref} 0 R'
        assert extracted.xref_get_key(marks[3].xref, 'IRT')[1] == f'{marks[1].xref} 0 R'
    with pymupdf.open(root / f'{name}-removed.pdf') as removed:
        assert len(list(removed[0].annots())) == 3
    print('PASS:', name, 'independent Unicode reply, unchanged existing dictionaries, parent links and extraction remapping')
