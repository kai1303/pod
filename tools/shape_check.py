#!/usr/bin/env python3
"""Foreign vector-annotation producers and independent preservation/render checks."""
import json
import math
import subprocess
import sys
from pathlib import Path
import pymupdf

root = Path(sys.argv[1])
if '--fixtures' in sys.argv:
    from link_fixtures import serialize
    root.mkdir(parents=True, exist_ok=True)
    invalid = root/'invalid'; invalid.mkdir(exist_ok=True)
    names = []
    for kind in ['square','circle','line','polyline','polygon']:
        doc = pymupdf.open(); page = doc.new_page(width=300,height=360)
        if kind == 'square': mark = page.add_rect_annot((60,90,220,230))
        elif kind == 'circle': mark = page.add_circle_annot((60,90,220,230))
        elif kind == 'line': mark = page.add_line_annot((60,120),(220,230))
        elif kind == 'polyline': mark = page.add_polyline_annot([(60,90),(100,230),(220,100)])
        else: mark = page.add_polygon_annot([(60,90),(100,230),(220,100)])
        mark.set_info(content='Bài học ✓',title='Teacher',subject='Keep this metadata')
        mark.set_colors(stroke=(.1,.3,.7),fill=(.8,.7,.2))
        mark.set_border(width=3,dashes=[9,4])
        if kind in ('line','polyline'): mark.set_line_ends(pymupdf.PDF_ANNOT_LE_CLOSED_ARROW,pymupdf.PDF_ANNOT_LE_OPEN_ARROW)
        mark.update()
        name='mupdf-'+kind; doc.save(root/(name+'.pdf')); names.append(name); doc.close()

    def stream(data, entries=b''):
        return b'<< /Length '+str(len(data)).encode()+b' '+entries+b' >>\nstream\n'+data+b'\nendstream'
    def handmade(extra=b'', ap=b'/AP << /N 6 0 R >>', subtype=b'Square', geometry=b'', shared=False, flags=b'4', color=b'[.1 .3 .7]', opacity=b'.1', border=b'/BS << /W 3 /S /D /D [9 4] >>'):
        mark=b'<< /Type /Annot /Subtype /'+subtype+b' /Rect [60 90 220 230] /Contents (Original) /T (Teacher) /Subj (Keep this metadata) /NM (shape-1) /CreationDate (D:20261107000000Z) /F '+flags+b' /C '+color+b' /CA '+opacity+b' '+border+b' '+ap+b' '+geometry+b' '+extra+b' >>'
        return serialize([
            b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 360] /Resources << >> /Contents 4 0 R /Annots [5 0 R'+(b' 7 0 R' if shared else b'')+b'] >>',
            stream(b'.8 .9 1 rg 0 0 300 360 re f'),mark,
            stream(b'q /Half gs .8 .2 .1 rg 0 0 100 100 re f Q 0 0 1 RG 4 w [9 4] 2 d 5 5 90 90 re S',b'/Subtype /Form /BBox [0 0 100 100] /Matrix [1 .2 -.1 1 5 2] /Resources << /ExtGState << /Half << /ca .5 >> >> >>'),
            mark.replace(b'[60 90 220 230]',b'[20 20 80 80]').replace(b'(shape-1)',b'(shape-2)')])
    cases={
        'transformed':handmade(),
        'shared':handmade(shared=True),
        'states':handmade(ap=b'/AP << /N << /Selected 6 0 R >> /R 6 0 R /D 6 0 R >> /AS /Selected'),
        'cloudy-metadata':handmade(extra=b'/BE << /S /C /I 2 >> /RD [4 5 6 7] /Custom (Preserve me)'),
        'locked':handmade(flags=b'132'),
        'rich':handmade(extra=b'/RC (<p>Rich note</p>)'),
        'line-caption':handmade(subtype=b'Line',geometry=b'/L [80 100 200 210] /LE [/ClosedArrow /ROpenArrow] /Cap true /CO [2 3] /LL 12 /LLE 4 /LLO 2'),
    }
    for subtype in (b'Square', b'Circle'):
        for variant,options in {
            'solid':dict(border=b'/BS << /W 3 >>',extra=b'/IC [.8 .7 .2]',opacity=b'1'),
            'dashed':dict(extra=b'/IC [.8 .7 .2]',opacity=b'.5'),
            'insets':dict(extra=b'/RD [5 10 15 20] /IC [.8 .7 .2]',border=b'/BS << /W 2 >>',opacity=b'1'),
            'partial-insets':dict(extra=b'/RD [0 3 0 3] /IC [.8 .7 .2]',border=b'/BS << /W 8 >>',opacity=b'1'),
            'default':dict(border=b'',color=b'null',opacity=b'1'),
            'transparent':dict(color=b'[]',extra=b'/IC [.8 .7 .2]',opacity=b'.5'),
            'zero-width':dict(border=b'/BS << /W 0 >>',extra=b'/IC [.8 .7 .2]',opacity=b'.5'),
            'legacy':dict(border=b'/Border [0 0 3 [9 4]]',extra=b'/IC [.8 .7 .2]',opacity=b'1'),
            'border-precedence':dict(border=b'/Border [5 5 50] /BS << /W 2 /S /S >>',opacity=b'1'),
            'default-dash':dict(border=b'/BS << /W 2 /S /D >>',opacity=b'1'),
            'odd-dash':dict(border=b'/BS << /W 2 /S /D /D [7 3 2] >>',opacity=b'1'),
        }.items():
            cases['fallback-'+subtype.decode().lower()+'-'+variant]=handmade(ap=b'',subtype=subtype,**options)
    endings=['None','Square','Circle','Diamond','OpenArrow','ClosedArrow','Butt','ROpenArrow','RClosedArrow','Slash']
    for i,ending in enumerate(endings):
        # Alternating diagonal direction and mixed endings exercise both endpoints.
        geom=b'/L [85 120 195 195]' if i%2==0 else b'/L [195 120 85 195]'
        geom+=f' /LE [/{ending} /{endings[(i+3)%len(endings)]}]'.encode()
        cases['fallback-line-'+ending.lower()]=handmade(ap=b'',subtype=b'Line',geometry=geom,extra=b'/IC [.8 .7 .2]',opacity=b'1' if i%2==0 else b'.5')
    for kind in (b'PolyLine',b'Polygon'):
        for variant,geometry,options in [
            ('solid',b'/Vertices [80 115 105 200 190 130]',dict(border=b'/BS << /W 3 >>',opacity=b'1')),
            ('dashed',b'/Vertices [80 115 105 200 190 130]',dict(opacity=b'1')),
            ('duplicate',b'/Vertices [80 115 80 115 105 200 190 130 190 130]',dict(border=b'/BS << /W 3 >>',opacity=b'.5')),
            ('acute',b'/Vertices [80 115 175 195 85 125]',dict(border=b'/BS << /W 4 >>',opacity=b'1')),
        ]:
            if kind==b'PolyLine': geometry+=b' /LE [/Circle /ClosedArrow]'
            cases['fallback-'+kind.decode().lower()+'-'+variant]=handmade(ap=b'',subtype=kind,geometry=geometry,extra=b'/IC [.8 .7 .2]',**options)
    for name,geometry in {
        'leader-positive':b'/L [85 130 185 130] /LL 20 /LLE 6 /LLO 4 /LE [/OpenArrow /ClosedArrow]',
        'leader-negative':b'/L [85 160 185 190] /LL -20 /LLE 6 /LLO 4 /LE [/Butt /Slash]',
        'horizontal':b'/L [85 160 185 160]',
        'vertical':b'/L [130 120 130 200] /LE [/ROpenArrow /RClosedArrow]',
        'coincident':b'/L [130 160 130 160] /LE [/Circle /Square]',
    }.items():
        cases['fallback-line-'+name]=handmade(ap=b'',subtype=b'Line',geometry=geometry,extra=b'/IC [.8 .7 .2]',opacity=b'1')
    for name,data in cases.items():
        if name.startswith(('fallback-line-', 'fallback-polyline-', 'fallback-polygon-')):
            # Rect must enclose outward-facing markers as well as the vertices.
            data=data.replace(b'/Rect [60 90 220 230]',b'/Rect [40 60 250 260]')
        (root/(name+'.pdf')).write_bytes(data); names.append(name)
    bad={
        'missing-ap':handmade(ap=b'',subtype=b'Line',geometry=b'/L [60 90 220 230] /Cap true /CP /Invalid'),'missing-normal':handmade(ap=b'/AP << >>'),
        'malformed-normal':handmade(ap=b'/AP << /N 99 0 R >>'),
        'state':handmade(ap=b'/AP << /N << /On 6 0 R >> >> /AS /Off'),
        'hidden':handmade(flags=b'2'),
        'no-zoom':handmade(flags=b'8'),
        'optional-content':handmade(extra=b'/OC << /Type /OCG >>'),
        'line-geometry':handmade(subtype=b'Line',geometry=b'/L [1 2 3]'),
        'polygon-geometry':handmade(subtype=b'Polygon',geometry=b'/Vertices [1 2 3 4]'),
        'nonfinite-range':handmade(subtype=b'PolyLine',geometry=b'/Vertices [1 2 3000000 4]'),
        'color':handmade(color=b'[2 0 0]'),
        'opacity':handmade(opacity=b'2'),
        'fallback-insets':handmade(ap=b'',extra=b'/RD [100 0 60 0]'),
        'fallback-negative-insets':handmade(ap=b'',extra=b'/RD [-1 0 0 0]'),
        'fallback-cloudy':handmade(ap=b'',extra=b'/BE << /S /C /I 2 >>'),
        'fallback-border':handmade(ap=b'',border=b'/BS << /W -1 >>'),
        'fallback-dash':handmade(ap=b'',border=b'/BS << /W 2 /S /D /D [0 0] >>'),
        'fallback-endings':handmade(ap=b'',subtype=b'Line',geometry=b'/L [60 90 220 230] /LE [/Square]'),
        'fallback-ending-name':handmade(ap=b'',subtype=b'PolyLine',geometry=b'/Vertices [60 90 220 230] /LE [/Unknown /None]'),
        'fallback-leader':handmade(ap=b'',subtype=b'Line',geometry=b'/L [60 90 220 230] /LLE 5'),
        'fallback-leader-negative':handmade(ap=b'',subtype=b'Line',geometry=b'/L [60 90 220 230] /LL 20 /LLO -1'),
        'fallback-rounded':handmade(ap=b'',border=b'/Border [2 2 3]'),
    }
    for name,data in bad.items(): (invalid/(name+'.pdf')).write_bytes(data)
    (root/'cases.json').write_text(json.dumps(names))
    print(f'PASS: {len(names)} foreign shape fixtures; {len(bad)} invalid fixtures')
    raise SystemExit

import numpy as np
from pypdf import PdfReader

def reference_document(path, name):
    doc=pymupdf.open(path)
    if name.endswith('-default-dash'):
        # ISO 32000-1 table 166 specifies [3]. MuPDF and PDFBox omit this default.
        # Materialize it only in the oracle; source and saved inputs stay untouched.
        for mark in doc[0].annots() or []:
            doc.xref_set_key(mark.xref,'BS/D','[3]')
        normalized=doc.tobytes();doc.close()
        return pymupdf.open(stream=normalized,filetype='pdf')
    if name.startswith(('fallback-line-', 'fallback-polyline-', 'fallback-polygon-')):
        # Use MuPDF's native appearance writer; PyMuPDF's higher-level update()
        # adds a second set of differently sized PolyLine endpoint decorations.
        page=doc[0]
        changed=False
        for mark in page.annots() or []:
            if doc.xref_get_key(mark.xref,'AP')[0]!='null': continue
            if mark.type[0] in (pymupdf.PDF_ANNOT_POLY_LINE, pymupdf.PDF_ANNOT_POLYGON):
                # Zero-length segments leave the same path, but MuPDF's marker
                # direction calculation uses the immediate duplicate endpoint.
                raw=list(map(float,doc.xref_get_key(mark.xref,'Vertices')[1].strip('[]').split()))
                vertices=list(zip(raw[::2],raw[1::2]))
                compact=[v for i,v in enumerate(vertices) if i==0 or v!=vertices[i-1]]
                if len(compact)!=len(vertices):
                    doc.xref_set_key(mark.xref,'Vertices','['+' '.join(str(v) for pair in compact for v in pair)+']')
            original_rect=doc.xref_get_key(mark.xref,'Rect')[1]
            pymupdf.mupdf.pdf_dirty_annot(mark.this)
            pymupdf.mupdf.pdf_update_annot(mark.this)
            # Its auto-computed bounds omit acute miter extents. Geometry is
            # already in page coordinates: retain the input annotation clip.
            appearance=int(doc.xref_get_key(mark.xref,'AP/N')[1].split()[0])
            doc.xref_set_key(appearance,'BBox',original_rect)
            doc.xref_set_key(mark.xref,'Rect',original_rect)
            changed=True
        if changed:
            normalized=doc.tobytes();doc.close()
            reference=pymupdf.open(stream=normalized,filetype='pdf')
            reference._pod_generated_shape_ap=True
            return reference
    return doc

def square_reference(path, output, width):
    # MuPDF caps a dash across the closed seam. PDFBox joins it, but its fallback
    # also changes geometry and composites fill/stroke separately. Supply an
    # analytic standard appearance to that test-only reader, with one opacity group.
    from pypdf import PdfWriter
    from pypdf.generic import NameObject as N, DictionaryObject as D, DecodedStreamObject, ArrayObject, FloatObject, BooleanObject
    writer=PdfWriter();writer.append(PdfReader(path))
    for ref in writer.pages[0].get('/Annots',[]):
        mark=ref.get_object()
        if '/AP' in mark:
            shape=mark['/AP']['/N'].get_object()
            bbox=shape['/BBox']
            state=shape['/Resources']['/ExtGState']['/GS']
            assert float(state['/CA'])==float(mark['/CA']) and float(state['/ca'])==float(mark['/CA'])
            state[N('/CA')]=FloatObject(1);state[N('/ca')]=FloatObject(1)
        else:
            x0,y0,x1,y1=map(float,mark['/Rect'])
            bbox=ArrayObject([FloatObject(v) for v in (x0,y0,x1,y1)])
            shape=DecodedStreamObject()
            shape.set_data(f'.1 .3 .7 RG .8 .7 .2 rg 3 w [9 4] 0 d {x0+1.5} {y0+1.5} {x1-x0-3} {y1-y0-3} re B'.encode())
            shape.update({N('/Subtype'):N('/Form'),N('/BBox'):bbox})
        shape[N('/Group')]=D({N('/S'):N('/Transparency'),N('/I'):BooleanObject(True),N('/K'):BooleanObject(True)})
        ap=DecodedStreamObject();ap.set_data(b'q /GS gs /Shape Do Q')
        ap.update({N('/Subtype'):N('/Form'),N('/BBox'):bbox,N('/Resources'):D({N('/XObject'):D({N('/Shape'):writer._add_object(shape)}),N('/ExtGState'):D({N('/GS'):D({N('/CA'):mark['/CA'],N('/ca'):mark['/CA']})})})})
        mark[N('/AP')]=D({N('/N'):writer._add_object(ap)})
    reference=output.with_suffix('.pdf');writer.write(reference)
    # Supersample the oracle's transparency-group bitmap to avoid Java2D's
    # whole-pixel group placement at half-pixel shape edges.
    subprocess.run(['java','--class-path','.tools/pdfbox-app-3.0.5.jar','tools/PdfboxRender.java',str(reference),str(output),str(width*4)],check=True)
    result=pymupdf.Pixmap(str(output));result.shrink(2)
    return result

def path_reference(path, output, width):
    # Java2D and Ghostscript disagree at exact dash/corner boundaries. PDFBox's
    # geometry agrees with explicit analytic dash contours; isolate each paint
    # to apply opacity once to combined fill/stroke, as required for PDF B/b.
    from pypdf import PdfWriter
    from pypdf.generic import NameObject as N, DictionaryObject as D, DecodedStreamObject, FloatObject, BooleanObject, ContentStream
    writer=PdfWriter();writer.append(PdfReader(path))
    for ref in writer.pages[0].get('/Annots',[]):
        mark=ref.get_object();form=mark['/AP']['/N'].get_object()
        resources=form['/Resources'];alpha=float(mark.get('/CA',1))
        for state in resources.get('/ExtGState',{}).values():
            state=state.get_object()
            assert float(state.get('/CA',1))==alpha and float(state.get('/ca',1))==alpha
            state[N('/CA')]=FloatObject(1);state[N('/ca')]=FloatObject(1)
        prefix=[];commands=[];calls=[];layers=D();depth=0
        for operands,op in ContentStream(form,writer).operations:
            if op in (b'm',b'l',b'c',b're',b'h'): commands.append((operands,op))
            elif op in (b'S',b's',b'B',b'b',b'f'):
                stream=ContentStream(None,writer)
                stream.operations=prefix+commands+[(operands,op)]+[([],b'Q')]*depth
                layer=DecodedStreamObject();layer.set_data(stream.get_data())
                layer.update({N('/Subtype'):N('/Form'),N('/BBox'):form['/BBox'],N('/Resources'):resources,N('/Group'):D({N('/S'):N('/Transparency'),N('/I'):BooleanObject(True),N('/K'):BooleanObject(True)})})
                key='/Paint'+str(len(layers));layers[N(key)]=writer._add_object(layer)
                calls.append(f'q /Opacity gs {key} Do Q');commands=[]
            else:
                prefix.append((operands,op))
                if op==b'q':depth+=1
                if op==b'Q':depth-=1
        replacement=DecodedStreamObject();replacement.set_data('\n'.join(calls).encode())
        replacement.update({N('/Subtype'):N('/Form'),N('/BBox'):form['/BBox'],N('/Resources'):D({N('/XObject'):layers,N('/ExtGState'):D({N('/Opacity'):D({N('/CA'):FloatObject(alpha),N('/ca'):FloatObject(alpha)})})})})
        mark[N('/AP')]=D({N('/N'):writer._add_object(replacement)})
    reference=output.with_suffix('.pdf');writer.write(reference)
    subprocess.run(['java','--class-path','.tools/pdfbox-app-3.0.5.jar','tools/PdfboxRender.java',str(reference),str(output),str(width*4)],check=True)
    result=pymupdf.Pixmap(str(output));result.shrink(2)
    return result

def appearances(mark):
    def snapshot(value):
        value=value.get_object()
        if hasattr(value,'get_data'):
            return (value.get_data(),value._data,{str(k):snapshot(v) for k,v in value.items() if k!='/Length'})
        if isinstance(value,dict): return {str(k):snapshot(v) for k,v in value.items()}
        if isinstance(value,list): return [snapshot(v) for v in value]
        return str(value)
    return snapshot(mark.get('/AP')) if mark.get('/AP') is not None else None

maximum_mean=maximum_interior=0; count=0
filters=[arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--filter=')]
for name in json.loads((root/'cases.json').read_text()):
    if filters and not any(name.startswith(prefix) for prefix in filters): continue
    original=PdfReader(root/(name+'.pdf'))
    base=[x.get_object() for x in original.pages[0]['/Annots'] if x.get_object()['/Subtype']!='/Popup']
    suffixes=['','-saved','-rotated','-organized']
    if name.startswith('fallback-'): suffixes+=['-resized','-restyled','-edited-again']
    if name!='locked': suffixes+=['-moved','-removed']
    if name not in ('locked','rich','line-caption'): suffixes+=['-noted']
    for suffix in suffixes:
        path=root/(name+suffix+'.pdf')
        with reference_document(path,name) as doc:
            for width in (300,600):
                expected=doc[0].get_pixmap(matrix=pymupdf.Matrix(width/doc[0].rect.width,width/doc[0].rect.width),alpha=False)
                if name in ('fallback-square-dashed','fallback-square-legacy') or (name in ('fallback-square-default-dash','fallback-square-odd-dash') and suffix in ('-resized','-restyled','-edited-again')):
                    refs=root/'references';refs.mkdir(exist_ok=True)
                    expected=square_reference(path,refs/f'{name}{suffix}-{width}.png',width)
                if name=='mupdf-polygon' or name.startswith(('fallback-line-', 'fallback-polyline-', 'fallback-polygon-')):
                    # MuPDF caps the dash at this closed seam. Ghostscript agrees
                    # with the joined outline and the analytic closed-dash tests.
                    refs=root/'references';refs.mkdir(exist_ok=True)
                    png=refs/f'{name}{suffix}-{width}.png'
                    reference=path
                    if getattr(doc,'_pod_generated_shape_ap',False):
                        reference=refs/f'{name}{suffix}.pdf'
                        reference.write_bytes(doc.tobytes())
                    supersample=1 if name=='mupdf-polygon' else 4
                    scale=width*supersample/doc[0].rect.width
                    subprocess.run(['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-dUseCropBox','-dFIXEDMEDIA','-sDEVICE=png16m','-dGraphicsAlphaBits=4','-dTextAlphaBits=4',f'-r{scale*72}',f'-g{width*supersample}x{math.ceil(doc[0].rect.height*scale)}','-sOutputFile='+str(png),str(reference)],check=True)
                    expected=pymupdf.Pixmap(str(png))
                    # Avoid whole-pixel device-height placement on fractional
                    # crop/rotation sizes while keeping the comparison tolerance.
                    if supersample==4: expected.shrink(2)
                if name.startswith('fallback-') and suffix=='-restyled' and any('/Square' in mark.get('/LE',[]) for mark in base):
                    expected=path_reference(path,root/'references'/f'{name}{suffix}-pdfbox-{width}.png',width)
                actual=pymupdf.Pixmap(str(root/f'{name}{suffix}-{width}.png'))
                assert (expected.width,expected.height)==(actual.width,actual.height),(name,suffix,'size')
                a=np.frombuffer(expected.samples,np.uint8).reshape(expected.height,expected.width,3).astype(np.int16)
                b=np.frombuffer(actual.samples,np.uint8).reshape(actual.height,actual.width,actual.n)[:,:,:3].astype(np.int16)
                delta=np.abs(a-b); mean=delta.mean(); interior=np.ones(a.shape[:2],dtype=bool)
                for y in (-1,0,1):
                    for x in (-1,0,1): interior &= np.all(a==np.roll(a,(y,x),(0,1)),axis=2)
                error=delta.max(axis=2)[interior].max()
                assert mean<1 and error<=2,(name,suffix,width,float(mean),int(error))
                maximum_mean=max(maximum_mean,float(mean)); maximum_interior=max(maximum_interior,int(error)); count+=1
        if suffix in ('-saved','-moved','-noted','-organized','-resized','-restyled','-edited-again'):
            saved=PdfReader(path); marks=[x.get_object() for x in saved.pages[0]['/Annots'] if x.get_object()['/Subtype']!='/Popup']
            assert len(base)==len(marks)
            for i,(before,after) in enumerate(zip(base,marks)):
                edited=suffix in ('-resized','-restyled','-edited-again') and i==0
                translated_dot=name=='fallback-line-coincident' and suffix=='-resized'
                regenerated=edited and not translated_dot
                if not regenerated: assert appearances(before)==appearances(after),(name,suffix,'appearance modified')
                if edited:
                    assert '/AP' not in before
                    if regenerated: assert int(after['/PodShapeAppearance'])==1
                    assert '/PodKind' not in after and after['/Subtype']==before['/Subtype']
                    expected_rect=[53.25,70.5,244,250.75] if suffix=='-resized' else [float(v)+(13.17 if j%2==0 else -7.31) for j,v in enumerate(before['/Rect'])] if suffix=='-edited-again' else list(map(float,before['/Rect']))
                    path_shape=before['/Subtype'] in ('/Line','/PolyLine','/Polygon')
                    if path_shape:
                        key='/L' if before['/Subtype']=='/Line' else '/Vertices'
                        points=list(map(float,before[key])); original_rect=list(map(float,before['/Rect']))
                        if suffix=='-resized':
                            points=[(v-original_rect[j%2])/(original_rect[2+j%2]-original_rect[j%2])*(190.75 if j%2==0 else 180.25)+(53.25 if j%2==0 else 70.5) for j,v in enumerate(points)]
                        elif suffix=='-edited-again': points=[v+(13.17 if j%2==0 else -7.31) for j,v in enumerate(points)]
                        assert np.allclose(list(map(float,after[key])),points,rtol=0,atol=1e-8)
                        expected_rect=list(map(float,after['/Rect']))
                        if translated_dot:
                            delta=[points[j]-float(before[key][j]) for j in (0,1)]
                            assert np.allclose(expected_rect,[v+delta[j%2] for j,v in enumerate(original_rect)],rtol=0,atol=1e-8)
                        assert expected_rect[2]>expected_rect[0] and expected_rect[3]>expected_rect[1]
                    else: assert np.allclose(list(map(float,after['/Rect'])),expected_rect,rtol=0,atol=1e-8)
                    if regenerated: assert np.allclose(list(map(float,after['/AP']['/N']['/BBox'])),[0,0,expected_rect[2]-expected_rect[0],expected_rect[3]-expected_rect[1]],rtol=0,atol=1e-8)
                    if suffix!='-resized':
                        assert list(map(float,after['/C']))==[.65,.15,.35]
                        assert list(map(float,after['/IC']))==[.2,.7,.4] and float(after['/CA'])==.6
                        expected_width=1.25 if suffix=='-edited-again' else 4
                        assert float(after['/BS']['/W'] if '/BS' in after else after['/Border'][2])==expected_width
                        if '/BS' in before:
                            assert str(before['/BS'].get('/S'))==str(after['/BS'].get('/S'))
                            assert str(before['/BS'].get('/D'))==str(after['/BS'].get('/D'))
                        elif '/Border' in before:
                            assert before['/Border'][:2]==after['/Border'][:2] and before['/Border'][3:]==after['/Border'][3:]
                changed={'/Rect','/L','/Vertices'} if suffix=='-moved' and i==0 else {'/Contents'} if suffix=='-noted' and i==0 else set()
                if edited: changed={'/Rect','/L','/Vertices'} if suffix=='-resized' else {'/Rect','/L','/Vertices','/Contents','/C','/IC','/CA','/BS','/Border'}
                for key in before:
                    if key not in changed|{'/AP','/P','/Popup','/AAPL:AKExtras'}:
                        assert str(before[key])==str(after[key]),(name,suffix,key)
                if suffix=='-moved' and i==0:
                    assert [float(x) for x in after['/Rect']]==[float(x)+(13 if j%2==0 else -7) for j,x in enumerate(before['/Rect'])]
    print('PASS:',name,'independent appearance and metadata preservation')
print(f'{count} independent shape rasters; maximum mean {maximum_mean:.6f}/255; maximum interior {maximum_interior}/255')
