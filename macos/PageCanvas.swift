import AppKit
import PDFKit

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
    var onOpenLink: ((URL) -> Void)?
    var onDestination: ((PageDestination) -> Void)?
    private var pressedLink: PageLink?
    var readingPage: (() -> PDFPage?)?
    var onPassage: ((ReadingPassage, Bool) -> Void)?
    var onEditReadingNote: ((Markup) -> Void)?
    var onReplyComment: ((Markup) -> Void)?
    private var commentOpen: [UInt32:Bool] = [:]
    private var commentPopups: [UInt32:CommentPopupView] = [:]
    func resetCommentPopups() {
        commentOpen.removeAll()
        for popup in commentPopups.values { popup.removeFromSuperview() }
        commentPopups.removeAll()
    }
    func showComment(_ mark:Markup) {
        commentOpen[mark.comment.threadRoot == 0 ? mark.id:mark.comment.threadRoot] = true
        refreshCommentPopups()
    }
    private func refreshCommentPopups() {
        let all = page?.annotations ?? []
        let openedReplies = Set(all.filter { $0.comment.replyTo != 0 && $0.comment.initiallyOpen }.map { $0.comment.threadRoot })
        let marks = all.filter { $0.comment.replyTo == 0 && (commentOpen[$0.id] ?? ($0.comment.initiallyOpen || openedReplies.contains($0.id))) }
        let ids = Set(marks.map(\.id))
        for id in Array(commentPopups.keys) where !ids.contains(id) {
            commentPopups.removeValue(forKey:id)?.removeFromSuperview()
        }
        for mark in marks {
            let card: CommentPopupView
            if let existing = commentPopups[mark.id] { card = existing }
            else {
                card = CommentPopupView()
                card.onClose = { [weak self] in
                    guard let self else { return }
                    commentOpen[mark.id] = false
                    commentPopups.removeValue(forKey:mark.id)?.removeFromSuperview()
                    window?.makeFirstResponder(self)
                }
                card.onEdit = { [weak self] id in
                    guard let self, interactionEnabled, !collaborating,
                          let current = page?.annotations.first(where: { $0.id == id }), current.canEditContents else { return }
                    onEditReadingNote?(current)
                }
                card.onReply = { [weak self] id in
                    guard let self, interactionEnabled, !collaborating,
                          let current = page?.annotations.first(where: { $0.id == id }), !current.inkLocked else { return }
                    onReplyComment?(current)
                }
                card.onDelete = { [weak self] id in
                    guard let self, interactionEnabled, !collaborating,
                          let current = page?.annotations.first(where: { $0.id == id }), !current.inkLocked,
                          page?.annotations.contains(where: { $0.comment.replyTo == id }) == false else { return }
                    onDelete?(id)
                }
                commentPopups[mark.id] = card
                addSubview(card,positioned:.above,relativeTo:nil)
                if allowsMotion, !deleteEaseSamples.isEmpty {
                    let appear = CAKeyframeAnimation(keyPath:"opacity")
                    appear.values = deleteEaseSamples; appear.duration = 0.14
                    card.layer?.add(appear,forKey:"commentPopup")
                }
            }
            let children = Dictionary(grouping:all.filter { $0.comment.threadRoot == mark.id },by: { $0.comment.replyTo })
            var pending = (children[mark.id] ?? []).reversed().map { ($0,1) }
            var replies: [(Markup,Int)] = []
            while let (reply,depth) = pending.popLast(), replies.count < all.count {
                replies.append((reply,depth))
                pending += (children[reply.id] ?? []).reversed().map { ($0,depth+1) }
            }
            card.configure(mark,replies:replies,editable:interactionEnabled && !collaborating)
        }
        positionCommentPopups()
    }
    private func positionCommentPopups() {
        let viewport = visibleRect.insetBy(dx:8,dy:8)
        guard viewport.width > 0, viewport.height > 0 else { return }
        for mark in page?.annotations ?? [] {
            guard let card = commentPopups[mark.id] else { continue }
            let size = CGSize(width:min(card.preferredSize.width,viewport.width),height:min(card.preferredSize.height,viewport.height))
            let icon = annotationViewRect(mark)
            let preferred = mark.comment.popupRect.map { viewRect($0).origin } ?? CGPoint(x:icon.maxX+8,y:icon.minY)
            card.frame = CGRect(x:max(viewport.minX,min(preferred.x,viewport.maxX-size.width)),
                                y:max(viewport.minY,min(preferred.y,viewport.maxY-size.height)),width:size.width,height:size.height)
        }
    }
    private var passage: ReadingPassage?
    private var selectingText = false
    private var passageBar: NSVisualEffectView?
    private func clearPassage() {
        passageBar?.removeFromSuperview()
        passageBar = nil
        passage = nil
        selectingText = false
        needsDisplay = true
    }
    func revealPassage(_ value: ReadingPassage) {
        clearPassage()
        passage = value
        scrollToVisible(viewRect(value.lines[0]).insetBy(dx:-12,dy:-20))
        needsDisplay = true
    }
    private func showPassageActions(at anchor: CGRect, mark: Markup? = nil) {
        passageBar?.removeFromSuperview()
        let bar = NSVisualEffectView()
        bar.material = .popover
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 8
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.separatorColor.cgColor
        var items: [(String, Selector)] = []
        if let mark {
            items = [(mark.text.isEmpty ? "Add Note" : "Edit Note", #selector(noteOnMark))]
        } else if let passage {
            items = [("Highlight", #selector(highlightPassage)), ("Add Note", #selector(noteOnPassage)), ("Copy", #selector(copyPassage))]
            if passage.text.trimmingCharacters(in:.whitespacesAndNewlines).range(of:#"^[\p{L}\p{M}]+(?:['’-][\p{L}\p{M}]+)*$"#,options:.regularExpression) != nil {
                items.append(("Look Up", #selector(lookupPassage)))
            }
        }
        let buttons = items.map { title, action -> NSButton in
            let b = NSButton(title:title,target:self,action:action)
            b.bezelStyle = .accessoryBarAction
            b.controlSize = .small
            b.setAccessibilityLabel(title)
            return b
        }
        let row = NSStackView(views:buttons)
        row.spacing = 3
        let size = row.fittingSize
        row.frame = CGRect(origin:CGPoint(x:6,y:4),size:size)
        bar.addSubview(row)
        let width = size.width+12, height = size.height+8
        let clip = visibleRect
        bar.frame = CGRect(x:max(clip.minX,min(anchor.midX-width/2,clip.maxX-width)),
                           y:max(clip.minY,min(anchor.minY-height-5 >= clip.minY ? anchor.minY-height-5 : anchor.maxY+5,clip.maxY-height)),
                           width:width,height:height)
        addSubview(bar, positioned:.above, relativeTo:nil)
        passageBar = bar
        if allowsMotion, !deleteEaseSamples.isEmpty {
            let appear = CAKeyframeAnimation(keyPath:"opacity")
            appear.values = deleteEaseSamples
            appear.duration = 0.14
            bar.layer?.add(appear,forKey:"readingActions")
        }
    }
    @objc private func highlightPassage() { if let passage { onPassage?(passage,false) } }
    @objc private func noteOnPassage() { if let passage { onPassage?(passage,true) } }
    @objc private func noteOnMark() { if let mark = selectionMark { onEditReadingNote?(mark) } }
    @objc private func copyPassage() {
        guard let passage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(passage.text, forType:.string)
    }
    @objc func copy(_ sender: Any?) { copyPassage() }
    @objc private func lookupPassage() {
        guard let passage else { return }
        let rect = viewRect(passage.lines[0])
        showDefinition(for:NSAttributedString(string:passage.text),at:CGPoint(x:rect.minX,y:rect.maxY))
    }
    var tool: MarkupKind? {
        willSet { finishInk(); clearPassage() }
        didSet {
            onCursor?(nil,false)
            onDraft?(nil)
            draft=[]
            positionStrokeControls()
            needsDisplay=true
            window?.invalidateCursorRects(for:self)
        }
    }
    var panning = false {
        didSet { panStart = nil; panRelease = nil; positionStrokeControls(); window?.invalidateCursorRects(for: self) }
    }
    var panSpring: [Double] = []
    private var panStart: (mouse: CGPoint, origin: CGPoint)?
    private var panTime: TimeInterval = 0
    private var panTravel = CGPoint.zero
    private var panRelease: (start: TimeInterval, origin: CGPoint, delta: CGPoint, last: CGPoint)?

    var erasing=false { didSet { positionStrokeControls(); if !erasing { eraserTrail=[]; clearErasePreview() } } }
    var eraserMode = Markup.EraserMode.stroke
    var eraserWidth: CGFloat = 16
    private var eraserTrail: [CGPoint] = []
    var onErasePreview: (([Markup], [UInt32], @escaping (CGImage?) -> Void) -> Void)?
    private var erasedLocal: [UInt32: Markup.EraserResult] = [:]
    private var erasedShared: [UUID: Markup.EraserResult] = [:]
    var hasStrokeErasePreview: Bool { erasePreviewImage != nil }
    private var erasePreviewImage: NSImage?
    private var eraseMask = CGMutablePath()
    private var eraseGeneration = 0
    private var previewRotation = 0

    // Each hit has its own clock so crossing another stroke cannot restart its fade.
    private struct ErasedInk {
        let outline: CGPath   // PDF coordinates
        let color: NSColor
    }
    private var pendingEraseInk: [ErasedInk] = []
    private var fadingEraseInk: [(ink: ErasedInk, start: TimeInterval)] = []
    var deleteEaseSamples: [Double] = []

    private func presentEraseInk() {
        if allowsMotion, !pendingEraseInk.isEmpty {
            let now = ProcessInfo.processInfo.systemUptime
            fadingEraseInk += pendingEraseInk.map { ($0, now) }
            startMotionFrames()
        }
        pendingEraseInk.removeAll()
    }

    func clearErasePreview(keepingFade: Bool = false) {
        pendingEraseInk.removeAll()
        if !keepingFade { fadingEraseInk.removeAll() }
        eraseGeneration += 1
        erasedLocal.removeAll()
        erasedShared.removeAll()
        eraseMask = CGMutablePath()
        erasePreviewImage = nil
        needsDisplay = true
    }

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
    var interactionEnabled=true { didSet { if oldValue != interactionEnabled { positionStrokeControls(); refreshCommentPopups() }; if !interactionEnabled { onCursor?(nil,false) } } }
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
    private func deleteProgress(since start: TimeInterval) -> CGFloat {
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - start) / fadeDuration))
        guard deleteEaseSamples.count >= 2 else { return t * (2 - t) }
        let frame = t * Double(deleteEaseSamples.count - 1)
        let i = Int(frame), next = min(i+1, deleteEaseSamples.count-1)
        return deleteEaseSamples[i] + (frame-Double(i)) * (deleteEaseSamples[next]-deleteEaseSamples[i])
    }
    var onStrokeStyle: ((MarkupStyle) -> Void)?
    private lazy var strokeControls = StrokeControls { [weak self] width, color in
        guard let self, interactionEnabled, let mark = selectionMark, !mark.inkLocked else { return }
        var style = mark.style
        if let width { style.width = width }
        if let color { style.stroke = color }
        onStrokeStyle?(style)
    }

    private func positionStrokeControls() {
        guard let mark = selectionMark, mark.kind.isFreehand, !mark.inkLocked,
              tool == nil, !panning, !erasing, interactionEnabled, preview == nil else {
            strokeControls.isHidden = true
            return
        }
        let anchor = viewRect(mark.geometryBounds).insetBy(dx: -3, dy: -3)
        let visible = visibleRect.insetBy(dx: 5, dy: 5)
        let size = strokeControls.frame.size
        guard visible.intersects(anchor), visible.width >= size.width, visible.height >= size.height else {
            strokeControls.isHidden = true
            return
        }
        if strokeControls.superview == nil { addSubview(strokeControls, positioned: .above, relativeTo: nil) }
        let above = anchor.minY - size.height - 28
        let y = above >= visible.minY ? above : min(visible.maxY - size.height, anchor.maxY + 28)
        strokeControls.setFrameOrigin(CGPoint(x: max(visible.minX, min(anchor.midX - size.width/2, visible.maxX - size.width)),
                                              y: max(visible.minY, y)))
        strokeControls.display(style: mark.style)
        strokeControls.isHidden = false
    }

    private func selectionChanged() {
        positionStrokeControls()
        selectionStart = allowsMotion && selectionMark?.kind == .ink ? ProcessInfo.processInfo.systemUptime : nil
        if selectionStart != nil { startMotionFrames() }
        needsDisplay = true
    }
    private func stopMotion() {
        panRelease = nil
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
        for entry in fadingEraseInk {
            dirty = dirty.union(viewRect(entry.ink.outline.boundingBoxOfPath).insetBy(dx:-2,dy:-2))
        }
        fadingEraseInk.removeAll { !allowsMotion || deleteProgress(since: $0.start) >= 1 }
        if let fade = inkFade {
            let box = fade.mask.boundingBoxOfPath
            dirty = dirty.union(CGRect(x: pageRect.minX + box.minX * zoom, y: pageRect.minY + box.minY * zoom,
                           width: box.width * zoom, height: box.height * zoom).insetBy(dx: -2, dy: -2))
            if progress(since: fade.start) >= 1 { inkFade = nil }
        }
        if let start = selectionStart {
            if let mark = selectionMark {
                dirty = dirty.union(viewRect(mark.geometryBounds).insetBy(dx: -10, dy: -28))
            }
            if progress(since: start) >= 1 { selectionStart = nil }
        }
        if let release = panRelease, allowsMotion, let scroll = enclosingScrollView, !scroll.isHidden,
           release.last == scroll.contentView.bounds.origin {
            let frame = (ProcessInfo.processInfo.systemUptime - release.start) * 60
            let last = panSpring.count - 1
            let i = min(Int(frame), last)
            let t = panSpring[i] + (panSpring[min(i + 1, last)] - panSpring[i]) * (frame - Double(i))
            let clip = scroll.contentView
            var rect = clip.bounds
            rect.origin = CGPoint(x: release.origin.x + t * release.delta.x, y: release.origin.y + t * release.delta.y)
            clip.scroll(to: clip.constrainBoundsRect(rect).origin)
            scroll.reflectScrolledClipView(clip)
            panRelease?.last = clip.bounds.origin
            if i == last { panRelease = nil }
        } else { panRelease = nil }
        if !allowsMotion || (inkFade == nil && selectionStart == nil && panRelease == nil && fadingEraseInk.isEmpty) { stopMotion() }
        if !dirty.isNull {
            if let overlay { overlay.setNeedsDisplay(overlay.convert(dirty, from: self)) }
            else { setNeedsDisplay(dirty) }
        }
    }
    func fadeInkChange(_ marks: [Markup], previousShared: [DrawingStroke] = []) {
        guard erasedShared.isEmpty, allowsMotion, let image, let page, !marks.isEmpty else { return }
        let mask = CGMutablePath()
        for mark in marks {
            if mark.kind == .comment {
                let rect=annotationViewRect(mark)
                mask.addRect(CGRect(x:(rect.minX-pageRect.minX)/zoom,y:(rect.minY-pageRect.minY)/zoom,
                                    width:rect.width/zoom,height:rect.height/zoom).insetBy(dx:-1/zoom,dy:-1/zoom))
            } else if mark.kind == .ink {
                mask.addPath(mark.inkOutline(width: mark.style.width + 2 / zoom, transform: page.displayPoint))
            } else {
                let padding = mark.style.width / 2 + 1 / zoom
                mask.addRect(page.displayRect(mark.rect.union(mark.geometryBounds)).insetBy(dx:-padding,dy:-padding))
            }
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
        context.setAlpha(1 - deleteProgress(since: fade.start))
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
        if eraserTrail.isEmpty { clearErasePreview(keepingFade: true) }
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
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(degrees) * .pi / 180)
        context.draw(image, in: CGRect(x: -CGFloat(image.width)/2, y: -CGFloat(image.height)/2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    func configure(_ pixels: PagePixels, page original: PageInfo, zoom: CGFloat, metalPage scene: MetalPage? = nil, viewRotation: Int = 0, renderedView: Bool = false, completingAnnotation:Bool = false, draftID:Int? = nil, fadingInk: [Markup] = []) {
        stopMotion()
        clearPassage()
        pressedLink = nil
        previewRotation = renderedView ? 0 : viewRotation
        let keepErasePreview = completingAnnotation && erasePreviewImage != nil
        if keepErasePreview {
            // Carry an in-flight dimming stroke from the preview onto the committed page.
            presentEraseInk()
            if !fadingEraseInk.isEmpty { startMotionFrames() }
        } else { clearErasePreview(); fadeInkChange(fadingInk) }
        let metalPage = renderedView || viewRotation == 0 ? scene : nil
        let page = PageInfo(box: original.box, mediaBox: original.mediaBox,
                            rotation: (original.rotation + viewRotation) % 360,
                            runs: original.runs, annotations: original.annotations, links: original.links)
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
        let cg = pixels.cgImage!
        image=NSImage(cgImage:renderedView || viewRotation == 0 ? cg : (rotatedImage(cg, degrees: viewRotation) ?? cg),size:page.displaySize)
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
                addSubview(view, positioned: .below, relativeTo: nil)
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
        refreshCommentPopups()
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
        positionStrokeControls()
        positionCommentPopups()
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
    var viewportPDFPoint: CGPoint {
        guard let page, let clip = enclosingScrollView?.contentView else { return .zero }
        return page.pdfPoint(CGPoint(x:(clip.bounds.minX-pageRect.minX)/zoom,y:(clip.bounds.minY-pageRect.minY)/zoom))
    }
    func applyDestination(_ view: DestinationView) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin = CGPoint(x:pageRect.minX+view.anchor.x*zoom-clip.bounds.width*view.alignment.x,
                                y:pageRect.minY+view.anchor.y*zoom-clip.bounds.height*view.alignment.y)
        clip.scroll(to:clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }
    func viewRect(_ pdf: CGRect) -> CGRect {
        guard let page else { return .zero }
        let rect=page.displayRect(pdf)
        return CGRect(x:pageRect.minX+rect.minX*zoom,y:pageRect.minY+rect.minY*zoom,width:max(rect.width*zoom,3),height:max(rect.height*zoom,4))
    }
    func annotationViewRect(_ mark: Markup) -> CGRect {
        guard mark.kind == .comment, let page else { return viewRect(mark.geometryBounds) }
        let anchor = page.displayPoint(CGPoint(x:mark.rect.minX,y:mark.rect.maxY))
        return CGRect(x:pageRect.minX+anchor.x*zoom,y:pageRect.minY+anchor.y*zoom,width:mark.rect.width,height:mark.rect.height)
    }
    private func annotationHitTest(_ mark: Markup, point: CGPoint) -> Bool {
        if mark.comment.replyTo != 0 { return false }
        guard mark.kind == .comment, let page else { return mark.hitTest(point,tolerance:4/zoom) }
        let p = page.displayPoint(point)
        return annotationViewRect(mark).insetBy(dx:-4,dy:-4).contains(CGPoint(x:pageRect.minX+p.x*zoom,y:pageRect.minY+p.y*zoom))
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
        if let erasePreviewImage, let context = NSGraphicsContext.current?.cgContext {
            var transform = CGAffineTransform(translationX: pageRect.minX, y: pageRect.minY).scaledBy(x: zoom, y: zoom)
            if let mask = eraseMask.copy(using: &transform) {
                context.saveGState()
                context.addPath(mask); context.clip()
                erasePreviewImage.draw(in: pageRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
                context.restoreGState()
            }
        }
        for stroke in sharedDrawings where preview == nil || stroke.id != movingSharedID {
            switch erasedShared[stroke.id] {
            case .removed: continue
            case .edited(let remaining): drawInk(remaining)
            default: drawShared(stroke)
            }
        }
        drawInkFade()
        if let context = NSGraphicsContext.current?.cgContext, !fadingEraseInk.isEmpty {
            // Map PDF coordinates using the same rotation and crop as the live canvas.
            func viewPoint(_ p: CGPoint) -> CGPoint {
                let point = page.displayPoint(p)
                return CGPoint(x: pageRect.minX + point.x*zoom, y: pageRect.minY + point.y*zoom)
            }
            let o = viewPoint(.zero), x = viewPoint(CGPoint(x:1,y:0)), y = viewPoint(CGPoint(x:0,y:1))
            context.saveGState()
            context.concatenate(CGAffineTransform(a:x.x-o.x,b:x.y-o.y,c:y.x-o.x,d:y.y-o.y,tx:o.x,ty:o.y))
            for entry in fadingEraseInk {
                entry.ink.color.setFill()
                context.setAlpha(1 - deleteProgress(since: entry.start))
                context.addPath(entry.ink.outline)
                context.fillPath()
            }
            context.restoreGState()
        }
        if let stroke=sharedPreview { drawShared(stroke) }
        drawMarkupOverlay()
        drawPeerCursor()
        if let passage {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).setFill()
            for rect in passage.lines { viewRect(rect).fill() }
        }
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
        pressedLink = nil
        clearPassage()
        if panning, let clip = enclosingScrollView?.contentView {
            panRelease = nil
            panTravel = .zero
            panTime = event.timestamp
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
            clearErasePreview(keepingFade: true)
            eraserTrail=[]
            appendEraserPoint(p)
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
        if let page, let hit=selectionMark, hit.canChangeAppearance, hypot(pageRect.minX+page.displayPoint(p).x*zoom-annotationViewRect(hit).maxX,pageRect.minY+page.displayPoint(p).y*zoom-annotationViewRect(hit).maxY)<9 {
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
        if let hit=page?.annotations.reversed().first(where:{annotationHitTest($0,point:p)}) {
            annotationSelection=hit.id; selected=nil; onAnnotationSelect?(hit.id); moving=hit.canMove ? hit : nil; resizing=false
        } else {
            annotationSelection=nil; onAnnotationSelect?(nil)
            pressedLink = page?.links.reversed().first { $0.isActive && $0.contains(p) }
            let hit=page?.runs.reversed().first { $0.bounds.insetBy(dx:-4/zoom,dy:-4/zoom).contains(p) }
            selected=hit?.id; onSelect?(selected)
            selectingText = hit != nil
            if event.clickCount == 2, let textPage = readingPage?() {
                passage = ReadingPassage(textPage.selectionForWord(at:p),page:textPage)
                if passage != nil { onSelect?(nil) }
            }
        }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        if let start = panStart, let scroll = enclosingScrollView {
            let clip = scroll.contentView
            let previous = clip.bounds.origin
            var rect = clip.bounds
            rect.origin.x = start.origin.x - (event.locationInWindow.x - start.mouse.x)
            rect.origin.y = start.origin.y + (event.locationInWindow.y - start.mouse.y)
            clip.scroll(to: clip.constrainBoundsRect(rect).origin)
            scroll.reflectScrolledClipView(clip)
            let projection = 0.060 / max(0.008, event.timestamp - panTime)
            panTravel = CGPoint(x: min(64, max(-64, (clip.bounds.minX - previous.x) * projection)),
                                y: min(64, max(-64, (clip.bounds.minY - previous.y) * projection)))
            panTime = event.timestamp
            return
        }
        publishCursor(event,drawing:tool == .ink)
        guard interactionEnabled,let start=dragStart else { return }
        let p=pdfPoint(event); dragged=true
        if erasing { appendEraserPoint(p); needsDisplay=true; return }
        if !collaborating, moving == nil, selectingText || tool?.isTextMarkup == true, let textPage = readingPage?() {
            if selected != nil { selected=nil; onSelect?(nil) }
            passage = ReadingPassage(textPage.selection(from:start,to:p),page:textPage)
            needsDisplay=true
            return
        }
        if let moving {
            strokeControls.isHidden = true
            if rotating {
                let box=moving.geometryBounds
                let angle=atan2(p.y-box.midY,p.x-box.midX)-atan2(start.y-box.midY,start.x-box.midX)
                preview=moving.rotated(by:angle)
            } else if resizing {
                guard let page else { return }
                if moving.kind == .comment {
                    let anchor = annotationViewRect(moving).origin, point=page.displayPoint(p)
                    let geometry=moving.geometryBounds
                    let padding=CGSize(width:moving.rect.width-geometry.width,height:moving.rect.height-geometry.height)
                    let width=max(4,pageRect.minX+point.x*zoom-anchor.x-padding.width)
                    let height=max(4,pageRect.minY+point.y*zoom-anchor.y-padding.height)
                    preview=moving.scaled(to:CGRect(x:geometry.minX,y:geometry.maxY-height,width:width,height:height))
                    preview?.rect=CGRect(x:moving.rect.minX,y:moving.rect.maxY-height-padding.height,width:width+padding.width,height:height+padding.height)
                } else {
                    let bounds=page.displayRect(moving.geometryBounds), point=page.displayPoint(p)
                    let end=CGPoint(x:max(bounds.minX+4,point.x),y:max(bounds.minY+4,point.y))
                    let box=pointRect([page.pdfPoint(bounds.origin),page.pdfPoint(end)])
                    preview=moving.scaled(to:box)
                }
            } else { preview=moving.translated(x:p.x-start.x,y:p.y-start.y) }
        } else if let tool,!tool.isText,tool != .polygon,tool != .polyline {
            if tool == .ink { appendInkPoint(p) } else if tool.isFreehand { if draft.count>=4096 { draft=draft.enumerated().compactMap{ $0.offset.isMultiple(of:2) ? $0.element:nil } }; draft.append(p) } else { draft=[start,p] }
        }
        if tool == .ink { publishInkPreview() }
        needsDisplay=true
    }
    private func appendEraserPoint(_ point: CGPoint) {
        guard eraserTrail.last != point else { return }
        let start = eraserTrail.last ?? point
        eraserTrail.append(point)
        guard eraserMode == .stroke, let page else { return }
        let path = CGMutablePath()
        path.move(to: start); path.addLine(to: point)
        let brush = start == point
            ? CGPath(ellipseIn: CGRect(x: point.x-eraserWidth/2, y: point.y-eraserWidth/2, width: eraserWidth, height: eraserWidth), transform: nil)
            : path.copy(strokingWithWidth: eraserWidth, lineCap: .round, lineJoin: .round, miterLimit: 1)
        if collaborating {
            for stroke in sharedDrawings where stroke.owner == drawingOwner {
                if let hit = strokeHit(stroke.markup, previous: erasedShared[stroke.id], brush: brush) { erasedShared[stroke.id] = hit }
            }
            presentEraseInk()
            return
        }
        var changed = false
        for mark in page.annotations where mark.kind.isFreehand {
            guard let hit = strokeHit(mark, previous: erasedLocal[mark.id], brush: brush) else { continue }
            if erasedLocal[mark.id] == nil { eraseMask.addPath(mark.inkOutline(width: mark.style.width + 2/zoom, transform: page.displayPoint)) }
            erasedLocal[mark.id] = hit
            changed = true
        }
        guard changed else { return }
        var marks: [Markup] = [], deleting: [UInt32] = []
        for (id, result) in erasedLocal {
            switch result {
            case .removed: deleting.append(id)
            case .edited(let mark): marks.append(mark)
            default: break
            }
        }
        eraseGeneration += 1
        let generation = eraseGeneration
        onErasePreview?(marks, deleting) { [weak self] raster in
            guard let self, generation == eraseGeneration, let raster else { return }
            let rotated = previewRotation == 0 ? raster : rotatedImage(raster, degrees: previewRotation) ?? raster
            erasePreviewImage = NSImage(cgImage: rotated, size: page.displaySize)
            presentEraseInk()
            needsDisplay = true
        }
    }

    private func strokeHit(_ original: Markup, previous: Markup.EraserResult?, brush: CGPath) -> Markup.EraserResult? {
        let candidate: Markup
        switch previous {
        case .removed: return nil
        case .edited(let mark): candidate = mark
        default: candidate = original
        }
        let hit = candidate.subtractingInk(brush, mode: .stroke) { outline in
            guard self.allowsMotion else { return }
            self.pendingEraseInk.append(ErasedInk(outline: outline, color: candidate.style.stroke.withAlphaComponent(candidate.style.opacity)))
        }
        if case .unchanged = hit { return nil }
        return hit
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
        guard !eraserTrail.isEmpty else { return }
        let brush=brushPath(transform:{$0},width:eraserWidth)
        if collaborating {
            var edits:[(UUID,Markup)]=[], deletions:[UUID]=[]
            for stroke in sharedDrawings where stroke.owner==drawingOwner {
                switch stroke.markup.subtractingInk(brush, mode: eraserMode) {
                case .edited(let mark): edits.append((stroke.id,mark))
                case .removed: deletions.append(stroke.id)
                case .tooComplex: onEraseLimit?(); return
                case .unchanged: break
                }
            }
            if !edits.isEmpty || !deletions.isEmpty { onEraseSharedGroup?(edits,deletions) }
            erasedShared.removeAll()
        } else if let page {
            var edits:[Markup]=[], deletions:[UInt32]=[]
            for mark in page.annotations where mark.kind.isFreehand {
                let result = eraserMode == .stroke ? erasedLocal[mark.id] ?? .unchanged : mark.subtractingInk(brush)
                switch result {
                case .edited(let changed): edits.append(contentsOf: changed.erasedFragments)
                case .removed: deletions.append(mark.id)
                case .tooComplex: onEraseLimit?(); return
                case .unchanged: break
                }
            }
            if !edits.isEmpty || !deletions.isEmpty { onEraseAnnotations?(edits,deletions) }
        }
    }
    override func mouseUp(with event:NSEvent) {
        defer { pressedLink = nil }
        if panning {
            defer { panStart = nil; NSCursor.openHand.set() }
            guard panStart != nil, allowsMotion, event.timestamp - panTime <= 0.09, panSpring.count >= 2,
                  let clip = enclosingScrollView?.contentView else { return }
            let origin = clip.bounds.origin
            let end = clip.constrainBoundsRect(clip.bounds.offsetBy(dx: panTravel.x, dy: panTravel.y)).origin
            let delta = CGPoint(x: end.x - origin.x, y: end.y - origin.y)
            guard abs(delta.x) + abs(delta.y) >= 1 else { return }
            panRelease = (ProcessInfo.processInfo.systemUptime, origin, delta, origin)
            startMotionFrames()
            return
        }
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
        defer { onDraft?(nil); dragStart=nil; moving=nil; preview=nil; positionStrokeControls(); needsDisplay=true }
        if let value=preview,dragged {
            if collaborating {
                if let id=movingSharedID, id==selectedSharedInk { onUpdateSharedInk?(id,value) }
            } else { onUpdate?(value) }
            return
        }
        if tool == nil, !erasing, !collaborating, !dragged,
           let link = pressedLink, link.contains(pdfPoint(event)), link.isActive {
            clearPassage()
            if let destination = link.destination { onDestination?(destination) }
            else if let url = link.url { onOpenLink?(url) }
            return
        }
        if tool == nil, !collaborating {
            if !dragged, event.clickCount > 1, let mark = selectionMark, mark.kind == .comment || page?.annotations.contains(where: { $0.comment.threadRoot == mark.id }) == true {
                clearPassage(); showComment(mark)
            } else if let passage { showPassageActions(at:viewRect(passage.lines.last!)) }
            else if !dragged, let mark = selectionMark, mark.kind.isTextMarkup, mark.hasEditableText {
                showPassageActions(at:viewRect(CGRect(origin:start,size:.zero)),mark:mark)
            }
            return
        }
        guard let tool,!tool.isText,tool != .polygon,tool != .polyline else { return }
        let end=pdfPoint(event)
        if tool.isTextMarkup {
            if let textPage = readingPage?() {
                let selection = dragged ? textPage.selection(from:start,to:end) : textPage.selectionForWord(at:start)
                if let value = ReadingPassage(selection,page:textPage) { onCreate?([value.markup(tool,style:annotationStyle)]) }
            }
            clearPassage()
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
        if event.keyCode==53 { clearPassage(); clearErasePreview(); eraserTrail=[]; if tool == .ink { draft=[]; finishInk() }; onCursor?(nil,false); onDraft?(nil); draft=[]; preview=nil; moving=nil; dragStart=nil; needsDisplay=true; return }
        if event.keyCode==36 { finishPolygon(); return }
        if interactionEnabled, [51,117].contains(event.keyCode), let mark=selectionMark, mark.canDelete {
            if collaborating, let id=selectedSharedInk { onEraseShared?(id) }
            else if page?.annotations.contains(where: { $0.comment.replyTo == mark.id }) == false { onDelete?(mark.id) }
            return
        }
        super.keyDown(with:event)
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        if panning { addCursorRect(visibleRect, cursor: .openHand); return }
        addCursorRect(pageRect,cursor:tool == nil && !erasing ? .arrow:.crosshair)
        if interactionEnabled, tool == nil, !erasing, !collaborating {
            for link in page?.links ?? [] where link.isActive {
                let rect = viewRect(link.rect).intersection(pageRect).intersection(visibleRect)
                if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
            }
        }
    }
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
            let rect=annotationViewRect(mark).insetBy(dx:-2,dy:-2)
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
            if mark.canChangeAppearance { NSColor.white.setFill(); let handle=NSRect(x:rect.maxX-4,y:rect.maxY-4,width:8,height:8); handle.fill(); PodTheme.focus.setStroke(); NSBezierPath(rect:handle).stroke() }
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

private final class StrokeControls: NSVisualEffectView {
    private let thickness = NSPopUpButton()
    private let colors = NSPopUpButton()
    private let widths: [CGFloat] = [1, 2, 4, 8, 12, 16]
    private let palette: [(String, NSColor)] = [
        ("Black", .black), ("Red", NSColor(srgbRed: 215/255, green: 48/255, blue: 39/255, alpha: 1)),
        ("Blue", NSColor(srgbRed: 69/255, green: 117/255, blue: 180/255, alpha: 1)),
        ("Teal", NSColor(srgbRed: 90/255, green: 180/255, blue: 172/255, alpha: 1)),
        ("Yellow", NSColor(srgbRed: 254/255, green: 224/255, blue: 144/255, alpha: 1)), ("White", .white)
    ]
    private let change: (CGFloat?, NSColor?) -> Void

    init(change: @escaping (CGFloat?, NSColor?) -> Void) {
        self.change = change
        super.init(frame: NSRect(x: 0, y: 0, width: 172, height: 34))
        material = .popover
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        thickness.frame = NSRect(x: 5, y: 5, width: 69, height: 24)
        colors.frame = NSRect(x: 77, y: 5, width: 90, height: 24)
        for (control, label) in [(thickness, "Stroke thickness"), (colors, "Stroke color")] {
            control.controlSize = .small
            control.toolTip = label
            control.setAccessibilityLabel(label)
            control.target = self
            control.action = #selector(applyChoice(_:))
            addSubview(control)
        }
        for width in widths { addWidth(width) }
        for (name, color) in palette { addColor(name, color) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addWidth(_ width: CGFloat) {
        thickness.addItem(withTitle: String(format: "%g pt", width))
        thickness.lastItem?.representedObject = width
    }
    private func addColor(_ name: String, _ color: NSColor) {
        colors.addItem(withTitle: name)
        colors.lastItem?.representedObject = color
        colors.lastItem?.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            dot.fill()
            NSColor.separatorColor.setStroke()
            dot.stroke()
            return true
        }
    }

    func display(style: MarkupStyle) {
        if thickness.selectedItem?.representedObject as? CGFloat != style.width {
            if thickness.numberOfItems > widths.count { thickness.removeItem(at: widths.count) }
            if !widths.contains(style.width) { addWidth(style.width) }
            thickness.selectItem(at: widths.firstIndex(of: style.width) ?? widths.count)
        }
        let color = style.stroke.usingColorSpace(.sRGB) ?? style.stroke
        if (colors.selectedItem?.representedObject as? NSColor)?.usingColorSpace(.sRGB) != color {
            if colors.numberOfItems > palette.count { colors.removeItem(at: palette.count) }
            let index = palette.firstIndex { $0.1.usingColorSpace(.sRGB) == color }
            if index == nil { addColor("Current", color) }
            colors.selectItem(at: index ?? palette.count)
        }
    }

    @objc private func applyChoice(_ sender: NSPopUpButton) {
        if sender === thickness { change(sender.selectedItem?.representedObject as? CGFloat, nil) }
        else { change(nil, sender.selectedItem?.representedObject as? NSColor) }
    }
}


// Popup visibility is viewer state. Content edits go through the existing editor
// so navigation, undo and save use the same document mutation path as the sidebar.
private final class CommentContentView: NSView { override var isFlipped: Bool { true } }
private func commentTextHeight(_ text:String,width:CGFloat,font:NSFont) -> CGFloat {
    ceil((text as NSString).boundingRect(with:CGSize(width:max(1,width),height:CGFloat.greatestFiniteMagnitude),
        options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height)+4
}
private final class CommentReplyRow: NSView {
    let id: UInt32
    var depth = 1
    var onEdit:(() -> Void)?, onReply:(() -> Void)?, onDelete:(() -> Void)?
    private let author = NSTextField(labelWithString:"")
    private let body = NSTextField(wrappingLabelWithString:"")
    private let edit = NSButton(title:"Edit",target:nil,action:nil)
    private let reply = NSButton(title:"Reply",target:nil,action:nil)
    private let remove = NSButton(title:"Delete",target:nil,action:nil)
    override var isFlipped: Bool { true }
    init(id:UInt32) {
        self.id=id; super.init(frame:.zero)
        identifier=NSUserInterfaceItemIdentifier("comment-reply-\(id)")
        author.font = .systemFont(ofSize:12,weight:.semibold)
        author.lineBreakMode = .byTruncatingTail
        body.font = .systemFont(ofSize:13); body.isSelectable = true
        edit.target=self; edit.action=#selector(editReply)
        reply.target=self; reply.action=#selector(addReply)
        remove.target=self; remove.action=#selector(deleteReply)
        for button in [edit,reply,remove] { button.bezelStyle = .rounded; button.controlSize = .small }
        for view in [author,body,edit,reply,remove] { addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(_ mark:Markup,depth:Int,editable:Bool,hasReplies:Bool) {
        self.depth=depth
        let name = mark.comment.author.isEmpty ? "Anonymous":mark.comment.author
        author.stringValue = "↳ "+name
        let text = mark.comment.reviewState.isEmpty ? mark.text:mark.text+"\n\(mark.comment.stateModel): \(mark.comment.reviewState)"
        if body.stringValue != text { body.stringValue=text }
        edit.isEnabled=editable && mark.canEditContents
        reply.isEnabled=editable && !mark.inkLocked
        remove.isEnabled=editable && !mark.inkLocked && !hasReplies
        remove.toolTip=hasReplies ? "Delete this reply's replies first.":nil
        edit.setAccessibilityLabel("Edit reply from "+name)
        reply.setAccessibilityLabel("Reply to "+name)
        remove.setAccessibilityLabel("Delete reply from "+name)
        needsLayout=true
    }
    func height(for width:CGFloat) -> CGFloat { 58+max(20,commentTextHeight(body.stringValue,width:width,font:body.font!)) }
    override func layout() {
        super.layout()
        author.frame=CGRect(x:0,y:8,width:bounds.width,height:18)
        body.frame=CGRect(x:0,y:30,width:bounds.width,height:max(20,bounds.height-58))
        for (i,button) in [edit,reply,remove].enumerated() { button.frame=CGRect(x:CGFloat(i)*66,y:bounds.height-26,width:62,height:24) }
    }
    override func draw(_ dirtyRect:NSRect) { NSColor.separatorColor.setFill(); NSRect(x:0,y:0,width:bounds.width,height:1).fill() }
    @objc private func editReply() { onEdit?() }
    @objc private func addReply() { onReply?() }
    @objc private func deleteReply() { onDelete?() }
}
private final class CommentPopupView: NSVisualEffectView {
    var onClose: (() -> Void)?
    var onEdit: ((UInt32) -> Void)?
    var onReply: ((UInt32) -> Void)?
    var onDelete: ((UInt32) -> Void)?
    private var rootID: UInt32 = 0
    private var rows: [CommentReplyRow] = []
    var preferredSize: CGSize { CGSize(width:rows.isEmpty ? 280:340,height:rows.isEmpty ? 224:420) }
    private let author = NSTextField(labelWithString:"")
    private let subject = NSTextField(labelWithString:"")
    private let body = NSTextView()
    private let content = CommentContentView()
    private let scroll = NSScrollView()
    private let close = NSButton(title:"Close Note",target:nil,action:nil)
    private let edit = NSButton(title:"Edit Note",target:nil,action:nil)
    private let reply = NSButton(title:"Reply",target:nil,action:nil)
    override var isFlipped: Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        identifier = NSUserInterfaceItemIdentifier("comment-popup")
        setAccessibilityLabel("Comment popup")
        material = .popover; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 10; layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        author.font = .systemFont(ofSize:13,weight:.semibold)
        author.lineBreakMode = .byTruncatingTail
        subject.font = .systemFont(ofSize:11); subject.textColor = .secondaryLabelColor
        subject.lineBreakMode = .byTruncatingTail
        body.isEditable = false; body.isSelectable = true; body.isRichText = false
        body.drawsBackground = false; body.font = .systemFont(ofSize:13); body.textColor = .labelColor
        body.textContainerInset = CGSize(width:0,height:4)
        body.textContainer?.lineFragmentPadding = 0
        body.isVerticallyResizable = false; body.isHorizontallyResizable = false
        body.textContainer?.widthTracksTextView = true
        body.setAccessibilityLabel("Comment text")
        content.addSubview(body)
        scroll.documentView = content; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        close.target = self; close.action = #selector(closeNote)
        edit.target = self; edit.action = #selector(editNote)
        reply.target = self; reply.action = #selector(replyNote)
        for button in [close,edit,reply] { button.bezelStyle = .rounded; button.controlSize = .small }
        for view in [author,subject,scroll,close,edit,reply] { addSubview(view) }
    }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(_ mark:Markup,replies:[(Markup,Int)],editable:Bool) {
        rootID=mark.id
        author.stringValue = mark.comment.author.isEmpty ? "Comment" : mark.comment.author
        subject.stringValue = mark.comment.subject
        if body.string != mark.text { body.string = mark.text }
        edit.isEnabled = editable && mark.canEditContents
        reply.isEnabled = editable && !mark.inkLocked
        edit.toolTip = mark.contentsLockReason
        let existing = Dictionary(uniqueKeysWithValues:rows.map { ($0.id,$0) })
        let ids = Set(replies.map { $0.0.id }), parents = Set(replies.map { $0.0.comment.replyTo })
        for row in rows where !ids.contains(row.id) { row.removeFromSuperview() }
        rows = replies.map { item,depth in
            let row = existing[item.id] ?? CommentReplyRow(id:item.id)
            if row.superview == nil { content.addSubview(row) }
            row.onEdit = { [weak self] in self?.onEdit?(item.id) }
            row.onReply = { [weak self] in self?.onReply?(item.id) }
            row.onDelete = { [weak self] in self?.onDelete?(item.id) }
            row.configure(item,depth:depth,editable:editable,hasReplies:parents.contains(item.id))
            return row
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = max(0,bounds.width-24), header:CGFloat = subject.stringValue.isEmpty ? 34:52
        author.frame = CGRect(x:12,y:10,width:width,height:18)
        subject.frame = CGRect(x:12,y:30,width:width,height:16)
        subject.isHidden = subject.stringValue.isEmpty
        scroll.frame = CGRect(x:12,y:header,width:width,height:max(0,bounds.height-header-44))
        let contentWidth=max(1,scroll.contentSize.width)
        let bodyHeight=max(32,commentTextHeight(body.string,width:contentWidth,font:body.font!)+8)
        body.frame=CGRect(x:0,y:0,width:contentWidth,height:bodyHeight)
        var y=bodyHeight+8
        for row in rows {
            let indent=CGFloat(min(row.depth-1,3))*12
            let height=row.height(for:contentWidth-indent)
            row.frame=CGRect(x:indent,y:y,width:contentWidth-indent,height:height)
            y += height+10
        }
        content.frame=CGRect(x:0,y:0,width:contentWidth,height:max(scroll.contentSize.height,y))
        close.frame = CGRect(x:8,y:bounds.height-34,width:88,height:26)
        edit.frame = CGRect(x:bounds.width-180,y:bounds.height-34,width:82,height:26)
        reply.frame = CGRect(x:bounds.width-88,y:bounds.height-34,width:80,height:26)
    }
    override func mouseDown(with event:NSEvent) {}
    @objc private func closeNote() { onClose?() }
    @objc private func editNote() { onEdit?(rootID) }
    @objc private func replyNote() { onReply?(rootID) }
}
