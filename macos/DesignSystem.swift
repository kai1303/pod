import AppKit

// Observed Lumin dimensions and source theme roles. See research/lumin/FIDELITY.md.
enum PodMetrics {
    static let control:CGFloat=32
    static let largeControl:CGFloat=40
    static let radius:CGFloat=8
    static let gap:CGFloat=8
    static let section:CGFloat=16
    static let header:CGFloat=56
    static let toolbar:CGFloat=48
    static let palette:CGFloat=300
    static let paletteContent:CGFloat=268
    static let pageInset:CGFloat=28
}

enum PodTypography {
    static let body=LuminAssets.font(14,420)
    static let control=LuminAssets.font(12,460)
    static let caption=LuminAssets.font(11,460)
    static let section=LuminAssets.font(14,520)
    static let heading=LuminAssets.font(18,520)
}

enum PodTheme {
    static func color(_ hex:UInt32)->NSColor {
        NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
    }
    private static func adaptive(_ name:String,_ light:UInt32,_ dark:UInt32)->NSColor {
        NSColor(name:NSColor.Name("Pod.\(name)")) { appearance in
            color(appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark:light)
        }
    }
    static let accent=color(0x087191)
    static let primary=adaptive("primary",0x035970,0x8EDEF4)
    static let primaryContainer=adaptive("primaryContainer",0xC4F0FD,0x087191)
    static let onAccent=color(0xCDE6F2)
    static let surface=adaptive("surface",0xEDEEF0,0x1D2021)
    static let chrome=adaptive("chrome",0xF3F4F6,0x191C1D)
    static let controlTrack=adaptive("controlTrack",0xFFFFFF,0x111415)
    static let raised=adaptive("raised",0xFFFFFF,0x282B2C)
    static let canvas=adaptive("canvas",0xF8F9FB,0x111415)
    static let text=adaptive("text",0x191C1D,0xE1E2E4)
    static let secondaryText=adaptive("secondaryText",0x42474A,0xC2C7CA)
    static let border=adaptive("border",0xD6DBDE,0x42474A)
    static let navigationHover=adaptive("navigationHover",0xE7E8EA,0x282B2C)
    static let hover=adaptive("hover",0xE7E8EA,0x343738)
    static let selectedSurface=adaptive("selectedSurface",0xC4F0FD,0x087191)
    static let selectedText=adaptive("selectedText",0x012832,0xC4F0FD)
    static let focus=adaptive("focus",0x087191,0x8EDEF4)
    static let badgeYellow=color(0xE79A00)
    static let onBadgeYellow=adaptive("onBadgeYellow",0xFFEFCF,0x5A4300)
    static let danger=adaptive("danger",0xB3261E,0xFF8A77)
    static let secondary=adaptive("secondary",0x1C333D,0xB2CAD6)
    static let dockFocus=adaptive("dockFocus",0xCDE6F2,0x334A54)
    static let onSecondary=adaptive("onSecondary",0xFFFFFF,0x1C333D)
    // ChromePicker uses the legacy theme roles inside the newer Kiwi popper.
    static let pickerText=adaptive("pickerText",0x325167,0xBCCFDC)
    static let pickerOutline=adaptive("pickerOutline",0xBCCFDC,0x325167)
    static let lowText=adaptive("lowText",0x757779,0x8E9192)
    static let outline=adaptive("outline",0xA6ABAE,0x8C9194)
    static let information=adaptive("information",0x1F5ABD,0x7CACFA)
    static let onInformation=adaptive("onInformation",0xFFFFFF,0x082A63)
    static let informationContainer=adaptive("informationContainer",0xE9F1FE,0x10418E)
    static let onSecondaryContainer=adaptive("onSecondaryContainer",0x051E27,0xCDE6F2)
}

class PodSurfaceView:NSView {
    var surface:NSColor=PodTheme.surface { didSet { needsDisplay=true } }
    override var allowsVibrancy:Bool { false }
    override var isOpaque:Bool { true }
    override func draw(_ dirtyRect:NSRect) { surface.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

class PodSurfaceStack:NSStackView {
    var surface:NSColor=PodTheme.surface { didSet { needsDisplay=true } }
    var bottomBorder=false
    override var allowsVibrancy:Bool { false }
    override var isOpaque:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        surface.setFill(); bounds.fill()
        if bottomBorder { PodTheme.border.setFill(); NSRect(x:0,y:0,width:bounds.width,height:1).fill() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

// Keep NSButton's native tracking, keyboard activation and accessibility; only replace its paint.
final class PodButton:NSButton {
    enum Emphasis { case plain, primary, destructive }
    var emphasis:Emphasis = .plain { didSet { needsDisplay=true } }
    var cornerRadius:CGFloat=PodMetrics.radius
    var iconSize:CGFloat=24
    var isSelected=false { didSet { state=isSelected ? .on:.off; needsDisplay=true } }
    private var hovered=false
    private var hoverArea:NSTrackingArea?
    override var isEnabled:Bool { didSet { needsDisplay=true } }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override var allowsVibrancy:Bool { false }

    override init(frame:NSRect) {
        super.init(frame:frame)
        isBordered=false; setButtonType(.momentaryPushIn); font=PodTypography.control
        focusRingType = .exterior
    }
    convenience init(title:String,target:AnyObject?,action:Selector?) {
        self.init(frame:.zero); self.title=title; self.target=target; self.action=action
        toolTip=title; setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize {
        let textSize=(title as NSString).size(withAttributes:[.font:font ?? PodTypography.control])
        return NSSize(width:max(PodMetrics.control,ceil(textSize.width)+(image == nil ? 0:iconSize+4)+16),height:PodMetrics.control)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); hoverArea=area
    }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds,xRadius:cornerRadius,yRadius:cornerRadius).fill() }
    override var focusRingMaskBounds:NSRect { bounds }
    override func draw(_ dirtyRect:NSRect) {
        let active=isEnabled && (hovered || isHighlighted)
        let background: NSColor = emphasis == .primary ? PodTheme.accent : (isSelected ? PodTheme.selectedSurface:(active ? PodTheme.hover:.clear))
        let foreground: NSColor = emphasis == .primary ? PodTheme.onAccent : (isSelected ? PodTheme.selectedText:(emphasis == .destructive ? PodTheme.danger:PodTheme.text))
        let opacity:CGFloat=isEnabled ? 1:0.38
        background.withAlphaComponent(background.alphaComponent * (isEnabled ? 1:0.25)).setFill()
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:cornerRadius,yRadius:cornerRadius); shape.fill()
        if isHighlighted && isEnabled { foreground.withAlphaComponent(0.12).setFill(); shape.fill() }
        let attributes:[NSAttributedString.Key:Any]=[.font:font ?? PodTypography.control,.foregroundColor:foreground.withAlphaComponent(opacity)]
        let size=(title as NSString).size(withAttributes:attributes)
        let iconWidth:CGFloat=image == nil ? 0:iconSize
        let gap:CGFloat=image == nil || title.isEmpty ? 0:4
        let total=size.width+iconWidth+gap
        let x=alignment == .left ? 8:max(4,(bounds.width-total)/2)
        if let image {
            LuminAssets.tinted(image,foreground).draw(in:NSRect(x:x,y:(bounds.height-iconSize)/2,width:iconSize,height:iconSize),from:.zero,operation:.sourceOver,fraction:opacity,respectFlipped:true,hints:nil)
        }
        (title as NSString).draw(in:NSRect(x:x+iconWidth+gap,y:(bounds.height-size.height)/2,width:max(0,bounds.width-x-iconWidth-gap-8),height:size.height),withAttributes:attributes)
    }
}

final class PodChoiceGroup:PodSurfaceStack {
    override var isOpaque:Bool { false }
    override func draw(_ dirtyRect:NSRect) {
        surface.setFill(); NSBezierPath(roundedRect:bounds,xRadius:16,yRadius:16).fill()
    }
    private(set) var selectedIndex:Int
    var onChange:((Int)->Void)?
    init(labels:[String],selectedIndex:Int) {
        self.selectedIndex=selectedIndex
        super.init(frame:.zero)
        orientation = .horizontal; distribution = .fillEqually; spacing=0; surface=PodTheme.controlTrack
        setAccessibilityLabel("Style")
        for (index,label) in labels.enumerated() {
            let button=PodButton(title:label,target:self,action:#selector(pick)); button.tag=index
            button.font=PodTypography.section; button.cornerRadius=16; button.isSelected=index==selectedIndex
            addArrangedSubview(button)
        }
        heightAnchor.constraint(equalToConstant:PodMetrics.control).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func pick(_ sender:PodButton) {
        selectedIndex=sender.tag
        for case let button as PodButton in arrangedSubviews { button.isSelected=button.tag==selectedIndex }
        onChange?(selectedIndex)
    }
}

// Shared CSS line-box label used by source dialog surfaces.
final class LuminTextLabel:NSView {
    var text:String { didSet { setAccessibilityValue(text); needsDisplay=true } }
    let font:NSFont,lineHeight:CGFloat
    var horizontalInset:CGFloat=0
    var truncates=false
    override var wantsDefaultClipping:Bool { false }
    var color:NSColor
    override var isFlipped:Bool { true }
    init(_ text:String,font:NSFont,lineHeight:CGFloat,color:NSColor=PodTheme.text) {
        self.text=text; self.font=font; self.lineHeight=lineHeight; self.color=color; super.init(frame:.zero)
        setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityValue(text)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=lineHeight; paragraph.maximumLineHeight=lineHeight; paragraph.lineBreakMode = truncates ? .byTruncatingTail:.byClipping
        let width=truncates ? bounds.width-horizontalInset*2:max(bounds.width-horizontalInset*2,(text as NSString).size(withAttributes:[.font:font]).width)
        (text as NSString).draw(in:NSRect(x:horizontalInset,y:(bounds.height-lineHeight)/2,width:width,height:lineHeight),withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph])
    }
}

