import AppKit

// The default WebViewer margin scales with zoom. Its layout ceils the document
// width but floors page containers; see mode-rail-canvas-source-evidence.md.
struct LuminCanvasLayout {
    let margin:CGFloat,documentSize:NSSize,imageFrame:NSRect,borderFrame:NSRect
    init(pageSize:NSSize,zoom:CGFloat,viewport:NSSize) {
        margin=round(max(1,4*zoom))
        let scaled=NSSize(width:pageSize.width*zoom,height:pageSize.height*zoom)
        let flowWidth=ceil(scaled.width+2*margin)
        documentSize=NSSize(width:max(viewport.width,flowWidth),height:max(viewport.height,floor(scaled.height)+2*margin+96))
        let origin=NSPoint(x:(documentSize.width-flowWidth)/2+margin,y:48+margin)
        imageFrame=NSRect(origin:origin,size:scaled); borderFrame=NSRect(origin:origin,size:NSSize(width:floor(scaled.width),height:floor(scaled.height)))
    }
}

enum LuminCanvasPattern {
    static let tile:CGFloat=26,radius:CGFloat=1
    static var color:NSColor { PodTheme.text.withAlphaComponent(0.16) }
    static func centers(in rect:NSRect,origin:NSPoint)->[NSPoint] {
        let firstX=Int(ceil((rect.minX-origin.x-13-radius)/tile)),lastX=Int(floor((rect.maxX-origin.x-13+radius)/tile))
        let firstY=Int(ceil((rect.minY-origin.y-13-radius)/tile)),lastY=Int(floor((rect.maxY-origin.y-13+radius)/tile))
        guard firstX<=lastX,firstY<=lastY else { return [] }
        return (firstY...lastY).flatMap{row in (firstX...lastX).map{column in NSPoint(x:origin.x+13+CGFloat(column)*tile,y:origin.y+13+CGFloat(row)*tile)}}
    }
}

final class LuminCanvasClipView:NSClipView {
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override init(frame:NSRect) { super.init(frame:frame); drawsBackground=false; wantsLayer=true; layer?.cornerRadius=8; layer?.masksToBounds=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        if let layer { layer.maskedCorners=layer.isGeometryFlipped ? [.layerMinXMinYCorner,.layerMaxXMinYCorner]:[.layerMinXMaxYCorner,.layerMaxXMaxYCorner] }
    }
    override func setBoundsOrigin(_ newOrigin:NSPoint) { super.setBoundsOrigin(newOrigin); needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        PodTheme.canvas.setFill(); bounds.fill(); LuminCanvasPattern.color.setFill()
        for point in LuminCanvasPattern.centers(in:dirtyRect,origin:bounds.origin) { NSBezierPath(ovalIn:NSRect(x:point.x-1,y:point.y-1,width:2,height:2)).fill() }
    }
}

struct LuminViewerLayout {
    let header,toolbar,canvas,restore:NSRect
    init(viewport:NSSize,focus:Bool,navigationExpanded:Bool=false) {
        let top:CGFloat=focus ? 0:56,left:CGFloat=focus ? 0:navigationExpanded ? 276:80,right:CGFloat=focus ? 0:56
        header=NSRect(x:0,y:0,width:viewport.width,height:top)
        toolbar=NSRect(x:left,y:top,width:viewport.width-left-right,height:48)
        canvas=NSRect(x:left+2,y:top+48,width:viewport.width-left-right-4,height:viewport.height-top-48)
        restore=NSRect(x:0,y:viewport.height-60,width:36,height:48)
    }
}
