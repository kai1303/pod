import AppKit

struct LuminTypeState {
    var family="Inter"
    var size=12
    var bold=false,italic=false,underline=false,strikeThrough=false
    var textColor=PodTheme.color(0x102D42)
    var fill:NSColor?
    var stroke=NSColor.black
    var strokeWidth=0.0
    var opacity=1.0
}

// Geometry and options come from the live SecondaryToolbar and its downloaded source.
final class LuminTypeToolbar:PodSurfaceStack {
    static let families:[(label:String,value:String)]=[("Arimo","Arimo"),("EB Garamond","EBGaramond"),("Inter","Inter"),("Lora","Lora"),("Merriweather","Merriweather"),("Montserrat","Montserrat"),("Noto Sans","NotoSans"),("Noto Sans Japanese","NotoSansJP"),("Noto Sans Korean","NotoSansKR"),("Noto Sans Simplified Chinese","NotoSansSC"),("Noto Sans Traditional Chinese","NotoSansTC"),("Nunito","Nunito"),("Open Sans","OpenSans"),("Roboto","Roboto"),("Source Sans 3","SourceSans"),("Source Serif 4","SourceSerif"),("Spectral","Spectral"),("Vollkorn","Vollkorn")]
    enum Purpose { case text,date }
    private(set) var purpose:Purpose = .text
    private(set) var state=LuminTypeState()
    private var textState=LuminTypeState()
    private var dateState=LuminTypeState(family:"Helvetica",textColor:.black)
    var fontChoices:[(label:String,value:String)] {
        Self.families.contains{$0.value==state.family} ? Self.families:[(state.family,state.family)]+Self.families
    }
    var onChange:((LuminTypeState)->Void)?
    var onClose:(()->Void)?
    var canCloseOnEscape:(()->Bool)?
    private let family=LuminTypeSelectButton()
    private let size=LuminTypeSelectButton()
    private var formats:[PodButton]=[]
    private let color=LuminTypePaintButton(kind:.color)
    private let frameButton=LuminTypePaintButton(kind:.frame)
    private let opacity=LuminTypePaintButton(kind:.opacity)
    private var popper:LuminPopper?
    private var submenu=""
    private var keyboardMonitor:Any?

    init() {
        super.init(frame:.zero)
        orientation = .horizontal; alignment = .centerY; distribution = .fill; spacing=4
        surface=PodTheme.raised; edgeInsets=NSEdgeInsets(top:4,left:9,bottom:4,right:4)
        wantsLayer=true; layer?.cornerRadius=8; layer?.masksToBounds=true
        setAccessibilityLabel("Text formatting")
        heightAnchor.constraint(equalToConstant:40).isActive=true
        family.target=self; family.action=#selector(fontPicked); family.setAccessibilityLabel("Font family"); family.widthAnchor.constraint(equalToConstant:108).isActive=true
        size.target=self; size.action=#selector(sizePicked); size.setAccessibilityLabel("Font size"); size.widthAnchor.constraint(equalToConstant:78).isActive=true
        addArrangedSubview(family); divider(); addArrangedSubview(size); divider()
        for (i,item) in [("Bold","md_bold"),("Italic","md_italic"),("Underline","md_underline"),("Strikethrough","md_strike_though")].enumerated() {
            let b=PodButton(title:"",target:self,action:#selector(formatPicked)); b.image=LuminAssets.icon("pdf-icon-"+item.1); b.setAccessibilityLabel(item.0); b.toolTip=item.0; b.tag=i; b.widthAnchor.constraint(equalToConstant:32).isActive=true
            formats.append(b); addArrangedSubview(b)
        }
        divider()
        for (b,name,action) in [(color,"Text color",#selector(colorPicked)),(frameButton,"Text frame",#selector(framePicked)),(opacity,"Opacity",#selector(opacityPicked))] {
            b.target=self; b.action=action; b.setAccessibilityLabel(name); b.toolTip=name; addArrangedSubview(b)
            if b !== opacity { b.widthAnchor.constraint(equalToConstant:32).isActive=true }
            if b === frameButton { divider() }
        }
        let space=NSView(); space.setContentHuggingPriority(.init(1),for:.horizontal); addArrangedSubview(space)
        let close=PodButton(title:"",target:self,action:#selector(closeToolbar)); close.image=LuminAssets.icon("kiwi-icon-x-sm",size:16); close.iconSize=16; close.widthAnchor.constraint(equalToConstant:32).isActive=true; close.setAccessibilityLabel("Close text formatting"); close.toolTip="Close"; addArrangedSubview(close)
        refresh()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        // NSStackView rounds intrinsic widths; the source percentage control keeps its fractional text advance.
        var frame=opacity.frame; frame.size.width=opacity.intrinsicContentSize.width; if opacity.frame != frame { opacity.frame=frame }
    }
    override func draw(_ rect:NSRect) { super.draw(rect); PodTheme.border.setStroke(); let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8); outline.lineWidth=1; outline.stroke() }
    func open(for purpose:Purpose = .text) {
        if self.purpose != purpose {
            popper?.close()
            if self.purpose == .text { textState=state } else { dateState=state }
            self.purpose=purpose; state=purpose == .text ? textState:dateState; refresh()
        }
        isHidden=false
        if keyboardMonitor==nil {
            keyboardMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                self?.handleEscape(event)==true ? nil:event
            }
        }
        onChange?(state)
    }
    func handleEscape(_ event:NSEvent)->Bool {
        guard !isHidden,event.window === window,event.keyCode==53,popper?.isShown != true,canCloseOnEscape?() != false else { return false }
        onClose?(); return true
    }
    func dismissPopovers() { popper?.close() }
    func dismiss() {
        popper?.close(); isHidden=true
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor=nil }
    }
    deinit { if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) } }
    private func divider() { let v=NSBox(); v.boxType = .separator; v.widthAnchor.constraint(equalToConstant:1).isActive=true; v.heightAnchor.constraint(equalToConstant:24).isActive=true; addArrangedSubview(v) }
    private func refresh() {
        family.title=Self.families.first{$0.value==state.family}?.label ?? state.family; family.previewFamily=state.family
        size.title="\(state.size)pt"
        for (b,value) in zip(formats,[state.bold,state.italic,state.underline,state.strikeThrough]) { b.isSelected=value; b.setAccessibilityValue(value ? "Selected":"Not selected") }
        color.stateValue=state; frameButton.stateValue=state; opacity.stateValue=state
        family.needsDisplay=true; size.needsDisplay=true
    }
    private func changed() { refresh(); onChange?(state) }
    private func show(_ content:NSViewController,from button:NSButton,key:String,escapeClosesToolbar:Bool=true) {
        if submenu==key && popper?.isShown==true { popper?.close(); return }
        popper?.close(); submenu=key
        let pop=LuminPopper(); pop.alignment = .start; pop.gap=8; pop.contentViewController=content
        if let list=content as? LuminTypeChoiceMenu { pop.onKeyDown={ [weak list] event in list?.handleKey(event) ?? false } }
        if escapeClosesToolbar { pop.onEscape={ [weak self] in self?.onClose?() } }
        popper=pop; pop.show(relativeTo:button.bounds,of:button)
    }
    @objc private func fontPicked() {
        let menu=LuminTypeChoiceMenu(choices:fontChoices.map{.init(label:$0.label,value:$0.value,family:$0.value)},selected:state.family,width:purpose == .date ? 227.484375:211.5234375)
        menu.onSelect={ [weak self] value in self?.state.family=value; self?.popper?.close(); self?.changed() }
        show(menu,from:family,key:"font",escapeClosesToolbar:false)
    }
    @objc private func sizePicked() {
        let menu=LuminTypeChoiceMenu(choices:(5...45).map{.init(label:"\($0)pt",value:String($0),family:nil)},selected:String(state.size),width:72.1640625)
        menu.onSelect={ [weak self] value in guard let size=Int(value) else { return }; self?.state.size=size; self?.popper?.close(); self?.changed() }
        show(menu,from:size,key:"size",escapeClosesToolbar:false)
    }
    @objc private func formatPicked(_ sender:NSButton) {
        switch sender.tag { case 0: state.bold.toggle(); case 1: state.italic.toggle(); case 2: state.underline.toggle(); default: state.strikeThrough.toggle() }; changed()
    }
    @objc private func colorPicked() {
        let menu=LuminTypeColorMenu(width:278,color:state.textColor)
        menu.onChange={ [weak self] value in if let value { self?.state.textColor=value; self?.changed() } }
        show(menu,from:color,key:"color")
    }
    @objc private func framePicked() {
        let menu=LuminTypeFrameMenu(state:state)
        menu.onChange={ [weak self] fill,stroke,width in self?.state.fill=fill; self?.state.stroke=stroke; self?.state.strokeWidth=width; self?.changed() }
        show(menu,from:frameButton,key:"frame")
    }
    @objc private func opacityPicked() {
        let menu=LuminTypeOpacityMenu(value:state.opacity)
        menu.onChange={ [weak self] value in self?.state.opacity=value; self?.changed() }
        show(menu,from:opacity,key:"opacity")
    }
    @objc private func closeToolbar() { onClose?() }
}

private class LuminTypeSelectButton:LuminTypeHoverButton {
    var previewFamily="Inter"
    override init(frame:NSRect) { super.init(frame:frame); isBordered=false; setButtonType(.momentaryPushIn); heightAnchor.constraint(equalToConstant:32).isActive=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect:NSRect) {
        super.draw(rect)
        let p=NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in:NSRect(x:8,y:6,width:bounds.width-40,height:20),withAttributes:[.font:LuminAssets.previewFont(previewFamily,size:14),.foregroundColor:PodTheme.text,.paragraphStyle:p])
        if let icon=LuminAssets.icon("kiwi-icon-chevron-down-md",size:20) { LuminAssets.tinted(icon,PodTheme.secondaryText).draw(in:NSRect(x:bounds.width-26,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

private final class LuminTypePaintButton:LuminTypeHoverButton {
    enum Kind { case color,frame,opacity }
    let kind:Kind
    var stateValue=LuminTypeState() { didSet { invalidateIntrinsicContentSize(); needsDisplay=true } }
    init(kind:Kind) { self.kind=kind; super.init(frame:.zero); isBordered=false; setButtonType(.momentaryPushIn); heightAnchor.constraint(equalToConstant:32).isActive=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize {
        let text="\(Int((stateValue.opacity*100).rounded()))%"
        return NSSize(width:kind == .opacity ? 41+(text as NSString).size(withAttributes:[.font:LuminAssets.font(12,500)]).width:32,height:32)
    }
    override func draw(_ rect:NSRect) {
        super.draw(rect)
        switch kind {
        case .color:
            if let icon=LuminAssets.icon("kiwi-icon-ph-text-t",size:20) { LuminAssets.tinted(icon,PodTheme.text).draw(in:NSRect(x:6,y:4,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            stateValue.textColor.setFill(); NSRect(x:6,y:24,width:20,height:4).fill()
        case .frame:
            let frame=NSRect(x:6,y:6,width:20,height:20)
            if let fill=stateValue.fill { fill.setFill(); frame.fill() } else { LuminAssets.bitmap("empty")?.draw(in:frame) }
            if stateValue.strokeWidth>0 { stateValue.stroke.setStroke(); let path=NSBezierPath(rect:frame.insetBy(dx:1,dy:1)); path.lineWidth=2; path.stroke() }
        case .opacity:
            if let drop=LuminAssets.bitmap("drop") { LuminAssets.tinted(drop,PodTheme.text).draw(in:NSRect(x:8,y:4,width:17,height:24),from:.zero,operation:.sourceOver,fraction:stateValue.opacity,respectFlipped:true,hints:nil) }
            ("\(Int((stateValue.opacity*100).rounded()))%" as NSString).draw(in:NSRect(x:33,y:8,width:bounds.width-41,height:16),withAttributes:[.font:LuminAssets.font(12,500),.foregroundColor:PodTheme.text])
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

final class LuminTypeChoiceMenu:NSViewController {
    struct Choice { let label:String; let value:String; let family:String? }
    let choices:[Choice]
    private var active:Int
    private let menuWidth:CGFloat
    private var buttons:[PodButton]=[]
    private let scroll=NSScrollView()
    var onSelect:((String)->Void)?
    init(choices:[Choice],selected:String,width:CGFloat) { self.choices=choices; active=choices.firstIndex{$0.value==selected} ?? 0; menuWidth=width; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=PodSurfaceStack(); root.surface=PodTheme.raised; root.orientation = .vertical; root.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        let list=LuminTypeFlippedStack(); list.orientation = .vertical; list.alignment = .leading; list.spacing=0; list.translatesAutoresizingMaskIntoConstraints=false
        for (index,choice) in choices.enumerated() {
            let b=PodButton(title:choice.label,target:self,action:#selector(pick)); b.tag=index; b.alignment = .left; b.font=choice.family.map{LuminAssets.previewFont($0,size:14,weight:500)} ?? LuminAssets.font(14,500); b.cornerRadius=4
            b.widthAnchor.constraint(equalToConstant:menuWidth-16).isActive=true; b.heightAnchor.constraint(equalToConstant:28).isActive=true
            list.addArrangedSubview(b); buttons.append(b)
        }
        scroll.drawsBackground=false; scroll.hasVerticalScroller=false; scroll.documentView=list
        scroll.widthAnchor.constraint(equalToConstant:menuWidth-16).isActive=true; scroll.heightAnchor.constraint(equalToConstant:min(300,CGFloat(choices.count)*28)).isActive=true
        root.addArrangedSubview(scroll); view=root; preferredContentSize=NSSize(width:menuWidth,height:min(300,CGFloat(choices.count)*28)+16)
        list.setFrameSize(NSSize(width:menuWidth-16,height:CGFloat(choices.count)*28)); updateSelection()
    }
    private func updateSelection() { for (i,b) in buttons.enumerated() { b.isSelected=i==active }; if buttons.indices.contains(active) { buttons[active].scrollToVisible(buttons[active].bounds) } }
    @objc private func pick(_ sender:NSButton) { active=sender.tag; updateSelection(); onSelect?(choices[active].value) }
    func handleKey(_ event:NSEvent)->Bool {
        switch event.keyCode {
        case 125: active=min(choices.count-1,active+1)
        case 126: active=max(0,active-1)
        case 36,76: onSelect?(choices[active].value); return true
        default: return false
        }
        updateSelection(); return true
    }
}

private final class LuminTypeColorRow:NSView {
    private(set) var color:NSColor?
    var onChange:((NSColor?)->Void)?
    private var chips:[SwatchButton]=[]
    private let custom=NSButton()
    private var customPicker:LuminPopper?
    private let noFill:Bool
    init(color:NSColor?,noFill:Bool=false) {
        self.color=color; self.noFill=noFill; super.init(frame:.zero)
        let defaults:[NSColor]=[.black,PodTheme.color(0xD73027),PodTheme.color(0x4575B4),PodTheme.color(0x5AB4AC),PodTheme.color(0xFEE090),PodTheme.color(0xE0F3F8),.white]
        var palette=defaults
        if let color,color.alphaComponent>0,!defaults.contains(where:{equal($0,color)}) { palette=Array(defaults.dropFirst())+[color] }
        let values:[NSColor?]=(noFill ? [nil]:[])+palette
        for (i,c) in values.enumerated() {
            let b=SwatchButton(); b.swatch=c; b.isBordered=false; b.target=self; b.action=#selector(pick); b.tag=i; b.selected=equal(c,color); b.setAccessibilityLabel(c.map{hex($0)} ?? "No fill"); addSubview(b); chips.append(b)
        }
        custom.isBordered=false; custom.image=LuminAssets.bitmap("color-picker"); custom.imageScaling = .scaleProportionallyDown; custom.target=self; custom.action=#selector(pickCustom); custom.setAccessibilityLabel("Custom color"); addSubview(custom)
        heightAnchor.constraint(equalToConstant:32).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout(); let gap=(bounds.width-32-CGFloat(chips.count)*22)/CGFloat(chips.count)
        for (i,b) in chips.enumerated() { b.frame=NSRect(x:CGFloat(i)*(22+gap)-3,y:2,width:28,height:28) }
        custom.frame=NSRect(x:bounds.width-32,y:0,width:32,height:32)
    }
    private func hex(_ c:NSColor)->String { let c=c.usingColorSpace(.sRGB)!; return String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded())) }
    private func equal(_ a:NSColor?,_ b:NSColor?)->Bool { if a==nil && b==nil { return true }; guard let a,let b else { return false }; return hex(a)==hex(b) }
    @objc private func pick(_ sender:SwatchButton) { color=sender.swatch; chips.forEach{$0.selected=$0===sender;$0.needsDisplay=true}; onChange?(color) }
    @objc private func pickCustom() {
        customPicker?.close()
        customPicker=LuminColorPicker.present(from:custom,color:color ?? .clear) { [weak self] value in
            guard let self else { return }; color=value
            let colors=chips.filter{$0.swatch != nil}
            if !colors.contains(where:{self.equal($0.swatch,value)}) {
                let values=colors.dropFirst().compactMap{$0.swatch}+[value]
                for (button,value) in zip(colors,values) { button.swatch=value; button.setAccessibilityLabel(hex(value)) }
            }
            chips.forEach{$0.selected=self.equal($0.swatch,self.color);$0.needsDisplay=true}; onChange?(color)
        }
    }
}

private final class LuminTypeColorMenu:NSViewController {
    var onChange:((NSColor?)->Void)?
    let initial:NSColor
    let width:CGFloat
    init(width:CGFloat,color:NSColor) { self.width=width; initial=color; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=PodSurfaceStack(); root.surface=PodTheme.raised; root.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        let colors=LuminTypeColorRow(color:initial); colors.widthAnchor.constraint(equalToConstant:width-16).isActive=true; colors.onChange={ [weak self] color in self?.onChange?(color) }
        root.addArrangedSubview(colors); view=root; preferredContentSize=NSSize(width:width,height:48)
    }
}

private final class LuminTypeValueRow:NSStackView {
    let slider:LuminSlider
    let input=NSTextField()
    var onChange:((Double)->Void)?
    let unit:String
    init(value:Double,unit:String) {
        self.unit=unit; slider=LuminSlider(value:value,min:unit=="%" ? 0:0.1,max:unit=="%" ? 100:20,opacity:unit=="%")
        super.init(frame:.zero); orientation = .horizontal; alignment = .centerY; spacing=16
        if unit=="pt" { let icon=NSImageView(image:LuminAssets.tool("Stroke") ?? NSImage()); icon.contentTintColor=PodTheme.secondaryText; icon.widthAnchor.constraint(equalToConstant:24).isActive=true; addArrangedSubview(icon) }
        slider.target=self; slider.action=#selector(change); slider.setAccessibilityLabel(unit=="%" ? "Opacity":"Border width"); addArrangedSubview(slider)
        let field=NSStackView(); field.orientation = .horizontal; field.spacing=2; field.edgeInsets=NSEdgeInsets(top:0,left:4,bottom:0,right:8); field.wantsLayer=true; field.layer?.cornerRadius=8; field.layer?.borderWidth=1
        field.widthAnchor.constraint(equalToConstant:60).isActive=true; field.heightAnchor.constraint(equalToConstant:32).isActive=true
        input.stringValue=String(format:unit=="%" ? "%.0f":"%g",value); input.font=LuminAssets.font(12); input.textColor=PodTheme.secondaryText; input.isBordered=false; input.drawsBackground=false; input.alignment = .right; input.target=self; input.action=#selector(change); input.setAccessibilityLabel(unit=="%" ? "Opacity percent":"Border width points")
        let suffix=NSTextField(labelWithString:unit); suffix.font=LuminAssets.font(12); suffix.textColor=PodTheme.secondaryText
        field.addArrangedSubview(input); field.addArrangedSubview(suffix); addArrangedSubview(field)
        heightAnchor.constraint(equalToConstant:32).isActive=true; field.layer?.borderColor=PodTheme.border.cgColor
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func change(_ sender:NSControl) { let value=min(slider.maxValue,max(0,sender.doubleValue)); slider.doubleValue=value; input.stringValue=String(format:unit=="%" ? "%.0f":"%g",value); onChange?(value) }
}

private final class LuminTypeOpacityMenu:NSViewController {
    let initial:Double
    var onChange:((Double)->Void)?
    init(value:Double) { initial=value; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { let root=PodSurfaceStack(); root.surface=PodTheme.raised; root.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8); let row=LuminTypeValueRow(value:initial*100,unit:"%"); row.widthAnchor.constraint(equalToConstant:288).isActive=true; row.onChange={ [weak self] value in self?.onChange?(value/100) }; root.addArrangedSubview(row); view=root; preferredContentSize=NSSize(width:304,height:48) }
}

private final class LuminTypeFrameMenu:NSViewController {
    var state:LuminTypeState
    var onChange:((NSColor?,NSColor,Double)->Void)?
    init(state:LuminTypeState) { self.state=state; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=PodSurfaceStack(); root.surface=PodTheme.raised; root.orientation = .vertical; root.alignment = .leading; root.spacing=8; root.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        func heading(_ name:String) { let label=NSTextField(labelWithString:name); label.font=LuminAssets.font(14,500); label.textColor=PodTheme.text; label.heightAnchor.constraint(equalToConstant:20).isActive=true; root.addArrangedSubview(label) }
        heading("Fill")
        let fill=LuminTypeColorRow(color:state.fill,noFill:true); fill.widthAnchor.constraint(equalToConstant:288).isActive=true; fill.onChange={ [weak self] value in self?.state.fill=value; self?.changed() }; root.addArrangedSubview(fill); root.setCustomSpacing(16,after:fill)
        heading("Stroke")
        let stroke=LuminTypeColorRow(color:state.stroke); stroke.widthAnchor.constraint(equalToConstant:288).isActive=true; stroke.onChange={ [weak self] value in if let value { self?.state.stroke=value; self?.changed() } }; root.addArrangedSubview(stroke)
        let width=LuminTypeValueRow(value:state.strokeWidth,unit:"pt"); width.widthAnchor.constraint(equalToConstant:288).isActive=true; width.onChange={ [weak self] value in self?.state.strokeWidth=value; self?.changed() }; root.addArrangedSubview(width)
        view=root; preferredContentSize=NSSize(width:304,height:192)
    }
    private func changed() { onChange?(state.fill,state.stroke,state.strokeWidth) }
}

private final class LuminTypeFlippedStack:NSStackView { override var isFlipped:Bool { true } }

private class LuminTypeHoverButton:NSButton {
    private var hovered=false
    private var area:NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let area { removeTrackingArea(area) }
        let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); area=next
    }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        if hovered || isHighlighted { PodTheme.text.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill() }
    }
}
