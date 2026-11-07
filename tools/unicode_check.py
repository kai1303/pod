#!/usr/bin/env python3
"""Independent MuPDF validation only; never imported by Pod's engine or app."""
from pathlib import Path
import json
import sys
import pymupdf

root=Path(sys.argv[1])
cases=json.loads((root/'manifest.json').read_text())
with pymupdf.open(root/'plain.pdf') as plain:
    baseline=plain[0].get_pixmap().samples
for case in cases:
    name=case['name']
    with pymupdf.open(root/(name+'.pdf')) as original:
        page=original[0]
        assert page.get_text()==case['text']+' tail\n',(name,repr(page.get_text()))
        assert page.get_pixmap().samples==baseline,'Unicode map changed visible glyphs'
        tail=page.search_for('tail')
        assert len(tail)==1
        for suffix in ['-cli-edited','-annotated']:
            with pymupdf.open(root/(name+suffix+'.pdf')) as edited:
                result=edited[0]
                assert result.get_text().startswith(case['replacement']),(name,repr(result.get_text()))
                saved_tail=result.search_for('tail')
                assert len(saved_tail)==1
                assert max(abs(a-b) for a,b in zip(tail[0],saved_tail[0]))<0.001,(tail,saved_tail)
                if suffix=='-annotated': assert any(a.type[1]=='Highlight' for a in result.annots())
    print('PASS: independent MuPDF',name,'Unicode, unchanged original glyphs, CLI/native edits, annotations and positions')
print('MuPDF validation version:',pymupdf.VersionBind)
