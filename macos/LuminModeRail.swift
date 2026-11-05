import AppKit

enum LuminModeAssets {
    struct Record:Decodable { let key:String,width:CGFloat,height:CGFloat }
    static let records:[String:Record] = {
        let url=LuminAssets.directory.appendingPathComponent("Navigation/manifest.json")
        let values=(try? JSONDecoder().decode([Record].self,from:Data(contentsOf:url))) ?? []
        return Dictionary(uniqueKeysWithValues:values.map{($0.key,$0)})
    }()
    private static var images:[String:NSImage]=[:]
    static func image(_ key:String)->NSImage? {
        if let image=images[key] { return image }
        let image=LuminAssets.bitmap("Navigation/"+key); image?.isTemplate=true; images[key]=image; return image
    }
    static let labelWidths:[String:CGFloat] = (try? JSONDecoder().decode([String:CGFloat].self,from:Data(contentsOf:LuminAssets.directory.appendingPathComponent("Navigation/label-widths.json")))) ?? [:]
}

final class LuminModeButton:NSButton {
    let tab:String
    var selected=false { didSet { needsDisplay=true; setAccessibilityValue(selected ? "Selected":"Not selected") } }
    var menuHovered=false { didSet { needsDisplay=true } }
    var onHover:((Bool)->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    var assetKey:String { tab+"-"+(selected ? "active":"normal")+(effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? "Dark":"Light") }
    var sourceImage:NSImage? { LuminModeAssets.image(assetKey) }
    var iconWrapperRect:NSRect { NSRect(x:16,y:0,width:40,height:40) }
    var iconRect:NSRect { let asset=LuminModeAssets.records[assetKey]; return NSRect(x:24,y:8,width:asset?.width ?? 24,height:asset?.height ?? 24) }
    var labelRect:NSRect { let width=LuminModeAssets.labelWidths[title] ?? LuminHeaderMenuRow.width(title,font:LuminAssets.font(12,500)); return NSRect(x:floor((72-width)*32)/64,y:42,width:width,height:16) }
    var labelColor:NSColor { selected ? PodTheme.primary:PodTheme.secondaryText }
    var iconColor:NSColor { selected ? PodTheme.selectedText:PodTheme.secondaryText }
    var iconBackground:NSColor { selected ? PodTheme.primaryContainer:(hovered || menuHovered) ? PodTheme.navigationHover:.clear }
    init(_ title:String,tab:String) {
        self.tab=tab; super.init(frame:.zero); self.title=title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; setAccessibilityLabel(title); toolTip=title=="Explore" ? "Quick Search (Option /)":nil
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true; onHover?(true) }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true; onHover?(false) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        iconBackground.setFill(); NSBezierPath(roundedRect:iconWrapperRect,xRadius:8,yRadius:8).fill()
        if let image=sourceImage { LuminAssets.tinted(image,iconColor).draw(in:iconRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=16; paragraph.maximumLineHeight=16
        (title as NSString).draw(in:labelRect,withAttributes:[.font:LuminAssets.font(12,500),.foregroundColor:labelColor,.paragraphStyle:paragraph])
        if tab=="editPdfTab",let badge=LuminAssets.bitmap("Toolbar/premium") { badge.draw(in:NSRect(x:12,y:0,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

final class LuminModeRail:PodSurfaceView {
    static let titles=["Popular","Fill & Sign","Mark up","Edit text","Security","Organize","Explore"]
    let buttons:[LuminModeButton]
    let expandedPanel=LuminExpandedNavigation()
    var navigationExpanded=false { didSet { buttons.forEach{$0.isHidden=navigationExpanded}; focusButton.isHidden=navigationExpanded; expandedPanel.isHidden = !navigationExpanded; if !navigationExpanded { expandedPanel.dismissMenus() }; needsLayout=true } }
    let focusButton=LuminToolbarButton(title:"Focus mode",glyph:"pdf-icon-lg_collapse_right_panel",kind:.utility)
    var onFocusMode:(()->Void)?
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        buttons=zip(Self.titles,["popularTab","fillAndSignTab","annotateTab","editPdfTab","securityTab","pageToolsTab","exploreTab"]).map{LuminModeButton($0.0,tab:$0.1)}
        super.init(frame:frame); surface=PodTheme.chrome
        for (index,button) in buttons.enumerated() { button.tag=index; addSubview(button) }
        addSubview(expandedPanel); expandedPanel.isHidden=true
        focusButton.usesLegacyForeground=true; focusButton.target=self; focusButton.action=#selector(focus); focusButton.toolTip="Focus mode (⌘\\)"; addSubview(focusButton)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); expandedPanel.frame=bounds; for (index,button) in buttons.enumerated() { button.frame=NSRect(x:4,y:4+CGFloat(index)*74,width:72,height:58) }; focusButton.frame=NSRect(x:20,y:bounds.height-56,width:40,height:40) }
    @objc private func focus() { onFocusMode?() }
}

final class LuminFocusRestore:NSView {
    let button=LuminToolbarButton(title:"Show toolbars",glyph:"pdf-icon-lg_expand_right_panel",kind:.utility)
    var onRestore:(()->Void)?
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override init(frame:NSRect) { super.init(frame:frame); button.usesLegacyForeground=true; button.target=self; button.action=#selector(restore); addSubview(button) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); button.frame=NSRect(x:4,y:4,width:28,height:40) }
    @objc private func restore() { onRestore?() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8); shape.appendRect(NSRect(x:0,y:0,width:8,height:bounds.height)); PodTheme.surface.setFill(); shape.fill()
        PodTheme.canvas.setFill(); NSBezierPath(roundedRect:NSRect(x:4,y:4,width:28,height:40),xRadius:8,yRadius:8).fill()
    }
}
