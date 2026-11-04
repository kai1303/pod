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
        if isTextMarkup { return "Click a text line, or drag across lines, to mark them." }
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
struct Markup {
    var id: UInt32=0
    var kind: MarkupKind
    var points:[CGPoint]
    var rect:CGRect
    var text:String=""
    var style:MarkupStyle
    func translated(x:CGFloat,y:CGFloat) -> Markup {
        var result=self; result.points=points.map{CGPoint(x:$0.x+x,y:$0.y+y)}; result.rect=rect.offsetBy(dx:x,dy:y); return result
    }
    func hitTest(_ p:CGPoint,tolerance:CGFloat) -> Bool {
        if [.line,.arrow,.polyline,.ink,.freehandHighlight].contains(kind) {
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
