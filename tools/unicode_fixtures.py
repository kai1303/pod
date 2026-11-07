#!/usr/bin/env python3
"""ToUnicode source PDFs and CLI contract checks independent of the Zig parser."""
import json
from pathlib import Path
import random
import subprocess
import sys
import zlib
from font_fixtures import pdf

FONT = b'/BaseFont /Helvetica /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /fi /eacute] >>'
TEXT = b'BT /F1 16 Tf 1 0 0 1 72 700 Tm <4142434445464748> Tj ( tail) Tj ET'
PROGRAM = b'''/CIDInit /ProcSet findresource begin 12 dict begin
begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
/CMapName /Pod-Unicode def /CMapType 2 def
1 begincodespacerange <00> <ff> endcodespacerange
4 beginbfchar <41> <00660069> <42> <00650301> <43> <D83DDE00> <44> <0009000A0000> endbfchar
2 beginbfrange <45> <47> <0061> <48> <48> [<00660066>] endbfrange
endcmap CMapName currentdict /CMap defineresource pop end end'''

def stream(program, extra=b'', compressed=False):
    data = zlib.compress(program) if compressed else program
    return b'<< /Length ' + str(len(data)).encode() + extra + (b' /Filter /FlateDecode' if compressed else b'') + b' >>\nstream\n' + data + b'\nendstream'

def fixture(program=PROGRAM, compressed=False, base=None):
    objects = [stream(program,b' /UseCMap 7 0 R' if base else b'',compressed)]
    if base: objects.append(stream(base,compressed=True))
    return pdf(FONT+b' /ToUnicode 6 0 R',TEXT,objects)

def main(out, binary=None):
    out.mkdir(parents=True,exist_ok=True)
    (out/'plain.pdf').write_bytes(pdf(FONT,TEXT))
    expected = 'fie\u0301😀\t\n\x00abcff'
    cases = [('unicode',fixture(),expected,'fi😀'),
             ('compressed',fixture(compressed=True),expected,'fi😀'),
             ('inherited',fixture(b'begincmap /Pod-Unicode usecmap 1 beginbfchar <41> <006600660069> endbfchar endcmap',base=PROGRAM),'f'+expected,'ffi😀')]
    manifest = []
    for name, data, text, replacement in cases:
        path=out/(name+'.pdf'); path.write_bytes(data)
        manifest.append({'name':name,'text':text,'replacement':replacement})
        if binary:
            got=json.loads(subprocess.check_output([binary,'inspect',str(path)]))['pages'][0]['runs']
            assert got[0]['text']==text,got
            saved=out/(name+'-cli-edited.pdf')
            saved.unlink(missing_ok=True)
            subprocess.run([binary,'replace',str(path),str(saved),'1','0',replacement],check=True,capture_output=True)
            result=json.loads(subprocess.check_output([binary,'inspect',str(saved)]))['pages'][0]['runs']
            assert result[0]['text']==replacement,result
            assert abs(result[1]['x']-got[1]['x'])<1e-7
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False))
    invalid = {
        'surrogate': PROGRAM.replace(b'<D83DDE00>',b'<D83D0041>'),
        'range-overflow': PROGRAM.replace(b'<0061>',b'<00FF>'),
        'wrong-codespace': PROGRAM.replace(b'<00> <ff>',b'<0000> <00ff>'),
        'array-count': PROGRAM.replace(b'[<00660066>]',b'[]'),
        'operator': PROGRAM.replace(b'endcmap',b'(file) run endcmap'),
    }
    for name, program in invalid.items():
        path=out/('invalid-'+name+'.pdf'); path.write_bytes(fixture(program))
        if binary:
            result=subprocess.run([binary,'inspect',str(path)],capture_output=True)
            assert result.returncode==1,(name,result)
    if binary:
        rng=random.Random(5411)
        mutant=out/'mutation.pdf'
        for _ in range(128):
            program=bytearray(PROGRAM)
            for _ in range(rng.randint(1,5)):
                program[rng.randrange(len(program))]=rng.randrange(256)
            mutant.write_bytes(fixture(bytes(program)))
            result=subprocess.run([binary,'inspect',str(mutant)],capture_output=True,timeout=5)
            assert result.returncode in (0,1),(result.returncode,result.stderr)
            if result.returncode==0: json.loads(result.stdout)
        mutant.unlink()
        print('PASS: Unicode CLI extraction, JSON controls, editing, malformed maps and 128 parser mutations')
    print(out.resolve())

if __name__=='__main__': main(Path(sys.argv[1]),str(Path(sys.argv[2]).resolve()) if len(sys.argv)>2 else None)
