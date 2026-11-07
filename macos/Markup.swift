import AppKit

enum MarkupKind: UInt32, CaseIterable {
    case rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick
    case highlight, freehandHighlight, underline, squiggly, strikeout, ink, freeText, comment
    var title: String { ["Rectangle","Ellipse","Line","Arrow","Polyline","Polygon","Cloud","Star","Cross","Tick","Text highlight","Freehand highlight","Underline","Squiggly underline","Strikethrough","Draw","Type","Add comment"][Int(rawValue)] }
    var symbol: String { ["rectangle","circle","line.diagonal","arrow.up.right","point.topleft.down.to.point.bottomright.curvepath","pentagon","cloud","star","xmark","checkmark","highlighter","pencil.tip.crop.circle","underline","underline","strikethrough","pencil.tip","textformat","text.bubble"][Int(rawValue)] }
    var isShape: Bool { rawValue<10 }
    var isTextMarkup: Bool { [.highlight,.underline,.squiggly,.strikeout].contains(self) }
    var isPath: Bool { [.polyline,.polygon,.ink,.freehandHighlight].contains(self) }
    var isFreehand: Bool { self == .ink || self == .freehandHighlight }
    var isText: Bool { self == .freeText || self == .comment }
    var hint: String {
        if isTextMarkup { return "Click a word or drag across a passage to mark it." }
        if self == .polyline || self == .polygon { return "Click to add points. Double-click or press Return to finish. Escape cancels." }
        if self == .freeText { return "Click the page to place text. Edit it in the inspector." }
        if self == .comment { return "Click the page to leave a comment." }
        return "Drag on the page to create \(title.lowercased()). Escape cancels."
    }
}
struct MarkupStyle {
    var stroke=NSColor(srgbRed:69/255,green:117/255,blue:180/255,alpha:1)
    var fill: NSColor?=nil
    var opacity=1.0
    var width=2.0
    var fontSize=14.0
    static func initial(for kind:MarkupKind) -> MarkupStyle {
        var s=MarkupStyle()
        if kind == .highlight || kind == .freehandHighlight { s.stroke=NSColor(srgbRed:254/255,green:224/255,blue:144/255,alpha:1); s.fill=s.stroke; s.opacity=0.4; s.width=14 }
        if kind == .comment { s.stroke = .systemOrange; s.fill = .systemYellow }
        return s
    }
    var cValue: PodStyle {
        let stroke=self.stroke.usingColorSpace(.sRGB) ?? .black
        let fill=self.fill?.usingColorSpace(.sRGB)
        return PodStyle(stroke:(stroke.redComponent,stroke.greenComponent,stroke.blueComponent),fill:(Double(fill?.redComponent ?? 0),Double(fill?.greenComponent ?? 0),Double(fill?.blueComponent ?? 0)),opacity:opacity,width:width,font_size:fontSize,has_fill:fill == nil ? 0:1)
    }
    init() {}
    init(_ c:PodStyle) {
        stroke=NSColor(srgbRed:c.stroke.0,green:c.stroke.1,blue:c.stroke.2,alpha:1)
        fill=c.has_fill == 0 ? nil:NSColor(srgbRed:c.fill.0,green:c.fill.1,blue:c.fill.2,alpha:1)
        opacity=c.opacity; width=c.width; fontSize=c.font_size
    }
}
struct CommentInfo {
    var author = ""
    var subject = ""
    var initiallyOpen = false
    var popupRect: CGRect? = nil
    var richText = false
    var replyTo: UInt32 = 0
    var threadRoot: UInt32 = 0
    var reviewState = ""
    var stateModel = ""
}
struct Markup {
    var id: UInt32=0
    var kind: MarkupKind
    var points:[CGPoint]
    var rect:CGRect
    var text:String=""
    var style:MarkupStyle
    // Offsets into page-space points. An empty list denotes one continuous path.
    var inkPathStarts: [Int] = []
    var link: String = ""
    var legacyInk = false
    var importedComment = false
    var importedShape = false
    var importedFreeText = false
    var freeTextEditable = false
    var shapeEditable = false
    var hasCaption = false
    var comment = CommentInfo()
    var canMove: Bool { !inkLocked && !importedComment }
    var canChangeAppearance: Bool { canMove && (!importedFreeText || freeTextEditable) && (!importedShape || shapeEditable) }
    var importedInk = false
    var inkLocked = false
    var hasReplies = false
    var canDelete: Bool { !inkLocked && !hasReplies }
    var canEditContents: Bool { hasEditableText && contentsLockReason == nil }
    var contentsLockReason: String? {
        if inkLocked { return "This annotation is locked." }
        if importedFreeText && !freeTextEditable { return "This text box’s original formatting is preserved. Text editing is not supported yet." }
        if comment.richText { return "Rich-text note editing is not supported yet." }
        if hasCaption && !shapeEditable { return "This caption's original appearance is preserved. Text editing is not supported yet." }
        return nil
    }
    var hasEditableText: Bool { importedShape || kind == .ink || kind.isText || kind.isTextMarkup }
    func translated(x:CGFloat,y:CGFloat) -> Markup {
        var result=self; result.points=points.map{CGPoint(x:$0.x+x,y:$0.y+y)}; result.rect=rect.offsetBy(dx:x,dy:y); return result
    }
    func rotated(by radians: CGFloat) -> Markup {
        let box = geometryBounds
        let cosine = cos(radians), sine = sin(radians)
        var result = self
        result.points = points.map { point in
            let x = point.x-box.midX, y = point.y-box.midY
            return CGPoint(x:box.midX+x*cosine-y*sine, y:box.midY+x*sine+y*cosine)
        }
        result.rect = result.geometryBounds
        return result
    }
    private var inkRanges: [Range<Int>] {
        let starts = inkPathStarts.isEmpty ? [0] : inkPathStarts
        return zip(starts, starts.dropFirst() + [points.count]).map { $0..<$1 }
    }
    // Some PDF writers encode a dot as a move and line to the same point.
    private func isDot(_ range: Range<Int>) -> Bool {
        range.dropFirst().allSatisfy { points[$0] == points[range.lowerBound] }
    }
    private func inkLine(_ range: Range<Int>, transform: (CGPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: transform(points[range.lowerBound]))
        if kind == .freehandHighlight || legacyInk || importedInk || range.count <= 2 {
            for i in range.dropFirst() { path.addLine(to:transform(points[i])) }
        } else {
            for i in (range.lowerBound+1)..<(range.upperBound-1) {
                let control=transform(points[i]), next=transform(points[i+1])
                let end=i == range.upperBound-2 ? next : CGPoint(x:(control.x+next.x)/2,y:(control.y+next.y)/2)
                path.addQuadCurve(to:end,control:control)
            }
        }
        return path
    }
    private func inkOutline(_ range: Range<Int>, width: CGFloat, transform: (CGPoint) -> CGPoint) -> CGPath {
        if isDot(range) {
            let center = transform(points[range.lowerBound])
            return CGPath(ellipseIn: CGRect(x: center.x-width/2, y: center.y-width/2, width: width, height: width), transform: nil)
        }
        return inkLine(range, transform: transform).copy(strokingWithWidth: width,
            lineCap: legacyInk || kind == .freehandHighlight ? .butt : .round, lineJoin: kind == .freehandHighlight ? .miter : legacyInk ? .bevel : .round, miterLimit: 1)
    }
    func inkOutline(width: CGFloat, transform: (CGPoint) -> CGPoint = { $0 }) -> CGPath {
        let outline = CGMutablePath()
        for range in inkRanges where !range.isEmpty { outline.addPath(inkOutline(range, width: width, transform: transform)) }
        return outline
    }

    enum EraserResult { case unchanged, edited(Markup), removed, tooComplex }

    enum EraserMode: String { case stroke, precision }

    func subtractingInk(_ brush: CGPath, mode: EraserMode = .precision, onStrokeHit: ((CGPath) -> Void)? = nil) -> EraserResult {
        let padding = mode == .stroke ? style.width / 2 + 0.01 : 0.01
        guard kind.isFreehand, !inkLocked,
              geometryBounds.insetBy(dx:-padding,dy:-padding).intersects(brush.boundingBoxOfPath) else { return .unchanged }
        var kept: [[CGPoint]] = []
        var changed=false
        for range in inkRanges where !range.isEmpty {
            if mode == .stroke {
                let outline = inkOutline(range, width: style.width, transform: { $0 })
                if outline.intersects(brush) {
                    changed = true
                    onStrokeHit?(outline)
                } else { kept.append(Array(points[range])) }
                continue
            }
            if isDot(range) {
                if brush.contains(points[range.lowerBound]) { changed=true } else { kept.append(Array(points[range])) }
                continue
            }
            let line=inkLine(range,transform:{ $0 })
            if line.lineIntersection(brush).isEmpty {
                kept.append(Array(points[range]))
                continue
            }
            changed=true
            let remainder=line.lineSubtracting(brush)
            // Quartz clips the centerline. Preserve untouched paths verbatim and sample
            // just the cut path to sub-point precision, keeping each lift separate.
            var fragment: [CGPoint] = []
            func finishFragment() {
                guard !fragment.isEmpty else { return }
                if kind == .freehandHighlight && !Self.hasDrawnExtent(fragment, threshold: 0) { fragment = []; return }
                kept.append(fragment)
                fragment=[]
            }
            remainder.flattened(threshold:0.15).applyWithBlock { raw in
                let element=raw.pointee
                switch element.type {
                case .moveToPoint: finishFragment(); fragment=[element.points[0]]
                case .addLineToPoint:
                    if fragment.last != element.points[0] { fragment.append(element.points[0]) }
                default: break
                }
            }
            finishFragment()
        }
        guard changed else { return .unchanged }
        guard !kept.isEmpty else { return .removed }
        guard kept.reduce(0,{ $0+$1.count }) <= 4096 else { return .tooComplex }
        var result=self
        result.points=[]; result.inkPathStarts=[]
        for path in kept {
            if kept.count > 1 { result.inkPathStarts.append(result.points.count) }
            result.points.append(contentsOf:path)
        }
        result.rect=result.geometryBounds
        return .edited(result)
    }
    // Pod highlighters store one continuous PDF path per annotation.
    // Keep the original ID on the first surviving piece of a precision cut.
    var erasedFragments: [Markup] {
        guard kind == .freehandHighlight, !inkPathStarts.isEmpty else { return [self] }
        return inkRanges.enumerated().map { index, range in
            var fragment = self
            fragment.id = index == 0 ? id : 0
            fragment.inkPathStarts = []
            fragment.points = Array(points[range])
            fragment.rect = fragment.geometryBounds
            return fragment
        }
    }

    func hitTest(_ p:CGPoint,tolerance:CGFloat) -> Bool {
        if importedShape { return rect.insetBy(dx:-tolerance,dy:-tolerance).contains(p) }
        if kind.isFreehand {
            return inkOutline(width: style.width + 2*tolerance).contains(p)
        }
        if kind.isTextMarkup && points.count >= 4 && points.count.isMultiple(of: 4) {
            for start in stride(from: 0, to: points.count, by: 4) {
                var quad = Array(points[start..<(start + 4)])
                func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
                    (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x)
                }
                if turn(quad[0], quad[1], quad[2]) * turn(quad[1], quad[2], quad[3]) < 0 { quad.swapAt(2, 3) }
                var positive = false, negative = false
                for j in quad.indices {
                    let a = quad[j], b = quad[(j + 1) % 4]
                    let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                    let margin = tolerance * hypot(b.x - a.x, b.y - a.y)
                    positive = positive || cross > margin
                    negative = negative || cross < -margin
                }
                if !(positive && negative) { return true }
            }
            return false
        }
        if [.line,.arrow,.polyline,.freehandHighlight].contains(kind) {
            let radius=tolerance+style.width/2
            return zip(points,points.dropFirst()).contains { a,b in
                let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
                let t=length>0 ? min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)):0
                return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)<=radius
            }
        }
        return geometryBounds.insetBy(dx:-tolerance,dy:-tolerance).contains(p)
    }
    static func hasDrawnExtent(_ points:[CGPoint],threshold:CGFloat) -> Bool {
        guard let first=points.first,points.count>1 else { return false }
        return points.dropFirst().contains { hypot($0.x-first.x,$0.y-first.y)>threshold }
    }
    var geometryBounds:CGRect {
        if importedShape { return rect }
        guard let p=points.first else { return rect }
        return points.dropFirst().reduce(CGRect(x:p.x,y:p.y,width:0,height:0)) { r,p in
            let x=min(r.minX,p.x),y=min(r.minY,p.y)
            return CGRect(x:x,y:y,width:max(r.maxX,p.x)-x,height:max(r.maxY,p.y)-y)
        }
    }
    func scaled(to box:CGRect) -> Markup {
        let rect=geometryBounds
        var result=self
        result.points=points.map { CGPoint(x:box.minX+($0.x-rect.minX)*box.width/max(rect.width,1),y:box.minY+($0.y-rect.minY)*box.height/max(rect.height,1)) }
        result.rect=box; return result
    }
}
