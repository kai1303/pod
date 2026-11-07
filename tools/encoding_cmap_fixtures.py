#!/usr/bin/env python3
from pathlib import Path
import json, random, sys
from cid_font_fixtures import fixture
from truetype_fixtures import program, stream

SPACES=b'4 begincodespacerange <00> <7f> <8100> <81ff> <900000> <9000ff> <a0000000> <a00000ff> endcodespacerange'
MAP=b'begincmap /CMapName /PodMixed def /CMapType 1 def /WMode 0 def '+SPACES+b' 5 begincidchar <20> 1 <41> 2 <8142> 3 <900001> 6 <a0000001> 2 endcidchar endcmap'
UNICODE=b'begincmap '+SPACES+b' 5 beginbfchar <20> <0020> <41> <0041> <8142> <0042> <900001> <00e9> <a0000001> <0041> endbfchar endcmap'
CONTENT=b'BT /F1 24 Tf 1 0 0 1 72 700 Tm <418142900001> Tj <20a00000018142> Tj ET'
def cmap_stream(data,extra=b''):
    data=b'/CIDInit /ProcSet findresource begin 12 dict begin\n'+data.replace(b'begincmap',b'begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def /CMapVersion 1 def',1)+b'\nCMapName currentdict /CMap defineresource pop end end'
    return stream(data).replace(b'<< ',b'<< /Type /CMap /CMapName /PodMixed /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '+extra+b' ',1)
def make(font,data=MAP,extra=b'',parents=(),content=CONTENT):
    return fixture(font,encoding=b'11 0 R',content=content,unicode_override=UNICODE,extra_objects=[cmap_stream(data,extra),*parents])
def main(root):
    root.mkdir(parents=True,exist_ok=True)
    font=program()
    ranges=b'begincmap /CMapName /PodMixed def /CMapType 1 def '+SPACES+b' 5 begincidrange <20> <20> 1 <40> <41> 1 <8141> <8142> 2 <900001> <900001> 6 <a0000001> <a0000001> 2 endcidrange endcmap'
    base=MAP.replace(b'/PodMixed',b'/PodBase').replace(b'<41> 2',b'<41> 3')
    parent=cmap_stream(base).replace(b'/CMapName /PodMixed',b'/CMapName /PodBase')
    child=b'begincmap /CMapName /PodMixed def /PodBase usecmap '+SPACES+b' 1 begincidchar <41> 2 endcidchar endcmap'
    fallback=MAP.replace(b'5 begincidchar <20> 1',b'4 begincidchar').replace(b'endcmap',b'1 beginnotdefrange <20> <20> 1 endnotdefrange endcmap')
    rectangle_space=b'1 begincodespacerange <8140> <8242> endcodespacerange'
    rectangle_map=b'begincmap /CMapName /PodMixed def /CMapType 1 def '+rectangle_space+b' 1 begincidrange <8140> <8242> 1 endcidrange endcmap'
    rectangle_unicode=b'begincmap '+rectangle_space+b' 4 beginbfchar <8140> <0020> <8141> <0041> <8142> <0042> <8242> <00e9> endbfchar endcmap'
    cases={
        'rectangle':fixture(font,True,codes_override=[2,3,259,1],encoding=b'11 0 R',content=b'BT /F1 24 Tf 1 0 0 1 72 700 Tm <814181428242> Tj <814081418142> Tj ET',unicode_override=rectangle_unicode,extra_objects=[cmap_stream(rectangle_map)]),
        'identity-base':fixture(font,encoding=b'11 0 R',extra_objects=[cmap_stream(b'begincmap /CMapName /PodMixed def /CMapType 1 def /Identity-H usecmap endcmap',b'/UseCMap /Identity-H')]),

        'two-byte':fixture(font,encoding=b'11 0 R',extra_objects=[cmap_stream(b'begincmap /CMapName /PodMixed def /CMapType 1 def /WMode 0 def 1 begincodespacerange <0000> <ffff> endcodespacerange 1 begincidrange <0000> <ffff> 0 endcidrange endcmap')]),
        'mixed':make(font),
        'ranges':make(font,ranges),
        'override':make(font,MAP.replace(b'<41> 2',b'<41> 3').replace(b'endcmap',b'1 begincidchar <41> 2 endcidchar endcmap')),
        'inherited':make(font,child,b'/UseCMap 12 0 R',[parent]),
        'notdef':make(font,fallback),
        'word-spacing':make(font,content=CONTENT.replace(b'24 Tf',b'24 Tf 3 Tc 8 Tw 75 Tz')),
    }
    for name,data in cases.items():(root/(name+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps([{'name':n,'text':'ABé','replacement':'é','tail':'AB','pdfkit':n in ('two-byte','rectangle'),'pdfkitGeometry':n!='rectangle','oracle':'ghostscript' if n=='notdef' else 'mupdf'} for n in cases]))
    bad={
        'prefix-overlap':make(font,MAP.replace(b'<00> <7f>',b'<00> <ff>')),
        'out-of-space':make(font,MAP.replace(b'<41> 2',b'<ff> 2')),
        'cid-overflow':make(font,ranges.replace(b'<40> <41> 1',b'<40> <41> 65535')),
        'count':make(font,MAP.replace(b'5 begincidchar',b'6 begincidchar')),
        'operator':make(font,MAP.replace(b'endcmap',b'(file) run endcmap')),
        'truncated-code':make(font,content=CONTENT.replace(b'418142900001',b'4181429000')),
        'cycle':make(font,child,b'/UseCMap 11 0 R'),
        'name':make(font,MAP.replace(b'/PodMixed',b'/Wrong')),
    }
    for name,data in bad.items():(root/('invalid-'+name+'.pdf')).write_bytes(data)
    (root/'unsupported-vertical.pdf').unlink(missing_ok=True)
    (root/'invalid-writing-mode.pdf').write_bytes(make(font,MAP.replace(b'/WMode 0',b'/WMode 2')))
    rng=random.Random(5016)
    for i in range(64):
        mutated=bytearray(MAP)
        for _ in range(rng.randint(1,4)):mutated[rng.randrange(len(mutated))]=rng.randrange(256)
        (root/f'mutation-{i}.pdf').write_bytes(make(font,bytes(mutated)))
    print(root.resolve())
if __name__=='__main__':main(Path(sys.argv[1]))
