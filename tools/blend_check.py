#!/usr/bin/env python3
"""All standard RGB PDF blend modes, with independent test-only readers/producers."""
import json, math, shutil, subprocess, sys
from pathlib import Path
from link_fixtures import serialize

ROOT=Path(sys.argv[1])
MODES=['Normal','Multiply','Screen','Overlay','Darken','Lighten','ColorDodge','ColorBurn','HardLight','SoftLight','Difference','Exclusion','Hue','Saturation','Color','Luminosity']
COLORS=[(0,0,0),(255,255,255),(255,0,0),(0,255,0),(0,0,255),(0,255,255),(255,0,255),(255,255,0),(64,64,64),(128,128,128),(192,192,192),(51,102,204),(230,102,153),(1,254,128),(64,128,191),(254,1,0)]
CASES=[dict(name=mode+'-'+str(alpha),mode=mode,alpha=alpha,bm='/'+mode) for mode in MODES for alpha in [1,0.37]]
CASES += [dict(name=name,mode=mode,alpha=0.37,bm=bm) for name,mode,bm in [
 ('fallback-first','Screen','[/Future /Screen /Multiply]'),
 ('fallback-none','Normal','[/Future /Unregistered]'),
 ('fallback-empty','Normal','[]'),
 ('compatible','Normal','/Compatible'),
 ('fallback-indirect','Screen','[8 0 R /Multiply]'),
]]
CASES.append(dict(name='reportlab-mixed',mode='mixed',alpha=0.37,producer='reportlab'))

# Keep non-endpoint fixture colors away from differing round/truncate byte
# boundaries in independent readers; exact black/white still test singularities.
def rgb(color): return ' '.join(f'{(v+(0.25 if 0<v<255 else 0))/255:.12f}' for v in color)+' rg '
GLYPH_BACKGROUND=rgb((51,102,204))+'330 80 150 110 re f '
GLYPH_TEXT='/Blend gs BT /F1 100 Tf 1 0 0 1 340 100 Tm (B) Tj 1 0 0 1 370 100 Tm (B) Tj ET '
GLYPH_SECTION='q '+GLYPH_BACKGROUND+GLYPH_TEXT+'Q\n'

def fixtures():
 from truetype_fixtures import program,stream
 font=program()
 ROOT.mkdir(parents=True,exist_ok=True)
 for case in CASES:
  if case.get('producer')=='reportlab':
   from reportlab.pdfgen import canvas
   c=canvas.Canvas(str(ROOT/(case['name']+'.pdf')),pagesize=(612,792),pageCompression=1)
   for row,mode in enumerate(MODES):
    for col,fg in enumerate(COLORS):
     x,y=48+col*30,250+row*30
     c.saveState()
     c.setFillColorRGB(*[float(v) for v in rgb(COLORS[(row+col)%16]).split()[:3]])
     c.rect(x,y,30,30,stroke=0,fill=1)
     c.setBlendMode(mode);c.setFillAlpha(0.37 if col%2 else 1)
     c.setFillColorRGB(*[float(v) for v in rgb(fg).split()[:3]])
     c.rect(x+4,y+4,22,22,stroke=0,fill=1)
     c.restoreState()
   c.showPage();c.save()
   continue
  content=''
  for row,bg in enumerate(COLORS):
   for col,fg in enumerate(COLORS):
    x,y=48+col*30,250+row*30
    content+='q '+rgb(bg)+f'{x} {y} 30 30 re f /Blend gs '+rgb(fg)+f'{x+4} {y+4} 22 22 re f Q\n'
  # Exercise the same blend mode through stroke expansion, combined knockout,
  # clipping, and overlapping embedded glyphs, beyond the large color grid.
  content+='q '+rgb((51,102,204))+'60 80 200 110 re f 70 90 180 90 re W n /Blend gs 18 w 1 0 0 RG 0 1 0 rg 90 110 120 40 re B Q\n'
  content+=GLYPH_SECTION
  data=serialize([
   b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
   ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> /ExtGState << /Blend << /BM '+case['bm']+' /ca '+str(case['alpha'])+' /CA '+str(case['alpha'])+' >> >> >> /Contents 5 0 R >>').encode(),
   b'<< /Type /Font /Subtype /TrueType /BaseFont /PodFixture-Regular /FirstChar 65 /LastChar 66 /Widths [600 700] /Encoding /WinAnsiEncoding /FontDescriptor 6 0 R >>',
   stream(content.encode()),
   b'<< /Type /FontDescriptor /FontName /PodFixture-Regular /Flags 32 /FontBBox [0 -200 700 800] /Ascent 800 /Descent -200 /CapHeight 700 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>',
   stream(font),b'/Screen',
  ])
  (ROOT/(case['name']+'.pdf')).write_bytes(data)
 (ROOT/'cases.json').write_text(json.dumps(CASES))

if '--fixtures' in sys.argv:
 fixtures();raise SystemExit(0)

import numpy as np
import pymupdf

def reference(doc, case):
 # Expand the implicit text knockout group into the equivalent explicit group.
 # MuPDF's text batching otherwise overpaints between separate Tj operations.
 # This uses the test font's exact B outline (40,0)..(600,700) at size 100.
 if case.get('producer')=='reportlab': return doc
 if case['name'].startswith('fallback-'):
  # MuPDF does not implement every fallback-array form. Resolve this test-only
  # copy per PDF 1.7 section 7.5.2; native output must also exactly equal the
  # canonical named-mode fixture below, without changing the native input.
  doc.xref_set_key(doc[0].xref,'Resources/ExtGState/Blend/BM','/'+case['mode'])
 page=doc[0];ref=doc.get_new_xref()
 doc.update_object(ref,'<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Group << /S /Transparency /I false /K true /CS /DeviceRGB >> /Resources '+doc.xref_get_key(page.xref,'Resources')[1]+' >>')
 doc.update_stream(ref,('/Blend gs '+rgb((51,102,204))+'344 100 56 70 re f 374 100 56 70 re f').encode())
 doc.xref_set_key(page.xref,'Resources/XObject/Glyphs',f'{ref} 0 R')
 stream=doc.xref_stream(page.get_contents()[0]);assert GLYPH_SECTION.encode() in stream
 doc.update_stream(page.get_contents()[0],stream.replace(GLYPH_SECTION.encode(),('q '+GLYPH_BACKGROUND+'/Glyphs Do Q\n').encode()))
 return doc

def pixels(doc,case,suffix,width):
 page=doc[0];scale=width/page.rect.width
 if case['mode'] not in ['ColorDodge','ColorBurn','Hue','mixed']:
  return page.get_pixmap(matrix=pymupdf.Matrix(scale,scale),alpha=False)
 # MuPDF 1.26.5's 8-bit premultiplied source loses precision at partial alpha;
 # dodge/burn can amplify a one-byte loss into a large output difference.
 # Its Hue mode also differs at partial alpha (e.g. white over red).
 # Ghostscript agrees with the analytic blend result for these cases.
 gs=shutil.which('gs')
 if not gs: raise RuntimeError('Blend tests require Ghostscript')
 refs=ROOT/'references';refs.mkdir(exist_ok=True)
 path=refs/f"{case['name']}{suffix}-{width}.pdf";png=path.with_suffix('.png')
 path.write_bytes(doc.tobytes())
 height=math.ceil(page.rect.height*scale)
 subprocess.run([gs,'-q','-dSAFER','-dBATCH','-dNOPAUSE','-dUseCropBox','-dFIXEDMEDIA',
                 '-sDEVICE=png16m','-dGraphicsAlphaBits=4','-dTextAlphaBits=4',f'-r{scale*72}',
                 f'-g{width}x{height}','-sOutputFile='+str(png),str(path)],check=True)
 return pymupdf.Pixmap(str(png))

maximum_error=0.;maximum_probe=0;comparisons=0
for case in CASES:
 name=case['name']
 for suffix in ['', '-saved', '-annotated', '-rotated']:
  with pymupdf.open(ROOT/(name+suffix+'.pdf')) as doc:
   # Save preservation is checked before any test-only reference expansion.
   if suffix=='-saved':
    with pymupdf.open(ROOT/(name+'.pdf')) as original:
     assert original[0].get_pixmap().samples==doc[0].get_pixmap().samples,(name,'saved appearance')
     if case.get('producer')!='reportlab': assert original.xref_stream(7)==doc.xref_stream(7),(name,'embedded font changed')
   reference(doc,case)
   for width in [612,1224]:
    scale=width/612
    expected=pixels(doc,case,suffix,width)
    observed=pymupdf.Pixmap(str(ROOT/f'{name}{suffix}-{width}.png'))
    if name.startswith('fallback-'):
     canonical=pymupdf.Pixmap(str(ROOT/f"{case['mode']}-0.37{suffix}-{width}.png"))
     assert observed.samples==canonical.samples,(name,suffix,width,'fallback differs from named mode')
    a=np.frombuffer(expected.samples,np.uint8).reshape(expected.height,expected.width,3).astype(np.int16)
    b=np.frombuffer(observed.samples,np.uint8).reshape(observed.height,observed.width,observed.n)[:,:,:3].astype(np.int16)
    error=np.abs(a-b);mean=float(error.mean());maximum_error=max(mean,maximum_error)
    assert mean < 1.5,(name,suffix,width,mean)
    if suffix!='-rotated':
     coords=[(63+col*30,265+row*30) for row in range(16) for col in range(16)]+[(380,130),(350,130),(420,130),(95,130),(150,130)]
     for x,y in coords:
      px,py=int(x*scale),int((792-y)*scale)
      delta=int(error[py,px].max());maximum_probe=max(delta,maximum_probe)
      assert delta<=4,(name,suffix,width,x,y,delta,a[py,px],b[py,px])
    comparisons+=1
 print('PASS:',name,'ReportLab mixed modes' if case.get('producer')=='reportlab' else 'RGB grid, fill/stroke and glyph knockout','CPU/Metal, save/annotation/crop')
print(f'{comparisons} independent rasters; max mean error {maximum_error:.6f}/255; max interior channel error {maximum_probe}/255')
