import AppKit

enum LuminFormFieldKind:Int,CaseIterable {
    case text,checkbox,radio,signature
    var title:String { ["Text field","Checkbox","Radio button","Signature field"][rawValue] }
    var glyph:String { "pdf-icon-"+["md_text_box","md_checkbox","md_radio_box","md_signature"][rawValue] }
}

final class LuminFormBuilderMenu:NSViewController {
    private(set) var rows:[LuminHeaderMenuRow]=[]
    private var focused:Int?
    var onPrepare:(()->Void)?,onAutoDetect:(()->Void)?
    override func loadView() {
        let root=LuminFormSurface(); root.surface=PodTheme.raised
        for (i,item) in [LuminHeaderMenuItem(key:"prepare",title:"Prepare form",glyph:"kiwi-icon-pencil-lg"),.init(key:"detect",title:"AI auto-detect",glyph:"kiwi-icon-sparkles-lg")].enumerated() {
            let row=LuminHeaderMenuRow(item); row.frame=NSRect(x:8,y:8+CGFloat(i)*32,width:250,height:32)
            row.onChoose={ [weak self] key in if key=="prepare" { self?.onPrepare?() } else { self?.onAutoDetect?() } }
            root.addSubview(row); rows.append(row)
        }
        root.setAccessibilityElement(true); root.setAccessibilityRole(.menu); root.setAccessibilityLabel("Prepare form")
        root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows)); view=root; preferredContentSize=NSSize(width:266,height:80)
    }
    func handleKey(_ event:NSEvent)->Bool {
        let current=rows.firstIndex{$0.window?.firstResponder === $0} ?? focused
        let index:Int
        switch event.keyCode {
        case 125:index=current.map{($0+1)%2} ?? 0
        case 126:index=current.map{($0+1)%2} ?? 1
        case 115:index=0
        case 119:index=1
        case 36,76:guard let current else { return false }; rows[current].performClick(nil); return true
        default:return false
        }
        focused=index; rows.enumerated().forEach{$0.element.keyboardFocused=$0.offset==index}; view.window?.makeFirstResponder(rows[index]); return true
    }
}

private final class LuminFormSurface:PodSurfaceView { override var isFlipped:Bool { true } }
private final class LuminFormDocument:NSView { override var isFlipped:Bool { true } }
private final class LuminFormClip:NSClipView { override var isFlipped:Bool { true } }

final class LuminFormBuilderPanel:PodSurfaceView {
    private(set) var controls:[String:NSView]=[:]
    private(set) var tabs:[LuminFormTabButton]=[]
    private(set) var selectedKind:LuminFormFieldKind?
    let cancel=LuminShareButton("Cancel",style:.outlined)
    let apply=LuminShareButton("Apply",style:.filled)
    private let properties=NSScrollView()
    private let document=LuminFormDocument()
    var onCancel:(()->Void)?
    var onFieldChoice:((LuminFormFieldKind)->Void)?
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override init(frame:NSRect) {
        super.init(frame:frame); surface=PodTheme.canvas; wantsLayer=true; layer?.cornerRadius=8; layer?.masksToBounds=true
        setAccessibilityLabel("Form builder")
        func add(_ key:String,_ child:NSView) { controls[key]=child; addSubview(child) }
        add("header",NSView())
        add("headerTitle",LuminTextLabel("Form builder",font:LuminAssets.font(14,500),lineHeight:20))
        let close=LuminShareButton("",style:.text); close.size=14; close.glyph="kiwi-icon-x-sm"; close.imageSize=20; close.iconSlot=20; close.iconGap=0; close.setAccessibilityLabel("Close Form builder"); close.onPress={ [weak self] in self?.onCancel?() }; add("close",close)
        add("insertTitle",LuminTextLabel("Insert fields",font:LuminAssets.font(16,520),lineHeight:24,color:LuminLegacyStyle.variant))
        let track=LuminFormTabTrack(); add("tabTrack",track)
        for kind in LuminFormFieldKind.allCases {
            let button=LuminFormTabButton(kind); button.target=self; button.action=#selector(pickField)
            button.onNavigate={ [weak self] index in self?.select(index,focus:true) }; track.addSubview(button); tabs.append(button)
        }
        track.setAccessibilityElement(true); track.setAccessibilityRole(.tabGroup); track.setAccessibilityLabel("Insert fields"); track.setAccessibilityChildren(tabs)
        properties.contentView=LuminFormClip(); properties.documentView=document; properties.drawsBackground=false; properties.borderType = .noBorder; properties.hasVerticalScroller=true; properties.autohidesScrollers=true; properties.scrollerStyle = .overlay
        add("properties",properties)
        let title=LuminTextLabel("Properties",font:LuminAssets.font(16,520),lineHeight:24,color:LuminLegacyStyle.variant)
        let empty=LuminTextLabel("No field is selected. Select a field to edit its properties",font:LuminAssets.font(12,420),lineHeight:18,color:LuminLegacyStyle.variant)
        document.addSubview(title); document.addSubview(empty); controls["propertiesTitle"]=title; controls["empty"]=empty
        add("footer",NSView()); add("cancel",cancel); add("apply",apply)
        apply.isEnabled=false; cancel.onPress={ [weak self] in self?.onCancel?() }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout(); let w=bounds.width,h=bounds.height
        controls["header"]!.frame=NSRect(x:0,y:0,width:w,height:41)
        controls["headerTitle"]!.frame=NSRect(x:16,y:10,width:83.953125,height:20)
        controls["close"]!.frame=NSRect(x:w-36,y:4,width:32,height:32)
        controls["insertTitle"]!.frame=NSRect(x:16,y:53,width:w-32,height:24)
        controls["tabTrack"]!.frame=NSRect(x:16,y:85,width:w-32,height:42)
        for (i,tab) in tabs.enumerated() { tab.frame=NSRect(x:1+CGFloat(i)*(w-34)/4,y:1,width:(w-34)/4,height:40) }
        properties.frame=NSRect(x:0,y:129,width:w,height:max(0,h-198))
        document.frame=NSRect(x:0,y:0,width:w,height:max(74,properties.contentSize.height))
        controls["propertiesTitle"]!.frame=NSRect(x:16,y:12,width:w-32,height:24)
        controls["empty"]!.frame=NSRect(x:16,y:44,width:w-32,height:18)
        controls["footer"]!.frame=NSRect(x:0,y:h-69,width:w,height:58)
        cancel.frame=NSRect(x:16,y:h-67,width:(w-48)/2,height:40)
        apply.frame=NSRect(x:32+(w-48)/2,y:h-67,width:(w-48)/2,height:40)
    }
    override func draw(_ rect:NSRect) {
        super.draw(rect); PodTheme.border.setFill(); NSRect(x:0,y:40,width:bounds.width,height:1).fill()
    }
    func reset() { selectedKind=nil; tabs.forEach{$0.selected=false}; apply.isEnabled=false }
    @objc private func pickField(_ sender:LuminFormTabButton) { select(sender.kind.rawValue,focus:false) }
    private func select(_ index:Int,focus:Bool) {
        guard let kind=LuminFormFieldKind(rawValue:index) else { return }; selectedKind=kind
        tabs.forEach{$0.selected=$0.kind==kind}; if focus { window?.makeFirstResponder(tabs[index]) }; onFieldChoice?(kind)
    }
}

private final class LuminFormTabTrack:NSView {
    override var isFlipped:Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        PodTheme.surface.setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:20,yRadius:20).fill()
        LuminLegacyStyle.outline.setStroke(); let border=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:21,yRadius:21); border.lineWidth=1; border.stroke()
    }
}

final class LuminFormTabButton:NSButton {
    let kind:LuminFormFieldKind
    var selected=false { didSet { setAccessibilityValue(selected ? 1:0); needsDisplay=true } }
    var onNavigate:((Int)->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    init(_ kind:LuminFormFieldKind) {
        self.kind=kind; super.init(frame:.zero); title=""; image=LuminAssets.icon(kind.glyph); isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none
        setAccessibilityRole(.radioButton); setAccessibilityLabel(kind.title); setAccessibilityValue(0); toolTip="Add "+kind.title.lowercased()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds,xRadius:20,yRadius:20)
        if selected { PodTheme.primaryContainer.setFill(); shape.fill() }
        if hovered || isHighlighted { (selected ? PodTheme.primaryContainer:PodTheme.text).withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); shape.fill() }
        if let image { LuminAssets.tinted(image,PodTheme.text).draw(in:NSRect(x:(bounds.width-24)/2,y:8,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode {
        case 123:onNavigate?((kind.rawValue+3)%4)
        case 124:onNavigate?((kind.rawValue+1)%4)
        case 115:onNavigate?(0)
        case 119:onNavigate?(3)
        default:super.keyDown(with:event)
        }
    }
}
