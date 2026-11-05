import AppKit

// Geometry, mode order and the approximate collapse arithmetic are recovered from the
// shipped legacy toolbar. See research/lumin/main-toolbar-source-evidence.md.
enum LuminToolbarCollapse {
    static func count(viewport:CGFloat,left:CGFloat,baseline:CGFloat,count:Int,rightPanel:CGFloat=0,expandedNavigation:Bool=false)->Int? {
        let maximum=viewport-left-rightPanel-(expandedNavigation ? 260:0)-96-80-50
        guard maximum != 0,baseline != 0 else { return 0 }
        if viewport>=1808 { return 0 }
        let shortage=baseline-maximum
        if shortage>=maximum { return nil }
        if shortage<=0 { return 0 }
        if Int(ceil(shortage/54))>=count { return nil }
        return min(Int(ceil((shortage+27)/54)),count)
    }
}

enum LuminToolbarModel {
    static let groups:[String:[String]]=[
        "Popular":["Eraser","Shape","Highlight","Draw","Type","|","Signature","|","Add comment","Sign securely"],
        "Fill & Sign":["Prepare form","|","Cross","Tick","Dot","Stamp","Date","Type","Signature","Sign securely"],
        "Mark up":["Perform OCR","|","Image","Eraser","Shape","Text tools","Highlight","Draw","Type","|","Measure","|","Add comment"],
        "Security":["Redaction","Password protection"],
        "Edit text":["Edit content","Add text","Image"],
        "Organize":["Select pages","Thumbnail size","Bates numbering","Crop","Insert","Split & Extract","Merge"]]
    static let split:Set<String>=["Thumbnails","Eraser","Shape","Text tools","Highlight","Draw","Add comment"]
    static let premium:Set<String>=["Perform OCR","Stamp","Redaction"]
    static func overflow(_ mode:String)->[String] {
        let tools=(groups[mode] ?? []).filter{$0 != "|"}
        return tools.filter{!["Prepare form","Sign securely"].contains($0)}.reversed()+tools.filter{["Prepare form","Sign securely"].contains($0)}
    }
}

final class LuminToolbarButton:NSButton {
    enum Kind { case tool,suffix,sign,more,utility }
    var kind:Kind = .tool
    var glyphName:String? { didSet { image=glyphName.flatMap{LuminAssets.icon($0)} } }
    var showsLabel=false
    var inlineArrow=false
    var premium=false
    var preservesImageColors=false
    var imageSize:CGFloat?
    var usesLegacyForeground=false
    var splitHover=false { didSet { needsDisplay=true } }
    var isSelected=false { didSet { needsDisplay=true; setAccessibilityValue(isSelected ? "Selected":"Not selected") } }
    private var hovered=false
    private var tracking:NSTrackingArea?
    static let labelWidths:[String:Double] = (try? JSONDecoder().decode([String:Double].self,from:Data(contentsOf:LuminAssets.directory.appendingPathComponent("Toolbar/label-widths.json")))) ?? [:]
    var labelWidth:CGFloat { CGFloat(Self.labelWidths[title] ?? Double((title as NSString).size(withAttributes:[.font:LuminAssets.font(12,460)]).width)) }
    var sourcePopoverAnchor:NSView { (superview as? LuminToolbarSplit) ?? self }
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    override var intrinsicContentSize:NSSize {
        switch kind {
        case .suffix:return NSSize(width:20,height:20)
        case .sign:return NSSize(width:161.953125,height:32)
        case .more:return NSSize(width:32,height:32)
        case .utility:return NSSize(width:40,height:40)
        case .tool:return NSSize(width:32+(showsLabel ? labelWidth+4:0)+(inlineArrow ? 20:0),height:32)
        }
    }
    var cssForeground:NSColor {
        if !isEnabled { return LuminLegacyStyle.disabled }
        if kind == .sign { return LuminLegacyStyle.signText }
        if kind == .more || kind == .utility { return usesLegacyForeground ? LuminLegacyStyle.variant:PodTheme.secondary }
        return isSelected || isHighlighted ? LuminLegacyStyle.onSecondaryContainer:LuminLegacyStyle.variant
    }
    var cssBackground:NSColor {
        if kind == .suffix { return .clear }
        if kind == .sign { return LuminLegacyStyle.signContainer }
        if kind == .more || kind == .utility { return hovered || isHighlighted ? cssForeground.withAlphaComponent(isHighlighted ? 0.12:0.08):.clear }
        if splitHover { return isSelected ? PodTheme.selectedSurface:PodTheme.surface }
        if isSelected || isHighlighted { return LuminLegacyStyle.secondaryContainer }
        return hovered && isEnabled ? (kind == .more ? PodTheme.secondary:LuminLegacyStyle.variant).withAlphaComponent(0.08):.clear
    }
    init(title:String,glyph:String?=nil,kind:Kind = .tool) {
        super.init(frame:.zero); self.title=title; self.kind=kind; glyphName=glyph; image=glyph.flatMap{LuminAssets.icon($0)}
        isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; identifier=NSUserInterfaceItemIdentifier(title); setAccessibilityLabel(title); toolTip=title
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        cssBackground.setFill(); NSBezierPath(roundedRect:bounds,xRadius:kind == .suffix ? 4:8,yRadius:kind == .suffix ? 4:8).fill()
        let color=cssForeground
        if kind == .sign {
            for (name,x) in [("Toolbar/sign-logo",CGFloat(12)),("Toolbar/sign-caret",CGFloat(129.953125))] { if let image=LuminAssets.bitmap(name) { LuminAssets.tinted(image,color).draw(in:NSRect(x:x,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) } }
            (title as NSString).draw(in:NSRect(x:36,y:6,width:89.953125,height:20),withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:color]); return
        }
        let size=imageSize ?? (kind == .tool || kind == .utility ? 24:20),x:CGFloat=kind == .suffix ? 0:kind == .utility ? (bounds.width-size)/2:kind == .more ? 6:4
        if let image { (preservesImageColors ? image:LuminAssets.tinted(image,color)).draw(in:NSRect(x:x,y:(bounds.height-size)/2,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        if showsLabel { (title as NSString).draw(in:NSRect(x:32,y:9.1,width:labelWidth,height:13.8),withAttributes:[.font:LuminAssets.font(12,460),.foregroundColor:color]) }
        if inlineArrow,let image=LuminAssets.icon("pdf-icon-sm_down_stroke",size:20) { LuminAssets.tinted(image,color).draw(in:NSRect(x:bounds.width-24,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        if premium,let image=LuminAssets.bitmap("Toolbar/premium") { image.draw(in:NSRect(x:-4,y:-2,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

final class LuminToolbarSplit:NSView {
    let primary:LuminToolbarButton,options:LuminToolbarButton
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    init(_ primary:LuminToolbarButton,_ options:LuminToolbarButton) {
        self.primary=primary; self.options=options; super.init(frame:.zero); addSubview(primary); addSubview(options)
        wantsLayer=true; layer?.cornerRadius=8; layer?.masksToBounds=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:primary.intrinsicContentSize.width+22,height:34) }
    override func layout() { super.layout(); primary.frame=NSRect(x:1,y:1,width:primary.intrinsicContentSize.width,height:32); options.frame=NSRect(x:primary.frame.maxX,y:7,width:20,height:20) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; primary.splitHover=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; primary.splitHover=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) { if hovered { PodTheme.surface.setFill(); bounds.fill(); LuminLegacyStyle.text.withAlphaComponent(0.08).setFill(); bounds.fill() } }
}

private final class LuminToolbarDivider:PodSurfaceView {
    let sourceHeight:CGFloat
    init(height:CGFloat) { sourceHeight=height; super.init(frame:.zero); surface=LuminLegacyStyle.outline }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:1,height:sourceHeight) }
}

final class LuminMainToolbar:PodSurfaceView {
    let zoomField=LuminZoomField()
    var viewportWidth:CGFloat=1240 { didSet { needsLayout=true } }
    var expandedNavigation=false { didSet { needsLayout=true } }
    var rightPanelWidth:CGFloat=0 { didSet { needsLayout=true } }
    var onAction:((NSButton)->Void)?
    private(set) var mode="Popular"
    private var common:[NSView]=[],tools:[NSView]=[]
    private var collapsed:Int?=0
    private var fullWidth:CGFloat=0
    private var selectedTool="Select"
    private var formBuilderActive=false
    private var undoAvailable=false,redoAvailable=false
    private var thumbnailMode="Thumbnails"
    private(set) var commonFrame=NSRect.zero,toolsFrame=NSRect.zero
    var sourceButtons:[LuminToolbarButton] { (common+tools).flatMap{ view -> [LuminToolbarButton] in if let split=view as? LuminToolbarSplit { return [split.primary,split.options] }; return (view as? LuminToolbarButton).map{[$0]} ?? [] } }
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:48) }
    override init(frame:NSRect) { super.init(frame:frame); surface=PodTheme.surface; rebuild() }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func button(_ title:String)->LuminToolbarButton? { sourceButtons.first{$0.identifier?.rawValue==title} }
    func setMode(_ value:String) { if value != mode { mode=value; rebuild() }; needsLayout=true }
    func selectTool(_ value:String) { selectedTool=value; applyFormState() }
    func setFormBuilderActive(_ value:Bool) { formBuilderActive=value; applyFormState() }
    private func applyFormState() {
        for button in sourceButtons {
            let key=button.identifier?.rawValue ?? ""
            button.isSelected=key==selectedTool || (formBuilderActive && key=="Prepare form")
            if ["Thumbnails","Thumbnails options","Read aloud"].contains(key) { button.isEnabled = !formBuilderActive }
        }
    }
    func setHistory(undo:Bool,redo:Bool) { undoAvailable=undo; redoAvailable=redo; button("Undo")?.isEnabled=undo; button("Redo")?.isEnabled=redo }
    func setThumbnailMode(_ value:String) { thumbnailMode=value; button("Thumbnails")?.glyphName=value=="Outlines" ? "kiwi-icon-bookmark-lg":"kiwi-icon-thumbnail-lg" }
    private func make(_ title:String,showLabel:Bool)->NSView {
        let button=LuminToolbarButton(title:title,glyph:LuminAssets.tools[title],kind:title=="Sign securely" ? .sign:.tool)
        // Preserve the earlier preview icons for the not-yet-rebuilt Organize/gated branches.
        if button.image==nil,let symbol=["Edit content":"text.cursor","Add text":"text.badge.plus","Select pages":"checkmark.square","Thumbnail size":"slider.horizontal.3","Bates numbering":"number","Crop":"crop","Insert":"doc.badge.plus","Split & Extract":"doc.on.doc","Merge":"arrow.triangle.merge"][title] { button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title) }
        if title=="Thumbnails" { button.glyphName=thumbnailMode=="Outlines" ? "kiwi-icon-bookmark-lg":"kiwi-icon-thumbnail-lg" }
        button.showsLabel=showLabel; button.inlineArrow=["View controls","Prepare form","Password protection"].contains(title); button.premium=LuminToolbarModel.premium.contains(title)
        button.target=self; button.action=#selector(activate); button.isSelected=title==selectedTool || (formBuilderActive && title=="Prepare form")
        if LuminToolbarModel.split.contains(title) {
            let arrow=LuminToolbarButton(title:title+" options",glyph:"pdf-icon-sm_down_stroke",kind:.suffix); arrow.target=self; arrow.action=#selector(activate)
            return LuminToolbarSplit(button,arrow)
        }
        return button
    }
    private func width(_ views:[NSView])->CGFloat { views.reduce(0){$0+$1.intrinsicContentSize.width}+CGFloat(max(0,views.count-1))*4 }
    private func rebuild() {
        (common+tools).forEach{$0.removeFromSuperview()}; common=[]; tools=[]; collapsed=0
        if mode != "Organize" {
            let editing=mode != "Security"
            var titles=["Thumbnails","|"]
            if editing { titles += ["Read aloud","|"] }
            titles += ["Zoom","View controls","Rotate view","|","Select","Pan"]
            if editing { titles += ["|","Undo","Redo"] }
            for title in titles { common.append(title=="|" ? LuminToolbarDivider(height:editing ? 18:32):title=="Zoom" ? zoomField:make(title,showLabel:false)) }
            common.forEach(addSubview)
        }
        buildTools(hidden:0); fullWidth=width(tools); needsLayout=true
        setHistory(undo:undoAvailable,redo:redoAvailable)
        applyFormState()
    }
    private func buildTools(hidden:Int?) {
        tools.forEach{$0.removeFromSuperview()}; tools=[]
        if hidden==nil {
            let more=LuminToolbarButton(title:"More tools",glyph:"kiwi-icon-dots-md",kind:.more); more.target=self; more.action=#selector(activate); tools=[more]
        } else {
            var order=0
            for title in LuminToolbarModel.groups[mode] ?? [] {
                if title=="|" { tools.append(LuminToolbarDivider(height:18)); continue }
                let show=title=="Password protection" || hidden!<=order
                tools.append(make(title,showLabel:show)); order += 1
            }
        }
        tools.forEach(addSubview)
    }
    @objc private func activate(_ sender:NSButton) { onAction?(sender) }
    override func layout() {
        super.layout()
        let left=width(common)
        let toolCount=(LuminToolbarModel.groups[mode] ?? []).filter{$0 != "|"}.count
        let next=mode=="Organize" ? 0:LuminToolbarCollapse.count(viewport:viewportWidth,left:left,baseline:fullWidth.rounded(),count:toolCount,rightPanel:rightPanelWidth,expandedNavigation:expandedNavigation)
        if next != collapsed { collapsed=next; buildTools(hidden:next) }
        func place(_ views:[NSView],at start:CGFloat)->NSRect {
            var x=start
            for view in views { let size=view.intrinsicContentSize; view.frame=NSRect(x:x,y:(bounds.height-size.height)/2,width:size.width,height:size.height); view.layoutSubtreeIfNeeded(); x += size.width+4 }
            return NSRect(x:start,y:8,width:width(views),height:32)
        }
        commonFrame=place(common,at:8)
        toolsFrame=place(tools,at:mode=="Organize" ? 8:bounds.width-8-width(tools))
    }
    override func draw(_ dirtyRect:NSRect) {
        let w=bounds.width,h=bounds.height,r:CGFloat=16,p=NSBezierPath()
        p.move(to:NSPoint(x:0,y:h)); p.line(to:NSPoint(x:0,y:r)); p.appendArc(from:NSPoint(x:0,y:0),to:NSPoint(x:r,y:0),radius:r); p.line(to:NSPoint(x:w-r,y:0)); p.appendArc(from:NSPoint(x:w,y:0),to:NSPoint(x:w,y:r),radius:r); p.line(to:NSPoint(x:w,y:h)); p.close(); surface.setFill(); p.fill()
    }
}
