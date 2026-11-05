import AppKit

final class LuminShareButton:NSButton {
    enum Style { case text,outlined,filled,tonal,change,selector }
    let style:Style
    var size:CGFloat=16,weight:Double=500,horizontalPadding:CGFloat=16
    var glyph:String?,bitmap:String?,leadingBitmap:String?
    var imageSize:CGFloat=24,iconSlot:CGFloat=24,iconGap:CGFloat=8
    var arrow=false
    var onPress:(()->Void)?
    var keyboardFocused=false { didSet { needsDisplay=true; superview?.needsDisplay=true } }
    override var wantsDefaultClipping:Bool { false }
    private var hovered=false
    private var tracking:NSTrackingArea?
    var cssForeground:NSColor {
        if !isEnabled { return PodTheme.text.withAlphaComponent(0.38) }
        switch style { case .filled:return PodTheme.onSecondary; case .tonal:return PodTheme.onSecondaryContainer; case .change:return PodTheme.secondaryText; case .selector:return PodTheme.text; default:return PodTheme.secondary }
    }
    var cssBackground:NSColor { guard isEnabled else { return .clear }; return style == .filled ? PodTheme.secondary:style == .tonal ? PodTheme.chrome:.clear }
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:LuminHeaderMenuRow.width(title,font:LuminAssets.font(size,weight))+horizontalPadding*2+((arrow || glyph != nil || bitmap != nil) ? iconSlot+iconGap:0),height:size==16 ? 40:32) }
    init(_ title:String,style:Style = .text) { self.style=style; super.init(frame:.zero); self.title=title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(press); setAccessibilityLabel(title) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    @objc private func press() { onPress?() }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8); cssBackground.setFill(); path.fill()
        if style != .change && style != .selector && isEnabled && (hovered || isHighlighted) { cssForeground.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); path.fill() }
        if style == .outlined || style == .selector { (style == .selector ? (hovered ? PodTheme.secondary:PodTheme.border):PodTheme.secondary).setStroke(); path.lineWidth=1; path.stroke() }
        if keyboardFocused { PodTheme.color(0x228BE6).setStroke(); let ring=NSBezierPath(roundedRect:bounds.insetBy(dx:-3,dy:-3),xRadius:10,yRadius:10); ring.lineWidth=2; ring.stroke() }
        let line:CGFloat=size==16 ? 24:20,hasIcon=arrow || glyph != nil || bitmap != nil
        let gap:CGFloat=title.isEmpty ? 0:iconGap
        let width=LuminHeaderMenuRow.width(title,font:LuminAssets.font(size,weight)),content=width+(hasIcon ? iconSlot+gap:0)
        let x=style == .selector ? 33:(bounds.width-content)/2
        var attributes:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(size,weight),.foregroundColor:cssForeground]
        if style == .change { attributes[.underlineStyle]=NSUnderlineStyle.single.rawValue }
        (title as NSString).draw(in:NSRect(x:style == .change ? 0:x,y:(bounds.height-line)/2,width:style == .selector ? bounds.width-65:width,height:line),withAttributes:attributes)
        if let leadingBitmap,let image=LuminAssets.bitmap(leadingBitmap) { LuminAssets.tinted(image,cssForeground).draw(in:NSRect(x:6,y:8,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        let icon=glyph.flatMap{LuminAssets.icon($0,size:imageSize)} ?? bitmap.flatMap{LuminAssets.bitmap($0)} ?? (arrow ? LuminAssets.icon("kiwi-icon-chevron-down-md",size:20):nil)
        if let icon {
            let actual=arrow && bitmap==nil ? CGFloat(20):imageSize
            let iconX=style == .selector ? bounds.width-28:x+width+gap+(iconSlot-actual)/2
            let image=bitmap=="Share/slack-logo" ? icon:LuminAssets.tinted(icon,cssForeground)
            image.draw(in:NSRect(x:iconX,y:(bounds.height-actual)/2,width:actual,height:actual),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
    }
}

private final class LuminShareInputCell:NSTextFieldCell {
    var lineHeight:CGFloat=24,inset:CGFloat=2
    override func drawingRect(forBounds rect:NSRect)->NSRect { NSRect(x:rect.minX+inset,y:rect.midY-lineHeight/2,width:rect.width-inset*2,height:lineHeight) }
    override func edit(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,event:NSEvent?) { super.edit(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,event:event) }
    override func select(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,start selStart:Int,length selLength:Int) { super.select(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,start:selStart,length:selLength) }
}

final class LuminShareInput:NSView,NSTextFieldDelegate {
    let input=LuminZoomInput()
    let search:Bool
    private var focused=false
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    init(search:Bool) {
        self.search=search; super.init(frame:.zero)
        let cell=LuminShareInputCell(); cell.lineHeight=search ? 24:20; cell.inset=search ? 2:6; input.cell=cell; input.stringValue=""
        input.isBordered=false; input.isBezeled=false; input.drawsBackground=false; input.focusRingType = .none; input.font=LuminAssets.font(search ? 16:14,420); input.textColor=PodTheme.text; input.delegate=self; input.isEditable=search; input.isSelectable=true; input.lineBreakMode = .byTruncatingTail
        if search { input.placeholderAttributedString=NSAttributedString(string:"Enter email address",attributes:[.font:LuminAssets.font(16,420),.foregroundColor:PodTheme.text.withAlphaComponent(0.38)]) }
        input.setAccessibilityLabel(search ? "Enter email address":"Share link"); input.onFocus={ [weak self] in self?.focused=true; self?.needsDisplay=true }; addSubview(input)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); input.frame=search ? NSRect(x:37,y:0,width:bounds.width-46,height:40):NSRect(x:4,y:0,width:bounds.width-8,height:32) }
    func controlTextDidBeginEditing(_ notification:Notification) { focused=true; needsDisplay=true }
    func controlTextDidEndEditing(_ notification:Notification) { focused=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); input.textColor=PodTheme.text; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        guard search else { return }
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if focused { PodTheme.dockFocus.setStroke(); path.lineWidth=8; path.stroke() }
        (focused ? PodTheme.secondary:PodTheme.border).setStroke(); path.lineWidth=1; path.stroke()
        if let image=LuminAssets.icon("kiwi-icon-search-lg",size:24) { LuminAssets.tinted(image,PodTheme.text).draw(in:NSRect(x:9,y:8,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

final class LuminShareCheckbox:NSButton {
    var isOn=false { didSet { setAccessibilityValue(isOn ? 1:0); needsDisplay=true } }
    var onToggle:(()->Void)?
    override var isFlipped:Bool { true }
    init() { super.init(frame:.zero); title="People invited list"; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose); setAccessibilityRole(.checkBox); setAccessibilityLabel(title); setAccessibilityValue(0) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { onToggle?() }
    override func draw(_ rect:NSRect) {
        let box=NSBezierPath(roundedRect:NSRect(x:9.75,y:7.75,width:16.5,height:16.5),xRadius:2,yRadius:2)
        if isOn { PodTheme.secondary.setFill(); box.fill() }
        (isOn ? PodTheme.secondary:PodTheme.text).setStroke(); box.lineWidth=1.5; box.stroke()
        if isOn,let image=LuminAssets.bitmap("Share/check") { LuminAssets.tinted(image,PodTheme.onSecondary).draw(in:NSRect(x:12,y:11,width:12,height:10),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:36,y:6,width:bounds.width-44,height:20),withAttributes:[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.text])
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}
