import AppKit

private let markupAccent=PodTheme.text
private func caption(_ text:String) -> NSTextField {
    let label=NSTextField(labelWithString:text); label.font = LuminAssets.font(14,520); label.textColor=LuminLegacyStyle.text; label.heightAnchor.constraint(equalToConstant:23.796875).isActive=true; return label
}
final class SwatchButton:NSButton {
    override var allowsVibrancy:Bool { false }
    var swatch:NSColor?
    var selected=false
    override func draw(_ dirtyRect:NSRect) {
        let circle=NSBezierPath(ovalIn:bounds.insetBy(dx:3.5,dy:3.5))
        (swatch ?? .clear).setFill(); circle.fill()
        PodTheme.border.setStroke(); circle.lineWidth=1; circle.stroke()
        if swatch == nil {
            PodTheme.color(0xF2385A).setStroke(); let slash=NSBezierPath(); let delta=(bounds.width-6)/sqrt(8); slash.move(to:CGPoint(x:bounds.midX-delta,y:bounds.midY-delta)); slash.line(to:CGPoint(x:bounds.midX+delta,y:bounds.midY+delta)); slash.lineWidth=1; slash.stroke()
        }
        if selected { markupAccent.setStroke(); let ring=NSBezierPath(ovalIn:bounds.insetBy(dx:0.5,dy:0.5)); ring.lineWidth=1; ring.stroke() }
    }
}
// Fractional line boxes are retained explicitly; NSStackView.fittingSize rounds them up.
final class MarkupStyleView:NSView {
    var style:MarkupStyle
    let kind:MarkupKind
    let contentWidth:CGFloat
    var onChange:((MarkupStyle)->Void)?
    var onLayoutChange:(()->Void)?
    private var fillMode=false
    private var swatches:[SwatchButton]=[]
    private var presetColors:[NSColor]=[]
    private let colors=LuminPaletteColorRow()
    private let colorTrigger=LuminPaletteColorPickerButton()
    private var customPicker:LuminPopper?
    private var tabs:LuminPaletteTabs?
    private var styleHeading:NSTextField?
    private var opacityHeading:NSTextField?
    private var strokeRow:LuminPaletteValueRow?
    private let opacityRow:LuminPaletteValueRow
    private let widthSlider=LuminSlider(value:2,min:0.1,max:20,sourcePalette:true)
    private let opacitySlider:LuminSlider
    private let widthInput=NSTextField(string:"2")
    private let opacityInput=NSTextField(string:"100")
    private let fontInput=NSTextField(string:"14")
    private let allowsAutoFontSize:Bool
    private var fontRow:NSStackView?
    private var heightConstraint:NSLayoutConstraint?
    override var isFlipped:Bool { true }
    var contentHeight:CGFloat {
        if kind.isShape { return 180.390625+(fillMode ? 0:40) }
        if kind.isFreehand { return 80+opacityRow.rowHeight }
        if kind == .freeText { return 80+opacityRow.rowHeight }
        return 32+(kind.isTextMarkup ? 16:8)+opacityRow.rowHeight
    }
    init(kind:MarkupKind,style:MarkupStyle,allowsAutoFontSize:Bool=true) {
        self.allowsAutoFontSize=allowsAutoFontSize && kind == .freeText
        self.kind=kind; self.style=style; contentWidth=kind == .ink ? 272:268
        let nested=[MarkupKind.highlight,.freehandHighlight].contains(kind)
        opacitySlider=LuminSlider(value:100,min:0,max:100,opacity:true,sourcePalette:true,height:nested ? 32:32.796875)
        opacityRow=LuminPaletteValueRow(slider:opacitySlider,input:opacityInput,unit:"%",nested:nested)
        super.init(frame:.zero)
        widthAnchor.constraint(equalToConstant:contentWidth).isActive=true
        if kind.isShape {
            let supported = ![MarkupKind.line,.arrow,.polyline,.cross,.tick].contains(kind)
            fillMode=supported
            let heading=caption("Style"),opacity=caption("Opacity"),tabs=LuminPaletteTabs(fillSupported:supported)
            styleHeading=heading; opacityHeading=opacity; self.tabs=tabs
            tabs.onChange={ [weak self] index in self?.fillMode=index==0; self?.refresh() }
            for child in [heading,tabs,opacity] { addSubview(child) }
        }
        let highlight=kind == .highlight || kind == .freehandHighlight
        let values:[UInt32]=highlight ? [0xFEE08B,0xFC8D59,0xFFFFBF,0xE6F598,0x99D594,0x3288BD,0xD53E4F]:[0x000000,0xD73027,0x4575B4,0x5AB4AC,0xFEE090,0xE0F3F8,0xFFFFFF]
        presetColors=values.map{PodTheme.color($0)}
        let names=highlight ? ["No fill","Yellow","Orange","Cream","Lime","Green","Blue","Red"]:["No fill","Black","Red","Blue","Teal","Yellow","Light blue","White"]
        for (i,color) in ([nil]+values.map{Optional(PodTheme.color($0))}).enumerated() {
            let button=SwatchButton(); button.swatch=color; button.tag=i; button.target=self; button.action=#selector(colorPicked); button.isBordered=false; button.setButtonType(.momentaryChange)
            button.setAccessibilityLabel(names[i]); button.toolTip=names[i]; colors.addSubview(button); swatches.append(button)
        }
        colorTrigger.image=LuminAssets.bitmap("color-picker"); colorTrigger.isBordered=false; colorTrigger.target=self; colorTrigger.action=#selector(showCustomColor); colorTrigger.setAccessibilityLabel("Custom color")
        colors.addSubview(colorTrigger); colors.swatches=swatches; colors.picker=colorTrigger; addSubview(colors)
        if !kind.isTextMarkup && !kind.isText {
            let row=LuminPaletteValueRow(slider:widthSlider,input:widthInput,unit:"pt",nested:nested)
            strokeRow=row; addSubview(row); widthSlider.target=self; widthSlider.action=#selector(widthChanged); widthSlider.setAccessibilityLabel("Line width")
            widthInput.target=self; widthInput.action=#selector(widthChanged); widthInput.setAccessibilityLabel("Line width points")
        }
        if kind == .freeText {
            let row=NSStackView(); row.spacing=8; row.addArrangedSubview(caption("Courier")); fontInput.widthAnchor.constraint(equalToConstant:60).isActive=true; fontInput.target=self; fontInput.action=#selector(fontChanged); fontInput.setAccessibilityLabel("Text size"); row.addArrangedSubview(fontInput); row.addArrangedSubview(caption("pt")); addSubview(row); fontRow=row
        }
        addSubview(opacityRow); opacitySlider.target=self; opacitySlider.action=#selector(opacityChanged); opacitySlider.setAccessibilityLabel("Opacity")
        opacityInput.target=self; opacityInput.action=#selector(opacityChanged); opacityInput.setAccessibilityLabel("Opacity percent")
        heightConstraint=heightAnchor.constraint(equalToConstant:contentHeight); heightConstraint?.isActive=true
        refresh()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize:NSSize { NSSize(width:contentWidth,height:contentHeight) }
    override func layout() {
        super.layout()
        if kind.isShape {
            styleHeading?.frame=NSRect(x:0,y:0,width:contentWidth,height:23.796875)
            tabs?.frame=NSRect(x:0,y:31.796875,width:contentWidth,height:32)
            colors.frame=NSRect(x:0,y:71.796875,width:contentWidth,height:32)
            strokeRow?.frame=NSRect(x:0,y:111.796875,width:contentWidth,height:32)
            let offset:CGFloat=fillMode ? 0:40
            opacityHeading?.frame=NSRect(x:0,y:119.796875+offset,width:contentWidth,height:23.796875)
            opacityRow.frame=NSRect(x:0,y:147.59375+offset,width:contentWidth,height:opacityRow.rowHeight)
        } else {
            let leading=kind.isFreehand ? CGFloat(40):0
            strokeRow?.frame=NSRect(x:0,y:0,width:contentWidth,height:32)
            colors.frame=NSRect(x:0,y:leading,width:contentWidth,height:32)
            fontRow?.frame=NSRect(x:0,y:40,width:contentWidth,height:32)
            let opacityY=kind.isFreehand || kind == .freeText ? 80:32+(kind.isTextMarkup ? 16:8)
            opacityRow.frame=NSRect(x:0,y:CGFloat(opacityY),width:contentWidth,height:opacityRow.rowHeight)
        }
    }
    func setStyle(_ value:MarkupStyle) { style=value; refresh() }
    private func refresh() {
        strokeRow?.isHidden=fillMode
        widthSlider.doubleValue=style.width; widthInput.stringValue=String(format:"%g",style.width)
        opacitySlider.doubleValue=style.opacity*100; opacityInput.stringValue=String(format:"%.0f",style.opacity*100)
        fontInput.stringValue=style.fontSize == 0 && allowsAutoFontSize ? "Auto":String(format:"%.0f",style.fontSize)
        fontInput.placeholderString=allowsAutoFontSize ? "Auto or pt":nil
        let current=fillMode ? style.fill:style.stroke
        for (button,color) in zip(swatches.dropFirst(),presetColors) { button.swatch=color }
        if let current,!swatches.contains(where:{$0.swatch==current}) {
            let buttons=swatches.filter{$0.swatch != nil},values=swatches.filter{$0.swatch != nil}.dropFirst().compactMap{$0.swatch}+[current]
            for (button,value) in zip(buttons,values) { button.swatch=value; button.setAccessibilityLabel(value.description) }
        }
        for button in swatches { button.selected=(button.swatch == nil && current == nil) || (button.swatch != nil && button.swatch == current); button.isHidden=button.swatch == nil && !fillMode; button.isEnabled=fillMode || button.swatch != nil; button.needsDisplay=true }
        heightConstraint?.constant=contentHeight; invalidateIntrinsicContentSize(); needsLayout=true; colors.needsLayout=true; onLayoutChange?()
    }
    private func changed() { refresh(); onChange?(style) }
    @objc private func colorPicked(_ sender:SwatchButton) { if fillMode { style.fill=sender.swatch } else if let color=sender.swatch { style.stroke=color }; changed() }
    @objc private func showCustomColor() {
        customPicker?.close()
        customPicker=LuminColorPicker.present(from:colorTrigger,color:(fillMode ? style.fill:style.stroke) ?? .clear) { [weak self] color in
            guard let self else { return }; if fillMode { style.fill=color } else { style.stroke=color }; changed()
        }
    }
    @objc private func widthChanged(_ sender:NSControl) { let value=sender.doubleValue; guard value>=0.1,value<=20 else { refresh(); return }; style.width=value.rounded(); changed() }
    @objc private func opacityChanged(_ sender:NSControl) { let value=(sender as? NSTextField).flatMap{Double($0.stringValue)} ?? (sender is NSTextField ? .nan:sender.doubleValue); guard value.isFinite else { refresh(); return }; style.opacity=min(100,max(0,value)).rounded()/100; changed() }
    @objc private func fontChanged() {
        if allowsAutoFontSize && fontInput.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == "auto" { style.fontSize=0 }
        else if let size=Double(fontInput.stringValue),size.isFinite { style.fontSize=allowsAutoFontSize && size == 0 ? 0:min(72,max(6,size)) }
        else { refresh();return }
        changed()
    }
}

private final class LuminPaletteSurface:PodSurfaceView {
    var contentSize=NSSize.zero
    override var isFlipped:Bool { true }
    override var fittingSize:NSSize { contentSize }
    override var intrinsicContentSize:NSSize { contentSize }
}
final class MarkupPalette:NSViewController {
    let kinds:[MarkupKind]
    var current:MarkupKind
    var style:MarkupStyle
    var onChoose:((MarkupKind)->MarkupStyle)?
    var onStyle:((MarkupStyle)->Void)?
    private var styles:MarkupStyleView?
    private var toolButtons:[LuminLegacyIconButton]=[]
    init(kinds:[MarkupKind],current:MarkupKind,style:MarkupStyle) { self.kinds=kinds; self.current=current; self.style=style; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { rebuild() }
    override func viewDidLayout() { super.viewDidLayout(); updateSize() }
    private func updateSize() {
        guard let styles else { return }
        let y:CGFloat=kinds.count>1 ? (kinds.first?.isShape == true ? 135.796875:81):16
        styles.frame=NSRect(x:16,y:y,width:styles.contentWidth,height:styles.contentHeight)
        let size=NSSize(width:styles.contentWidth+32,height:y+styles.contentHeight+16)
        (view as? LuminPaletteSurface)?.contentSize=size
        if preferredContentSize != size { preferredContentSize=size }
    }
    func setStyle(_ value:MarkupStyle) { style=value; styles?.setStyle(value); updateToolColor() }
    private func updateToolColor() { toolButtons.filter{$0.isSelected}.forEach{$0.selectedGlyphColor=style.stroke; $0.needsDisplay=true} }
    private func rebuild() {
        let root=LuminPaletteSurface(); root.surface=PodTheme.raised; toolButtons=[]
        if kinds.count>1 {
            let shape=kinds.first?.isShape == true,heading=caption(shape ? "Shape":"Choose style")
            heading.frame=NSRect(x:16,y:shape ? 16:20.1015625,width:shape ? 268:156,height:23.796875); root.addSubview(heading)
            for (i,kind) in kinds.enumerated() {
                let button=LuminLegacyIconButton(); button.target=self; button.action=#selector(pick); button.image=LuminAssets.markup(kind); button.tag=Int(kind.rawValue); button.toolTip=kind.title; button.setAccessibilityLabel(kind.title); button.isSelected=kind == current; button.selectedGlyphColor=style.stroke
                button.frame=NSRect(x:shape ? 16+CGFloat(i%7)*40:172+CGFloat(i)*40,y:shape ? 47.796875+CGFloat(i/7)*40:16,width:32,height:32)
                root.addSubview(button); toolButtons.append(button)
            }
            if !shape { let divider=PodSurfaceView(); divider.surface=LuminLegacyStyle.outline; divider.frame=NSRect(x:16,y:64,width:268,height:1); root.addSubview(divider) }
        }
        let styles=MarkupStyleView(kind:current,style:style); self.styles=styles
        let configuredKind=current
        styles.onChange={ [weak self,weak root] value in
            guard let self,let root,self.current==configuredKind,self.view === root else { return }
            self.style=value; self.updateToolColor(); self.onStyle?(value)
        }
        styles.onLayoutChange={ [weak self] in self?.updateSize() }
        root.addSubview(styles); view=root; updateSize()
    }
    @objc private func pick(_ sender:NSButton) {
        guard let kind=MarkupKind(rawValue:UInt32(sender.tag)) else { return }
        current=kind; style=onChoose?(kind) ?? .initial(for:kind); rebuild()
    }
}

final class LuminPaletteColorRow:NSView {
    var swatches:[SwatchButton]=[]
    weak var picker:NSButton?
    override var isFlipped:Bool { true }
    override func layout() {
        super.layout()
        let visible=swatches.filter{!$0.isHidden},count=CGFloat(visible.count)
        let gap=count>0 ? (bounds.width-count*22-32)/count:0
        for (i,button) in visible.enumerated() { button.frame=NSRect(x:CGFloat(i)*(22+gap)-3,y:2,width:28,height:28) }
        picker?.frame=NSRect(x:bounds.width-32,y:0,width:32,height:32)
    }
}

// Shared legacy rows preserve the browser's line-box height and independent26px MUI root.
final class LuminPaletteValueRow:NSView {
    let slider:LuminSlider
    let input:NSTextField
    let unit:String
    let rowHeight:CGFloat
    private let field:LuminNumberFrame
    private let glyph:NSImageView?
    private let nested:Bool
    override var isFlipped:Bool { true }
    init(slider:LuminSlider,input:NSTextField,unit:String,nested:Bool=false,hideInput:Bool=false) {
        self.slider=slider; self.input=input; self.unit=unit; self.nested=nested
        rowHeight=unit=="%" && !nested ? 32.796875:32
        field=LuminNumberFrame(input:input,unit:unit)
        glyph=unit=="pt" ? NSImageView(image:LuminAssets.tool("Stroke") ?? NSImage()):nil
        super.init(frame:.zero)
        addSubview(slider); addSubview(field); field.isHidden=hideInput
        if let glyph { glyph.contentTintColor=LuminLegacyStyle.text; addSubview(glyph) }
        heightAnchor.constraint(equalToConstant:rowHeight).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let start:CGFloat=glyph==nil ? 0:40,tail:CGFloat=field.isHidden ? 0:76
        glyph?.frame=NSRect(x:0,y:4,width:24,height:24)
        slider.frame=NSRect(x:start,y:0,width:bounds.width-start-tail,height:rowHeight)
        field.frame=NSRect(x:bounds.width-60,y:unit=="pt" ? (nested ? 0:0.3984375):0,width:60,height:32)
    }
}

final class LuminPaletteColorPickerButton:NSButton {
    override var intrinsicContentSize:NSSize { NSSize(width:32,height:32) }
    override func draw(_ dirtyRect:NSRect) {
        image?.draw(in:NSRect(x:4,y:4,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}

private final class LuminNumberFrame:NSView,NSTextFieldDelegate {
    let input:NSTextField
    let suffix:NSTextField
    let suffixWidth:CGFloat
    private var hovered=false,focused=false
    private var hoverArea:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var allowsVibrancy:Bool { false }
    override var wantsDefaultClipping:Bool { false }
    init(input:NSTextField,unit:String) {
        self.input=input; suffix=NSTextField(labelWithString:unit); suffixWidth=unit=="%" ? 13.6875:13.015625
        super.init(frame:.zero)
        input.font=LuminAssets.font(14,420); input.textColor=LuminLegacyStyle.variant; input.isBordered=false; input.drawsBackground=false; input.alignment = .center; input.focusRingType = .none; input.delegate=self
        suffix.font=LuminAssets.font(14,420); suffix.textColor=LuminLegacyStyle.variant
        addSubview(input); addSubview(suffix)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let hoverArea { removeTrackingArea(hoverArea) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(area); hoverArea=area
    }
    private func updateColors() { let color=hovered || focused ? LuminLegacyStyle.text:LuminLegacyStyle.variant; input.textColor=color; suffix.textColor=color; needsDisplay=true }
    override func mouseEntered(with event:NSEvent) { hovered=true; updateColors() }
    override func mouseExited(with event:NSEvent) { hovered=false; updateColors() }
    func controlTextDidBeginEditing(_ notification:Notification) { focused=true; updateColors() }
    func controlTextDidEndEditing(_ notification:Notification) { focused=false; updateColors() }
    override func layout() {
        super.layout()
        input.frame=NSRect(x:9,y:1,width:42-suffixWidth,height:30)
        suffix.frame=NSRect(x:51-suffixWidth,y:5.5,width:suffixWidth,height:21)
    }
    override func draw(_ dirtyRect:NSRect) {
        if focused { LuminLegacyStyle.secondaryContainer.setStroke(); let ring=NSBezierPath(roundedRect:bounds.insetBy(dx:-1,dy:-1),xRadius:9,yRadius:9); ring.lineWidth=2; ring.stroke() }
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8)
        if hovered { LuminLegacyStyle.text.withAlphaComponent(0.08).setFill(); path.fill() }
        (focused ? LuminLegacyStyle.secondary:LuminLegacyStyle.outline).setStroke(); path.lineWidth=1; path.stroke()
    }
}

private final class LuminPaletteTabs:NSView {
    private let buttons:[LuminPaletteTab]
    var onChange:((Int)->Void)?
    override var isFlipped:Bool { true }
    init(fillSupported:Bool) {
        buttons=[LuminPaletteTab(title:"Fill",target:nil,action:nil),LuminPaletteTab(title:"Border line",target:nil,action:nil)]
        super.init(frame:.zero)
        for (i,button) in buttons.enumerated() { button.tag=i; button.target=self; button.action=#selector(pick); button.selected=i==(fillSupported ? 0:1); addSubview(button) }
        buttons[0].isEnabled=fillSupported
        heightAnchor.constraint(equalToConstant:32).isActive=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); for (i,b) in buttons.enumerated() { b.frame=NSRect(x:CGFloat(i)*bounds.width/2,y:0,width:bounds.width/2,height:32.1015625) } }
    override func draw(_ dirtyRect:NSRect) { LuminLegacyStyle.container.setFill(); NSBezierPath(roundedRect:bounds,xRadius:16,yRadius:16).fill() }
    @objc private func pick(_ sender:LuminPaletteTab) { for b in buttons { b.selected=b===sender }; onChange?(sender.tag) }
}

private final class LuminPaletteTab:NSButton {
    var selected=false { didSet { needsDisplay=true; setAccessibilityValue(selected ? "Selected":"Not selected") } }
    override func draw(_ dirtyRect:NSRect) {
        if selected { LuminLegacyStyle.selected.setFill(); NSBezierPath(roundedRect:bounds,xRadius:16,yRadius:16).fill() }
        let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,520),.foregroundColor:(selected ? PodTheme.selectedText:LuminLegacyStyle.variant).withAlphaComponent(isEnabled ? 1:0.5)]
        let size=(title as NSString).size(withAttributes:attrs)
        (title as NSString).draw(in:NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height),withAttributes:attrs)
    }
}

final class LuminEraserPalette:NSViewController {
    private(set) var size:Double
    var onChange:((Double)->Void)?
    var onMode: ((Markup.EraserMode) -> Void)?
    private var mode: Markup.EraserMode
    let slider:LuminSlider
    init(size:Double=16, mode:Markup.EraserMode = .stroke) { self.size=size; self.mode=mode; slider=LuminSlider(value:size,min:8,max:32,sourcePalette:true); super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminPaletteSurface(); root.surface=PodTheme.raised; root.contentSize=NSSize(width:312,height:100)
        let row=LuminPaletteValueRow(slider:slider,input:NSTextField(),unit:"pt",hideInput:true)
        root.addSubview(row); row.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),row.topAnchor.constraint(equalTo:root.topAnchor,constant:16),row.widthAnchor.constraint(equalToConstant:272)])
        slider.numberOfTickMarks=4; slider.allowsTickMarkValuesOnly=true; slider.setAccessibilityLabel("Eraser size"); slider.target=self; slider.action=#selector(change)
        let modes=NSSegmentedControl(labels:["Whole stroke","Precision"],trackingMode:.selectOne,target:self,action:#selector(changeMode(_:)))
        modes.selectedSegment=mode == .stroke ? 0:1
        modes.setAccessibilityLabel("Eraser mode")
        modes.frame=NSRect(x:16,y:56,width:280,height:28)
        root.addSubview(modes)
        view=root; preferredContentSize=NSSize(width:312,height:100)
    }
    @objc private func changeMode(_ sender:NSSegmentedControl) {
        mode = sender.selectedSegment == 0 ? .stroke : .precision
        onMode?(mode)
    }
    @objc private func change() { size=min(32,max(8,(slider.doubleValue/8).rounded()*8)); slider.doubleValue=size; onChange?(size) }
}
