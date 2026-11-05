import AppKit

// These older toolbar components mix legacy foreground roles with the newer Kiwi Paper.
// See the downloaded source and live DOM fixtures in research/lumin/.
enum LuminLegacyStyle {
    private static func adaptive(_ name:String,_ light:UInt32,_ dark:UInt32)->NSColor {
        NSColor(name:NSColor.Name("Pod.Legacy.\(name)")) { appearance in PodTheme.color(appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light) }
    }
    static let text=adaptive("text",0x161C21,0xE3E5E8)
    static let variant=adaptive("variant",0x325167,0xBCCFDC)
    static let primary=adaptive("primary",0x087191,0x74D6F1)
    static let selected=adaptive("selected",0xC4F0FD,0x087191)
    static let container=adaptive("container",0xEEEFF1,0x1A2025)
    static let outline=adaptive("outline",0xBCCFDC,0x325167)
    static let surface=adaptive("surface",0xF9F9FA,0x0E1419)
    static let inverseSurface=adaptive("inverseSurface",0x2B3137,0xE3E5E8)
    static let thumbOutline=PodTheme.color(0x8B9198)
    static let secondary=adaptive("secondary",0x516671,0xB4CAD6)
    static let secondaryContainer=adaptive("secondaryContainer",0xD0E6F2,0x3C535D)
    static let onSecondaryContainer=adaptive("onSecondaryContainer",0x081E27,0xD0E6F2)
    static let disabled=adaptive("disabled",0x161C21,0xE4E7EC).withAlphaComponent(0.38)
    static let signContainer=adaptive("signContainer",0xD0CCFF,0x3A28C0)
    static let signText=adaptive("signText",0x160F57,0xD0CCFF)
}

struct LuminViewState:Equatable {
    enum Transition { case pageByPage,continuous }
    enum Layout { case single,double,cover }
    var transition:Transition = .continuous
    var layout:Layout = .single
    var displayMode:String {
        switch (transition,layout) {
        case (.pageByPage,.single):return "Single"
        case (.continuous,.single):return "Continuous"
        case (.pageByPage,.double):return "Facing"
        case (.continuous,.double):return "FacingContinuous"
        case (.pageByPage,.cover):return "CoverFacing"
        case (.continuous,.cover):return "Cover"
        }
    }
}

final class LuminLegacyIconButton:NSButton {
    var selectedGlyphColor:NSColor?
    var glyphSize:CGFloat=24 { didSet { image=LuminAssets.icon(glyphName,size:glyphSize); needsDisplay=true } }
    var glyphName="" { didSet { image=LuminAssets.icon(glyphName,size:glyphSize); needsDisplay=true } }
    var hasArrow=false
    var isSelected=false { didSet { needsDisplay=true; setAccessibilityValue(isSelected ? "Selected":"Not selected") } }
    private var hovered=false
    private var tracking:NSTrackingArea?
    var cssBackground:NSColor { hovered && isEnabled ? LuminLegacyStyle.variant.withAlphaComponent(0.08):(isSelected ? LuminLegacyStyle.selected:.clear) }
    var cssForeground:NSColor { (isSelected ? LuminLegacyStyle.text:LuminLegacyStyle.variant).withAlphaComponent(isEnabled ? 1:0.38) }
    override var isFlipped:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); isBordered=false; title=""; setButtonType(.momentaryPushIn); focusRingType = .none }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:hasArrow ? 52:32,height:32) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        // Source &:hover replaces (rather than overlays) an active background.
        cssBackground.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        let color=isSelected ? (selectedGlyphColor ?? cssForeground):cssForeground
        if let image { LuminAssets.tinted(image,color).draw(in:NSRect(x:(32-glyphSize)/2,y:(32-glyphSize)/2,width:glyphSize,height:glyphSize),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        if hasArrow,let arrow=LuminAssets.icon("pdf-icon-sm_down_stroke",size:20) { LuminAssets.tinted(arrow,color).draw(in:NSRect(x:28,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

private final class LuminViewSurface:PodSurfaceView {
    override var isFlipped:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); surface=PodTheme.raised }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
}

final class LuminViewControlsMenu:NSViewController {
    private(set) var state:LuminViewState
    private(set) var buttons:[LuminLegacyIconButton]=[]
    var onChange:((LuminViewState)->Void)?
    init(state:LuminViewState) { self.state=state; super.init(nibName:nil,bundle:nil); title="View controls" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminViewSurface(frame:NSRect(x:0,y:0,width:275.4375,height:104))
        for (title,y) in [("Page transition",21.5),("Layout",61.5)] {
            let label=NSTextField(labelWithString:title); label.font=LuminAssets.font(14,420); label.textColor=LuminLegacyStyle.text
            label.frame=NSRect(x:16,y:y,width:97.71875,height:21); root.addSubview(label)
        }
        let options=[("defaultPageTransitionButton","md_single_page_view","Page by page",0,0),("continuousPageTransitionButton","md_continues_page_view","Continuous",1,0),("singleLayoutButton","md_one_page_view","Single page",0,1),("doubleLayoutButton","md_two_page_view","Double page",1,1),("coverLayoutButton","md_cover_page_view","Cover Facing",2,1)]
        for (index,item) in options.enumerated() {
            let button=LuminLegacyIconButton(); button.glyphName="pdf-icon-"+item.1; button.identifier=NSUserInterfaceItemIdentifier(item.0); button.setAccessibilityLabel(item.2); button.toolTip=item.2; button.tag=index; button.target=self; button.action=#selector(choose)
            button.frame=NSRect(x:129.71875+CGFloat(item.3)*48.5703125,y:16+CGFloat(item.4)*40,width:32,height:32)
            root.addSubview(button); buttons.append(button)
        }
        view=root; preferredContentSize=root.frame.size; refresh()
    }
    private func refresh() { for (button,selected) in zip(buttons,[state.transition == .pageByPage,state.transition == .continuous,state.layout == .single,state.layout == .double,state.layout == .cover]) { button.isSelected=selected } }
    @objc private func choose(_ sender:NSButton) {
        switch sender.tag { case 0:state.transition = .pageByPage; case 1:state.transition = .continuous; case 2:state.layout = .single; case 3:state.layout = .double; default:state.layout = .cover }
        refresh(); onChange?(state)
    }
}

enum LuminZoomAction:Equatable {
    case fitWidth,fitHeight,percent(Double),zoomIn,zoomOut
    var closesMenu:Bool { switch self { case .zoomIn,.zoomOut:return false; default:return true } }
    static func stepped(_ percentage:Double,increase:Bool)->Double {
        let step:Double=percentage<=80 ? 7.5:percentage<=150 ? 12.5:percentage<=250 ? 25:50
        return min(9999,max(5,percentage+(increase ? step:-step)))
    }
}

final class LuminZoomMenu:NSViewController {
    private(set) var rows:[LuminZoomMenuRow]=[]
    private(set) var separators:[NSView]=[]
    private var focused:Int?
    private var typed="",lastTyped:TimeInterval=0
    var onChoose:((LuminZoomAction)->Void)?
    override init(nibName:NSNib.Name?=nil,bundle:Bundle?=nil) { super.init(nibName:nibName,bundle:bundle); title="Zoom" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminViewSurface(frame:NSRect(x:0,y:0,width:166.4140625,height:306)); var y:CGFloat=8
        let choices:[(String,String?,LuminZoomAction)]=[("Fit width",nil,.fitWidth),("Fit height","⌘0",.fitHeight),("50%",nil,.percent(50)),("100%",nil,.percent(100)),("200%",nil,.percent(200)),("300%",nil,.percent(300)),("Zoom in","⌘+",.zoomIn),("Zoom out","⌘-",.zoomOut)]
        for (index,item) in choices.enumerated() {
            if index==2 || index==6 { y += 8; let divider=PodSurfaceView(frame:NSRect(x:8,y:y,width:150.4140625,height:1)); divider.surface=LuminLegacyStyle.outline; root.addSubview(divider); separators.append(divider); y += 9 }
            let row=LuminZoomMenuRow(label:item.0,shortcut:item.1,choice:item.2); row.frame=NSRect(x:8,y:y,width:150.4140625,height:32); row.onChoose={ [weak self] action in self?.onChoose?(action) }; root.addSubview(row); rows.append(row); y += 32
            row.onPointerFocus={ [weak self] in self?.clearKeyboardFocus() }
        }
        view=root; preferredContentSize=root.frame.size
    }
    func handleKey(_ event:NSEvent)->Bool {
        if let current=rows.firstIndex(where:{$0.window?.firstResponder === $0}) { focused=current }
        switch event.keyCode {
        case 125:focused=focused.map{($0+1)%rows.count} ?? 0
        case 126:focused=focused.map{($0+rows.count-1)%rows.count} ?? rows.count-1
        case 115:focused=0
        case 119:focused=rows.count-1
        case 36,76:guard let focused else { return false }; rows[focused].performClick(nil); return true
        default:
            guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),let character=event.charactersIgnoringModifiers,character.count==1,character.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0)}) else { return false }
            let now=ProcessInfo.processInfo.systemUptime
            typed=now-lastTyped>0.5 ? character.lowercased():typed+character.lowercased(); lastTyped=now
            let repeated=Set(typed).count==1,query=repeated ? String(typed.prefix(1)):typed
            let start=focused.map{repeated ? ($0+1)%rows.count:$0} ?? 0
            guard let match=(0..<rows.count).map({(start+$0)%rows.count}).first(where:{rows[$0].title.lowercased().hasPrefix(query)}) else { return true }
            focused=match
        }
        focusRow(focused!); return true
    }
    func focusRow(_ index:Int) {
        focused=index; view.window?.makeKey(); view.window?.makeFirstResponder(rows[index])
        for (offset,row) in rows.enumerated() { row.keyboardFocused=offset==index }
    }
    func clearKeyboardFocus() { focused=nil; rows.forEach{$0.keyboardFocused=false} }
}

final class LuminZoomMenuRow:NSButton {
    let shortcut:String?
    let choice:LuminZoomAction
    var onChoose:((LuminZoomAction)->Void)?
    var onPointerFocus:(()->Void)?
    var keyboardFocused=false { didSet { needsDisplay=true } }
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    init(label:String,shortcut:String?,choice:LuminZoomAction) {
        self.shortcut=shortcut; self.choice=choice; super.init(frame:.zero)
        title=label; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose)
        setAccessibilityRole(.menuItem); setAccessibilityLabel(label+(shortcut.map{" "+$0} ?? ""))
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func mouseDown(with event:NSEvent) { onPointerFocus?(); window?.makeKey(); window?.makeFirstResponder(self); super.mouseDown(with:event) }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    @objc private func choose() { onChoose?(choice) }
    override func draw(_ rect:NSRect) {
        if hovered || keyboardFocused { LuminLegacyStyle.text.withAlphaComponent(0.08).setFill(); NSBezierPath(roundedRect:bounds,xRadius:4,yRadius:4).fill() }
        let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,420),.foregroundColor:LuminLegacyStyle.text]
        (title as NSString).draw(in:NSRect(x:8,y:5.5,width:bounds.width-(shortcut==nil ? 16:80),height:21),withAttributes:attrs)
        if let shortcut { var trailing=attrs; trailing[.foregroundColor]=LuminLegacyStyle.variant; let width=(shortcut as NSString).size(withAttributes:trailing).width; (shortcut as NSString).draw(in:NSRect(x:bounds.width-4-width,y:5.5,width:width,height:21),withAttributes:trailing) }
    }
}

final class LuminZoomInput:NSTextField {
    var onFocus:(()->Void)?
    override func becomeFirstResponder()->Bool {
        let accepted=super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
    override func mouseDown(with event:NSEvent) { super.mouseDown(with:event); onFocus?() }
}

final class LuminZoomField:NSView,NSTextFieldDelegate {
    let input=LuminZoomInput()
    private let suffix=NSButton()
    var percentage:Double=100 { didSet { input.stringValue=String(format:"%.0f%%",percentage) } }
    var onOpen:(()->Void)?
    var onCommit:((Double)->Void)?
    private var hovered=false,focused=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:68,height:32) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        input.isBordered=false; input.isBezeled=false; input.drawsBackground=false; input.focusRingType = .none; input.font=LuminAssets.font(12,460); input.textColor=LuminLegacyStyle.variant; input.delegate=self; input.target=self; input.action=#selector(submit); input.stringValue="100%"; input.setAccessibilityLabel("Zoom percentage")
        input.onFocus={ [weak self] in self?.focused=true; self?.needsDisplay=true; self?.onOpen?() }
        suffix.isBordered=false; suffix.focusRingType = .none; suffix.image=LuminAssets.icon("pdf-icon-sm_down_stroke",size:20); suffix.imageScaling = .scaleNone; suffix.contentTintColor=LuminLegacyStyle.variant; suffix.target=self; suffix.action=#selector(openMenu); suffix.setAccessibilityLabel("Zoom options")
        addSubview(input); addSubview(suffix)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); input.frame=NSRect(x:8,y:7.375,width:36,height:17.25); suffix.frame=NSRect(x:44,y:6,width:20,height:20) }
    func commit() {
        let raw=input.stringValue.replacingOccurrences(of:"%",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
        let value=Double(raw) ?? percentage
        percentage=value.isFinite ? min(9999,max(5,value)):percentage
        onCommit?(percentage)
    }
    @objc private func submit() { commit() }
    @objc private func openMenu() { onOpen?() }
    func controlTextDidBeginEditing(_ notification:Notification) { focused=true; needsDisplay=true; onOpen?() }
    func controlTextDidChange(_ notification:Notification) {
        let raw=input.stringValue
        var number=raw.hasPrefix("-") ? "-":"",hasDecimal=false
        for character in raw {
            if character >= "0" && character <= "9" { number.append(character) }
            else if character=="." && !hasDecimal { number.append(character); hasDecimal=true }
        }
        let formatted=number.isEmpty ? "":number+"%"
        if formatted != raw {
            let editor=input.currentEditor() as? NSTextView,selection=editor?.selectedRange()
            input.stringValue=formatted
            if let selection { editor?.setSelectedRange(NSRange(location:min(selection.location,number.utf16.count),length:0)) }
        }
    }
    func controlTextDidEndEditing(_ notification:Notification) { focused=false; needsDisplay=true }
    override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(input) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); input.textColor=LuminLegacyStyle.variant; suffix.contentTintColor=LuminLegacyStyle.variant; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if hovered { (focused ? LuminLegacyStyle.container:LuminLegacyStyle.variant.withAlphaComponent(0.08)).setFill(); path.fill() }
        if focused { LuminLegacyStyle.primary.setStroke(); path.lineWidth=1; path.stroke() }
    }
}
