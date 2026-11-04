import AppKit

private let markupAccent=NSColor(srgbRed:8/255,green:113/255,blue:145/255,alpha:1)
private func caption(_ text:String) -> NSTextField {
    let label=NSTextField(labelWithString:text); label.font = .systemFont(ofSize:13,weight:.medium); return label
}
private final class PaletteStack:NSStackView {
    override var allowsVibrancy:Bool { false }
    override var isOpaque:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        (dark ? NSColor(srgbRed:40/255,green:43/255,blue:44/255,alpha:1):NSColor.windowBackgroundColor).setFill(); bounds.fill()
    }
}
final class SwatchButton:NSButton {
    override var allowsVibrancy:Bool { false }
    var swatch:NSColor?
    var selected=false
    override func draw(_ dirtyRect:NSRect) {
        let circle=NSBezierPath(ovalIn:bounds.insetBy(dx:5,dy:5))
        (swatch ?? .clear).setFill(); circle.fill()
        NSColor.secondaryLabelColor.withAlphaComponent(0.4).setStroke(); circle.lineWidth=1; circle.stroke()
        if swatch == nil {
            NSColor.systemRed.setStroke(); let slash=NSBezierPath(); slash.move(to:CGPoint(x:7,y:7)); slash.line(to:CGPoint(x:bounds.width-7,y:bounds.height-7)); slash.lineWidth=1.5; slash.stroke()
        }
        if selected { markupAccent.setStroke(); let ring=NSBezierPath(ovalIn:bounds.insetBy(dx:2,dy:2)); ring.lineWidth=2; ring.stroke() }
    }
}
final class MarkupStyleView:NSStackView {
    var style:MarkupStyle
    let kind:MarkupKind
    var onChange:((MarkupStyle)->Void)?
    private var fillMode=false
    private var swatches:[SwatchButton]=[]
    private let widthSlider=NSSlider(value:2,minValue:0.1,maxValue:20,target:nil,action:nil)
    private let opacitySlider=NSSlider(value:100,minValue:0,maxValue:100,target:nil,action:nil)
    private let widthInput=NSTextField(string:"2")
    private let opacityInput=NSTextField(string:"100")
    private let colorWell=NSColorWell()
    private let fontInput=NSTextField(string:"14")
    init(kind:MarkupKind,style:MarkupStyle) {
        self.kind=kind; self.style=style
        super.init(frame:.zero)
        orientation = .vertical; alignment = .leading; spacing=12
        widthAnchor.constraint(equalToConstant:268).isActive=true
        if kind.isShape && ![.line,.arrow,.polyline,.cross,.tick].contains(kind) {
            addArrangedSubview(caption("Style"))
            let tabs=NSSegmentedControl(labels:["Fill","Border line"],trackingMode:.selectOne,target:self,action:#selector(tabChanged))
            tabs.segmentStyle = .rounded; tabs.selectedSegment=1; tabs.widthAnchor.constraint(equalToConstant:268).isActive=true; tabs.heightAnchor.constraint(equalToConstant:32).isActive=true
            addArrangedSubview(tabs)
        }
        let colors:[NSColor?]=[nil,.black,NSColor(srgbRed:215/255,green:48/255,blue:39/255,alpha:1),NSColor(srgbRed:69/255,green:117/255,blue:180/255,alpha:1),NSColor(srgbRed:90/255,green:180/255,blue:172/255,alpha:1),NSColor(srgbRed:254/255,green:224/255,blue:144/255,alpha:1),NSColor(srgbRed:224/255,green:243/255,blue:248/255,alpha:1),.white]
        let row=NSStackView(); row.orientation = .horizontal; row.spacing=0
        for (i,color) in colors.enumerated() {
            let b=SwatchButton(); b.swatch=color; b.tag=i; b.target=self; b.action=#selector(colorPicked); b.isBordered=false; b.setButtonType(.momentaryChange)
            b.widthAnchor.constraint(equalToConstant:29).isActive=true; b.heightAnchor.constraint(equalToConstant:32).isActive=true
            b.setAccessibilityLabel(["No fill","Black","Red","Blue","Teal","Yellow","Light blue","White"][i]); b.toolTip=b.accessibilityLabel()
            row.addArrangedSubview(b); swatches.append(b)
        }
        colorWell.color=style.stroke; colorWell.target=self; colorWell.action=#selector(customColor)
        colorWell.widthAnchor.constraint(equalToConstant:32).isActive=true; colorWell.heightAnchor.constraint(equalToConstant:28).isActive=true; colorWell.setAccessibilityLabel("Custom color"); row.addArrangedSubview(colorWell)
        addArrangedSubview(row)
        if !kind.isTextMarkup && !kind.isText { addArrangedSubview(sliderRow(widthSlider,widthInput,"pt",#selector(widthChanged))); widthSlider.setAccessibilityLabel("Line width") }
        if kind == .freeText {
            let row=NSStackView(); row.spacing=8; row.addArrangedSubview(caption("Courier")); fontInput.widthAnchor.constraint(equalToConstant:60).isActive=true; fontInput.target=self; fontInput.action=#selector(fontChanged); fontInput.setAccessibilityLabel("Text size"); row.addArrangedSubview(fontInput); row.addArrangedSubview(caption("pt")); addArrangedSubview(row)
        }
        addArrangedSubview(caption("Opacity"))
        addArrangedSubview(sliderRow(opacitySlider,opacityInput,"%",#selector(opacityChanged))); opacitySlider.setAccessibilityLabel("Opacity")
        refresh()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private func sliderRow(_ slider:NSSlider,_ input:NSTextField,_ unit:String,_ action:Selector) -> NSStackView {
        let row=NSStackView(); row.orientation = .horizontal; row.spacing=8
        slider.target=self; slider.action=action; slider.isContinuous=false; slider.widthAnchor.constraint(equalToConstant:180).isActive=true
        input.target=self; input.action=action; input.alignment = .right; input.font = .systemFont(ofSize:12); input.widthAnchor.constraint(equalToConstant:48).isActive=true
        input.setAccessibilityLabel(unit == "%" ? "Opacity percent":"Line width points")
        for v in [slider,input,caption(unit)] { row.addArrangedSubview(v) }; return row
    }
    func setStyle(_ value:MarkupStyle) { style=value; refresh() }
    private func refresh() {
        widthSlider.doubleValue=style.width; widthInput.stringValue=String(format:"%.1f",style.width)
        opacitySlider.doubleValue=style.opacity*100; opacityInput.stringValue=String(format:"%.0f",style.opacity*100)
        fontInput.stringValue=String(format:"%.0f",style.fontSize)
        let current=fillMode ? style.fill:style.stroke
        if let current { colorWell.color=current }
        for b in swatches { b.selected=(b.swatch == nil && current == nil) || (b.swatch != nil && b.swatch == current); b.isEnabled=fillMode || b.swatch != nil; b.needsDisplay=true }
    }
    private func changed() { refresh(); onChange?(style) }
    @objc private func tabChanged(_ sender:NSSegmentedControl) { fillMode=sender.selectedSegment==0; refresh() }
    @objc private func colorPicked(_ sender:SwatchButton) { if fillMode { style.fill=sender.swatch } else if let color=sender.swatch { style.stroke=color }; changed() }
    @objc private func customColor() { if fillMode { style.fill=colorWell.color } else { style.stroke=colorWell.color }; changed() }
    @objc private func widthChanged(_ sender:NSControl) { style.width=min(20,max(0.1,sender.doubleValue)); changed() }
    @objc private func opacityChanged(_ sender:NSControl) { style.opacity=min(1,max(0,sender.doubleValue/100)); changed() }
    @objc private func fontChanged() { style.fontSize=min(72,max(6,fontInput.doubleValue)); changed() }
}
final class MarkupPalette:NSViewController {
    let kinds:[MarkupKind]
    var current:MarkupKind
    var style:MarkupStyle
    var onChoose:((MarkupKind)->MarkupStyle)?
    var onStyle:((MarkupStyle)->Void)?
    init(kinds:[MarkupKind],current:MarkupKind,style:MarkupStyle) { self.kinds=kinds; self.current=current; self.style=style; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { rebuild() }
    func setStyle(_ value:MarkupStyle) { style=value; (view as? NSStackView)?.arrangedSubviews.compactMap{$0 as? MarkupStyleView}.forEach{$0.setStyle(value)} }
    private func rebuild() {
        let stack=PaletteStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=16; stack.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        if kinds.count>1 {
            stack.addArrangedSubview(caption(kinds.first?.isShape == true ? "Shape":"Choose style"))
            if kinds.contains(.highlight) {
                for kind in kinds {
                    let title=kind == .freehandHighlight ? "Freehand highlight\nGreat for scanned PDFs":"Text highlight (H)"
                    let b=NSButton(title:title,target:self,action:#selector(pick)); b.tag=Int(kind.rawValue); b.isBordered=false; b.alignment = .left; b.font = .systemFont(ofSize:13); b.image=NSImage(systemSymbolName:kind.symbol,accessibilityDescription:kind.title); b.imagePosition = .imageLeading; b.widthAnchor.constraint(equalToConstant:268).isActive=true; b.heightAnchor.constraint(equalToConstant:kind == .highlight ? 40:59).isActive=true; stack.addArrangedSubview(b)
                }
            } else {
                for start in stride(from:0,to:kinds.count,by:7) {
                    let row=NSStackView(); row.orientation = .horizontal; row.spacing=8
                    for kind in kinds[start..<min(start+7,kinds.count)] {
                        let b=NSButton(image:NSImage(systemSymbolName:kind.symbol,accessibilityDescription:kind.title) ?? NSImage(),target:self,action:#selector(pick)); b.tag=Int(kind.rawValue); b.toolTip=kind.title; b.setAccessibilityLabel(kind.title); b.bezelStyle = .regularSquare; b.isBordered=false; b.wantsLayer=true; b.layer?.cornerRadius=8; b.layer?.backgroundColor=(kind == current ? markupAccent:NSColor.clear).cgColor
                        b.contentTintColor=kind == current ? .white:.labelColor
                        b.widthAnchor.constraint(equalToConstant:32).isActive=true; b.heightAnchor.constraint(equalToConstant:32).isActive=true; row.addArrangedSubview(b)
                    }; stack.addArrangedSubview(row)
                }
            }
        }
        let styles=MarkupStyleView(kind:current,style:style)
        let configuredKind=current
        styles.onChange={ [weak self, weak stack] value in
            guard let self,let stack,self.current==configuredKind,self.view === stack else { return }
            self.style=value; self.onStyle?(value)
        }
        stack.addArrangedSubview(styles)
        view=stack; preferredContentSize=NSSize(width:300,height:stack.fittingSize.height)
    }
    @objc private func pick(_ sender:NSButton) {
        guard let kind=MarkupKind(rawValue:UInt32(sender.tag)) else { return }
        current=kind; style = onChoose?(kind) ?? .initial(for:kind); rebuild()
    }
}
