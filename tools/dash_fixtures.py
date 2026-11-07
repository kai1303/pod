#!/usr/bin/env python3
"""Independent dashed-stroke PDFs, including ReportLab and adversarial patterns."""
import io,json,sys
from pathlib import Path
from link_fixtures import serialize
root=Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True);(root/'invalid').mkdir(exist_ok=True)
def stream(data,entries=b''):
    return b'<< /Length '+str(len(data)).encode()+b' '+entries+b' >>\nstream\n'+data+b'\nendstream'
def pdf(content,states=b'',nested=False,split=False):
    local=b'/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Courier >> >> /ExtGState << '+states+b' >> /XObject << >>'
    resources=b'/XObject << /Fm 5 0 R >>' if nested else local
    bodies=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << '+resources+b' >> /Contents '+(b'[4 0 R 5 0 R]' if split else b'4 0 R')+b' >>',
        stream(b'q [30 10] 0 d /Fm Do Q' if nested else content.split(b'|')[0])]
    if nested:bodies.append(stream(content,b'/Subtype /Form /BBox [0 0 612 792] /Matrix [1 .1 .2 .9 0 0] /Resources << '+local+b' >>'))
    if split:bodies.append(stream(content.split(b'|')[1]))
    return serialize(bodies)
cases={}
def add(name,content,**kwargs):cases['dash-'+name]=pdf(content.encode(),**kwargs)
line='100 300 m 500 300 l S'
for cap in range(3):
    add(f'cap-{cap}',f'12 w {cap} J [25 15] 0 d '+line)
    add(f'dots-{cap}',f'12 w {cap} J [0 24] 0 d '+line)
    add(f'zero-path-{cap}',f'12 w {cap} J [30 10] 0 d 100 300 m 100 300 l S')
for join in range(3):
    add(f'join-{join}',f'18 w {join} j [200 30] 20 d 100 300 m 250 500 l 400 300 l S')
for name,pattern,phase in [('odd','[30 10 5]',0),('single','[25]',0),('phase','[30 10]',12),('gap-phase','[30 10]',35),('large-phase','[30 10]',1000000012),('negative-phase','[30 10]',-5),('zero-gap','[30 0]',0),('zero-sequence','[0 0 20 0 0 10]',0)]:
    add(name,f'10 w 1 J {pattern} {phase} d '+line)
add('closed','14 w 0 J [140 40] 20 d 100 200 300 240 re S')
add('closed-round','14 w 1 J 1 j [140 40] 20 d 100 200 300 240 re S')
add('closed-solid','14 w 1 J [2000 10] 0 d 100 200 300 240 re S')
add('subpaths','10 w [30 10] 12 d 100 300 m 500 300 l 100 350 m 500 350 l S')
add('curves','10 w 1 J [30 10] 4 d 100 200 m 100 600 500 600 500 200 c S')
add('affine','1.5 .2 .4 .7 10 80 cm 12 w 1 J 1 j [30 10] 4 d 50 100 m 100 450 l 220 100 l S')
add('reflected','-1 .2 .1 1 570 20 cm 12 w 1 J [30 10] 4 d 100 200 m 100 600 400 600 400 200 c S')
add('hairline','0 w [30 10] 0 d 100 300 m 500 300 l S')
add('hairline-affine','1.5 .2 .4 .7 10 80 cm 0 w [30 10] 4 d 50 100 m 100 450 l 220 100 l S')
add('saved-state','8 w [30 10] 0 d 100 200 m 500 200 l S q [] 17 d 100 250 m 500 250 l S Q 100 300 m 500 300 l S')
add('extgstate','/D gs '+line,states=b'/D << /LW 12 /LC 1 /D [[25 15] 8] >>')
add('split','q 12 w [25 15] 8 d |'+line+' Q',split=True)
add('nested','12 w 1 J '+line,nested=True)
add('fill-stroke','12 w [30 20] 5 d .2 .4 .8 rg 1 0 0 RG 100 200 300 240 re B')
add('clip','100 220 300 130 re W n 12 w 1 J [30 10] 4 d 100 200 m 100 600 500 600 500 200 c S')
add('transparent','/A gs 18 w 1 J [60 5] 0 d 100 200 m 500 200 l 100 300 l 500 300 l S',states=b'/A << /CA .5 /BM /Multiply >>')
# 4,000 edges exceed the former per-paint cap, within the total GPU work budget.
add('grid','0.8 w [4 4] 0 d '+ ' '.join(f'100 {100+y*12} m 500 {100+y*12} l' for y in range(40))+' S')
from reportlab.pdfgen import canvas
out=io.BytesIO();c=canvas.Canvas(out,pagesize=(612,792),pageCompression=1)
c.setDash([22,9,5],7);c.setLineWidth(8);c.setLineCap(1);c.line(100,300,500,300);c.roundRect(100,400,300,180,25,stroke=1,fill=0);c.showPage();c.save()
cases['dash-reportlab']=out.getvalue()
bad={'ctm-in-path':b'100 300 m 500 300 l 2 0 0 1 0 0 cm 10 w [20 10] 0 d S','negative':b'[-1 2] 0 d','zero':b'[0 0] 0 d','type':b'[1 /Bad] 0 d','phase':b'[1 2] /Bad d','array':b'1 0 d','arity':b'[1] d','huge':b'[10000000000000 1] 0 d','count':b'['+b'1 '*129+b'] 0 d','budget':b'[0.000001 0.000001] 0 d 0 0 m 600 600 l S','singular':b'[1 2] 0 d 1 0 0 0 0 0 cm 0 w 0 0 m 10 10 l S'}
for name,data in cases.items():(root/(name+'.pdf')).write_bytes(data)
for name,content in bad.items():(root/'invalid'/(name+'.pdf')).write_bytes(pdf(content))
(root/'cases.json').write_text(json.dumps(list(cases)))
print('PASS:',len(cases),'dash fixtures;',len(bad),'invalid fixtures')
