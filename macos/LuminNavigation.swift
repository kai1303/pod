import AppKit

enum LuminNavigationAssets {
    static let keys=["cloud-arrow-up","arrow-square-out","desktop","logo-googledrive-md","logo-onedrive-md","logo-dropbox-md","pdf-xl"]
    private static let images=Dictionary(uniqueKeysWithValues:keys.compactMap{key in LuminAssets.bitmap("NavigationExpanded/"+key).map{(key,$0)}})
    static func image(_ key:String)->NSImage? { images[key] }
}

// Upload is a Radix menu; its neutral roles differ from the surrounding Kiwi UI.
enum LuminNavigationStyle {
    private static func adaptive(_ name:String,_ light:UInt32,_ dark:UInt32)->NSColor { NSColor(name:NSColor.Name("Pod.Navigation."+name)) { a in PodTheme.color(a.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light) } }
    static let popover=adaptive("popover",0xFFFFFF,0x171717)
    static let foreground=adaptive("foreground",0x0A0A0A,0xFAFAFA)
    static let accent=adaptive("accent",0xF5F5F5,0x404040)
    static let accentForeground=adaptive("accentForeground",0x171717,0xFAFAFA)
    static let muted=adaptive("muted",0x737373,0xA3A3A3)
}

final class LuminNavigationButton:NSButton {
    enum Style { case back,close,upload,newTab }
    let style:Style
    var onChoose:(()->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    var foreground:NSColor { style == .newTab ? PodTheme.text:PodTheme.secondary }
    var iconRect:NSRect { NSRect(x:style == .back ? 12:6,y:6,width:20,height:20) }
    init(_ title:String,style:Style) {
        self.style=style; super.init(frame:.zero); self.title=title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; font=LuminAssets.font(14,500); target=self; action=#selector(choose); setAccessibilityLabel(title)
        if style == .upload { setAccessibilityRole(.popUpButton); setAccessibilityExpanded(false) }
        if style == .back { image=LuminAssets.icon("kiwi-icon-arrow-narrow-left-md",size:20) }
        if style == .close { image=LuminAssets.icon("kiwi-icon-x-md",size:20) }
        if style == .newTab { image=LuminNavigationAssets.image("arrow-square-out") }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { if isEnabled { onChoose?() } }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:style == .newTab ? 4:8,yRadius:style == .newTab ? 4:8)
        if isEnabled && (hovered || isHighlighted) { foreground.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); shape.fill() }
        if style == .upload { foreground.setStroke(); shape.lineWidth=1; shape.stroke() }
        let color=foreground.withAlphaComponent(isEnabled ? 1:0.38)
        if let image { LuminAssets.tinted(image,color).draw(in:iconRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        if style == .back || style == .upload {
            let width:CGFloat=style == .back ? 99.21875:47.6171875,x:CGFloat=style == .back ? 36:(bounds.width-width)/2
            (title as NSString).draw(in:NSRect(x:x,y:6,width:width,height:20),withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:color])
        }
    }
}

final class LuminNavigationUploadArea:NSView {
    let button=LuminNavigationButton("Upload",style:.upload)
    var onPickDevice:(()->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    var hoverOverlayColor:NSColor { hovered ? PodTheme.text.withAlphaComponent(0.08):.clear }
    override var isFlipped:Bool { true }
    var cloudRect:NSRect { NSRect(x:9,y:13,width:20,height:20) }
    var captionRect:NSRect { NSRect(x:37,y:15,width:183.3203125,height:16) }
    var borderColor:NSColor { PodTheme.outline }
    override init(frame:NSRect) { super.init(frame:frame); addSubview(button); button.frame=NSRect(x:9,y:45,width:226,height:32) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func mouseDown(with event:NSEvent) { onPickDevice?() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        hoverOverlayColor.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        borderColor.setStroke(); let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8); path.lineWidth=1; path.setLineDash([3,3],count:2,phase:0); path.stroke()
        if let image=LuminNavigationAssets.image("cloud-arrow-up") { LuminAssets.tinted(image,PodTheme.text).draw(in:cloudRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        ("Click or drag and drop to upload" as NSString).draw(in:captionRect,withAttributes:[.font:LuminAssets.font(12,420),.foregroundColor:PodTheme.text])
    }
}

struct LuminNavigationDocument {
    let id,title:String
    var thumbnail:NSImage?
    var selected:Bool
}

final class LuminNavigationDocumentRow:NSButton {
    let document:LuminNavigationDocument
    let newTabButton=LuminNavigationButton("Open in new tab",style:.newTab)
    var onChoose:((String)->Void)?
    var onNewTab:((String)->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    var background:NSColor { document.selected ? PodTheme.primaryContainer:hovered ? PodTheme.text.withAlphaComponent(0.08):.clear }
    var foreground:NSColor { PodTheme.text }
    var thumbnailRect:NSRect { NSRect(x:8,y:8,width:24,height:24) }
    var textRect:NSRect { NSRect(x:40,y:10,width:max(0,bounds.width-88),height:20) }
    init(_ document:LuminNavigationDocument) {
        self.document=document; super.init(frame:.zero); title=document.title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose); setAccessibilityLabel(title); setAccessibilityValue(document.selected ? "Selected":"Not selected")
        addSubview(newTabButton); newTabButton.alphaValue=0; newTabButton.setAccessibilityHidden(true); newTabButton.onChoose={ [weak self] in guard let self else { return }; onNewTab?(self.document.id) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { onChoose?(document.id) }
    override func layout() { super.layout(); newTabButton.frame=NSRect(x:bounds.width-36,y:4,width:32,height:32) }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; newTabButton.alphaValue=1; newTabButton.setAccessibilityHidden(false); needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; newTabButton.alphaValue=0; newTabButton.setAccessibilityHidden(true); needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        background.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        let outline=NSBezierPath(roundedRect:thumbnailRect.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4); PodTheme.primaryContainer.setFill(); outline.fill()
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect:thumbnailRect.insetBy(dx:1,dy:1),xRadius:4,yRadius:4).addClip()
        if let image=document.thumbnail ?? LuminNavigationAssets.image("pdf-xl") {
            let target=thumbnailRect.insetBy(dx:1,dy:1),scale=max(target.width/image.size.width,target.height/image.size.height),size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:NSRect(x:target.midX-size.width/2,y:target.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        NSGraphicsContext.restoreGraphicsState(); PodTheme.border.setStroke(); outline.lineWidth=1; outline.stroke()
        let p=NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in:textRect,withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:foreground,.paragraphStyle:p])
    }
}

final class LuminUploadMenuRow:NSButton {
    let key:String,sourceImage:NSImage?
    var onChoose:((String)->Void)?
    var onPointer:((Bool)->Void)?
    var focused=false { didSet { needsDisplay=true } }
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var iconRect:NSRect { NSRect(x:6,y:7,width:18,height:18) }
    var labelRect:NSRect { NSRect(x:32,y:6,width:bounds.width-38,height:20) }
    var foreground:NSColor { focused ? LuminNavigationStyle.accentForeground:LuminNavigationStyle.foreground }
    var background:NSColor { focused ? LuminNavigationStyle.accent:.clear }
    init(_ key:String,_ title:String,_ asset:String) { self.key=key; sourceImage=LuminNavigationAssets.image(asset); super.init(frame:.zero); self.title=title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose); setAccessibilityRole(.menuItem); setAccessibilityLabel(title) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { if isEnabled { onChoose?(key) } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { onPointer?(true) }
    override func mouseExited(with event:NSEvent) { onPointer?(false) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1:0.5)
        background.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        if let image=sourceImage { (key=="device" ? LuminAssets.tinted(image,LuminNavigationStyle.muted):image).draw(in:iconRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:labelRect,withAttributes:[.font:LuminAssets.font(14,400),.foregroundColor:foreground])
    }
}
private final class LuminUploadMenuSurface:PodSurfaceView {
    override var isFlipped:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); wantsLayer=true; layer?.borderWidth=1; updateBorder() }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateBorder() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor=LuminNavigationStyle.foreground.withAlphaComponent(0.1).cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateBorder() }
}

final class LuminUploadMenu:NSViewController {
    private let width:CGFloat
    private(set) var rows:[LuminUploadMenuRow]=[]
    private(set) var focusedIndex:Int?
    var onChoose:((String)->Void)?
    init(width:CGFloat=226) { self.width=width; super.init(nibName:nil,bundle:nil); title="Upload" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminUploadMenuSurface(frame:NSRect(x:0,y:0,width:width,height:136)); root.surface=LuminNavigationStyle.popover; root.wantsLayer=true; root.layer?.cornerRadius=10
        for (index,value) in [("device","From my device","desktop"),("google","From Google Drive","logo-googledrive-md"),("onedrive","From OneDrive","logo-onedrive-md"),("dropbox","From Dropbox","logo-dropbox-md")].enumerated() {
            let row=LuminUploadMenuRow(value.0,value.1,value.2); row.frame=NSRect(x:4,y:4+CGFloat(index)*32,width:width-8,height:32)
            row.onChoose={ [weak self] in self?.onChoose?($0) }; row.onPointer={ [weak self] entered in self?.focus(entered ? index:nil) }; root.addSubview(row); rows.append(row)
        }
        root.setAccessibilityElement(true); root.setAccessibilityRole(.menu); root.setAccessibilityLabel("Upload"); root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows)); view=root; preferredContentSize=root.frame.size
    }
    private func focus(_ index:Int?) { focusedIndex=index; for (i,row) in rows.enumerated() { row.focused=i==index }; view.window?.makeFirstResponder(index.map{rows[$0] as NSResponder} ?? view.window) }
    func handleKey(_ event:NSEvent)->Bool {
        guard let window=view.window,event.window === window else { return false }
        switch event.keyCode {
        case 125:focus(min((focusedIndex ?? -1)+1,rows.count-1))
        case 126:focus(max((focusedIndex ?? rows.count)-1,0))
        case 115:focus(0)
        case 119:focus(rows.count-1)
        case 48:return true // Radix prevents Tab from leaving an open menu.
        case 36,76,49:guard let focusedIndex else { return false }; rows[focusedIndex].performClick(nil)
        default:return false
        }
        return true
    }
}

private final class LuminNavigationList:NSView { override var isFlipped:Bool { true } }
final class LuminExpandedNavigation:PodSurfaceView {
    let uploadArea=LuminNavigationUploadArea()
    private let titleLabel=NSTextField(labelWithString:"Recent documents")
    private let emptyLabel=NSTextField(wrappingLabelWithString:"The latest documents you open will be shown here.")
    private let listScroll=NSScrollView(),list=LuminNavigationList()
    private var popup:LuminPopper?
    private(set) var rows:[LuminNavigationDocumentRow]=[]
    var documents:[LuminNavigationDocument]=[] { didSet { rebuild() } }
    var onDocument:((String)->Void)?
    var onNewTab:((String)->Void)?
    var onUpload:((String)->Void)?
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); surface=PodTheme.chrome
        titleLabel.font=LuminAssets.font(12,500); titleLabel.textColor=PodTheme.text
        emptyLabel.font=LuminAssets.font(12,420); emptyLabel.textColor=PodTheme.secondaryText
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=16; paragraph.maximumLineHeight=16
        emptyLabel.attributedStringValue=NSAttributedString(string:emptyLabel.stringValue,attributes:[.font:LuminAssets.font(12,420),.foregroundColor:PodTheme.secondaryText,.paragraphStyle:paragraph])
        listScroll.drawsBackground=false; listScroll.hasVerticalScroller=true; listScroll.autohidesScrollers=true; listScroll.scrollerStyle = .overlay; listScroll.documentView=list
        for view in [uploadArea,titleLabel,listScroll,emptyLabel] { addSubview(view) }
        uploadArea.onPickDevice={ [weak self] in self?.onUpload?("device") }; uploadArea.button.onChoose={ [weak self] in self?.showUpload() }
        rebuild()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private func rebuild() {
        rows.forEach{$0.removeFromSuperview()}; rows=documents.map { document in let row=LuminNavigationDocumentRow(document); row.onChoose={ [weak self] in self?.onDocument?($0) }; row.onNewTab={ [weak self] in self?.onNewTab?($0) }; list.addSubview(row); return row }
        emptyLabel.isHidden = !rows.isEmpty; listScroll.isHidden=rows.isEmpty; needsLayout=true; needsDisplay=true
    }
    override func layout() {
        super.layout(); uploadArea.frame=NSRect(x:16,y:4,width:244,height:86); titleLabel.frame=rows.isEmpty ? NSRect(x:25,y:119,width:226,height:16):NSRect(x:24,y:110,width:228,height:16)
        let height=CGFloat(rows.count)*44-(rows.isEmpty ? 0:4); listScroll.frame=NSRect(x:4,y:134,width:268,height:min(height,max(0,bounds.height-170)))
        list.frame=NSRect(x:0,y:0,width:268,height:height)
        for (index,row) in rows.enumerated() { let frame=NSRect(x:12,y:CGFloat(index)*44,width:244,height:40); if row.frame != frame { row.frame=frame; row.needsLayout=true }; row.layoutSubtreeIfNeeded() }
        emptyLabel.frame=NSRect(x:25,y:147,width:226,height:32)
    }
    private func showUpload() {
        if popup?.isShown==true { popup?.close(); return }
        let menu=LuminUploadMenu(width:uploadArea.button.bounds.width),pop=LuminPopper(); popup=pop
        pop.contentViewController=menu; pop.alignment = .start; pop.gap=4; pop.cornerRadius=10; pop.keepsAnchorInteractive=true
        uploadArea.button.setAccessibilityExpanded(true)
        pop.onClose={ [weak self] in self?.uploadArea.button.setAccessibilityExpanded(false) }
        pop.onKeyDown={ [weak menu] in menu?.handleKey($0) ?? false }; pop.onEscape={ [weak self] in guard let self else { return }; window?.makeFirstResponder(uploadArea.button) }
        menu.onChoose={ [weak self,weak pop] key in pop?.close(); self?.onUpload?(key) }
        pop.show(relativeTo:uploadArea.button.bounds,of:uploadArea.button)
    }
    func dismissMenus() { popup?.close() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); titleLabel.textColor=PodTheme.text; emptyLabel.textColor=PodTheme.secondaryText }
    override func draw(_ rect:NSRect) { super.draw(rect); if rows.isEmpty { PodTheme.border.setStroke(); let shape=NSBezierPath(roundedRect:NSRect(x:16.5,y:110.5,width:243,height:77),xRadius:8,yRadius:8); shape.lineWidth=1; shape.setLineDash([3,3],count:2,phase:0); shape.stroke() } }
}
