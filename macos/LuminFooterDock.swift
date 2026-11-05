import AppKit

// Shipped sc-fddb1da9/sc-68e165ab/sc-6d0ce6e5 and InputButton CSS.
// Source DOM fixture and known native rendering limits: research/lumin/footer-dock-source-evidence.md.
final class LuminDockButton:NSButton {
    let glyphName:String
    let legacy:Bool
    var glyphRect:NSRect { NSRect(x:6,y:6,width:20,height:20) }
    private var hovered=false
    private var tracking:NSTrackingArea?
    var cssForeground:NSColor { isEnabled ? (legacy ? LuminLegacyStyle.variant:PodTheme.secondary):(legacy ? LuminLegacyStyle.disabled:PodTheme.text.withAlphaComponent(0.38)) }
    var cssBackground:NSColor { isEnabled && (hovered || isHighlighted) ? (legacy ? LuminLegacyStyle.variant:PodTheme.secondary).withAlphaComponent(isHighlighted ? 0.12:0.08):.clear }
    override var isFlipped:Bool { true }
    init(_ label:String,_ glyph:String,legacy:Bool=false) {
        glyphName=glyph; self.legacy=legacy; super.init(frame:.zero)
        title=""; image=LuminAssets.icon(glyph,size:20); isBordered=false; focusRingType = .none; setButtonType(.momentaryPushIn)
        setAccessibilityLabel(label); toolTip=label
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        cssBackground.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        if let image { LuminAssets.tinted(image,cssForeground).draw(in:glyphRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

final class LuminDockField:NSView,NSTextFieldDelegate {
    let input=LuminZoomInput()
    var onCommit:((String)->Void)?
    var onActivity:((Bool)->Void)?
    var focused=false { didSet { needsDisplay=true; onActivity?(focused) } }
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    override var intrinsicContentSize:NSSize {
        // react-input-autosize rounds the sizer width up to an integer CSS pixel.
        NSSize(width:max(40,ceil((input.stringValue as NSString).size(withAttributes:[.font:LuminAssets.font(12,420)]).width))+8,height:32)
    }
    init(label:String) {
        super.init(frame:.zero)
        input.isBordered=false; input.isBezeled=false; input.drawsBackground=false; input.focusRingType = .none; input.font=LuminAssets.font(12,420); input.textColor=PodTheme.text; input.alignment = .center; input.delegate=self; input.target=self; input.action=#selector(submit); input.setAccessibilityLabel(label)
        input.onFocus={ [weak self] in self?.focused=true }
        addSubview(input)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); input.frame=NSRect(x:4,y:7,width:bounds.width-8,height:18) }
    func commit() { onCommit?(input.stringValue) }
    @objc private func submit() { if input.currentEditor() != nil { window?.makeFirstResponder(superview) } else { commit() } }
    func controlTextDidBeginEditing(_ notification:Notification) { focused=true; input.currentEditor()?.selectAll(nil) }
    func controlTextDidEndEditing(_ notification:Notification) { focused=false; commit() }
    func controlTextDidChange(_ notification:Notification) { invalidateIntrinsicContentSize(); superview?.invalidateIntrinsicContentSize(); superview?.needsLayout=true }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); input.textColor=PodTheme.text; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        if focused { PodTheme.dockFocus.setStroke(); path.lineWidth=6; path.stroke() }
        PodTheme.chrome.setFill(); path.fill()
        if hovered { PodTheme.text.setStroke(); path.lineWidth=1; path.stroke() }
    }
}

final class LuminFooterDock:NSView {
    let zoomOut=LuminDockButton("Zoom out","pdf-icon-md_zoom_out",legacy:true)
    let zoomIn=LuminDockButton("Zoom in","pdf-icon-md_zoom_in",legacy:true)
    let firstPage=LuminDockButton("First page","kiwi-icon-ph-caret-double-left")
    let previousPage=LuminDockButton("Previous page","kiwi-icon-ph-caret-left")
    let nextPage=LuminDockButton("Next page","kiwi-icon-ph-caret-right")
    let lastPage=LuminDockButton("Last page","kiwi-icon-ph-caret-double-right")
    let zoomField=LuminDockField(label:"Bottom zoom percentage"),pageField=LuminDockField(label:"Current page")
    let totalLabel=NSTextField(labelWithString:"/1")
    let divider=PodSurfaceView()
    var onPage:((Int)->Void)?
    var onZoom:((Double)->Void)?
    private var page=1,total=1,percentage=100.0
    private var available=false
    private var pointerInside=false
    private var tracking:NSTrackingArea?
    private var inactivity:DispatchWorkItem?
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override var wantsDefaultClipping:Bool { false }
    override var acceptsFirstResponder:Bool { true }
    private var totalWidth:CGFloat { ceil((totalLabel.stringValue as NSString).size(withAttributes:[.font:LuminAssets.font(12,500)]).width*64)/64 }
    override var intrinsicContentSize:NSSize { NSSize(width:245+zoomField.intrinsicContentSize.width+pageField.intrinsicContentSize.width+totalWidth,height:44) }
    override init(frame:NSRect) {
        super.init(frame:frame); alphaValue=0.7
        totalLabel.font=LuminAssets.font(12,500); totalLabel.textColor=PodTheme.text
        divider.surface=LuminLegacyStyle.outline
        for view in [zoomOut,zoomField,zoomIn,divider,firstPage,previousPage,pageField,totalLabel,nextPage,lastPage] { addSubview(view) }
        zoomField.onCommit={ [weak self] raw in
            guard let self else { return }
            let number=Double(raw.components(separatedBy:"%").first?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "") ?? .nan
            let valid=(5...9999).contains(number) ? number:percentage
            previewZoom(valid); onZoom?(valid)
        }
        pageField.onCommit={ [weak self] raw in
            guard let self else { return }
            let number=Double(raw.trimmingCharacters(in:.whitespacesAndNewlines)) ?? .nan
            let valid=number.isFinite && number.rounded(.towardZero)==number && number>=1 && number<=Double(total) ? Int(number):page
            pageField.input.stringValue=String(valid); onPage?(valid)
        }
        for field in [zoomField,pageField] { field.onActivity={ [weak self] focused in focused ? self?.activate():self?.scheduleInactivity() } }
        for (index,button) in [firstPage,previousPage,nextPage,lastPage].enumerated() { button.tag=index; button.target=self; button.action=#selector(navigate) }
        update(page:1,total:1,percentage:100,available:false)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout(); var x:CGFloat=8
        func place(_ view:NSView,_ width:CGFloat,_ height:CGFloat=32) { view.frame=NSRect(x:x,y:(44-height)/2,width:width,height:height); x+=width+4 }
        place(zoomOut,32); place(zoomField,zoomField.intrinsicContentSize.width); place(zoomIn,32)
        // The shipped MUI divider resolves to zero height in the live legacy shell.
        place(divider,1,0); place(firstPage,32); place(previousPage,32); place(pageField,pageField.intrinsicContentSize.width); place(totalLabel,totalWidth,16); place(nextPage,32); place(lastPage,32)
    }
    func update(page:Int,total:Int,percentage:Double,available:Bool) {
        self.page=page; self.total=max(1,total); self.percentage=percentage; self.available=available
        pageField.input.stringValue=String(page); totalLabel.stringValue="/\(self.total)"; zoomField.input.stringValue=String(format:"%.0f%%",percentage)
        firstPage.isEnabled=available && page>1; previousPage.isEnabled=firstPage.isEnabled
        lastPage.isEnabled=available && page<total; nextPage.isEnabled=lastPage.isEnabled
        zoomOut.isEnabled=available && percentage>5; zoomIn.isEnabled=available && percentage<9999
        pageField.input.isEnabled=available; zoomField.input.isEnabled=available
        invalidateIntrinsicContentSize(); needsLayout=true
    }
    func previewZoom(_ value:Double) { percentage=value; zoomField.input.stringValue=String(format:"%.0f%%",value); zoomOut.isEnabled=available && value>5; zoomIn.isEnabled=available && value<9999; invalidateIntrinsicContentSize(); needsLayout=true }
    @objc private func navigate(_ sender:NSButton) { onPage?([1,max(1,page-1),min(total,page+1),total][sender.tag]) }
    func setActive(_ value:Bool) { alphaValue=value ? 1:0.7; needsDisplay=true }
    private func activate() { inactivity?.cancel(); setActive(true) }
    private func scheduleInactivity() {
        inactivity?.cancel(); guard !pointerInside,!zoomField.focused,!pageField.focused else { return }
        let work=DispatchWorkItem { [weak self] in self?.setActive(false) }; inactivity=work; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { pointerInside=true; activate() }
    override func mouseExited(with event:NSEvent) { pointerInside=false; scheduleInactivity() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); totalLabel.textColor=PodTheme.text; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        let shadows:[(CGFloat,CGFloat,CGFloat)] = alphaValue==1 ? [(11,4,0.01),(6,4,0.04),(3,3,0.07),(0,2,0.16)]:[(5,2,0.01),(3,2,0.05),(1,1,0.08),(0,1,0.16)]
        for (offset,blur,alpha) in shadows { NSGraphicsContext.saveGraphicsState(); let shadow=NSShadow(); shadow.shadowOffset=NSSize(width:0,height:offset); shadow.shadowBlurRadius=blur; shadow.shadowColor=NSColor.black.withAlphaComponent(alpha); shadow.set(); PodTheme.raised.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState() }
        PodTheme.raised.setFill(); path.fill()
        // AppKit's shadow rasterizer differs from CSS; retain the source inset-light role.
        NSGraphicsContext.saveGraphicsState(); path.addClip(); NSColor.white.withAlphaComponent(0.64).setStroke(); path.lineWidth=0.5; path.stroke(); NSGraphicsContext.restoreGraphicsState()
    }
}
