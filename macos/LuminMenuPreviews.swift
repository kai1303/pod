import AppKit

// Source-only UI models: these drafts do not write PDF signatures or cloud records.
enum LuminSignatureStyle {
    private static func adaptive(_ name:String,_ light:UInt32,_ dark:UInt32)->NSColor {
        NSColor(name:NSColor.Name("Lumin.Signature."+name)) { appearance in PodTheme.color(appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light) }
    }
    static let board=adaptive("board",0xF9F9FA,0xC1C7CE)
    static let foreground=adaptive("foreground",0x161C21,0x090F14)
    static let hint=adaptive("hint",0x325167,0x233F52)
    static let error=adaptive("error",0xC7361E,0xFF8C77)
    static let checker=adaptive("checker",0xE3E5E8,0x2F363B)
    static let dragForeground=adaptive("dragForeground",0xF1F2F4,0x2B3137)
    static let tertiary=adaptive("tertiary",0xE3DFFF,0x454364)
    static let onTertiary=adaptive("onTertiary",0x19182F,0xE3DFFF)
    static let inverseOnSurface=adaptive("inverseOnSurface",0xFFFFFF,0x191C1D)
}
struct LuminSignaturePreview {
    let id=UUID()
    var text=""
    var family="DrSugiyama"
    var color=NSColor.black
    var image:NSImage?
    var strokes:[[NSPoint]]=[]
    var width:CGFloat=8
    func draw(in rect:NSRect) {
        if let image {
            let scale=min(rect.width/image.size.width,rect.height/image.size.height),size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } else if !text.isEmpty {
            let font=LuminAssets.signatureFont(family,size:48),attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color],size=(text as NSString).size(withAttributes:attrs)
            let scale=min(1,min(rect.width/max(1,size.width),rect.height/max(1,size.height)))
            NSGraphicsContext.saveGraphicsState(); let transform=NSAffineTransform(); transform.translateX(by:rect.midX-size.width*scale/2,yBy:rect.midY-size.height*scale/2); transform.scale(by:scale); transform.concat(); (text as NSString).draw(at:.zero,withAttributes:attrs); NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGraphicsContext.saveGraphicsState(); let transform=NSAffineTransform(); transform.translateX(by:rect.minX,yBy:rect.minY); transform.scaleX(by:rect.width/832,yBy:rect.height/300); transform.concat()
            color.setStroke()
            for points in strokes where !points.isEmpty { let path=NSBezierPath(); path.move(to:points[0]); points.dropFirst().forEach{path.line(to:$0)}; path.lineWidth=width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke() }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
private final class LuminSignatureMenuSurface:PodSurfaceView {
    var contentSize=NSSize.zero
    override var isFlipped:Bool { true }
    override var fittingSize:NSSize { contentSize }
}
private final class LuminSignatureList:NSView { override var isFlipped:Bool { true } }
final class LuminSignatureMenu:NSViewController {
    var onAddSignature:(()->Void)?
    var onCertify:(()->Void)?
    var onRepeatChange:((Bool)->Void)?
    var onSelect:((LuminSignaturePreview)->Void)?
    var onDelete:((UUID)->Void)?
    private(set) var repeatsSignature:Bool
    private var previews:[LuminSignaturePreview]
    let limit:Int
    private(set) var controls:[String:NSView]=[:]
    init(repeatsSignature:Bool=false,previews:[LuminSignaturePreview]=[],limit:Int=100) {
        self.repeatsSignature=repeatsSignature; self.previews=previews; self.limit=limit; super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { rebuild() }
    private func rebuild() {
        let root=LuminSignatureMenuSurface(); root.surface=PodTheme.raised; controls=[:]
        func add(_ key:String,_ child:NSView,_ rect:NSRect) { child.frame=rect; root.addSubview(child); controls[key]=child }
        let heading=LuminTextLabel("Sign securely",font:LuminAssets.font(14,520),lineHeight:23.796875,color:LuminLegacyStyle.text)
        add("secure",heading,NSRect(x:16,y:16,width:368,height:23.796875))
        let certify=LuminCertificationButton(title:"Create a certified version",target:self,action:#selector(certify))
        certify.setAccessibilityLabel("Create a certified version. Create a tamper-proof version with audit trail")
        add("certification",certify,NSRect(x:16,y:47.796875,width:368,height:68.296875))
        add("yourSignatures",LuminTextLabel("Your Signatures",font:LuminAssets.font(14,520),lineHeight:23.796875,color:LuminLegacyStyle.text),NSRect(x:16,y:124.09375,width:368,height:23.796875))
        let document=LuminSignatureList(),hasAdd=previews.count<limit
        let addHeight:CGFloat=hasAdd ? 48:0,listHeight=previews.isEmpty ? CGFloat(0):CGFloat(previews.count)*64+CGFloat(previews.count-1)*8
        let documentHeight=24+addHeight+8+listHeight,scrollHeight=min(400,documentHeight)
        document.frame=NSRect(x:0,y:0,width:368,height:documentHeight)
        let scroll=NSScrollView(); scroll.drawsBackground=true; scroll.backgroundColor=LuminLegacyStyle.container; scroll.borderType = .noBorder; scroll.hasVerticalScroller=true; scroll.scrollerStyle = .overlay; scroll.autohidesScrollers=true; scroll.documentView=document; scroll.wantsLayer=true; scroll.layer?.cornerRadius=8; scroll.layer?.masksToBounds=true
        add("scrollArea",scroll,NSRect(x:16,y:155.890625,width:368,height:scrollHeight))
        if hasAdd {
            let button=LuminDashedSignatureButton(target:self,action:#selector(addSignature)); button.frame=NSRect(x:12,y:12,width:344,height:48); document.addSubview(button); controls["add"]=button
        }
        for (i,preview) in previews.enumerated() {
            let row=LuminSignaturePreviewRow(preview:preview); row.frame=NSRect(x:12,y:12+addHeight+8+CGFloat(i)*72,width:344,height:64)
            row.onChoose={ [weak self] in self?.onSelect?(preview) }
            row.onDelete={ [weak self] in guard let self else { return }; previews.removeAll{$0.id==preview.id}; onDelete?(preview.id); rebuild() }
            document.addSubview(row)
        }
        let repeatButton=LuminSignatureRepeatButton(); repeatButton.isOn=repeatsSignature; repeatButton.onToggle={ [weak self] value in self?.repeatsSignature=value; self?.onRepeatChange?(value) }
        add("repeat",repeatButton,NSRect(x:20,y:155.890625+scrollHeight+8,width:226.2734375,height:20))
        root.contentSize=NSSize(width:400,height:155.890625+scrollHeight+8+25.796875+16); view=root; preferredContentSize=root.contentSize
    }
    @objc private func addSignature() { onAddSignature?() }
    @objc private func certify() { onCertify?() }
}

final class LuminSignatureRepeatButton:NSButton {
    var isOn=false { didSet { setAccessibilityValue(isOn ? 1:0); needsDisplay=true } }
    var onToggle:((Bool)->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    override init(frame:NSRect) {
        super.init(frame:frame); title="Place signature multiple times"; isBordered=false; setButtonType(.momentaryPushIn); setAccessibilityRole(.checkBox); setAccessibilityLabel(title); setAccessibilityValue(0); target=self; action=#selector(toggle)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func toggle() { isOn.toggle(); onToggle?(isOn) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(area); tracking=area }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        if hovered { PodTheme.text.withAlphaComponent(0.08).setFill(); NSBezierPath(ovalIn:NSRect(x:-10,y:-10,width:40,height:40)).fill() }
        let box=NSBezierPath(roundedRect:NSRect(x:1.75,y:1.75,width:16.5,height:16.5),xRadius:2,yRadius:2)
        PodTheme.text.setStroke(); box.lineWidth=1.5
        if isOn { PodTheme.text.setFill(); box.fill() }; box.stroke()
        if isOn,let image=LuminAssets.bitmap("Share/check") { LuminAssets.tinted(image,LuminSignatureStyle.inverseOnSurface).draw(in:NSRect(x:4,y:5,width:12,height:10),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=20; paragraph.maximumLineHeight=20
        (title as NSString).draw(in:NSRect(x:28,y:0,width:198.2734375,height:20),withAttributes:[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.text,.paragraphStyle:paragraph])
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

private final class LuminSignaturePreviewRow:NSButton {
    let preview:LuminSignaturePreview
    var onChoose:(()->Void)?,onDelete:(()->Void)?
    private let remove=LuminLegacyIconButton()
    override var isFlipped:Bool { true }
    init(preview:LuminSignaturePreview) {
        self.preview=preview; super.init(frame:.zero); isBordered=false; setButtonType(.momentaryPushIn); setAccessibilityLabel("Signature"); target=self; action=#selector(choose)
        remove.glyphSize=16; remove.glyphName="pdf-icon-sm_close"; remove.target=self; remove.action=#selector(delete); remove.setAccessibilityLabel("Delete signature"); addSubview(remove)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); remove.frame=NSRect(x:bounds.width-36,y:4,width:32,height:32) }
    override func draw(_ rect:NSRect) { LuminSignatureStyle.board.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill(); preview.draw(in:bounds.insetBy(dx:8,dy:8)) }
    @objc private func choose() { onChoose?() }
    @objc private func delete() { onDelete?() }
}

private let luminMenuOutline=PodTheme.color(0x8B9198) // Legacy le_main_outline in both appearances.

private class LuminMenuPaintButton:NSButton {
    var pointerInside=false
    private var hoverArea:NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); hoverArea=area
    }
    override func mouseEntered(with event:NSEvent) { pointerInside=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { pointerInside=false; needsDisplay=true }
}

private final class LuminDashedSignatureButton:LuminMenuPaintButton {
    init(target:AnyObject?,action:Selector?) {
        super.init(frame:.zero)
        title="Add Signature"; self.target=target; self.action=action
        isBordered=false; setButtonType(.momentaryPushIn); setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect:NSRect) {
        let border=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if pointerInside || isHighlighted { LuminLegacyStyle.text.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); border.fill() }
        luminMenuOutline.setStroke(); border.lineWidth=1
        border.setLineDash([3,3],count:2,phase:0); border.stroke()
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=16.1015625; paragraph.maximumLineHeight=16.1015625
        let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,520),.foregroundColor:LuminLegacyStyle.variant,.paragraphStyle:paragraph]
        let textSize=(title as NSString).size(withAttributes:attrs)
        let iconWidth:CGFloat=23.8359375,x=(bounds.width-textSize.width-iconWidth-4)/2
        if let image=LuminAssets.icon("pdf-icon-md_add") { LuminAssets.tinted(image,LuminLegacyStyle.variant).draw(in:NSRect(x:x,y:(bounds.height-24)/2,width:iconWidth,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:x+iconWidth+4,y:(bounds.height-16.1015625)/2,width:textSize.width,height:16.1015625),withAttributes:attrs)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

private final class LuminCertificationButton:LuminMenuPaintButton {
    private static let background=NSColor(name:"Lumin.Signature.TertiaryContainer") { appearance in
        PodTheme.color(appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? 0x454364:0xE3DFFF)
    }
    private static let foreground=NSColor(name:"Lumin.Signature.OnTertiaryContainer") { appearance in
        PodTheme.color(appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? 0xE3DFFF:0x19182F)
    }
    override init(frame:NSRect) {
        super.init(frame:frame); isBordered=false; setButtonType(.momentaryPushIn)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        Self.background.setFill(); path.fill()
        if pointerInside || isHighlighted { Self.foreground.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); path.fill() }
        if let icon=LuminAssets.icon("pdf-icon-icon-sign",size:40) {
            LuminAssets.tinted(icon,Self.foreground).draw(in:NSRect(x:8,y:12,width:40,height:40),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        let x:CGFloat=56, width:CGFloat=255.2578125
        let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping; paragraph.minimumLineHeight=23.796875; paragraph.maximumLineHeight=23.796875
        // NSButton coordinates are flipped; the source uses a 14 px title over 12 px body copy.
        ("Create a certified version" as NSString).draw(in:NSRect(x:x,y:13.25,width:width,height:23.796875),withAttributes:[.font:LuminAssets.font(14,520),.foregroundColor:Self.foreground,.paragraphStyle:paragraph])
        paragraph.minimumLineHeight=18; paragraph.maximumLineHeight=18
        ("Create a tamper-proof version with audit trail" as NSString).draw(in:NSRect(x:x,y:37.046875,width:width,height:18),withAttributes:[.font:LuminAssets.font(12,420),.foregroundColor:Self.foreground,.paragraphStyle:paragraph])
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

// Legacy highlight dropdown: two menu items, each with its own properties trigger.
final class LuminHighlightMenu:NSViewController {
    var onChoose:((MarkupKind)->Void)?
    var onOptions:((MarkupKind,NSButton)->Void)?
    private(set) var current:MarkupKind
    private var rows:[LuminHighlightMenuRow]=[]
    init(current:MarkupKind = .highlight) {
        self.current=current
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=PodSurfaceStack(); root.surface=PodTheme.raised
        root.orientation = .vertical; root.alignment = .leading; root.spacing=0
        root.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        for kind in [MarkupKind.highlight,.freehandHighlight] {
            let row=LuminHighlightMenuRow(kind:kind)
            row.onChoose={ [weak self] in self?.choose(kind) }
            row.selected=kind==current
            row.onOptions={ [weak self] button in self?.onOptions?(kind,button) }
            row.widthAnchor.constraint(equalToConstant:255.328125).isActive=true
            row.heightAnchor.constraint(equalToConstant:kind == .highlight ? 40:59).isActive=true
            root.addArrangedSubview(row); rows.append(row)
        }
        view=root; preferredContentSize=NSSize(width:271.328125,height:115)
    }
    private func choose(_ kind:MarkupKind) {
        current=kind
        rows.forEach{$0.selected=$0.kind==current}
        onChoose?(current)
    }
}

private final class LuminHighlightMenuRow:NSView {
    let kind:MarkupKind
    var selected=false { didSet { main.selected=selected } }
    var onChoose:(()->Void)?
    var onOptions:((NSButton)->Void)?
    private let main:LuminHighlightMainButton
    private let options=LuminLegacyIconButton()
    init(kind:MarkupKind) {
        self.kind=kind; main=LuminHighlightMainButton(kind:kind)
        super.init(frame:.zero)
        main.target=self; main.action=#selector(choose)
        options.target=self; options.action=#selector(showOptions)
        options.glyphName="pdf-icon-md_more_horizontal_menu"
        options.toolTip=main.title+" options"; options.setAccessibilityLabel(main.title+" options")
        for child in [main,options] { child.translatesAutoresizingMaskIntoConstraints=false; addSubview(child) }
        NSLayoutConstraint.activate([main.leadingAnchor.constraint(equalTo:leadingAnchor),main.trailingAnchor.constraint(equalTo:trailingAnchor),main.topAnchor.constraint(equalTo:topAnchor),main.bottomAnchor.constraint(equalTo:bottomAnchor),options.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-4),options.topAnchor.constraint(equalTo:topAnchor,constant:4),options.widthAnchor.constraint(equalToConstant:32),options.heightAnchor.constraint(equalToConstant:32)])
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { onChoose?() }
    @objc private func showOptions(_ sender:NSButton) { onOptions?(sender) }
}

private final class LuminHighlightMainButton:NSButton {
    let kind:MarkupKind
    var selected=false { didSet { state=selected ? .on:.off; needsDisplay=true } }
    private var hovered=false
    private var hoverArea:NSTrackingArea?
    init(kind:MarkupKind) {
        self.kind=kind
        super.init(frame:.zero)
        isBordered=false; setButtonType(.momentaryPushIn)
        title=kind == .highlight ? "Text highlight (H)":"Freehand highlight"
        setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); hoverArea=area
    }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        if selected { PodTheme.selectedSurface.setFill(); shape.fill() }
        if hovered || isHighlighted { PodTheme.text.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); shape.fill() }
        let foreground=LuminLegacyStyle.text
        let iconName=kind == .highlight ? "pdf-icon-md_highlight":"pdf-icon-md_free_hand_highlight"
        if let icon=LuminAssets.icon(iconName) { LuminAssets.tinted(icon,selected ? PodTheme.selectedText:foreground).draw(in:NSRect(x:8,y:8,width:23.8359375,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:39.8359375,y:8,width:135.4921875,height:21),withAttributes:[.font:LuminAssets.font(14,420),.foregroundColor:foreground])
        if kind == .freehandHighlight {
            ("Great for scanned PDFs" as NSString).draw(in:NSRect(x:39.8359375,y:33,width:135.4921875,height:18),withAttributes:[.font:LuminAssets.font(12,420),.foregroundColor:LuminLegacyStyle.variant])
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}
