import AppKit

// Source ChromePicker override: 205px, hidden alpha control, explicit confirmation.
final class LuminColorPicker:NSViewController {
    var onConfirm:((NSColor)->Void)?
    var onCancel:(()->Void)?
    private var color:NSColor
    private enum Format { case hex,rgb,hsl }
    private var format:Format
    private var hue:CGFloat=0
    private let saturation=LuminSaturationControl()
    private let hueControl=LuminHueControl()
    private let preview=LuminColorPreview()
    private var inputs:[LuminColorInput]=[]
    private var labels:[NSTextField]=[]

    init(color:NSColor) { self.color=color.usingColorSpace(.sRGB) ?? .black; format=color.alphaComponent==1 ? .hex:.rgb; super.init(nibName:nil,bundle:nil); title="Custom color" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminColorPickerView(frame:NSRect(x:0,y:0,width:205,height:297.7421875))
        saturation.frame=NSRect(x:8,y:8,width:189,height:103.9453125); saturation.setAccessibilityLabel("Saturation and brightness")
        saturation.setAccessibilityElement(true)
        saturation.onChange={ [weak self] s,b in guard let self else { return }; color=Self.hsv(hue:hue,saturation:s,brightness:b).withAlphaComponent(color.alphaComponent); refresh() }
        root.addSubview(saturation)
        preview.frame=NSRect(x:8,y:127.9453125,width:10,height:10); root.addSubview(preview)
        hueControl.frame=NSRect(x:30,y:127.9453125,width:167,height:10); hueControl.setAccessibilityLabel("Hue")
        hueControl.setAccessibilityElement(true)
        hueControl.onChange={ [weak self] value in guard let self else { return }; hue=value; color=Self.hsv(hue:value,saturation:saturation.saturation,brightness:saturation.brightness).withAlphaComponent(color.alphaComponent); refresh() }; root.addSubview(hueControl)
        for index in 0..<3 {
            let input=LuminColorInput(frame:NSRect(x:8+CGFloat(index)*54.33203125,y:157.4453125,width:48.33203125,height:21))
            input.tag=index; input.target=self; input.action=#selector(channelChanged); input.delegate=self
            let label=NSTextField(labelWithString:""); label.frame=NSRect(x:input.frame.minX,y:190.7421875,width:input.frame.width,height:15)
            label.alignment = .center; label.font=LuminAssets.font(12,400); label.textColor=PodTheme.pickerText
            inputs.append(input); labels.append(label); root.addSubview(input); root.addSubview(label)
        }
        let toggle=LuminPickerButton(frame:NSRect(x:165,y:165.9453125,width:24,height:24)); toggle.image=LuminAssets.bitmap("color-format"); toggle.target=self; toggle.action=#selector(toggleFormat); toggle.setAccessibilityLabel("Switch color format"); toggle.toolTip="Switch color format"; root.addSubview(toggle)
        let confirm=LuminPickerButton(frame:NSRect(x:8,y:217.7421875,width:189,height:32)); confirm.title="Confirm"; confirm.filled=true; confirm.target=self; confirm.action=#selector(confirmColor); confirm.setAccessibilityLabel("Confirm"); root.addSubview(confirm)
        let cancel=LuminPickerButton(frame:NSRect(x:8,y:257.7421875,width:189,height:32)); cancel.title="Cancel"; cancel.outlined=true; cancel.target=self; cancel.action=#selector(cancelColor); cancel.setAccessibilityLabel("Cancel"); root.addSubview(cancel)
        view=root; preferredContentSize=root.frame.size; refresh()
    }
    static func present(from anchor:NSView,color:NSColor,onConfirm:@escaping (NSColor)->Void)->LuminPopper {
        let picker=LuminColorPicker(color:color),pop=LuminPopper()
        pop.alignment = .center; pop.gap=8; pop.contentViewController=picker
        picker.onConfirm={ [weak pop] value in pop?.close(); onConfirm(value) }
        picker.onCancel={ [weak pop] in pop?.close() }
        pop.show(relativeTo:anchor.bounds,of:anchor); return pop
    }
    private func refresh() {
        let c=color.usingColorSpace(.sRGB)!,r=c.redComponent,g=c.greenComponent,b=c.blueComponent
        var s:CGFloat=0,v:CGFloat=0,h:CGFloat=0,a:CGFloat=0
        c.getHue(&h,saturation:&s,brightness:&v,alpha:&a)
        if s>0 && v>0 { hue=h }
        saturation.hue=hue; saturation.saturation=s; saturation.brightness=v; saturation.needsDisplay=true
        hueControl.hue=hue; hueControl.needsDisplay=true; preview.color=color; preview.needsDisplay=true
        let names=format == .hsl ? ["H","S","L"]:["R","G","B"]
        let maxValue=max(r,g,b),minValue=min(r,g,b),light=(maxValue+minValue)/2
        let sat=maxValue==minValue ? 0:(maxValue-minValue)/(1-abs(2*light-1))
        let values=format == .hsl ? [String(Int((hue*360).rounded())),"\(Int((sat*100).rounded()))%","\(Int((light*100).rounded()))%"]:[r,g,b].map{String(Int(($0*255).rounded()))}
        for i in 0..<3 {
            inputs[i].isHidden=format == .hex && i>0; labels[i].isHidden=inputs[i].isHidden
            inputs[i].frame.size.width=format == .hex && i==0 ? 157:48.33203125; labels[i].frame.size.width=inputs[i].frame.width
            inputs[i].stringValue=format == .hex && i==0 ? String(format:"#%02X%02X%02X",Int((r*255).rounded()),Int((g*255).rounded()),Int((b*255).rounded())):values[i]
            let name=format == .hex && i==0 ? "HEX":names[i]
            inputs[i].setAccessibilityLabel(name); labels[i].stringValue=name
        }
        saturation.setAccessibilityValue("Saturation \(Int(s*100))%, brightness \(Int(v*100))%")
        hueControl.setAccessibilityValue(hue*360)
    }
    @objc private func toggleFormat() { switch format { case .hex:format = .rgb; case .rgb:format = .hsl; case .hsl:format=color.alphaComponent==1 ? .hex:.rgb }; refresh() }
    @objc private func channelChanged(_ sender:NSTextField) {
        if format == .hex {
            var value=inputs[0].stringValue.trimmingCharacters(in:.whitespaces)
            if value.hasPrefix("#") { value.removeFirst() }
            if value.count==3 { value=value.map{String(repeating:String($0),count:2)}.joined() }
            guard value.count==6,let hex=UInt32(value,radix:16) else { refresh(); return }
            color=PodTheme.color(hex); refresh(); return
        }
        let values=inputs.map{Double($0.stringValue.replacingOccurrences(of:"%",with:"").trimmingCharacters(in:.whitespaces))}
        guard values.allSatisfy({$0?.isFinite==true}) else { refresh(); return }
        let numbers=values.map{$0!}
        if format == .hsl {
            guard (0...360).contains(numbers[0]),numbers.dropFirst().allSatisfy({(0...100).contains($0)}) else { refresh(); return }
            hue=CGFloat(numbers[0]/360)
            color=Self.hslColor(hue:hue,saturation:CGFloat(numbers[1]/100),light:CGFloat(numbers[2]/100))
        } else {
            guard numbers.allSatisfy({(0...255).contains($0)}) else { refresh(); return }
            color=NSColor(srgbRed:CGFloat(numbers[0]/255),green:CGFloat(numbers[1]/255),blue:CGFloat(numbers[2]/255),alpha:1)
        }
        refresh()
    }
    @objc private func confirmColor() { view.window?.makeFirstResponder(nil); onConfirm?(color.withAlphaComponent(1)) }
    @objc private func cancelColor() { onCancel?() }
    private static func hsv(hue:CGFloat,saturation:CGFloat,brightness:CGFloat)->NSColor {
        NSColor(hue:hue,saturation:saturation,brightness:brightness,alpha:1).usingColorSpace(.sRGB)!
    }
    private static func hslColor(hue:CGFloat,saturation:CGFloat,light:CGFloat)->NSColor {
        let chroma=(1-abs(2*light-1))*saturation,h=(hue*6).truncatingRemainder(dividingBy:6)
        let x=chroma*(1-abs(h.truncatingRemainder(dividingBy:2)-1)),m=light-chroma/2
        let channels:[CGFloat]
        switch h { case 0..<1: channels=[chroma,x,0]; case 1..<2: channels=[x,chroma,0]; case 2..<3: channels=[0,chroma,x]; case 3..<4: channels=[0,x,chroma]; case 4..<5: channels=[x,0,chroma]; default: channels=[chroma,0,x] }
        return NSColor(srgbRed:channels[0]+m,green:channels[1]+m,blue:channels[2]+m,alpha:1)
    }
}
extension LuminColorPicker:NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification:Notification) { if let input=notification.object as? NSTextField { channelChanged(input) } }
}

private final class LuminColorPickerView:PodSurfaceView {
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:205,height:297.7421875) }
    override init(frame:NSRect) { super.init(frame:frame); surface=PodTheme.raised }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
}
private final class LuminColorInput:NSTextField {
    override init(frame:NSRect) {
        super.init(frame:frame); isBordered=false; drawsBackground=false; alignment = .center; font=LuminAssets.font(11,400); textColor=PodTheme.pickerText
        focusRingType = .none; wantsLayer=true; layer?.cornerRadius=4; layer?.borderWidth=1; layer?.borderColor=PodTheme.pickerOutline.cgColor
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); layer?.borderColor=PodTheme.pickerOutline.cgColor }
}
private final class LuminPickerButton:NSButton {
    var filled=false,outlined=false
    private var hovered=false
    private var area:NSTrackingArea?
    override init(frame:NSRect) { super.init(frame:frame); isBordered=false; setButtonType(.momentaryPushIn); font=LuminAssets.font(14,500) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let area { removeTrackingArea(area) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); area=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:outlined ? 0.5:0,dy:outlined ? 0.5:0),xRadius:image == nil ? 8:5,yRadius:image == nil ? 8:5)
        if filled { PodTheme.secondary.setFill(); path.fill() }
        if outlined { PodTheme.secondary.setStroke(); path.lineWidth=1; path.stroke() }
        if hovered || isHighlighted { PodTheme.secondary.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); path.fill() }
        if let image { LuminAssets.tinted(image,PodTheme.pickerText).draw(in:bounds); return }
        let attrs:[NSAttributedString.Key:Any]=[.font:font!, .foregroundColor:filled ? PodTheme.onSecondary:PodTheme.secondary]
        let size=(title as NSString).size(withAttributes:attrs)
        (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attrs)
    }
}

private final class LuminColorPreview:NSView {
    var color=NSColor.clear
    override func draw(_ dirtyRect:NSRect) { NSGraphicsContext.saveGraphicsState(); NSBezierPath(ovalIn:bounds).addClip(); if let image=LuminAssets.bitmap("empty") { image.draw(in:bounds) }; color.setFill(); bounds.fill(); NSGraphicsContext.restoreGraphicsState() }
}

private final class LuminSaturationControl:NSControl {
    var hue:CGFloat=0,saturation:CGFloat=0,brightness:CGFloat=0
    var onChange:((CGFloat,CGFloat)->Void)?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func draw(_ rect:NSRect) {
        guard let context=NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect:bounds,xRadius:2,yRadius:2).addClip()
        NSColor(hue:hue,saturation:1,brightness:1,alpha:1).setFill(); bounds.fill()
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        let white=CGGradient(colorsSpace:space,colors:[NSColor.white.cgColor,NSColor.white.withAlphaComponent(0).cgColor] as CFArray,locations:[0,1])!
        context.drawLinearGradient(white,start:.zero,end:NSPoint(x:bounds.width,y:0),options:[])
        let black=CGGradient(colorsSpace:space,colors:[NSColor.black.withAlphaComponent(0).cgColor,NSColor.black.cgColor] as CFArray,locations:[0,1])!
        context.drawLinearGradient(black,start:.zero,end:NSPoint(x:0,y:bounds.height),options:[])
        NSColor.white.setStroke(); let marker=NSBezierPath(ovalIn:NSRect(x:saturation*bounds.width-5.5,y:(1-brightness)*bounds.height-5.5,width:11,height:11)); marker.lineWidth=1; marker.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    private func update(_ event:NSEvent) { let p=convert(event.locationInWindow,from:nil); saturation=min(1,max(0,p.x/bounds.width)); brightness=1-min(1,max(0,p.y/bounds.height)); onChange?(saturation,brightness); needsDisplay=true }
    override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self); update(event) }
    override func mouseDragged(with event:NSEvent) { update(event) }
    override func keyDown(with event:NSEvent) { switch event.keyCode { case 123:saturation=max(0,saturation-0.01); case 124:saturation=min(1,saturation+0.01); case 125:brightness=max(0,brightness-0.01); case 126:brightness=min(1,brightness+0.01); default:super.keyDown(with:event); return }; onChange?(saturation,brightness); needsDisplay=true }
    override func accessibilityRole()->NSAccessibility.Role? { .slider }
}
private final class LuminHueControl:NSControl {
    var hue:CGFloat=0
    var onChange:((CGFloat)->Void)?
    override var acceptsFirstResponder:Bool { true }
    override func draw(_ rect:NSRect) {
        guard let context=NSGraphicsContext.current?.cgContext else { return }
        let gradient=CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:[NSColor.red,NSColor.yellow,NSColor.green,NSColor.cyan,NSColor.blue,NSColor.magenta,NSColor.red].map{$0.cgColor} as CFArray,locations:[0,0.17,0.33,0.5,0.67,0.83,1])!
        context.saveGState(); context.clip(to:bounds)
        context.drawLinearGradient(gradient,start:.zero,end:NSPoint(x:bounds.width,y:0),options:[])
        context.restoreGState()
        let marker=NSBezierPath(ovalIn:NSRect(x:hue*bounds.width-6,y:-1,width:12,height:12))
        let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.37); shadow.shadowOffset=NSSize(width:0,height:-1); shadow.shadowBlurRadius=4
        NSGraphicsContext.saveGraphicsState(); shadow.set(); PodTheme.color(0xF8F8F8).setFill(); marker.fill(); NSGraphicsContext.restoreGraphicsState()
    }
    private func update(_ event:NSEvent) { let p=convert(event.locationInWindow,from:nil); hue=min(1,max(0,p.x/bounds.width)); onChange?(hue); needsDisplay=true }
    override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self); update(event) }
    override func mouseDragged(with event:NSEvent) { update(event) }
    override func keyDown(with event:NSEvent) { switch event.keyCode { case 123,125:hue=max(0,hue-1/360); case 124,126:hue=min(1,hue+1/360); default:super.keyDown(with:event); return }; onChange?(hue); needsDisplay=true }
    override func accessibilityRole()->NSAccessibility.Role? { .slider }
}
