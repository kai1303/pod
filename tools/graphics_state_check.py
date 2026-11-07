#!/usr/bin/env python3
"""Independent graphics-state fixtures and compositing checks; test-only producers/readers."""
import json, math, shutil, subprocess, sys
from pathlib import Path
from link_fixtures import serialize

ROOT = Path(sys.argv[1])
STATES = b'''<<
 /Half << /Type /ExtGState /ca 0.5 /CA 0.25 /LW 20 /LC 2 /LJ 1 /ML 3 >>
 /Multiply << /BM /Multiply >> /Normal << /BM [/Normal /Multiply] >>
 /Opaque << /ca 1 /CA 1 >> /Zero << /ca 0 /CA 0 >>
 /NoStroke << /CA 0 >> /NoKnockout << /TK false >> /Knockout << /TK true >>
 /Font << /Font [4 0 R 100] >> /Thin << /LW 4 /LC 0 /LJ 2 /ML 1 >>
 /Safe << /OP false /op false /OPM 0 /AIS false /SA false /SMask /None /RI /RelativeColorimetric /D [[] 0] >>
>>'''
BG = '0.2 0.4 0.8 rg 0 0 612 600 re f '
RECT = '1 0 0 rg 0 1 0 RG 100 100 200 200 re '
TEXT = '/Font gs BT 1 0 0 1 100 300 Tm (B) Tj 1 0 0 1 130 300 Tm (B) Tj ET '
CASES = {
 'fill-alpha': BG + '/Half gs 1 0 0 rg 100 100 300 300 re f 200 200 300 300 re f',
 'multiply': BG + '/Half gs /Multiply gs 0.8 0.3 0.5 rg 100 100 300 300 re f /Normal gs 300 300 200 200 re f',
 'zero-alpha': BG + '/Zero gs ' + RECT + 'B',
 'zero-stroke-knockout': BG + '/Half gs /NoStroke gs ' + RECT + 'B',
 'saved-state': BG + '/Half gs ' + RECT + 'B q /Opaque gs /Multiply gs /Thin gs ' + RECT.replace('100 100','340 100') + 'B Q ' + RECT.replace('100 100','100 350') + 'B',
 'line-settings': BG + '/Half gs 0 1 0 RG 100 100 m 200 400 l 300 100 l S q /Thin gs 350 100 m 450 400 l 550 100 l S Q 100 500 m 500 500 l S',
 'clip': BG + '120 120 180 180 re W n /Half gs ' + RECT + 'B',
 'text-knockout': BG + '/Half gs 1 0 0 rg ' + TEXT,
 'text-composite': BG + '/Half gs /NoKnockout gs 1 0 0 rg ' + TEXT,
 'text-multiply': BG + '/Half gs /Multiply gs 1 0 0 rg ' + TEXT,
 'text-distinct-objects': BG + '/Half gs /Font gs 1 0 0 rg BT 1 0 0 1 100 300 Tm (B) Tj ET BT 1 0 0 1 130 300 Tm (B) Tj ET',
 'text-state-changes': BG + '/Font gs BT 1 0 0 rg 1 0 0 1 100 300 Tm (B) Tj /Half gs 0 1 0 rg 1 0 0 1 130 300 Tm (B) Tj ET',
 'text-zero-knockout': BG + '/Font gs BT 1 0 0 rg 1 0 0 1 100 300 Tm (B) Tj /Zero gs 1 0 0 1 130 300 Tm (B) Tj ET',
 'safe-state': BG + '/Safe gs /RelativeColorimetric ri /Half gs ' + RECT + 'B',
}
for op in ['B','B*','b','b*']:
 CASES['combined-'+op.replace('*','star')] = BG + '/Half gs ' + RECT + op
CASES['split-streams'] = BG + 'q /Half gs ' + RECT + 'B Q 1 0 0 rg 400 100 100 100 re f'
CASES['indirect-state'] = BG + '/Half gs ' + RECT + 'B'
CASES['opaque-text'] = BG + '1 0 0 rg ' + TEXT
INVALID = {
 'missing': ('/Absent gs', STATES),
 'resource-type': ('/Half gs', b'12'),
 'entry-type': ('/Bad gs', b'<< /Bad 4 >>'),
 'alpha-type': ('/Bad gs', b'<< /Bad << /ca /bad >> >>'),
 'alpha-range': ('/Bad gs', b'<< /Bad << /CA 1.1 >> >>'),
 'knockout-in-text': ('BT /Bad gs ET', b'<< /Bad << /TK false >> >>'),
 'soft-mask': ('/Bad gs', b'<< /Bad << /SMask << /S /Alpha >> >> >>'),
 'blend': ('/Bad gs', b'<< /Bad << /BM /Unregistered >> >>'),
 'blend-fallback': ('/Bad gs', b'<< /Bad << /BM [/Screen 123] >> >>'),
 'overprint': ('/Bad gs', b'<< /Bad << /OP true >> >>'),
 'alpha-shape': ('/Bad gs', b'<< /Bad << /AIS true >> >>'),
 'dash': ('/Bad gs', b'<< /Bad << /D [[-3 2] 0] >> >>'),
 'font-size': ('/Bad gs', b'<< /Bad << /Font [4 0 R -1] >> >>'),
 'intent': ('/Bad gs', b'<< /Bad << /RI /Perceptual >> >>'),
 'path-in-text': ('BT 0 0 10 10 re f ET', STATES),
}

def fixtures():
 from truetype_fixtures import program, stream
 font = program()
 def pdf(content, states, name=''):
  objects = [
   b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
   b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> /ExtGState 8 0 R >> /Contents 5 0 R >>',
   b'<< /Type /Font /Subtype /TrueType /BaseFont /PodFixture-Regular /FirstChar 65 /LastChar 66 /Widths [600 700] /Encoding /WinAnsiEncoding /FontDescriptor 6 0 R >>',
   stream(content.encode()),
   b'<< /Type /FontDescriptor /FontName /PodFixture-Regular /Flags 32 /FontBBox [0 -200 700 800] /Ascent 800 /Descent -200 /CapHeight 700 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>',
   stream(font), states,
  ]
  if name=='split-streams':
   before,after=content.split('1 0 0 rg',1)
   objects[2]=objects[2].replace(b'/Contents 5 0 R',b'/Contents [5 0 R 9 0 R]')
   objects[4]=stream(before.encode())
   objects.append(stream(('1 0 0 rg'+after).encode()))
  elif name=='indirect-state':
   objects[7]=b'<< /Half 9 0 R >>'
   objects += [b'<< /ca 10 0 R /CA 11 0 R /LW 20 /LC 2 /LJ 1 >>',b'0.5',b'0.25']
  return serialize(objects)
 ROOT.mkdir(parents=True, exist_ok=True)
 for name, content in CASES.items(): (ROOT / (name+'.pdf')).write_bytes(pdf(content,STATES,name))
 (ROOT/'invalid').mkdir(exist_ok=True)
 for name,(content,states) in INVALID.items(): (ROOT/'invalid'/ (name+'.pdf')).write_bytes(pdf(content,states))
 (ROOT/'cases.json').write_text(json.dumps(list(CASES)))

if '--fixtures' in sys.argv:
 fixtures()
 raise SystemExit(0)

import numpy as np
import pymupdf

def reference_pixels(doc, name, width, suffix):
 # PDF 1.7 sections 5.2.7 and 7.6.2 define implicit knockout groups. MuPDF
 # 1.26.5 misses some text-object boundaries and skips zero-alpha painting.
 # Ghostscript 10.02.1 handles ordinary TK and transparent borders, but flushes
 # text groups on graphics-state changes and skips zero-alpha glyphs as well.
 # For the latter two, compare to an equivalent explicit knockout Form group.
 special = {'text-knockout', 'text-state-changes', 'text-zero-knockout', 'zero-stroke-knockout'}
 if name not in special:
  return doc[0].get_pixmap(matrix=pymupdf.Matrix(width/doc[0].rect.width,width/doc[0].rect.width),alpha=False)
 gs=shutil.which('gs')
 if not gs: raise RuntimeError('Graphics-state tests require Ghostscript')
 if name in {'text-state-changes','text-zero-knockout'}:
  page=doc[0];stream=doc.xref_stream(page.get_contents()[0]);split=stream.index(b're f ')+5
  background,content=stream[:split],stream[split:]
  if name=='text-state-changes':
   content=content.replace(b'(B) Tj',b'(B) Tj ET BT')
  else:
   # FontTools fixture B has the rectangular outline (40,0)..(600,700).
   # At size 100 these are exactly the two glyph shapes in the source PDF.
   content=b'1 0 0 rg 104 300 56 70 re f /Zero gs 134 300 56 70 re f'
  ref=doc.get_new_xref()
  doc.update_object(ref,'<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Group << /S /Transparency /I false /K true /CS /DeviceRGB >> /Resources '+doc.xref_get_key(page.xref,'Resources')[1]+' >>')
  doc.update_stream(ref,content)
  doc.xref_set_key(page.xref,'Resources/XObject/Knockout',f'{ref} 0 R')
  doc.update_stream(page.get_contents()[0],background+b'/Knockout Do')
 refs=ROOT/'references';refs.mkdir(exist_ok=True)
 path=refs/f'{name}{suffix}-{width}.pdf';png=path.with_suffix('.png')
 # Reference rewrites are test artifacts only, never the source/saved outputs.
 path.write_bytes(doc.tobytes())
 scale=width/doc[0].rect.width;height=math.ceil(doc[0].rect.height*scale)
 subprocess.run([gs,'-q','-dSAFER','-dBATCH','-dNOPAUSE','-dUseCropBox','-dFIXEDMEDIA',
                 '-sDEVICE=png16m','-dGraphicsAlphaBits=4','-dTextAlphaBits=4',f'-r{scale*72}',
                 f'-g{width}x{height}','-sOutputFile='+str(png),str(path)],check=True)
 return pymupdf.Pixmap(str(png))

worst_mean = 0.0
for name in CASES:
 for suffix in ['', '-saved', '-annotated', '-rotated']:
  with pymupdf.open(ROOT/(name+suffix+'.pdf')) as doc:
   for width in [612,1224]:
    # Use a separate document because reference group expansion must not mutate
    # the next width's input or the saved-appearance preservation check.
    with pymupdf.open(ROOT/(name+suffix+'.pdf')) as reference_doc:
     reference=reference_pixels(reference_doc,name,width,suffix)
    actual=pymupdf.Pixmap(str(ROOT/f'{name}{suffix}-{width}.png'))
    expected=np.frombuffer(reference.samples,np.uint8).reshape(reference.height,reference.width,3).astype(np.int16)
    observed=np.frombuffer(actual.samples,np.uint8).reshape(actual.height,actual.width,actual.n)[:,:,:3].astype(np.int16)
    error=np.abs(observed-expected)
    mean=float(error.mean());worst_mean=max(worst_mean,mean)
    assert mean < 1.5, (name,suffix,width,mean)
    # Interior probes detect wrong opacity/blend/knockout even for small glyphs.
    if suffix != '-rotated':
     for x,y in [(140,330),(110,330),(175,330),(105,200),(200,200),(450,450)]:
      scale=width/612;px,py=int(x*scale),int((792-y)*scale)
      delta=error[py-1:py+2,px-1:px+2].max()
      assert delta<=3,(name,suffix,width,x,y,int(delta),observed[py,px],expected[py,px])
   if suffix=='-saved':
    with pymupdf.open(ROOT/(name+'.pdf')) as original:
     assert original[0].get_pixmap().samples==doc[0].get_pixmap().samples, (name,'save changed appearance')
 print('PASS:',name,'independent compositing, saved appearance, annotation isolation and crop/rotation')
print(f'{len(CASES)*8} independent rasters: maximum mean channel error {worst_mean:.6f}/255')
