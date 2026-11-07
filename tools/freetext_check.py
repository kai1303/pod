#!/usr/bin/env python3
"""Independent FreeText producers, preservation and saved-appearance checks."""
import json
import re
import sys
from pathlib import Path
import pymupdf

root = Path(sys.argv[1])
if '--fixtures' in sys.argv:
    from link_fixtures import serialize
    root.mkdir(parents=True, exist_ok=True)
    invalid=root/'invalid'; invalid.mkdir(exist_ok=True)
    names=[]
    for name, options in {
        'mupdf-left': {}, 'mupdf-center': {'align':1}, 'mupdf-right': {'align':2},
        'mupdf-courier': {'fontname':'Cour'}, 'mupdf-times': {'fontname':'TiRo'}, 'mupdf-rotated': {'rotate':90},
        'mupdf-border': {'border_width':2},
    }.items():
        doc=pymupdf.open();page=doc.new_page(width=300,height=360)
        page.draw_rect(page.rect,color=None,fill=(.8,.9,1))
        args={'fontsize':14,'fontname':'Helv','text_color':(.1,.2,.4),'fill_color':(.9,.8,.6),'opacity':.6}
        args.update(options)
        mark=page.add_freetext_annot((60,90,240,210),'Read this paragraph.\nA teacher note.',**args)
        mark.set_info(title='Teacher',subject='Review',content='Read this paragraph.\nA teacher note.')
        doc.save(root/(name+'.pdf'));doc.close();names.append(name)
    for source in names.copy():
        doc=pymupdf.open(root/(source+'.pdf')); page=doc[0]; mark=next(page.annots())
        doc.xref_set_key(mark.xref,'AP','null')
        name='fallback-'+source
        doc.save(root/(name+'.pdf'));doc.close();names.append(name)
    for name, text, rect, options in [
        ('fallback-wrap','Students read, highlight, and explain their thinking. ALongWordWithoutAnySpacesToBreak.',(60,90,170,230),{}),
        ('fallback-wrap-center','Students read, highlight, and explain their thinking.',(60,90,170,230),{'align':1}),
        ('fallback-overflow','One\nTwo\nThree\nFour\nFive',(60,90,200,112),{}),
        ('fallback-unicode','Café costs €5.\nRésumé',(60,90,240,210),{}),
        ('fallback-rotate180','Reading notes',(60,90,240,210),{'rotate':180}),
        ('fallback-rotate270','Reading notes',(60,90,240,210),{'rotate':270}),
        ('fallback-empty','',(60,90,240,210),{}),
    ]:
        doc=pymupdf.open();page=doc.new_page(width=300,height=360)
        page.draw_rect(page.rect,color=None,fill=(.8,.9,1))
        mark=page.add_freetext_annot(rect,text,fontsize=14,text_color=(.1,.2,.4),fill_color=(.9,.8,.6),**options)
        doc.xref_set_key(mark.xref,'AP','null');doc.save(root/(name+'.pdf'));doc.close();names.append(name)
    def stream(data, extra=b''):
        return b'<< /Length '+str(len(data)).encode()+b' '+extra+b' >>\nstream\n'+data+b'\nendstream'
    def fixture(extra=b'', ap=b'/AP << /N 6 0 R >>', flags=b'4', shared=False, callout=False, da=b'/OtherFont 29 Tf 1 0 0 rg', align=2, content=b'Teacher note', rect=b'[60 90 240 230]'):
        mark=b'<< /Type /Annot /Subtype /FreeText /Rect '+rect+b' /Contents ('+content+b') /DA ('+da+b') /Q '+str(align).encode()+b' /NM (text-1) /T (Teacher) /Subj (Keep metadata) /F '+flags+b' '+ap+b' '+extra+b' >>'
        program=b'q /Half gs .9 .8 .6 rg 0 0 180 140 re f 0 g BT /F 14 Tf 1 0 0 1 12 104 Tm (Teacher note) Tj ET Q'
        placement=b'/BBox [0 0 180 140] /Matrix [1 .2 -.1 1 5 2]'
        if callout:
            mark=mark.replace(b'/Rect [60 90 240 230]',b'/Rect [20 40 240 230]')
            placement=b'/BBox [0 0 220 190] /Matrix [1 0 0 1 0 0]'
            line=b'5 20 m 20 50 l 50 80 l S' if b'40 90' in extra else b'5 20 m 50 80 l S'
            program=b'q /Half gs .9 .8 .6 rg 50 60 170 130 re f .1 .2 .4 RG 2 w '+line+b' 0 g BT /F 14 Tf 1 0 0 1 62 154 Tm (Teacher note) Tj ET Q'
        return serialize([
            b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 360] /Resources << >> /Contents 4 0 R /Annots [5 0 R'+(b' 7 0 R' if shared else b'')+b'] >>',
            stream(b'.8 .9 1 rg 0 0 300 360 re f'), mark,
            stream(program,b'/Type /XObject /Subtype /Form '+placement+b' /Resources << /ExtGState << /Half << /ca .6 >> >> /Font << /F << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> >> >>'),
            mark.replace(b'[60 90 240 230]',b'[20 20 100 80]').replace(b'(text-1)',b'(text-2)'),
        ])
    cases={
        'transformed': fixture(), 'shared': fixture(shared=True),
        'states': fixture(ap=b'/AP << /N << /Selected 6 0 R >> /R 6 0 R /D 6 0 R >> /AS /Selected'),
        'callout-two': fixture(b'/CL [25 60 70 120] /IT /FreeTextCallout /LE /None /RD [50 60 0 0]',callout=True),
        'callout-three': fixture(b'/CL [25 60 40 90 70 120] /IT /FreeTextCallout /RD [50 60 0 0] /BE << /S /C /I 2 >>',callout=True),
        'rich': fixture(b'/RC (<p style="color:blue">Teacher note</p>) /DS (font: Helvetica 14pt) /Rotate 270'),
        'locked': fixture(flags=b'132'),
    }
    for name,cl in [('fallback-callout-two',b'25 60 70 120'),('fallback-callout-three',b'25 60 40 90 70 120')]:
        cases[name]=fixture(b'/CL ['+cl+b'] /IT /FreeTextCallout /LE /None /RD [50 60 0 0] /BS << /W 2 >> /C [.9 .8 .6]',ap=b'',callout=True,da=b'/Helv 14 Tf .1 .2 .4 rg')
    for ending in (b'OpenArrow',b'ClosedArrow'):
        cases['fallback-callout-'+ending.decode()]=fixture(b'/CL [25 60 40 90 70 120] /IT /FreeTextCallout /LE /'+ending+b' /RD [50 60 0 0] /BS << /W 2 >> /C [.9 .8 .6]',ap=b'',callout=True,da=b'/Helv 14 Tf .1 .2 .4 rg')
    for name,content,extra in [
        ('single',b'Teacher note',b'/BS << /W 0 >>'),
        ('wrap',b'Students read, highlight, and explain their thinking. Then discuss with a partner.',b'/BS << /W 1 >>'),
        ('long-word',b'ALongWordWithoutAnySpacesToBreak.',b'/BS << /W 1 >>'),
        ('lines',b'First\nSecond\nThird',b'/BS << /W 2 >>'),
        ('rotated',b'Reading notes',b'/Rotate 90 /BS << /W 2 >>'),
        ('insets',b'Reading notes',b'/RD [25 20 15 10] /BS << /W 2 >>'),
        ('empty',b'',b'/BS << /W 1 >>'),
    ]:
        cases['fallback-auto-'+name]=fixture(extra,ap=b'',da=b'/Helv 0 Tf .1 .2 .4 rg',content=content)
    cases['fallback-auto-callout']=fixture(b'/CL [25 60 40 90 70 120] /IT /FreeTextCallout /LE /OpenArrow /RD [50 60 0 0] /BS << /W 2 >>',ap=b'',callout=True,da=b'/Helv 0 Tf .1 .2 .4 rg')
    for name,scale,size,align,extra in [
        ('narrow',50,14,0,b''), ('wide',175,14,1,b''), ('fraction',33.3,14,2,b''),
        ('rotated',75,14,2,b'/Rotate 90'), ('auto',200,0,2,b''),
        ('auto-rotated',150,0,1,b'/Rotate 270'),
    ]:
        cases['fallback-hscale-'+name]=fixture(extra+b'/BS << /W 1 >>',ap=b'',align=align,
            da=f'/Helv {size} Tf .1 .2 .4 rg {scale} Tz'.encode(),
            content=b'Students read and explain. Then discuss with a partner.\nA second line.')
    for name,state,size,align,extra in [
        ('character',b'2 Tc',14,0,b''), ('word',b'8 Tw',14,1,b''),
        ('combined',b'1 Tc 5 Tw 75 Tz',14,2,b'/Rotate 90'),
        ('tight',b'-1 Tc -2 Tw',14,1,b''), ('backwards',b'-20 Tc',14,0,b''),
        ('backwards-words',b'-30 Tw',14,2,b''),
        ('auto',b'2 Tc 5 Tw',0,2,b''), ('auto-negative',b'-20 Tc',0,1,b'/Rotate 270'),
    ]:
        cases['fallback-spacing-'+name]=fixture(extra+b'/BS << /W 1 >>',ap=b'',align=align,
            da=b'/Helv '+str(size).encode()+b' Tf .1 .2 .4 rg '+state,
            content=b'Read and discuss.\nA teacher note.')
    cases['fallback-spacing-auto-interval']=fixture(b'/BS << /W 0 >>',ap=b'',da=b'/Cour 0 Tf -20 Tc',content=b'ABC',rect=b'[60 90 85 150]')
    for name,data in cases.items(): (root/(name+'.pdf')).write_bytes(data);names.append(name)
    bad={
        'fallback-unknown-font':fixture(ap=b''), 'empty-ap':fixture(ap=b'/AP << >>'), 'missing-object':fixture(ap=b'/AP << /N 88 0 R >>'),
        'state':fixture(ap=b'/AP << /N << /On 6 0 R >> >> /AS /Off'),
        'callout-count':fixture(b'/CL [1 2 3]'), 'callout-range':fixture(b'/CL [1 2 1000001 4]'),
        'hidden':fixture(flags=b'2'), 'optional-content':fixture(b'/OC << /Type /OCG >>'),
        'fallback-rich':fixture(b'/RC (<p>Rich text</p>)',ap=b''),
        'fallback-negative-size':fixture(ap=b'',da=b'/Helv -1 Tf'),
        'fallback-zero-scale':fixture(ap=b'',da=b'/Helv 12 Tf 0 Tz'),
        'fallback-negative-scale':fixture(ap=b'',da=b'/Helv 12 Tf -100 Tz'),
        'fallback-malformed-scale':fixture(ap=b'',da=b'/Helv 12 Tf 50 60 Tz'),
        'fallback-malformed-spacing':fixture(ap=b'',da=b'/Helv 12 Tf 1 2 Tc'),
        'fallback-large-spacing':fixture(ap=b'',da=b'/Helv 12 Tf 1000001 Tw'),
        'fallback-spacing-no-fit':fixture(b'/BS << /W 0 >>',ap=b'',da=b'/Cour 0 Tf 20 Tc',content=b'ABC',rect=b'[60 90 90 150]'),
        'fallback-auto-no-space':fixture(b'/BS << /W 100 >>',ap=b'',da=b'/Helv 0 Tf'),
        'fallback-alignment':fixture(ap=b'',da=b'/Helv 12 Tf',align=3),
        'fallback-rotation':fixture(b'/Rotate 45',ap=b'',da=b'/Helv 12 Tf'),
        'fallback-insets':fixture(b'/RD [100 0 100 0]',ap=b'',da=b'/Helv 12 Tf'),
    }
    (invalid/'missing-ap.pdf').unlink(missing_ok=True)
    (invalid/'fallback-auto-size.pdf').unlink(missing_ok=True)
    for name,data in bad.items(): (invalid/(name+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps(names))
    print(f'PASS: {len(names)} FreeText fixtures, {len(bad)} invalid/unsupported fixtures')
    raise SystemExit

if '--normalize-pdfkit' in sys.argv:
    from pypdf import PdfReader, PdfWriter
    for name in ('pdfkit-left','pdfkit-center'):
        path=root/(name+'.pdf')
        reader=PdfReader(path)
        annotation=reader.pages[0]['/Annots'][0].get_object()
        fonts=annotation['/AP']['/N']['/Resources']['/Font']
        # PDFKit writes these FontFile2 streams without the required Length.
        # Retain the malformed originals and validate Length1 before a test-only
        # rewrite materializes their lengths. Production parsing stays strict.
        for ref in fonts.values():
            program=ref.get_object()['/FontDescriptor']['/FontFile2']
            data=program.get_data();length=int(program['/Length1'])
            assert program.get('/Filter') is None and len(data)>=length
            assert data[length:] in (b'',b'\n',b'\r',b'\r\n')
            program.set_data(data[:length])
        (root/'invalid'/(name+'-raw.pdf')).write_bytes(path.read_bytes())
        writer=PdfWriter(clone_from=reader)
        temporary=root/(name+'-normalized.pdf')
        writer.write(temporary);temporary.replace(path)
    print('PASS: normalized two PDFKit test font-stream lengths; raw inputs retained as invalid fixtures')
    raise SystemExit

import numpy as np
from PIL import Image
from pypdf import PdfReader
from pypdf.generic import ContentStream
from reference_fonts import embed_reference_fonts

def snapshot(value):
    if hasattr(value,'get_object'): value=value.get_object()
    if hasattr(value,'get_data'): return (value.get_data(),value._data,{str(k):snapshot(v) for k,v in value.items() if k!='/Length'})
    if isinstance(value,dict): return {str(k):snapshot(v) for k,v in value.items() if k not in ('/P','/Parent')}
    if isinstance(value,list): return [snapshot(v) for v in value]
    return str(value)

def font_size(mark):
    da=str(mark.get('/DA','')).split()
    # Imported custom appearances need not have a DA that Pod can regenerate.
    return float(da[da.index('Tf')-1]) if 'Tf' in da else None

def horizontal_scale(mark):
    tokens=str(mark.get('/DA','')).split()
    values=[float(tokens[i-1])/100 for i,token in enumerate(tokens) if token=='Tz']
    return values[-1] if values else 1

def spacing(mark):
    tokens=str(mark.get('/DA','')).split()
    values={token:float(tokens[i-1]) for i,token in enumerate(tokens) if token in ('Tc','Tw')}
    return values.get('Tc',0),values.get('Tw',0)

def check_auto_fit(path):
    mark=PdfReader(path).pages[0]['/Annots'][0].get_object()
    assert font_size(mark)==0
    form=mark['/AP']['/N']
    family=str(form['/Resources']['/Font']['/Text']['/BaseFont'])[1:]
    font=pymupdf.Font(fontname=family)
    rect=list(map(float,mark['/Rect']));rd=list(map(float,mark.get('/RD',[0,0,0,0])))
    width=rect[2]-rect[0]-rd[0]-rd[2];height=rect[3]-rect[1]-rd[1]-rd[3]
    if int(mark.get('/Rotate',0)) in (90,270): width,height=height,width
    border=float(mark.get('/BS',{}).get('/W',1));width-=4*border;height-=4*border
    size=0;lines=0;scale=1;character=0;word=0
    for operands,operator in ContentStream(form,None).operations:
        if operator==b'Tf': size=float(operands[1]);assert 0<size<=200
        if operator==b'Tz': scale=float(operands[0])/100
        if operator==b'Tc': character=float(operands[0])
        if operator==b'Tw': word=float(operands[0])
        if operator==b'Tj':
            text=operands[0]
            raw=bytes(text) if isinstance(text,bytes) else text.original_bytes
            # Independent standard-font metrics verify the emitted line advances.
            if character or word:
                pen=0;left=0;right=0
                for code in raw:
                    char=bytes([code]).decode('cp1252')
                    end=pen+font.text_length(char,fontsize=size)
                    if char!=' ':
                        left=min(left,pen,end);right=max(right,pen,end)
                    pen=end+character+(word if code==32 else 0)
                extent=right-left
            else:
                extent=font.text_length(raw.decode('cp1252').rstrip(' '),fontsize=size)
            assert extent*scale<=width+0.001,(path,'line width')
            lines+=1
    assert lines>0 and lines*1.2*size<=height+0.001,(path,'line height')

count=0;worst=0;interior_worst=0
for name in json.loads((root/'cases.json').read_text()):
    original=PdfReader(root/(name+'.pdf')).pages[0]['/Annots']
    resource_font=name.startswith('resource-')
    scaled='-hscale-' in name
    spaced='-spacing-' in name
    edits=('-edited','-edited-again','-restyled','-resized') if resource_font or name.startswith(('fallback-','pod-created-')) else ()
    for suffix in ('','-saved','-rotated','-organized')+(() if name=='locked' else ('-moved','-removed'))+edits:
        path=root/(name+suffix+'.pdf')
        marks=PdfReader(path).pages[0].get('/Annots',[])
        expected=original[1:] if suffix=='-removed' else original
        assert len(marks)==len(expected),(name,suffix,'count')
        for i,(new,old) in enumerate(zip(marks,expected)):
            new=new.get_object();old=old.get_object()
            assert horizontal_scale(new)==horizontal_scale(old),(name,suffix,'horizontal scale changed')
            assert spacing(new)==spacing(old),(name,suffix,'spacing changed')
            changed={'/Rect','/CL','/AAPL:AKExtras'} if suffix=='-moved' and i==0 else set()
            if resource_font and suffix=='-organized':
                changed.add('/DA')
                assert str(new['/DA']).split()[1:]==str(old['/DA']).split()[1:]
            if suffix in edits and i==0:
                changed={'/AP','/PodFreeTextAppearance','/AAPL:AKExtras'}
                assert new['/PodFreeTextAppearance']==1 and '/N' in new['/AP']
                if suffix in ('-edited','-edited-again'):
                    changed.add('/Contents')
                    expected_text=('AB é\nAB' if suffix=='-edited' else 'é AB') if resource_font else ('Café — revised\nA second line' if suffix=='-edited' else 'Edited again — €5')
                    if name=='fallback-spacing-auto-interval':expected_text='AB\nAB' if suffix=='-edited' else 'ABC'
                    assert new['/Contents']==expected_text
                elif suffix=='-restyled':
                    changed|={'/DA','/C','/CA','/BS','/Border'}
                    da=str(new['/DA']).split();old_da=str(old['/DA']).split()
                    assert da[2]=='Tf' and da[6]=='rg' and float(da[1])==float(old_da[old_da.index('Tf')-1])+2
                    assert np.allclose(list(map(float,da[3:6])),[.2,.4,.1])
                    assert np.allclose(list(map(float,new['/C'])),[1,.9,.5]) and float(new['/CA'])==.5
                    old_width=float(old['/BS'].get('/W',1)) if '/BS' in old else float(old.get('/Border',[0,0,1])[2])
                    assert float(new['/BS']['/W'])==old_width+1
                    assert {k:snapshot(v) for k,v in new['/BS'].items() if k!='/W'}=={k:snapshot(v) for k,v in old.get('/BS',{}).items() if k!='/W'}
                else:
                    changed|={'/Rect','/CL','/RD'}
                    rect=np.array(list(map(float,old['/Rect'])))
                    target=rect+[-5,-5,5,5]
                    assert np.allclose(list(map(float,new['/Rect'])),target)
                    scale=(target[2:]-target[:2])/(rect[2:]-rect[:2])
                    if '/RD' in old:
                        assert np.allclose(list(map(float,new['/RD'])),np.array(list(map(float,old['/RD'])))*np.tile(scale,2))
                    if '/CL' in old:
                        points=np.array(list(map(float,old['/CL']))).reshape(-1,2)
                        assert np.allclose(np.array(list(map(float,new['/CL']))).reshape(-1,2),target[:2]+(points-rect[:2])*scale)
            assert {str(k):snapshot(v) for k,v in new.items() if k not in changed|{'/P'}}=={str(k):snapshot(v) for k,v in old.items() if k not in changed|{'/P'}},(name,suffix,'metadata')
            if suffix=='-moved' and i==0:
                for key in ('/Rect','/CL'):
                    if key not in old: continue
                    assert np.allclose(list(map(float,new[key])),[float(v)+(13 if j%2==0 else -7) for j,v in enumerate(old[key])]),(name,key)
        reference_path=root/(name+suffix+'-reference.pdf')
        reference_input=path
        automatic=bool(marks) and font_size(marks[0].get_object())==0
        if automatic or resource_font or scaled or spaced:
            # Autosizing algorithms vary between readers. Check the fitting constraints
            # independently, then compare the saved drawing in another renderer.
            if marks and not isinstance(marks[0].get_object().get('/AP'),dict):
                reference_input=root/(name+suffix+'-materialized.pdf')
            if automatic and not resource_font: check_auto_fit(reference_input)
            if scaled and marks:
                reference_mark=PdfReader(reference_input).pages[0]['/Annots'][0].get_object()
                scales=[float(args[0])/100 for args,op in ContentStream(reference_mark['/AP']['/N'],None).operations if op==b'Tz']
                assert scales==[horizontal_scale(reference_mark)],(name,suffix,'appearance scale')
            if spaced and marks:
                reference_mark=PdfReader(reference_input).pages[0]['/Annots'][0].get_object()
                state={op:float(args[0]) for args,op in ContentStream(reference_mark['/AP']['/N'],None).operations if op in (b'Tc',b'Tw',b'Tz')}
                assert (state.get(b'Tc',0),state.get(b'Tw',0))==spacing(reference_mark),(name,suffix,'appearance spacing')
                assert state.get(b'Tz',100)/100==horizontal_scale(reference_mark),(name,suffix,'appearance scaling')
            if resource_font:
                source_catalog=PdfReader(root/(name+'.pdf')).trailer['/Root']
                actual_catalog=PdfReader(path).trailer['/Root']
                if suffix!='-organized': assert snapshot(source_catalog['/AcroForm'])==snapshot(actual_catalog['/AcroForm']),(name,suffix,'font resources changed')
                if marks:
                    mark=PdfReader(reference_input).pages[0]['/Annots'][0].get_object()
                    key=re.sub(r'#([0-9a-fA-F]{2})',lambda m:chr(int(m[1],16)),str(mark['/DA']).split()[0])
                    selected=actual_catalog['/AcroForm']['/DR']['/Font'][key]
                    assert snapshot(mark['/AP']['/N']['/Resources']['/Font']['/Text'])==snapshot(selected)
                    assert snapshot(selected)==snapshot(source_catalog['/AcroForm']['/DR']['/Font']['/Lesson Font'])
                    if suffix!='-organized': assert key=='/Lesson Font'
                    assert font_size(mark)==font_size(marks[0].get_object())
        elif name.startswith(('fallback-','pod-created-')):
            generated=pymupdf.open(path)
            for page in generated:
                for annotation in page.annots() or []:
                    content=annotation.info['content']
                    normalized=content.replace('\r\n','\n').replace('\r','\n').replace('\t',' ')
                    if normalized!=content:
                        # PDFBox agrees with Pod's single CRLF break and tab-space layout.
                        # MuPDF adds a second CRLF break when regenerating; normalize only
                        # this oracle copy. The saved-AP comparison below uses original bytes.
                        assert name=='pod-created-lines' and content=='First\r\nSecond\rThird\tline'
                        generated.xref_set_key(annotation.xref,'Contents',pymupdf.get_pdf_str(normalized))
                    rect=generated.xref_get_key(annotation.xref,'Rect')
                    rd=generated.xref_get_key(annotation.xref,'RD')
                    callout=generated.xref_get_key(annotation.xref,'CL')
                    intent=generated.xref_get_key(annotation.xref,'IT')
                    annotation.update()
                    after=generated.xref_get_key(annotation.xref,'Rect')
                    if after!=rect:
                        # MuPDF tightens callout Rects and removes plain-box insets.
                        # Keep the source clipping box only when the independently
                        # generated drawing retains the exact same text-body bounds.
                        assert rd[0]=='array'
                        assert generated.xref_get_key(annotation.xref,'IT')==intent
                        assert generated.xref_get_key(annotation.xref,'CL')==callout
                        coordinates=lambda value: np.array([float(v) for v in value[1].strip('[]').split()])
                        old_body=coordinates(rect)+coordinates(rd)*[1,1,-1,-1]
                        new_body=coordinates(after)+coordinates(generated.xref_get_key(annotation.xref,'RD'))*[1,1,-1,-1]
                        assert np.allclose(old_body,new_body,rtol=0,atol=1e-5),(name,suffix,'reference moved text box')
                        normal=int(generated.xref_get_key(annotation.xref,'AP/N')[1].split()[0])
                        matrix=generated.xref_get_key(normal,'Matrix')
                        assert matrix[0]=='null' or np.array_equal(coordinates(matrix),[1,0,0,1,0,0])
                        assert generated.xref_get_key(normal,'BBox')==after
                        generated.xref_set_key(annotation.xref,'Rect',rect[1])
                        generated.xref_set_key(normal,'BBox',rect[1])
            reference_input=root/(name+suffix+'-generated.pdf')
            generated.save(reference_input);generated.close()
        sources=[reference_input]+([path] if not automatic and not resource_font and not scaled and not spaced and (suffix in edits or (name.startswith('pod-created-') and suffix!='-removed')) else [])
        for source in sources:
            embed_reference_fonts(source,reference_path)
            ref=pymupdf.open(reference_path)
            for width in (300,600):
                actual=np.array(Image.open(root/f'{name}{suffix}-{width}.png').convert('RGB'),dtype=np.int16)
                scale=width/ref[0].rect.width
                height=int(np.ceil(ref[0].rect.height*scale))
                # Fitted, scaled and spaced glyphs expose native-resolution sampling differences.
                # Supersample the independent renderer, keeping the same error bounds.
                factor=8 if automatic or scaled or spaced else 1
                pix=ref[0].get_pixmap(matrix=pymupdf.Matrix(scale*factor,scale*factor),alpha=False)
                samples=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width,3)
                if factor==1:
                    expected=samples.astype(np.int16)
                else:
                    expected=np.full((height*factor,width*factor,3),255,dtype=np.uint8)
                    h=min(pix.height,height*factor);w=min(pix.width,width*factor)
                    expected[:h,:w]=samples[:h,:w]
                    expected=np.rint(expected.reshape(height,factor,width,factor,3).mean((1,3))).astype(np.int16)
                assert actual.shape==expected.shape,(name,suffix,'size')
                delta=abs(actual-expected);mean=float(delta.mean());flat=np.ones(expected.shape[:2],bool)
                for y in (-1,0,1):
                    for x in (-1,0,1): flat&=np.all(expected==np.roll(expected,(y,x),(0,1)),axis=2)
                interior=int(delta[flat].max())
                assert mean<1 and interior<=2,(name,suffix,source.name,width,mean,interior)
                count+=1;worst=max(worst,mean);interior_worst=max(interior_worst,interior)
            ref.close()
    print(f'PASS: {name} appearance and metadata preservation; independent rendering')
for name in ('font-merge-original','font-merge-appearances','font-merge-edited'):
    path=root/(name+'.pdf')
    merged=PdfReader(path)
    assert len(merged.pages)==2
    for index,page in enumerate(merged.pages):
        source=PdfReader(root/f'{name}-source-{index}.pdf')
        old=source.pages[0]['/Annots'][0].get_object()
        new=page['/Annots'][0].get_object()
        assert {str(k):snapshot(v) for k,v in old.items() if k not in ('/DA','/P')}=={str(k):snapshot(v) for k,v in new.items() if k not in ('/DA','/P')},(name,index,'annotation metadata')
        assert str(new['/DA']).split()[1:]==str(old['/DA']).split()[1:]
        key=re.sub(r'#([0-9a-fA-F]{2})',lambda m:chr(int(m[1],16)),str(new['/DA']).split()[0])
        actual=merged.trailer['/Root']['/AcroForm']['/DR']['/Font'][key]
        expected=source.trailer['/Root']['/AcroForm']['/DR']['/Font']['/Lesson Font']
        assert snapshot(actual)==snapshot(expected),(name,index,'selected font')
    # Original boxes have no AP. Their unchanged drawing is covered by the
    # source-fixture materialization checks and exact native before/after pixels.
    if name=='font-merge-original':continue
    reference=root/(name+'-reference.pdf')
    embed_reference_fonts(path,reference)
    document=pymupdf.open(reference)
    for index,page in enumerate(document):
        for width in (300,600):
            pix=page.get_pixmap(matrix=pymupdf.Matrix(width/page.rect.width,width/page.rect.width),alpha=False)
            expected=np.frombuffer(pix.samples,np.uint8).reshape(pix.height,pix.width,3).astype(np.int16)
            actual=np.array(Image.open(root/f'{name}-page-{index}-{width}.png').convert('RGB'),dtype=np.int16)
            delta=abs(actual-expected);mean=float(delta.mean());flat=np.ones(expected.shape[:2],bool)
            for y in (-1,0,1):
                for x in (-1,0,1):flat&=np.all(expected==np.roll(expected,(y,x),(0,1)),axis=2)
            interior=int(delta[flat].max())
            assert mean<1 and interior<=2,(name,index,width,mean,interior)
            count+=1;worst=max(worst,mean);interior_worst=max(interior_worst,interior)
    document.close()
    print(f'PASS: {name} retains distinct font resources and independent appearance rendering')
print(f'PASS: {count} FreeText rasters; maximum mean {worst:.6f}/255, interior {interior_worst}/255')
