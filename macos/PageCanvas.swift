import AppKit

final class PageCanvas: NSView {
    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    private var metalView: MetalPageView?
    private var overlay: PageOverlayView?
    var didPresentMetal: Bool { metalView?.didPresentViewport == true }
    var presentationTime: CFTimeInterval { metalView?.presentationTime ?? 0 }
    var onMetalFailure: (() -> Void)?
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            super.needsDisplay = newValue
            // AppKit may coalesce the parent invalidation while its child still needs repainting.
            if newValue { overlay?.needsDisplay = true }
        }
    }
    var image: NSImage?
    var page: PageInfo?
    var zoom: CGFloat=1
    var selected: Int?
    var onSelect: ((Int?) -> Void)?
    var tool: MarkupKind? {
        willSet { finishInk() }
        didSet {
            onCursor?(nil,false)
            onDraft?(nil)
            draft=[]
            needsDisplay=true
            window?.invalidateCursorRects(for:self)
        }
    }
    var panning = false {
        didSet { panStart = nil; window?.invalidateCursorRects(for: self) }
    }
    private var panStart: (mouse: CGPoint, origin: CGPoint)?
    var erasing=false { didSet { if !erasing { eraserTrail=[] } } }
    var eraserWidth: CGFloat = 16
    private var eraserTrail: [CGPoint] = []
    var onEraseAnnotations: (([Markup], [UInt32]) -> Void)?
    var onEraseSharedGroup: (([(UUID,Markup)], [UUID]) -> Void)?
    var onEraseLimit: (() -> Void)?
    var selectedSharedInk: UUID? { didSet { if oldValue != selectedSharedInk { selectionChanged() } } }
    var onSelectSharedInk: ((UUID?) -> Void)?
    var onUpdateSharedInk: ((UUID,Markup) -> Void)?
    private var movingSharedID: UUID?
    private var selectionMark: Markup? {
        if collaborating { return sharedDrawings.first { $0.id == selectedSharedInk && $0.owner == drawingOwner }?.markup }
        return page?.annotations.first { $0.id == annotationSelection }
    }
    var annotationStyle=MarkupStyle() { willSet { if tool == .ink { finishInk() } } }
    var annotationSelection:UInt32? { didSet { if oldValue != annotationSelection { selectionChanged() } } }
    var interactionEnabled=true { didSet { if !interactionEnabled { onCursor?(nil,false) } } }
    var onAnnotationSelect:((UInt32?)->Void)?
    var onCreate:(([Markup])->Void)?
    var onUpdate:((Markup)->Void)?
    var onDelete:((UInt32)->Void)?
    var collaborating=false
    var drawingOwner:DrawingOwner = .host
    var sharedDrawings:[DrawingStroke]=[]
    var sharedPreview:DrawingStroke?
    var remoteCursor:DrawingCursor?
    var onCursor:((CGPoint?,Bool)->Void)?
    private var cursorTracking:NSTrackingArea?
    private var resignObserver:NSObjectProtocol?
    private var scrollObserver:NSObjectProtocol?
    var onDraft:((Markup?)->Void)?
    var onEraseShared:((UUID)->Void)?
    private var draft:[CGPoint]=[]
    private var pendingDrafts:[(id:Int, mark:Markup)]=[]
    private var nextDraftID=0
    private var committedDraftID=0
    private weak var pendingScene:MetalPage?

    // The PDF renderer bakes local annotations into the page. Fade the previous
    // page through a mask around the changed ink so text beneath it stays visible.
    private struct InkFade {
        let image: NSImage
        let previousShared: [DrawingStroke]
        let mask: CGPath  // unzoomed, top-left page coordinates
        let start: TimeInterval
    }
    private var inkFade: InkFade?
    private var selectionStart: TimeInterval?
    private var motionDisplayLink: CADisplayLink?
    private let fadeDuration: TimeInterval = 0.18
    private var allowsMotion: Bool {
        window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private func progress(since start: TimeInterval) -> CGFloat {
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - start) / fadeDuration))
        return t * t * (3 - 2 * t)
    }
    private func selectionChanged() {
        selectionStart = allowsMotion && selectionMark?.kind == .ink ? ProcessInfo.processInfo.systemUptime : nil
        if selectionStart != nil { startMotionFrames() }
        needsDisplay = true
    }
    private func stopMotion() {
        inkFade = nil
        selectionStart = nil
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
    }
    private func startMotionFrames() {
        guard motionDisplayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(advanceMotion))
        motionDisplayLink = link
        link.add(to: .main, forMode: .common)
    }
    @objc private func advanceMotion() {
        var dirty = CGRect.null
        if let fade = inkFade {
            let box = fade.mask.boundingBoxOfPath
            dirty = CGRect(x: pageRect.minX + box.minX * zoom, y: pageRect.minY + box.minY * zoom,
                           width: box.width * zoom, height: box.height * zoom).insetBy(dx: -2, dy: -2)
            if progress(since: fade.start) >= 1 { inkFade = nil }
        }
        if let start = selectionStart {
            if let mark = selectionMark {
                dirty = dirty.union(viewRect(mark.geometryBounds).insetBy(dx: -10, dy: -28))
            }
            if progress(since: start) >= 1 { selectionStart = nil }
        }
        if !allowsMotion || (inkFade == nil && selectionStart == nil) { stopMotion() }
        if !dirty.isNull {
            if let overlay { overlay.setNeedsDisplay(overlay.convert(dirty, from: self)) }
            else { setNeedsDisplay(dirty) }
        }
    }
    func fadeInkChange(_ marks: [Markup], previousShared: [DrawingStroke] = []) {
        guard allowsMotion, let image, let page, !marks.isEmpty else { return }
        let mask = CGMutablePath()
        for mark in marks {
            mask.addPath(mark.inkOutline(width: mark.style.width + 2 / zoom, transform: page.displayPoint))
        }
        let region = mask.boundingBoxOfPath
        let nearby = previousShared.filter { stroke in
            let mark = stroke.markup
            let padding = mark.style.width / 2 + 1 / zoom
            return page.displayRect(mark.geometryBounds).insetBy(dx: -padding, dy: -padding).intersects(region)
        }
        inkFade = InkFade(image: image, previousShared: nearby, mask: mask,
                          start: ProcessInfo.processInfo.systemUptime)
        startMotionFrames()
        needsDisplay = true
    }
    private func drawInkFade() {
        guard let fade = inkFade, let context = NSGraphicsContext.current?.cgContext else { return }
        var transform = CGAffineTransform(translationX: pageRect.minX, y: pageRect.minY).scaledBy(x: zoom, y: zoom)
        guard let mask = fade.mask.copy(using: &transform) else { return }
        context.saveGState()
        context.addPath(mask)
        context.clip()
        context.setAlpha(1 - progress(since: fade.start))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        fade.image.draw(in: pageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for stroke in fade.previousShared { drawShared(stroke) }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    func retainAnnotationDraft(_ mark: Markup) -> Int? {
        guard mark.id == 0, mark.kind.isFreehand || !draft.isEmpty else { return nil }
        nextDraftID += 1
        pendingDrafts.append((nextDraftID,mark))
        return nextDraftID
    }
    func discardDraft(_ id:Int?) {
        pendingDrafts.removeAll { $0.id == id }
        needsDisplay=true
    }
    private func finishPresentedDrafts() {
        pendingDrafts.removeAll { $0.id <= committedDraftID }
        pendingScene=nil
        needsDisplay=true
    }

    var hasPendingInk: Bool { tool == .ink && (liftedInk != nil || !draft.isEmpty) }
    var onInkLift: (() -> Void)?
    private var liftedInk: Markup?
    private var inkCompletion: DispatchWorkItem?
    private var lastLift: TimeInterval = 0
    private static let groupingInterval: TimeInterval = 0.1

    private func inkWithCurrentPath() -> Markup? {
        guard !draft.isEmpty else { return liftedInk }
        guard var group = liftedInk else { return mark(.ink, draft) }
        if group.inkPathStarts.isEmpty { group.inkPathStarts = [0] }
        group.inkPathStarts.append(group.points.count)
        group.points.append(contentsOf: draft)
        group.rect = group.geometryBounds
        return group
    }

    // Seal the group before a document action captures its PDF bytes.
    func finishInk() {
        guard tool == .ink else { return }
        inkCompletion?.cancel()
        inkCompletion = nil
        let ink = inkWithCurrentPath()
        liftedInk = nil
        draft = []
        dragStart = nil
        if let ink {
            onCreate?([ink])
            onDraft?(nil)
            needsDisplay = true
        }
    }

    private func publishInkPreview() {
        if collaborating { onDraft?(inkWithCurrentPath()) }
    }

    private func appendInkPoint(_ point: CGPoint) {
        guard point != draft.last else { return }
        // A PDF mark and a peer record both hold at most 4096 samples.
        if let group = liftedInk, group.points.count + draft.count >= 4096 {
            liftedInk = nil
            onCreate?([group])
        }
        if draft.count >= 4096 { draft = draft.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil } }
        draft.append(point)
    }

    private var dragStart:CGPoint?
    private var moving:Markup?
    private var rotating = false
    private func rotationHandle(for mark: Markup) -> CGPoint {
        let frame = viewRect(mark.geometryBounds).insetBy(dx:-2,dy:-2)
        return CGPoint(x:frame.midX, y:frame.minY-20 >= pageRect.minY+5 ? frame.minY-20 : frame.maxY+20)
    }
    private var resizing=false
    private var dragged=false
    var isTransformCommit: Bool { moving != nil && preview != nil && dragged }
    private var preview:Markup?

    private var pageLayout:LuminCanvasLayout? {
        page.map{LuminCanvasLayout(pageSize:$0.displaySize,zoom:zoom,viewport:bounds.size)}
    }
    var pageRect:CGRect { pageLayout?.imageFrame ?? .zero }
    // Rotation is a viewing preference. Keep PDF points and saved bytes in their original space.
    private func rotatedImage(_ image: CGImage, degrees: Int) -> CGImage? {
        let sideways = degrees % 180 != 0
        let width = sideways ? image.height : image.width
        let height = sideways ? image.width : image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(degrees) * .pi / 180)
        context.draw(image, in: CGRect(x: -CGFloat(image.width)/2, y: -CGFloat(image.height)/2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    func configure(_ pixels: PagePixels, page original: PageInfo, zoom: CGFloat, metalPage scene: MetalPage? = nil, viewRotation: Int = 0, completingAnnotation:Bool = false, draftID:Int? = nil, fadingInk: [Markup] = []) {
        stopMotion()
        fadeInkChange(fadingInk)
        let metalPage = viewRotation == 0 ? scene : nil
        let page = PageInfo(box: original.box, mediaBox: original.mediaBox,
                            rotation: (original.rotation + viewRotation) % 360,
                            runs: original.runs, annotations: original.annotations)
        if !completingAnnotation || tool?.isFreehand != true {
            onCursor?(nil,false); onDraft?(nil); draft=[]; dragStart=nil; moving=nil; movingSharedID=nil; preview=nil; eraserTrail=[]; dragged=false
        }
        if completingAnnotation {
            if let draftID { committedDraftID=draftID }
            pendingScene=metalPage
            if metalPage == nil { finishPresentedDrafts() }
        } else {
            inkCompletion?.cancel()
            inkCompletion = nil
            liftedInk = nil
            pendingDrafts.removeAll()
            pendingScene=nil
        }
        self.page=page; self.zoom=zoom
        let provider=CGDataProvider(data:pixels.data as CFData)!
        let cg=CGImage(width:pixels.width,height:pixels.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:pixels.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        image=NSImage(cgImage:viewRotation == 0 ? cg : (rotatedImage(cg, degrees: viewRotation) ?? cg),size:page.displaySize)
        if let scene = metalPage {
            if metalView == nil {
                wantsLayer = true
                let view = MetalPageView(device: scene.renderer.device)
                let overlay = PageOverlayView()
                overlay.wantsLayer = true
                overlay.canvas = self
                view.onPresentation = { [weak self] scene in
                    guard let self,self.pendingScene === scene else { return }
                    self.finishPresentedDrafts()
                }
                view.onFailure = { [weak self] in self?.removeMetalView(); self?.onMetalFailure?() }
                addSubview(view)
                addSubview(overlay, positioned: .above, relativeTo: view)
                self.metalView = view
                self.overlay = overlay
            }
            metalView?.scene = scene
            metalView?.needsDisplay = true
        } else {
            removeMetalView()
        }
        resizeToViewport()
    }

    private func removeMetalView() {
        if pendingScene != nil { finishPresentedDrafts() }
        metalView?.removeFromSuperview()
        overlay?.removeFromSuperview()
        metalView = nil
        overlay = nil
        needsDisplay = true
    }

    private func updateViewport() {
        guard let view = metalView, let scene = view.scene else { return }
        let rect = pageRect
        let visible = rect.intersection(visibleRect)
        guard !visible.isEmpty else { view.isHidden = true; overlay?.isHidden = true; return }
        let sx = CGFloat(scene.width) / rect.width, sy = CGFloat(scene.height) / rect.height
        let source = CGRect(x: (visible.minX - rect.minX) * sx, y: (visible.minY - rect.minY) * sy,
                            width: visible.width * sx, height: visible.height * sy)
        if view.frame != visible || view.sourceRect != source || view.isHidden {
            view.frame = visible
            view.sourceRect = source
            view.isHidden = false
            view.needsDisplay = true
            overlay?.frame = visible
            overlay?.isHidden = false
            overlay?.needsDisplay = true
        }
    }
    func resizeToViewport() {
        guard let page else { return }
        let viewport=enclosingScrollView?.contentSize ?? .zero
        setFrameSize(LuminCanvasLayout(pageSize:page.displaySize,zoom:zoom,viewport:viewport).documentSize)
        updateViewport()
        needsDisplay=true
    }
    func viewRect(_ pdf: CGRect) -> CGRect {
        guard let page else { return .zero }
        let rect=page.displayRect(pdf)
        return CGRect(x:pageRect.minX+rect.minX*zoom,y:pageRect.minY+rect.minY*zoom,width:max(rect.width*zoom,3),height:max(rect.height*zoom,4))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        if metalView != nil { return }
        NSColor.white.setFill(); pageRect.fill()
        image.draw(in:pageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        drawOverlays()
    }
    func drawOverlays() {
        guard let page else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:pageRect).addClip()
        defer {
            if let border=pageLayout?.borderFrame { LuminLegacyStyle.outline.setStroke(); let path=NSBezierPath(rect:border.insetBy(dx:0.5,dy:0.5)); path.lineWidth=1; path.stroke() }
            NSGraphicsContext.restoreGraphicsState()
        }
        for stroke in sharedDrawings where preview == nil || stroke.id != movingSharedID { drawShared(stroke) }
        drawInkFade()
        if let stroke=sharedPreview { drawShared(stroke) }
        drawMarkupOverlay()
        drawPeerCursor()
        if let id=selected, let run=page.runs.first(where:{$0.id==id}) {
            let rect=viewRect(run.bounds).insetBy(dx:-3,dy:-2)
            PodTheme.focus.withAlphaComponent(0.12).setFill(); rect.fill()
            PodTheme.focus.setStroke(); let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3); path.lineWidth=1.5; path.stroke()
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver=nil }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver); self.scrollObserver=nil }
        window?.acceptsMouseMovedEvents=true
        if let window {
            resignObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main) { [weak self] _ in self?.onCursor?(nil,false) }
            if let clip=enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications=true
                scrollObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:clip,queue:.main) { [weak self] _ in self?.onCursor?(nil,false); self?.updateViewport() }
            }
        } else { stopMotion(); onCursor?(nil,false) }
    }
    override func updateTrackingAreas() {
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let tracking=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect,.enabledDuringMouseDrag],owner:self,userInfo:nil)
        addTrackingArea(tracking); cursorTracking=tracking
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event:NSEvent) { publishCursor(event,drawing:false) }
    override func mouseEntered(with event:NSEvent) { publishCursor(event,drawing:false) }
    override func mouseExited(with event:NSEvent) { onCursor?(nil,false) }
    private func publishCursor(_ event:NSEvent,drawing:Bool) {
        guard collaborating,interactionEnabled,page != nil else { return }
        let point=convert(event.locationInWindow,from:nil)
        let inside=pageRect.contains(point) && visibleRect.contains(point)
        onCursor?(inside ? pdfPoint(event):nil,drawing)
    }
    private func drawPeerCursor() {
        guard collaborating,let cursor=remoteCursor else { return }
        let rect=viewRect(CGRect(x:cursor.point.x,y:cursor.point.y,width:0,height:0))
        let point=rect.origin,clip=pageRect.intersection(visibleRect)
        guard clip.contains(point) else { return }
        let color=cursor.owner == .host ? NSColor(srgbRed:0.72,green:0.24,blue:0.06,alpha:1):NSColor(srgbRed:0.13,green:0.32,blue:0.75,alpha:1)
        let arrow=NSBezierPath(); arrow.move(to:point)
        for offset in [CGPoint(x:0,y:19),CGPoint(x:5,y:14),CGPoint(x:10,y:23),CGPoint(x:14,y:21),CGPoint(x:9,y:12),CGPoint(x:17,y:12)] { arrow.line(to:CGPoint(x:point.x+offset.x,y:point.y+offset.y)) }
        arrow.close(); color.setFill(); arrow.fill(); NSColor.white.setStroke(); arrow.lineWidth=1.3; arrow.stroke()
        let title=(cursor.owner == .host ? "Host":"Guest")+(cursor.drawing ? " · drawing":"")
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.white]
        let size=(title as NSString).size(withAttributes:attributes)
        let width=size.width+14,height=size.height+8
        let x=max(clip.minX,min(point.x+17,clip.maxX-width)),y=max(clip.minY,min(point.y+22,clip.maxY-height))
        let badge=NSRect(x:x,y:y,width:width,height:height)
        color.setFill(); NSBezierPath(roundedRect:badge,xRadius:4,yRadius:4).fill()
        (title as NSString).draw(at:CGPoint(x:x+7,y:y+4),withAttributes:attributes)
    }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }
    private func pdfPoint(_ event:NSEvent) -> CGPoint {
        let p=convert(event.locationInWindow,from:nil)
        guard let page else { return .zero }
        let pdf=page.pdfPoint(CGPoint(x:(p.x-pageRect.minX)/zoom,y:(p.y-pageRect.minY)/zoom))
        return CGPoint(x:min(page.box.maxX,max(page.box.minX,pdf.x)),y:min(page.box.maxY,max(page.box.minY,pdf.y)))
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
        if panning, let clip = enclosingScrollView?.contentView {
            panStart = (event.locationInWindow, clip.bounds.origin)
            window?.makeFirstResponder(self)
            NSCursor.closedHand.set()
            return
        }
        publishCursor(event,drawing:tool == .ink)
        guard interactionEnabled,pageRect.contains(convert(event.locationInWindow,from:nil)) else { return }
        window?.makeFirstResponder(self)
        if tool == .ink {
            let elapsed = event.timestamp - lastLift
            if let liftedInk, elapsed >= Self.groupingInterval || elapsed < 0 || liftedInk.points.count >= 4096 { finishInk() }
            inkCompletion?.cancel()
            inkCompletion = nil
        }
        let p=pdfPoint(event); dragStart=p; dragged=false; moving=nil; movingSharedID=nil; preview=nil; rotating=false
        if erasing {
            eraserTrail=[p]
            needsDisplay=true
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
            if tool == .ink { publishInkPreview() }; needsDisplay=true; return
        }
        movingSharedID=selectedSharedInk
        if let mark=selectionMark, mark.kind == .ink, !mark.inkLocked {
            let handle = rotationHandle(for:mark)
            let location = convert(event.locationInWindow,from:nil)
            if hypot(location.x-handle.x,location.y-handle.y) <= 8 {
                moving=mark
                rotating=true
                return
            }
        }
        if let page, let hit=selectionMark, !hit.inkLocked, hypot(page.displayPoint(p).x-page.displayRect(hit.geometryBounds).maxX,page.displayPoint(p).y-page.displayRect(hit.geometryBounds).maxY)<9/zoom {
            // A tap-sized mark has no useful resize handle. Drag its ink to move it.
            moving=hit; resizing = hit.kind != .ink || hit.geometryBounds.size != .zero; return
        }
        if collaborating {
            let hit=sharedDrawings.reversed().first { $0.owner==drawingOwner && $0.markup.hitTest(p,tolerance:4/zoom) }
            selectedSharedInk=hit?.id
            onSelectSharedInk?(hit?.id)
            movingSharedID=hit?.id
            moving=hit?.markup
            resizing=false
            return
        }
        if let hit=page?.annotations.reversed().first(where:{$0.hitTest(p,tolerance:4/zoom)}) {
            annotationSelection=hit.id; selected=nil; onAnnotationSelect?(hit.id); moving=hit.inkLocked ? nil : hit; resizing=false
        } else {
            annotationSelection=nil; onAnnotationSelect?(nil)
            let hit=page?.runs.reversed().first { $0.bounds.insetBy(dx:-4/zoom,dy:-4/zoom).contains(p) }
            selected=hit?.id; onSelect?(selected)
        }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        if let start = panStart, let scroll = enclosingScrollView {
            let clip = scroll.contentView
            var rect = clip.bounds
            rect.origin.x = start.origin.x - (event.locationInWindow.x - start.mouse.x)
            rect.origin.y = start.origin.y + (event.locationInWindow.y - start.mouse.y)
            clip.scroll(to: clip.constrainBoundsRect(rect).origin)
            scroll.reflectScrolledClipView(clip)
            return
        }
        publishCursor(event,drawing:tool == .ink)
        guard interactionEnabled,let start=dragStart else { return }
        let p=pdfPoint(event); dragged=true
        if erasing { appendEraserPoint(p); needsDisplay=true; return }
        if let moving {
            if rotating {
                let box=moving.geometryBounds
                let angle=atan2(p.y-box.midY,p.x-box.midX)-atan2(start.y-box.midY,start.x-box.midX)
                preview=moving.rotated(by:angle)
            } else if resizing {
                guard let page else { return }
                let bounds=page.displayRect(moving.geometryBounds), point=page.displayPoint(p)
                let end=CGPoint(x:max(bounds.minX+4,point.x),y:max(bounds.minY+4,point.y))
                let box=pointRect([page.pdfPoint(bounds.origin),page.pdfPoint(end)])
                preview=moving.scaled(to:box)
            } else { preview=moving.translated(x:p.x-start.x,y:p.y-start.y) }
        } else if let tool,!tool.isText,tool != .polygon,tool != .polyline {
            if tool == .ink { appendInkPoint(p) } else if tool.isFreehand { if draft.count>=4096 { draft=draft.enumerated().compactMap{ $0.offset.isMultiple(of:2) ? $0.element:nil } }; draft.append(p) } else { draft=[start,p] }
        }
        if tool == .ink { publishInkPreview() }
        needsDisplay=true
    }
    private func appendEraserPoint(_ point: CGPoint) {
        guard eraserTrail.last != point else { return }
        eraserTrail.append(point)
    }
    private func brushPath(transform: (CGPoint)->CGPoint, width: CGFloat) -> CGPath {
        guard let first=eraserTrail.first else { return CGMutablePath() }
        let center=transform(first)
        if eraserTrail.count==1 {
            return CGPath(ellipseIn:CGRect(x:center.x-width/2,y:center.y-width/2,width:width,height:width),transform:nil)
        }
        let path=CGMutablePath()
        path.move(to:center)
        for point in eraserTrail.dropFirst() { path.addLine(to:transform(point)) }
        return path.copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:1)
    }
    private func completeEraser() {
        defer { eraserTrail=[]; dragStart=nil; needsDisplay=true }
        guard let first=eraserTrail.first else { return }
        let brush=brushPath(transform:{$0},width:eraserWidth)
        if collaborating {
            var edits:[(UUID,Markup)]=[], deletions:[UUID]=[]
            for stroke in sharedDrawings where stroke.owner==drawingOwner {
                switch stroke.markup.subtractingInk(brush) {
                case .edited(let mark): edits.append((stroke.id,mark))
                case .removed: deletions.append(stroke.id)
                case .tooComplex: onEraseLimit?(); return
                case .unchanged: break
                }
            }
            if !edits.isEmpty || !deletions.isEmpty { onEraseSharedGroup?(edits,deletions) }
        } else if let page {
            var edits:[Markup]=[], deletions:[UInt32]=[]
            for mark in page.annotations where mark.kind == .ink {
                switch mark.subtractingInk(brush) {
                case .edited(let changed): edits.append(changed)
                case .removed: deletions.append(mark.id)
                case .tooComplex: onEraseLimit?(); return
                case .unchanged: break
                }
            }
            if !edits.isEmpty || !deletions.isEmpty { onEraseAnnotations?(edits,deletions) }
            else if eraserTrail.count==1, let other=page.annotations.reversed().first(where:{$0.hitTest(first,tolerance:4/zoom)}), other.kind != .ink {
                onDelete?(other.id)
            }
        }
    }
    override func mouseUp(with event:NSEvent) {
        if panning { panStart = nil; NSCursor.openHand.set(); return }
        publishCursor(event,drawing:false)
        guard interactionEnabled,let start=dragStart else { return }
        if erasing {
            appendEraserPoint(pdfPoint(event))
            completeEraser()
            return
        }
        if tool == .ink {
            appendInkPoint(pdfPoint(event))
            liftedInk = inkWithCurrentPath()
            draft = []
            dragStart = nil
            lastLift = event.timestamp
            publishInkPreview()
            onInkLift?()
            let completion = DispatchWorkItem { [weak self] in self?.finishInk() }
            inkCompletion = completion
            DispatchQueue.main.asyncAfter(deadline: .now()+Self.groupingInterval, execute:completion)
            needsDisplay = true
            return
        }
        defer { onDraft?(nil); dragStart=nil; moving=nil; preview=nil; needsDisplay=true }
        if let value=preview,dragged {
            if collaborating {
                if let id=movingSharedID, id==selectedSharedInk { onUpdateSharedInk?(id,value) }
            } else { onUpdate?(value) }
            return
        }
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
        if event.keyCode==53 { eraserTrail=[]; if tool == .ink { draft=[]; finishInk() }; onCursor?(nil,false); onDraft?(nil); draft=[]; preview=nil; moving=nil; dragStart=nil; needsDisplay=true; return }
        if event.keyCode==36 { finishPolygon(); return }
        if interactionEnabled, [51,117].contains(event.keyCode), let mark=selectionMark, !mark.inkLocked {
            if collaborating, let id=selectedSharedInk { onEraseShared?(id) }
            else { onDelete?(mark.id) }
            return
        }
        super.keyDown(with:event)
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { if panning { addCursorRect(visibleRect, cursor: .openHand); return }; addCursorRect(pageRect,cursor:tool == nil && !erasing ? .arrow:.crosshair) }
    private func drawShared(_ stroke:DrawingStroke) {
        drawInk(stroke.markup)
    }
    private func drawInk(_ ink: Markup) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outline = ink.inkOutline(width:ink.style.width*zoom) { point in
            self.viewRect(CGRect(origin:point,size:.zero)).origin
        }
        ink.style.stroke.withAlphaComponent(ink.style.opacity).setFill()
        context.addPath(outline)
        context.fillPath()
    }
    private func drawMarkupOverlay() {
        if let mark=preview ?? selectionMark {
            NSGraphicsContext.saveGraphicsState()
            if preview == nil, let start = selectionStart {
                NSGraphicsContext.current?.cgContext.setAlpha(progress(since: start))
            }
            let rect=viewRect(mark.geometryBounds).insetBy(dx:-2,dy:-2)
            PodTheme.focus.setStroke(); let path=NSBezierPath(rect:rect); path.lineWidth=1.5; path.stroke()
            if mark.kind == .ink && !mark.inkLocked {
                let knob=rotationHandle(for:mark)
                let stem=NSBezierPath()
                stem.move(to:CGPoint(x:rect.midX,y:knob.y<rect.minY ? rect.minY:rect.maxY))
                stem.line(to:knob)
                stem.stroke()
                let circle=NSBezierPath(ovalIn:CGRect(x:knob.x-4,y:knob.y-4,width:8,height:8))
                NSColor.white.setFill()
                circle.fill()
                circle.stroke()
            }
            if !mark.inkLocked { NSColor.white.setFill(); let handle=NSRect(x:rect.maxX-4,y:rect.maxY-4,width:8,height:8); handle.fill(); PodTheme.focus.setStroke(); NSBezierPath(rect:handle).stroke() }
            NSGraphicsContext.restoreGraphicsState()
        }
        if let preview, preview.kind == .ink { drawInk(preview) }
        if !eraserTrail.isEmpty, let ctx=NSGraphicsContext.current?.cgContext {
            NSColor.systemGray.withAlphaComponent(0.3).setFill()
            ctx.addPath(brushPath(transform:{ self.viewRect(CGRect(origin:$0,size:.zero)).origin },width:eraserWidth*zoom))
            ctx.fillPath()
        }
        for (_,mark) in pendingDrafts {
            if mark.kind == .ink { drawInk(mark) } else { drawDraft(mark.kind,mark.points,mark.style) }
        }
        if tool == .ink {
            if let ink = inkWithCurrentPath() { drawInk(ink) }
        } else if let tool,!draft.isEmpty { drawDraft(tool,draft,annotationStyle) }
    }
    private func drawDraft(_ tool:MarkupKind,_ draft:[CGPoint],_ annotationStyle:MarkupStyle) {
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
