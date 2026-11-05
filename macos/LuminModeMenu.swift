import AppKit

// The shipped registry expands Highlight, Form builder and Lumin Sign in rail menus.
// See mode-hover-source-evidence.md and the clean live DOM fixture.
struct LuminModeMenuEntry {
    let key,title,glyph:String
    var premium=false,disabled=false,legacyHighlight=false
}

final class LuminModeMenuRow:NSButton {
    let entry:LuminModeMenuEntry
    let sourceImage:NSImage?
    var onChoose:((LuminModeMenuRow)->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    private static let widths:[String:CGFloat]=(try? JSONDecoder().decode([String:CGFloat].self,from:Data(contentsOf:LuminAssets.directory.appendingPathComponent("ModeMenu/label-widths.json")))) ?? [:]
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var contentOpacity:CGFloat { isEnabled ? 1:0.38 }
    var labelColor:NSColor { PodTheme.text }
    var iconColor:NSColor { entry.legacyHighlight ? LuminLegacyStyle.text:PodTheme.text }
    var iconRect:NSRect { NSRect(x:8,y:8,width:entry.legacyHighlight ? 23.8359375:24,height:24) }
    // Flex shrinks the legacy icon box, while its24px font glyph keeps its paint size.
    var iconPaintRect:NSRect { NSRect(x:8,y:8,width:24,height:24) }
    var labelRect:NSRect { NSRect(x:16+iconRect.width,y:10,width:entry.legacyHighlight ? 144.1640625:Self.widths[title] ?? bounds.width-48,height:20) }
    var premiumRect:NSRect? { entry.premium ? NSRect(x:labelRect.maxX+4,y:12,width:16,height:16):nil }
    init(_ entry:LuminModeMenuEntry) {
        self.entry=entry; sourceImage=LuminAssets.icon(entry.glyph)
        super.init(frame:.zero); title=entry.title; isEnabled = !entry.disabled; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none
        target=self; action=#selector(choose); setAccessibilityRole(.menuItem); setAccessibilityLabel(title+(entry.premium ? " premium":""))
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { if isEnabled { onChoose?(self) } }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        if isEnabled && (hovered || isHighlighted) { PodTheme.text.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill() }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; NSGraphicsContext.current?.cgContext.setAlpha(contentOpacity)
        if let sourceImage { LuminAssets.tinted(sourceImage,iconColor).draw(in:iconPaintRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:labelRect,withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:labelColor])
        if let rect=premiumRect,let badge=LuminAssets.bitmap("Toolbar/premium") { badge.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

final class LuminRequestSignaturesButton:NSButton {
    var onChoose:(()->Void)?
    override var isFlipped:Bool { true }
    var iconRect:NSRect { NSRect(x:(bounds.width-153.078125)/2,y:6,width:20,height:20) }
    override init(frame:NSRect) { super.init(frame:frame); title="Request signatures"; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose); setAccessibilityLabel(title) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { onChoose?() }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        LuminLegacyStyle.signContainer.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        if let icon=LuminAssets.bitmap("Toolbar/sign-logo") { LuminAssets.tinted(icon,LuminLegacyStyle.signText).draw(in:iconRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:iconRect.maxX+8,y:6,width:125.078125,height:20),withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:LuminLegacyStyle.signText])
    }
}

final class LuminModeSignFooter:NSView {
    let button=LuminRequestSignaturesButton()
    override var isFlipped:Bool { true }
    var descriptionRect:NSRect { NSRect(x:8,y:8,width:248,height:56) }
    override init(frame:NSRect) { super.init(frame:frame); addSubview(button); button.frame=NSRect(x:8,y:64,width:248,height:32) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let p=NSMutableParagraphStyle(); p.minimumLineHeight=20; p.maximumLineHeight=20
        ("Digitally sign your documents with Lumin Sign" as NSString).draw(with:descriptionRect.insetBy(dx:0,dy:8),options:.usesLineFragmentOrigin,attributes:[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.text,.paragraphStyle:p])
    }
}

private final class LuminModeMenuSurface:PodSurfaceView {
    var onHover:((Bool)->Void)?
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { onHover?(true) }
    override func mouseExited(with event:NSEvent) { onHover?(false) }
}

final class LuminModeMenu:NSViewController {
    let mode:String
    private(set) var rows:[LuminModeMenuRow]=[]
    private(set) var signFooter:LuminModeSignFooter?
    private(set) var headingFrame:NSRect?
    private(set) var separatorFrames:[NSRect]=[]
    var onChoose:((LuminModeMenuRow)->Void)?
    var onHover:((Bool)->Void)?
    var onRequestSignatures:(()->Void)?
    init(mode:String) { self.mode=mode; super.init(nibName:nil,bundle:nil); title=mode+" tools" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    static func entries(for mode:String)->[LuminModeMenuEntry] {
        func e(_ key:String,_ title:String,_ glyph:String,_ premium:Bool=false)->LuminModeMenuEntry { .init(key:key,title:title,glyph:glyph,premium:premium) }
        let comment=e("comment","Comment","pdf-icon-md_comment_teardrop_text"),signature=e("signature","Signature","pdf-icon-md_signature"),type=e("type","Type","pdf-icon-md_text_tool"),draw=e("draw","Draw","pdf-icon-md_freehand"),shape=e("shape","Shape","pdf-icon-md_rectangle"),eraser=e("eraser","Eraser","pdf-icon-md_eraser")
        let highlights=[LuminModeMenuEntry(key:"textHighlight",title:"Text highlight",glyph:"pdf-icon-md_highlight",legacyHighlight:true),LuminModeMenuEntry(key:"freehandHighlight",title:"Freehand highlight",glyph:"pdf-icon-md_free_hand_highlight",legacyHighlight:true)]
        switch mode {
        case "Popular":return [comment,signature,type,draw]+highlights+[shape,eraser]
        case "Fill & Sign":return [signature,type,e("date","Date","pdf-icon-md_date_stamp"),e("stamp","Stamp","pdf-icon-md_stamp",true),e("dot","Dot","pdf-icon-tool_dot_stamp"),e("tick","Tick","pdf-icon-tool_check_stamp"),e("cross","Cross","pdf-icon-tool_cross_stamp"),e("customizeFields","Prepare form","kiwi-icon-pencil-lg"),e("aiAutoDetect","AI auto-detect","kiwi-icon-sparkles-lg")]
        case "Mark up":return [comment,e("measure","Measure","kiwi-icon-ph-ruler"),type,draw]+highlights+[e("textTools","Text tools","pdf-icon-md_text_underline"),shape,eraser,e("image","Image","pdf-icon-md_image"),e("performOCR","Perform OCR","pdf-icon-md_OCR",true)]
        case "Security":return [e("redaction","Redaction","pdf-icon-md_redaction",true),e("configureAccess","Set password","pdf-icon-set-password",true),.init(key:"removeAccess",title:"Remove password",glyph:"pdf-icon-remove-password",disabled:true)]
        case "Organize":return [e("batesNumbering","Bates numbering","kiwi-icon-ph-list-numbers"),e("mergeDocs","Merge","pdf-icon-md_merge"),e("splitExtract","Split & Extract","pdf-icon-md_split"),e("rotatePages","Rotate","pdf-icon-md_rotate"),e("deletePages","Delete","pdf-icon-md_delete"),e("movePages","Move","pdf-icon-md_move"),e("insertBlankPages","Insert blank page(s)","pdf-icon-md_insert"),e("cropPages","Crop","pdf-icon-md_crop")]
        default:return []
        }
    }
    override func loadView() {
        let root=LuminModeMenuSurface(); root.surface=PodTheme.raised; root.onHover={ [weak self] in self?.onHover?($0) }; var y:CGFloat=8
        func separator(_ y:CGFloat) { let frame=NSRect(x:0,y:y,width:280,height:1),line=PodSurfaceView(frame:NSRect(x:0,y:y,width:280,height:1)); line.surface=PodTheme.border; root.addSubview(line); separatorFrames.append(frame) }
        for (index,entry) in Self.entries(for:mode).enumerated() {
            if mode=="Fill & Sign" && index==7 {
                y+=8; separator(y); headingFrame=NSRect(x:8,y:y,width:264,height:40)
                let heading=NSTextField(labelWithString:"Form builder"); heading.font=LuminAssets.font(14,500); heading.textColor=PodTheme.text; heading.frame=NSRect(x:16,y:y+12,width:248,height:20); root.addSubview(heading); y+=40
            }
            let row=LuminModeMenuRow(entry); row.frame=NSRect(x:8,y:y,width:264,height:40); row.onChoose={ [weak self] in self?.onChoose?($0) }; root.addSubview(row); rows.append(row); y+=40
        }
        if mode=="Popular" || mode=="Fill & Sign" {
            y+=8; separator(y); let footer=LuminModeSignFooter(frame:NSRect(x:8,y:y,width:264,height:104)); footer.button.onChoose={ [weak self] in self?.onRequestSignatures?() }; root.addSubview(footer); signFooter=footer; y+=104
        }
        root.frame=NSRect(x:0,y:0,width:280,height:y+8); root.setAccessibilityElement(true); root.setAccessibilityRole(.menu); root.setAccessibilityLabel(title)
        root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows+(signFooter.map{[$0.button]} ?? [])))
        view=root; preferredContentSize=root.frame.size
    }
    func handleKey(_ event:NSEvent)->Bool {
        guard let window=view.window,event.window === window else { return false }
        // Mantine traversal excludes the two legacy Mui rows (no data-menu-item).
        let eligible=rows.filter{$0.isEnabled && !$0.entry.legacyHighlight}; guard !eligible.isEmpty else { return false }
        let current=eligible.firstIndex{$0.window?.firstResponder === $0},index:Int
        switch event.keyCode {
        case 125:index=current.map{($0+1)%eligible.count} ?? 0
        case 126:index=current.map{($0+eligible.count-1)%eligible.count} ?? eligible.count-1
        case 115:index=0
        case 119:index=eligible.count-1
        case 36,76:guard let current else { return false }; eligible[current].performClick(nil); return true
        default:return false
        }
        view.window?.makeFirstResponder(eligible[index]); return true
    }
}
