#!/usr/bin/env python3
"""Vertical-writing fixtures using test-only FontTools font programs."""
from pathlib import Path
import json, random, sys
from cid_font_fixtures import fixture
from truetype_fixtures import program
from encoding_cmap_fixtures import cmap_stream, MAP, UNICODE, CONTENT, SPACES

def main(root):
    root.mkdir(parents=True,exist_ok=True)
    font=program()
    custom=MAP.replace(b'/WMode 0',b'/WMode 1')
    parent=cmap_stream(custom.replace(b'/PodMixed',b'/PodBase')).replace(b'/CMapName /PodMixed',b'/CMapName /PodBase')
    child=b'begincmap /CMapName /PodMixed def /PodBase usecmap /WMode 1 def '+SPACES+b' endcmap'
    def mixed(data=custom,extra=b'',parents=(),content=CONTENT):
        return fixture(font,encoding=b'11 0 R',content=content,unicode_override=UNICODE,extra_objects=[cmap_stream(data,extra),*parents])
    cases={
        'default':fixture(font,encoding=b'/Identity-V'),
        'metrics':fixture(font,encoding=b'/Identity-V',cid_extra=b'/DW2 [900 -1100] /W2 [6 6 -950 250 800 2 [-1000 300 900 -1200 350 850]]'),
        'spacing':fixture(font,encoding=b'/Identity-V',content=b'BT /F1 24 Tf 3 Tc 80 Tw 50 Tz 5 Ts 1 0 0 1 72 700 Tm [<0002> 125 <00030006>] TJ <000100020003> Tj ET'),
        'rotated':fixture(font,encoding=b'/Identity-V',content=b'q 0 1 -1 0 500 0 cm BT /F1 24 Tf 1 0 0 1 72 400 Tm <000200030006> Tj <000100020003> Tj ET Q'),
        'upward':fixture(font,encoding=b'/Identity-V',content=b'BT /F1 24 Tf 1 0 0 1 72 400 Tm <000200030006> Tj <000100020003> Tj ET',cid_extra=b'/DW2 [880 1000]'),
        'range':fixture(font,encoding=b'/Identity-V',cid_extra=b'/W2 [1 3 -1100 -120 790]'),
        'highest-cid':fixture(font,True,encoding=b'/Identity-V',codes_override=[65533,65534,65535,32],cid_extra=b'/W2 [65533 [-1000 300 880 -1000 350 880 -1000 250 880]]'),
        'default-width':fixture(font,encoding=b'/Identity-V',widths=b'[]'),
        'mixed':mixed(),
        'inherited':mixed(child,b'/UseCMap 12 0 R',[parent]),
        'dictionary-mode':mixed(MAP.replace(b'/WMode 0 def',b''),b'/WMode 1'),
        'identity-base':fixture(font,encoding=b'11 0 R',extra_objects=[cmap_stream(b'begincmap /CMapName /PodMixed def /Identity-V usecmap /WMode 1 def endcmap',b'/UseCMap /Identity-V')]),
        'word-spacing':mixed(content=CONTENT.replace(b'24 Tf',b'24 Tf 3 Tc 8 Tw 75 Tz')),
    }
    for n,data in cases.items():(root/(n+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps([{'name':n,'text':'ABé','replacement':'é','tail':'B','vertical':True,'pdfkitGeometry':n!='upward','pdfkit':n not in ('mixed','inherited','dictionary-mode','word-spacing','identity-base')} for n in cases]))
    for n,extra in {'dw2-length':b'/DW2 [880]', 'w2-triple':b'/W2 [2 [-1000 300]]','w2-range':b'/W2 [6 2 -1000 300 880]','w2-overlap':b'/W2 [2 3 -1000 300 880 3 [-1000 300 880]]','w2-limit':b'/W2 [65535 [-1000 300 880 -1000 300 880]]','dw2-limit':b'/DW2 [1000001 -1000]','w2-value':b'/W2 [2 [ -1000 /Wrong 880]]'}.items():
        (root/('invalid-'+n+'.pdf')).write_bytes(fixture(font,encoding=b'/Identity-V',cid_extra=extra))
    for n,data in {'mode-conflict':mixed(MAP,b'/WMode 1'),'mode-range':mixed(custom.replace(b'/WMode 1',b'/WMode 2'))}.items():
        (root/('invalid-'+n+'.pdf')).write_bytes(data)
    rng=random.Random(5017)
    for i in range(64):
        values=[rng.choice([-1000001,-1000,0,880,1000001,b'/Wrong']) for _ in range(rng.randrange(1,10))]
        extra=b'/W2 [2 ['+b' '.join(v if isinstance(v,bytes) else str(v).encode() for v in values)+b']]'
        (root/f'mutation-{i}.pdf').write_bytes(fixture(font,encoding=b'/Identity-V',cid_extra=extra))
    print(root.resolve())
if __name__=='__main__':main(Path(sys.argv[1]))
