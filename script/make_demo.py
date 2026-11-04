#!/usr/bin/env python3
"""Generate the app's small, uncompressed demonstration PDF without dependencies."""
import pathlib, sys

def text(x, y, size, value, color='0.12 0.16 0.21'):
    value=value.replace('\\','\\\\').replace('(','\\(').replace(')','\\)')
    return f'{color} rg BT /F1 {size} Tf 1 0 0 1 {x} {y} Tm ({value}) Tj ET\n'

page1='0.96 0.97 0.98 rg 0 0 612 792 re f\n1 1 1 rg 34 34 544 724 re f\n'
page1+='0.10 0.38 0.32 rg 54 684 504 58 re f\n'
page1+=text(72,705,26,'A little room to think.', '1 1 1')
page1+=text(72,651,11,'POD / NATIVE PDF WORKSPACE', '0.10 0.38 0.32')
page1+=text(72,604,22,'Make the page yours.')
page1+=text(72,572,12,'Click any line to select and edit its text.')
page1+=text(72,550,12,'Your changes stay local. Save a copy when ready.')
page1+='0.86 0.91 0.88 rg 72 418 468 96 re f\n'
page1+=text(90,484,14,'A small plan for a good day')
page1+=text(90,460,12,'01  Clear a little space.')
page1+=text(90,438,12,'02  Make something worth keeping.')
page1+='0.10 0.38 0.32 RG 1 w 72 391 m 540 391 l S\n'
page1+=text(72,361,12,'Open. Read. Refine.')
page1+=text(72,333,11,'Try replacing this line with something shorter.')
page1+=text(72,311,11,'Undo brings it back. The next line stays in place.')
page1+=text(72,123,10,'A PDF drawn by the Pod engine, one pixel at a time.', '0.40 0.44 0.46')
page1+=text(72,98,10,'SAMPLE DOCUMENT                                      01', '0.40 0.44 0.46')
page2=text(72,710,26,'Notes for tomorrow')+text(72,667,12,'A second page, with room for a fresh thought.')
page2+=text(72,609,14,'Start small. Keep going.')+text(72,577,12,'Select this text to try the editor.')
page2+='0.10 0.38 0.32 RG 1 w 72 545 m 540 545 l S\n'
page2+=text(72,98,10,'SAMPLE DOCUMENT                                      02')
bodies=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> >>',b'<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>',b'<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>',None,b'<< /Type /Page /Parent 2 0 R /Contents 7 0 R >>',None]
for i,c in [(4,page1),(6,page2)]:
    c=c.encode('ascii'); bodies[i]=f'<< /Length {len(c)} >>\nstream\n'.encode()+c+b'endstream'
out=bytearray(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n'); offsets=[]
for i,body in enumerate(bodies,1):
    offsets.append(len(out)); out+=f'{i} 0 obj\n'.encode()+body+b'\nendobj\n'
xref=len(out); out+=f'xref\n0 {len(bodies)+1}\n0000000000 65535 f \n'.encode()
for offset in offsets: out+=f'{offset:010} 00000 n \n'.encode()
out+=f'trailer\n<< /Size {len(bodies)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(out)
