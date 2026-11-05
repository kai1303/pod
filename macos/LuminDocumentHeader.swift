import AppKit

final class LuminHeaderButton:NSButton {
    enum Style { case navigation,file,plain,share,shareOptions }
    let glyphName:String,style:Style
    private var hovered=false
    private var tracking:NSTrackingArea?
    var cssForeground:NSColor { (style == .share || style == .shareOptions ? PodTheme.onSecondaryContainer:style == .navigation ? PodTheme.secondary:PodTheme.text).withAlphaComponent(isEnabled ? 1:0.38) }
    var cssBackground:NSColor { style == .share || style == .shareOptions ? PodTheme.primaryContainer:style == .file ? PodTheme.surface:.clear }
    override var isFlipped:Bool { true }
    init(_ label:String,_ glyph:String,style:Style) {
        self.glyphName=glyph; self.style=style; super.init(frame:.zero)
        title=label; image=LuminAssets.icon(glyph,size:style == .navigation || style == .share || style == .shareOptions ? 24:20)
        isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; setAccessibilityLabel(label); toolTip=label
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        if style == .share { shape.appendRect(NSRect(x:bounds.maxX-8,y:0,width:8,height:bounds.height)) }
        if style == .shareOptions { shape.appendRect(NSRect(x:0,y:0,width:8,height:bounds.height)) }
        cssBackground.setFill(); shape.fill()
        if isEnabled && (hovered || isHighlighted) { cssForeground.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); shape.fill() }
        let size:CGFloat=style == .navigation || style == .share || style == .shareOptions ? 24:20
        let x:CGFloat=style == .share ? 16:(bounds.width-size)/2
        if let image { LuminAssets.tinted(image,cssForeground).draw(in:NSRect(x:x,y:(bounds.height-size)/2,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        if style == .share { ("Share" as NSString).draw(in:NSRect(x:48,y:8,width:44.265625,height:24),withAttributes:[.font:LuminAssets.font(16,500),.foregroundColor:cssForeground]) }
    }
}

final class LuminHeaderTitleBox:NSView,NSTextFieldDelegate {
    let input=NSTextField(string:"")
    private var hovered=false,focused=false
    private var tracking:NSTrackingArea?
    var onChange:(()->Void)?
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    override init(frame:NSRect) {
        super.init(frame:frame)
        input.isBordered=false; input.isBezeled=false; input.drawsBackground=false; input.focusRingType = .none; input.font=LuminAssets.font(14,520); input.textColor=LuminLegacyStyle.text; input.lineBreakMode = .byTruncatingTail; input.delegate=self; input.setAccessibilityLabel("Document title"); addSubview(input)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); input.frame=NSRect(x:9,y:4.1,width:max(0,bounds.width-18),height:23.8) }
    func controlTextDidBeginEditing(_ notification:Notification) { focused=true; needsDisplay=true }
    func controlTextDidEndEditing(_ notification:Notification) { focused=false; needsDisplay=true }
    func controlTextDidChange(_ notification:Notification) { onChange?() }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); input.textColor=LuminLegacyStyle.text; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if focused { LuminLegacyStyle.secondaryContainer.setStroke(); path.lineWidth=4; path.stroke(); LuminLegacyStyle.container.setFill(); path.fill() }
        if hovered || focused { (focused ? LuminLegacyStyle.variant:LuminLegacyStyle.outline).setStroke(); path.lineWidth=1; path.stroke() }
    }
}

final class LuminHeaderStatus:NSView {
    let text=NSTextField(labelWithString:"Edited today")
    private let icon=NSImageView()
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:28+ceil((text.stringValue as NSString).size(withAttributes:[.font:LuminAssets.font(12,500)]).width*64)/64,height:24) }
    override init(frame:NSRect) {
        super.init(frame:frame); icon.image=LuminAssets.icon("pdf-icon-sm_time",size:16); icon.contentTintColor=PodTheme.secondaryText
        text.font=LuminAssets.font(12,500); text.textColor=PodTheme.secondaryText
        addSubview(icon); addSubview(text); setAccessibilityLabel("Document status")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); icon.frame=NSRect(x:4,y:4,width:16,height:16); text.frame=NSRect(x:24,y:4,width:max(0,bounds.width-28),height:16) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); icon.contentTintColor=PodTheme.secondaryText; text.textColor=PodTheme.secondaryText }
}

final class LuminDocumentHeader:PodSurfaceView {
    let navigationBack=LuminNavigationButton("My documents",style:.back)
    let navigationClose=LuminNavigationButton("Close navigation",style:.close)
    var navigationExpanded=false { didSet { navigation.isHidden=navigationExpanded; navigationBack.isHidden = !navigationExpanded; navigationClose.isHidden = !navigationExpanded; needsLayout=true } }
    let navigation=LuminHeaderButton("Navigation","kiwi-icon-hamburger-md",style:.navigation)
    let fileMenu=LuminHeaderButton("File menu","pdf-icon-md_more_horizontal_menu",style:.file)
    let share=LuminHeaderButton("Share","pdf-icon-md_not_shared",style:.share)
    let shareOptions=LuminHeaderButton("Share options","pdf-icon-md_arrow_down",style:.shareOptions)
    let help=LuminHeaderButton("Help","pdf-icon-md_status_question",style:.plain)
    let notifications=LuminHeaderButton("Notifications","pdf-icon-viewer-notification",style:.plain)
    let identity=NSImageView()
    let titleBox=LuminHeaderTitleBox()
    let documentStatus=LuminHeaderStatus()
    var titleField:NSTextField { titleBox.input }
    private let divider=PodSurfaceView()
    var onAction:((NSButton)->Void)?
    var documentName="Welcome to Pod.pdf" { didSet { titleField.stringValue=documentName.lowercased().hasSuffix(".pdf") ? String(documentName.dropLast(4)):documentName; needsLayout=true } }
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); surface=PodTheme.chrome
        if let icon=Bundle.main.url(forResource:"Pod",withExtension:"icns") { identity.image=NSImage(contentsOf:icon) }
        else { identity.image=NSImage(contentsOfFile:"macos/Resources/Pod.icns") }
        identity.imageScaling = .scaleProportionallyUpOrDown; identity.setAccessibilityLabel("Pod")
        divider.surface=LuminLegacyStyle.outline
        for view in [navigationBack,navigationClose,navigation,titleBox,documentStatus,fileMenu,share,shareOptions,divider,help,notifications,identity] { addSubview(view) }
        for button in [navigation,fileMenu,share,shareOptions,help,notifications] { button.target=self; button.action=#selector(activate) }
        navigationBack.isHidden=true; navigationClose.isHidden=true
        navigationBack.onChoose={ [weak self] in guard let self else { return }; onAction?(navigationBack) }; navigationClose.onChoose={ [weak self] in guard let self else { return }; onAction?(navigationClose) }
        titleBox.onChange={ [weak self] in self?.needsLayout=true }
        titleField.stringValue="Welcome to Pod"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func activate(_ sender:NSButton) { onAction?(sender) }
    override func layout() {
        super.layout(); navigation.frame=NSRect(x:20,y:8,width:40,height:40)
        navigationBack.frame=NSRect(x:8,y:12,width:147.21875,height:32); navigationClose.frame=NSRect(x:240,y:12,width:32,height:32)
        let titleStart:CGFloat=navigationExpanded ? 288:76
        let statusWidth=documentStatus.intrinsicContentSize.width
        let measured=(titleField.stringValue as NSString).size(withAttributes:[.font:LuminAssets.font(14,520),.kern:-0.096]).width
        let titleWidth=min(max(40,ceil(measured)+20),max(40,bounds.width/2-titleStart-statusWidth-4))
        titleBox.frame=NSRect(x:titleStart,y:12,width:titleWidth,height:32); titleBox.needsLayout=true
        documentStatus.frame=NSRect(x:titleBox.frame.maxX+4,y:16,width:statusWidth,height:24); documentStatus.needsLayout=true
        // This legacy right group has an empty quick-action slot that still contributes a 12px gap.
        var x=bounds.width-334.265625
        fileMenu.frame=NSRect(x:x,y:12,width:32,height:32); x+=44
        share.frame=NSRect(x:x,y:8,width:108.265625,height:40); x+=109.265625
        shareOptions.frame=NSRect(x:x,y:8,width:40,height:40); x+=52
        divider.frame=NSRect(x:x,y:20,width:1,height:16); x+=7
        help.frame=NSRect(x:x,y:12,width:32,height:32); x+=34
        notifications.frame=NSRect(x:x,y:12,width:32,height:32); x+=44
        identity.frame=NSRect(x:x,y:10,width:36,height:36)
    }
}
