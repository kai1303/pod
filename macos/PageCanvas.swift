import AppKit

final class PageCanvas: NSView {
    override var isFlipped: Bool { true }
    var image: NSImage?
    var page: PageInfo?
    var zoom: CGFloat=1
    var selected: Int?
    var onSelect: ((Int?) -> Void)?
    var tool:MarkupKind?=nil { didSet { draft=[]; needsDisplay=true; window?.invalidateCursorRects(for:self) } }
    var erasing=false
    var annotationStyle=MarkupStyle()
    var annotationSelection:UInt32?
    var interactionEnabled=true
    var onAnnotationSelect:((UInt32?)->Void)?
    var onCreate:(([Markup])->Void)?
    var onUpdate:((Markup)->Void)?
    var onDelete:((UInt32)->Void)?
    private var draft:[CGPoint]=[]
    private var dragStart:CGPoint?
    private var moving:Markup?
    private var resizing=false
    private var dragged=false
    private var preview:Markup?

    var pageRect: CGRect {
        guard let page else { return .zero }
        let size=CGSize(width:page.box.width*zoom,height:page.box.height*zoom)
        return CGRect(x:max(28,(bounds.width-size.width)/2),y:28,width:size.width,height:size.height)
    }
    func configure(_ pixels: PagePixels, page: PageInfo, zoom: CGFloat) {
        draft=[]; dragStart=nil; moving=nil; preview=nil; dragged=false
        self.page=page; self.zoom=zoom
        let provider=CGDataProvider(data:pixels.data as CFData)!
        let cg=CGImage(width:pixels.width,height:pixels.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:pixels.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        image=NSImage(cgImage:cg,size:page.box.size)
        resizeToViewport()
    }
    func resizeToViewport() {
        guard let page else { return }
        let viewport=enclosingScrollView?.contentSize ?? .zero
        setFrameSize(CGSize(width:max(viewport.width,page.box.width*zoom+56),height:max(viewport.height,page.box.height*zoom+56)))
        needsDisplay=true
    }
    func viewRect(_ pdf: CGRect) -> CGRect {
        guard let page else { return .zero }
        return CGRect(x:pageRect.minX+(pdf.minX-page.box.minX)*zoom,y:pageRect.minY+(page.box.maxY-pdf.maxY)*zoom,width:max(pdf.width*zoom,3),height:max(pdf.height*zoom,4))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite:0.91,alpha:1).setFill(); bounds.fill()
        guard let page, let image else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius=12; shadow.shadowOffset=NSSize(width:0,height:2); shadow.set()
        NSColor.white.setFill(); pageRect.fill()
        NSGraphicsContext.restoreGraphicsState()
        image.draw(in:pageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        drawMarkupOverlay()
        if let id=selected, let run=page.runs.first(where:{$0.id==id}) {
            let rect=viewRect(run.bounds).insetBy(dx:-3,dy:-2)
            NSColor.systemTeal.withAlphaComponent(0.12).setFill(); rect.fill()
            NSColor.systemTeal.setStroke(); let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3); path.lineWidth=1.5; path.stroke()
        }
    }
    private func pdfPoint(_ event:NSEvent) -> CGPoint {
        let p=convert(event.locationInWindow,from:nil)
        guard let page else { return .zero }
        return CGPoint(x:min(page.box.maxX,max(page.box.minX,(p.x-pageRect.minX)/zoom+page.box.minX)),y:min(page.box.maxY,max(page.box.minY,page.box.maxY-(p.y-pageRect.minY)/zoom)))
    }
    private func pointRect(_ points:[CGPoint]) -> CGRect {
        guard let first=points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(x:first.x,y:first.y,width:0,height:0)) { r,p in
            let x=min(r.minX,p.x),y=min(r.minY,p.y)
            return CGRect(x:x,y:y,width:max(r.maxX,p.x)-x,height:max(r.maxY,p.y)-y)
        }
    }
    private func mark(_ kind:MarkupKind,_ points:[CGPoint]) -> Markup { Markup(kind:kind,points:points,rect:pointRect(points),style:annotationStyle) }
    override func mouseDown(with event:NSEvent) {
        guard interactionEnabled,pageRect.contains(convert(event.locationInWindow,from:nil)) else { return }
        window?.makeFirstResponder(self)
        let p=pdfPoint(event); dragStart=p; dragged=false; moving=nil; preview=nil
        if erasing {
            if let hit=page?.annotations.reversed().first(where:{$0.hitTest(p,tolerance:4/zoom)}) { onDelete?(hit.id) }
            return
        }
        if let tool {
            if tool == .polyline || tool == .polygon {
                if draft.last.map({hypot($0.x-p.x,$0.y-p.y)>1/zoom}) ?? true { draft.append(p) }
                if event.clickCount>1 { finishPolygon() }
            } else if tool.isText {
                let box=CGRect(x:p.x,y:p.y-(tool == .comment ? 24:40),width:tool == .comment ? 24:240,height:tool == .comment ? 24:40)
                onCreate?([mark(tool,[box.origin,CGPoint(x:box.maxX,y:box.maxY)])])
            } else { draft=[p] }
            needsDisplay=true; return
        }
        if let id=annotationSelection,let hit=page?.annotations.first(where:{$0.id==id}),hypot(p.x-hit.geometryBounds.maxX,p.y-hit.geometryBounds.minY)<9/zoom {
            moving=hit; resizing=true; return
        }
        if let hit=page?.annotations.reversed().first(where:{$0.hitTest(p,tolerance:4/zoom)}) {
            annotationSelection=hit.id; selected=nil; onAnnotationSelect?(hit.id); moving=hit; resizing=false
        } else {
            annotationSelection=nil; onAnnotationSelect?(nil)
            let hit=page?.runs.reversed().first { $0.bounds.insetBy(dx:-4/zoom,dy:-4/zoom).contains(p) }
            selected=hit?.id; onSelect?(selected)
        }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard interactionEnabled,!erasing,let start=dragStart else { return }
        let p=pdfPoint(event); dragged=true
        if let moving {
            if resizing {
                let bounds=moving.geometryBounds
                let box=CGRect(x:bounds.minX,y:min(p.y,bounds.maxY-4),width:max(4,p.x-bounds.minX),height:max(4,bounds.maxY-p.y))
                preview=moving.scaled(to:box)
            } else { preview=moving.translated(x:p.x-start.x,y:p.y-start.y) }
        } else if let tool,!tool.isText,tool != .polygon,tool != .polyline {
            if tool.isFreehand { if draft.count>=4096 { draft=draft.enumerated().compactMap{ $0.offset.isMultiple(of:2) ? $0.element:nil } }; draft.append(p) } else { draft=[start,p] }
        }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        guard interactionEnabled,!erasing,let start=dragStart else { return }
        defer { dragStart=nil; moving=nil; preview=nil; needsDisplay=true }
        if let value=preview,dragged { onUpdate?(value); return }
        guard let tool,!tool.isText,tool != .polygon,tool != .polyline else { return }
        let end=pdfPoint(event)
        if tool.isTextMarkup {
            let region=pointRect([start,end]).insetBy(dx:-1/zoom,dy:-1/zoom)
            let runs=page?.runs.filter { dragged ? $0.bounds.intersects(region):$0.bounds.insetBy(dx:-3/zoom,dy:-3/zoom).contains(start) } ?? []
            let marks=runs.filter{!$0.text.isEmpty}.map { run in mark(tool,[run.bounds.origin,CGPoint(x:run.bounds.maxX,y:run.bounds.maxY)]) }
            if !marks.isEmpty { onCreate?(marks) }
        } else if tool.isFreehand ? Markup.hasDrawnExtent(draft,threshold:1/zoom):hypot(end.x-start.x,end.y-start.y)>1/zoom {
            onCreate?([mark(tool,tool.isFreehand ? draft:[start,end])])
        }
        draft=[]
    }
    private func finishPolygon() {
        guard let tool,draft.count >= (tool == .polygon ? 3:2) else { return }
        onCreate?([mark(tool,draft)]); draft=[]; needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 { draft=[]; preview=nil; moving=nil; dragStart=nil; needsDisplay=true; return }
        if event.keyCode==36 { finishPolygon(); return }
        if [51,117].contains(event.keyCode),let id=annotationSelection { onDelete?(id); return }
        super.keyDown(with:event)
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(pageRect,cursor:tool == nil && !erasing ? .arrow:.crosshair) }
    private func drawMarkupOverlay() {
        if let id=annotationSelection,let mark=preview ?? page?.annotations.first(where:{$0.id==id}) {
            let rect=viewRect(mark.geometryBounds).insetBy(dx:-2,dy:-2)
            NSColor.systemTeal.setStroke(); let path=NSBezierPath(rect:rect); path.lineWidth=1.5; path.stroke()
            NSColor.white.setFill(); let handle=NSRect(x:rect.maxX-4,y:rect.maxY-4,width:8,height:8); handle.fill(); NSColor.systemTeal.setStroke(); NSBezierPath(rect:handle).stroke()
        }
        guard let tool,!draft.isEmpty else { return }
        let path=NSBezierPath(); path.lineWidth=max(1,annotationStyle.width*zoom)
        func viewPoint(_ p:CGPoint) -> CGPoint { let r=viewRect(CGRect(x:p.x,y:p.y,width:0,height:0)); return CGPoint(x:r.minX,y:r.minY) }
        if tool.isPath || tool == .line || tool == .arrow {
            path.move(to:viewPoint(draft[0])); for p in draft.dropFirst() { path.line(to:viewPoint(p)) }; if tool == .polygon && draft.count>2 { path.close() }
        } else if draft.count>1 {
            let rect=viewRect(pointRect(draft))
            if tool == .ellipse { path.appendOval(in:rect) } else { path.appendRect(rect) }
        }
        if let fill=annotationStyle.fill { fill.withAlphaComponent(annotationStyle.opacity).setFill(); path.fill() }
        annotationStyle.stroke.withAlphaComponent(annotationStyle.opacity).setStroke(); path.stroke()
    }
}
