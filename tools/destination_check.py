#!/usr/bin/env python3
"""Independent qpdf destination/metadata preservation checks (validation only)."""
from pathlib import Path
import sys
import pikepdf


def name_tree(node):
    result = {}
    pairs = node.get('/Names', [])
    for i in range(0, len(pairs), 2):
        result[str(pairs[i])] = pairs[i+1]
    for child in node.get('/Kids', []):
        result.update(name_tree(child))
    return result


def check(path):
    with pikepdf.open(path) as pdf:
        assert not pdf.check_pdf_syntax(), path
        assert len(pdf.pages) == 2
        modern = name_tree(pdf.Root.Names.Dests)
        modes = ['/XYZ', '/Fit', '/FitH', '/FitV', '/FitR', '/FitB', '/FitBH', '/FitBV', '/FitH', '/XYZ', '/FitB']
        for i, link in enumerate(pdf.pages[0].Annots):
            target = link.Dest if '/Dest' in link else link.A.D
            if isinstance(target, pikepdf.Name):
                target = pdf.Root.Dests[str(target)]
            elif isinstance(target, pikepdf.String):
                target = modern[str(target)]
            if isinstance(target, pikepdf.Dictionary):
                target = target.D
            assert target[0].objgen == pdf.pages[1].obj.objgen, (path, i)
            assert str(target[1]) == modes[i], (path, i)
            assert str(link.NM) == f'destination-{i}', (path, i)
        assert pdf.pages[1].Annots[0].Dest[0].objgen == pdf.pages[0].obj.objgen
        print(path.name, 'all 11 destination targets and modes verified by qpdf')


if __name__ == '__main__':
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'test-out/links')
    if '--generate' in sys.argv:
        for linearized in [False, True]:
            name = 'destinations-linearized.pdf' if linearized else 'destinations-objstm.pdf'
            with pikepdf.open(out / 'destinations.pdf') as pdf:
                pdf.save(out / name, object_stream_mode=pikepdf.ObjectStreamMode.generate, linearize=linearized)
    for name in ['destinations.pdf', 'destinations-edited.pdf']:
        check(out / name)
