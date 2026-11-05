import AppKit

// Source dense MenuItemBase, FileMenu, Share dropdown and Help MenuList.
// See header-menus-layout-fixture.json and header-menus-source-evidence.md.
struct LuminHeaderMenuItem {
    let key:String,title:String
    var glyph:String?=nil,bitmap:String?=nil
    var iconSize:CGFloat=24
    var iconSectionSize:CGFloat?=nil
    var shortcut:String?=nil
    var hasSwitch=false,hasBadge=false,premium=false
}

final class LuminMenuSwitch:NSButton {
    var keyboardFocused=false { didSet { needsDisplay=true; superview?.needsDisplay=true } }
    override var acceptsFirstResponder:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    var isOn=false { didSet { setAccessibilityValue(isOn ? 1:0); needsDisplay=true } }
    var trackColor:NSColor { isOn ? PodTheme.secondary:PodTheme.chrome }
    var thumbColor:NSColor { isOn ? PodTheme.onSecondary:PodTheme.secondaryText }
    override init(frame:NSRect) { super.init(frame:frame); title=""; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; setAccessibilityRole(.checkBox); setAccessibilityLabel("Dark page"); setAccessibilityValue(0) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let track=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:24,yRadius:24)
        trackColor.setFill(); track.fill(); (isOn ? PodTheme.secondary:PodTheme.outline).setStroke(); track.lineWidth=1; track.stroke()
        thumbColor.setFill(); NSBezierPath(ovalIn:NSRect(x:isOn ? 18:2,y:2,width:16,height:16)).fill()
        if keyboardFocused { PodTheme.color(0x228BE6).setStroke(); let focus=NSBezierPath(roundedRect:bounds.insetBy(dx:-3,dy:-3),xRadius:13,yRadius:13); focus.lineWidth=2; focus.stroke() }
    }
}

final class LuminHeaderMenuRow:NSButton {
    private(set) var item:LuminHeaderMenuItem
    private(set) var sourceImage:NSImage?
    private(set) var toggle:LuminMenuSwitch?
    var onChoose:((String)->Void)?
    var keyboardFocused=false { didSet { needsDisplay=true; superview?.needsDisplay=true } }
    var selected=false { didSet { needsDisplay=true } }
    var fitsLabelToText=false
    private let dense:Bool
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var wantsDefaultClipping:Bool { false }
    override var acceptsFirstResponder:Bool { true }
    override var canBecomeKeyView:Bool { true }
    var cssForeground:NSColor { PodTheme.text.withAlphaComponent(isEnabled ? 1:0.38) }
    var cssBackground:NSColor { selected ? PodTheme.selectedSurface:isEnabled && (hovered || isHighlighted) ? PodTheme.text.withAlphaComponent(isHighlighted ? 0.12:0.08):.clear }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    var iconRect:NSRect { NSRect(x:8+((item.iconSectionSize ?? item.iconSize)-item.iconSize)/2,y:(bounds.height-item.iconSize)/2,width:item.iconSize,height:item.iconSize) }
    private var shortcutWidth:CGFloat { item.shortcut.map{Self.width($0,font:LuminAssets.font(14,420))} ?? 0 }
    static func width(_ text:String,font:NSFont)->CGFloat { ((text as NSString).size(withAttributes:[.font:font]).width*64).rounded()/64 }
    var textRect:NSRect {
        let x:CGFloat=sourceImage==nil ? 8:16+(item.iconSectionSize ?? item.iconSize)
        let trailing:CGFloat=item.hasSwitch ? 44:item.shortcut==nil ? 0:shortcutWidth+8
        let width=bounds.width-x-8-trailing
        return NSRect(x:x,y:(bounds.height-20)/2,width:fitsLabelToText ? min(width,Self.width(title,font:LuminAssets.font(14,500))):width,height:20)
    }
    var badgeRect:NSRect? {
        guard item.hasBadge else { return nil }
        return NSRect(x:textRect.minX+Self.width(item.title+" ",font:LuminAssets.font(14,500)),y:9,width:36.6875,height:16)
    }
    var premiumRect:NSRect? {
        item.premium ? NSRect(x:textRect.minX+Self.width(title,font:LuminAssets.font(14,500))+4,y:(bounds.height-16)/2,width:16,height:16):nil
    }
    init(_ item:LuminHeaderMenuItem,dense:Bool=true) {
        self.dense=dense; self.item=item; sourceImage=item.glyph.flatMap{LuminAssets.icon($0,size:item.iconSize)} ?? item.bitmap.flatMap{LuminAssets.bitmap($0)}
        super.init(frame:.zero); title=item.title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose); setAccessibilityRole(.menuItem); setAccessibilityLabel(item.title+(item.hasBadge ? " NEW":""))
        if item.hasSwitch { let control=LuminMenuSwitch(); control.target=self; control.action=#selector(choose); addSubview(control); toggle=control }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func setStarred(_ value:Bool) {
        item=LuminHeaderMenuItem(key:"starred",title:value ? "Remove from starred":"Add to starred",glyph:value ? "pdf-icon-md_unstar_document":"pdf-icon-md_star_document")
        title=item.title; sourceImage=item.glyph.flatMap{LuminAssets.icon($0)}; setAccessibilityLabel(title); needsDisplay=true
    }
    override func layout() { super.layout(); toggle?.frame=NSRect(x:bounds.width-44,y:6,width:36,height:20) }
    @objc private func choose() { guard isEnabled else { return }; if let toggle { toggle.isOn.toggle() }; onChoose?(item.key) }
    override func mouseDown(with event:NSEvent) { keyboardFocused=false; window?.makeFirstResponder(self); super.mouseDown(with:event) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        cssBackground.setFill(); NSBezierPath(roundedRect:bounds,xRadius:dense ? 4:8,yRadius:dense ? 4:8).fill()
        if keyboardFocused { PodTheme.color(0x228BE6).setStroke(); let focus=NSBezierPath(roundedRect:bounds.insetBy(dx:-3,dy:-3),xRadius:6,yRadius:6); focus.lineWidth=2; focus.stroke() }
        if let sourceImage { LuminAssets.tinted(sourceImage,cssForeground).draw(in:iconRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:textRect,withAttributes:[.font:LuminAssets.font(14,500),.foregroundColor:cssForeground])
        if let shortcut=item.shortcut { (shortcut as NSString).draw(in:NSRect(x:bounds.width-8-shortcutWidth,y:6,width:shortcutWidth,height:20),withAttributes:[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.secondaryText]) }
        if let badge=badgeRect {
            PodTheme.badgeYellow.setFill(); NSBezierPath(roundedRect:badge,xRadius:4,yRadius:4).fill()
            ("NEW" as NSString).draw(in:badge.insetBy(dx:4,dy:0),withAttributes:[.font:LuminAssets.font(12,500),.foregroundColor:PodTheme.onBadgeYellow])
        }
        if let premium=premiumRect,let image=LuminAssets.bitmap("Toolbar/premium") { image.draw(in:premium,from:.zero,operation:.sourceOver,fraction:isEnabled ? 1:0.38,respectFlipped:true,hints:nil) }
    }
}

private final class LuminHeaderMenuSurface:PodSurfaceView { override var isFlipped:Bool { true } }

final class LuminHeaderMenu:NSViewController {
    enum Kind:String { case file,share,help }
    let kind:Kind
    private let darkAppearance:Bool,fullScreen:Bool
    private(set) var starred:Bool
    private(set) var darkPage:Bool
    private(set) var rows:[LuminHeaderMenuRow]=[]
    private(set) var dividers:[PodSurfaceView]=[]
    private(set) var focusedIndex:Int?
    var onChoose:((String)->Void)?
    var alignment:LuminPopper.Alignment { kind == .share ? .end:.center }
    let gap:CGFloat=8
    init(kind:Kind,darkAppearance:Bool,darkPage:Bool,starred:Bool,fullScreen:Bool=false) { self.fullScreen=fullScreen; self.kind=kind; self.darkAppearance=darkAppearance; self.darkPage=darkPage; self.starred=starred; super.init(nibName:nil,bundle:nil); title=kind == .file ? "File menu":kind == .share ? "Share options":"Help" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private var groups:[[LuminHeaderMenuItem]] {
        switch kind {
        case .file:return [
            [.init(key:"starred",title:starred ? "Remove from starred":"Add to starred",glyph:starred ? "pdf-icon-md_unstar_document":"pdf-icon-md_star_document"),.init(key:"copy",title:"Make a copy",glyph:"pdf-icon-md_copy"),.init(key:"move",title:"Move",glyph:"pdf-icon-md_move-1"),.init(key:"download",title:"Download",glyph:"pdf-icon-md_download"),.init(key:"template",title:"Save as template",bitmap:"Header/template")],
            [.init(key:"appearance",title:darkAppearance ? "Light Mode":"Dark Mode",glyph:darkAppearance ? "pdf-icon-md_lightmode":"pdf-icon-md_darkmode"),.init(key:"fullScreen",title:fullScreen ? "Exit full screen":"Full screen",glyph:fullScreen ? "pdf-icon-md_full_screen_closed":"pdf-icon-md_full_screen",iconSize:20),.init(key:"darkPage",title:"Dark page",bitmap:"Header/dark-page",hasSwitch:true),.init(key:"presenter",title:"Presenter mode",glyph:"kiwi-icon-monitor-play",shortcut:"⌘ Enter")],
            [.init(key:"info",title:"File information",glyph:"pdf-icon-md_info"),.init(key:"history",title:"Version history",glyph:"kiwi-icon-ph-clock-counter-clockwise")],
            [.init(key:"desktop",title:"Open in desktop app",bitmap:"Header/desktop",hasBadge:true)]]
        case .share:return [[.init(key:"copyLink",title:"Copy link",glyph:"kiwi-icon-link-lg"),.init(key:"signatures",title:"Send for signatures",glyph:"kiwi-icon-send-lg")]]
        case .help:return [[.init(key:"help",title:"Help center"),.init(key:"support",title:"Contact Support"),.init(key:"feedback",title:"Give Feedback")]]
        }
    }
    override func loadView() {
        let width:CGFloat=kind == .file ? 304:kind == .share ? 194.7578125:141.765625
        let root=LuminHeaderMenuSurface(); root.surface=PodTheme.raised; var y:CGFloat=8
        for (index,group) in groups.enumerated() {
            if index>0 { y+=8; let divider=PodSurfaceView(frame:NSRect(x:8,y:y,width:width-16,height:1)); divider.surface=LuminLegacyStyle.outline; root.addSubview(divider); dividers.append(divider); y+=9 }
            for item in group {
                let row=LuminHeaderMenuRow(item); row.frame=NSRect(x:8,y:y,width:width-16,height:32); row.toggle?.isOn=darkPage
                row.onChoose={ [weak self,weak row] key in guard let self else { return }; if key=="darkPage" { darkPage=row?.toggle?.isOn ?? false }; if key=="starred" { starred.toggle(); row?.setStarred(starred) }; onChoose?(key) }
                root.addSubview(row); rows.append(row); y+=32
            }
        }
        root.setAccessibilityElement(true); root.setAccessibilityRole(.menu); root.setAccessibilityLabel(title)
        root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows.flatMap { row -> [Any] in
            if let toggle=row.toggle { toggle.setAccessibilityParent(root); return [row,toggle] }
            return [row]
        }))
        root.frame=NSRect(x:0,y:0,width:width,height:y+8); view=root; preferredContentSize=root.frame.size; root.layoutSubtreeIfNeeded()
    }
    func handleKey(_ event:NSEvent)->Bool {
        let current=rows.firstIndex { row in guard let responder=row.window?.firstResponder else { return false }; return responder === row || responder === row.toggle } ?? focusedIndex
        let index:Int
        switch event.keyCode {
        case 125:index=current.map{($0+1)%rows.count} ?? 0
        case 126:index=current.map{($0+rows.count-1)%rows.count} ?? rows.count-1
        case 115:index=0
        case 119:index=rows.count-1
        case 48:
            if kind == .file,let toggle=rows.first(where:{$0.toggle != nil})?.toggle {
                focusedIndex=nil; rows.forEach{$0.keyboardFocused=false}; toggle.keyboardFocused=true; view.window?.makeFirstResponder(toggle); return true
            }
            index=current.map{($0+(event.modifierFlags.contains(.shift) ? rows.count-1:1))%rows.count} ?? 0
        case 36,76,49:guard let current else { return false }; rows[current].performClick(nil); return true
        default:return false
        }
        focusedIndex=index; rows.forEach{$0.toggle?.keyboardFocused=false}
        for (offset,row) in rows.enumerated() { row.keyboardFocused=offset==index }
        view.window?.makeFirstResponder(rows[index]); return true
    }
}
