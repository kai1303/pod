import AppKit
import UniformTypeIdentifiers

// Legacy branch from the shipped SignatureModal; no PDF/cloud signature operation.
final class LuminSignatureDialog:NSViewController,NSTextFieldDelegate {
    enum Tab:Int,CaseIterable { case draw,image,type
        var title:String { ["Draw","Image","Type"][rawValue] }
        var glyph:String { ["pdf-icon-md_pen","pdf-icon-md_image","pdf-icon-md_font_size"][rawValue] }
    }
    static let families=["DrSugiyama","AlexBrush","DancingScript","ArchitectsDaughter","HomemadeApple","RockSalt"]
    static let fontNames=["Dr Sugiyama","Alex Brush","Dancing Script","Architects Daughter","Homemade Apple","Rock Salt"]
    static let inputHeights:[CGFloat]=[70,60,57.5,33,52,57.5]
    private(set) var tab:Tab = .draw,fontIndex=0,handwriting:Bool
    private(set) var text="",image:NSImage?,color=NSColor.black,strokeWidth=3.0
    let count:Int,limit:Int
    let input=NSTextField()
    let repeatButton=LuminSignatureRepeatButton()
    let cancel=LuminShareButton("Cancel",style:.outlined),save=LuminShareButton("Save",style:.filled)
    private(set) var controls:[String:NSView]=[:]
    private let board=LuminSignatureBoard()
    private let colorButton=LuminSignatureColorButton()
    private let fontButton=LuminSignatureFontButton()
    private let clear=LuminLegacyIconButton()
    private let penGroup=LuminDialogPaper()
    private var penButtons:[LuminSignaturePenButton]=[]
    private var tabButtons:[LuminSignatureTabButton]=[]
    private var fontLabel:LuminTextLabel!
    private var counter:LuminTextLabel!
    private var errorLabel:LuminTextLabel!
    private let imageButton=LuminShareButton("Change image",style:.filled)
    private var popup:LuminPopper?
    var onCancel:(()->Void)?,onResize:(()->Void)?
    var onSave:((LuminSignaturePreview)->Void)?
    var onRepeatChange:((Bool)->Void)?,onPenModeChange:((Bool)->Void)?
    var repeatsSignature:Bool { repeatButton.isOn }
    var hasError:Bool { text.trimmingCharacters(in:Self.trimSet).utf16.count>50 }
    private static let trimSet=CharacterSet(charactersIn:"\u{9}\u{A}\u{B}\u{C}\u{D} \u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    init(count:Int=0,limit:Int=100,repeatsSignature:Bool=false,handwriting:Bool=true) {
        self.count=count; self.limit=limit; self.handwriting=handwriting; super.init(nibName:nil,bundle:nil); repeatButton.isOn=repeatsSignature
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminDialogPaper(); root.surface=PodTheme.raised; view=root
        func add(_ key:String,_ child:NSView) { root.addSubview(child); controls[key]=child }
        add("title",LuminTextLabel("Create New Signature (\(count)/\(limit))",font:LuminAssets.font(18,520),lineHeight:26.1015625,color:LuminLegacyStyle.text))
        let track=LuminDialogPaper(); track.radius=20; track.surface=LuminLegacyStyle.container; add("tabs",track)
        for item in Tab.allCases {
            let button=LuminSignatureTabButton(item); button.tag=item.rawValue; button.target=self; button.action=#selector(selectTab); track.addSubview(button); tabButtons.append(button); controls["tab."+item.title]=button
        }
        penGroup.surface=PodTheme.color(0xF1F3F5); penGroup.radius=8; add("penGroup",penGroup)
        for (i,title) in ["Handwriting","Classic"].enumerated() { let b=LuminSignaturePenButton(title:title,target:self,action:#selector(selectPen)); b.tag=i; penGroup.addSubview(b); penButtons.append(b); controls[title]=b }
        fontLabel=LuminTextLabel("Change Font",font:LuminAssets.font(14,520),lineHeight:16.1015625,color:LuminLegacyStyle.text); add("fontLabel",fontLabel)
        fontButton.target=self; fontButton.action=#selector(showFonts); add("font",fontButton)
        colorButton.target=self; colorButton.action=#selector(showColors); add("color",colorButton)
        let divider=PodSurfaceView(); divider.surface=LuminLegacyStyle.outline; add("divider",divider)
        clear.glyphName="pdf-icon-md_trash"; clear.target=self; clear.action=#selector(clearDraft); clear.setAccessibilityLabel("Clear signature"); add("clear",clear)
        board.onDrawingChange={ [weak self] in self?.refresh() }; board.onBrowse={ [weak self] in self?.browse() }; board.onImageDrop={ [weak self] in self?.setImage($0) }; add("board",board)
        input.isBordered=false; input.drawsBackground=false; input.focusRingType = .none; input.alignment = .center; input.delegate=self; input.setAccessibilityLabel("Type your Signature here")
        root.addSubview(input); controls["input"]=input
        counter=LuminTextLabel("0/50",font:LuminAssets.font(12,420),lineHeight:18,color:LuminLegacyStyle.variant); add("counter",counter)
        errorLabel=LuminTextLabel("This field must be less than 50 characters.",font:LuminAssets.font(12,420),lineHeight:18,color:LuminSignatureStyle.error); add("error",errorLabel)
        repeatButton.onToggle={ [weak self] value in self?.onRepeatChange?(value) }; add("repeat",repeatButton)
        cancel.onPress={ [weak self] in self?.onCancel?() }; add("cancel",cancel)
        save.onPress={ [weak self] in self?.saveDraft() }; add("save",save)
        imageButton.size=14; imageButton.weight=500; imageButton.horizontalPadding=12; imageButton.onPress={ [weak self] in self?.browse() }; add("changeImage",imageButton)
        refresh()
    }
    override func viewDidLayout() { super.viewDidLayout(); arrange() }
    private var toolbarHeight:CGFloat { tab == .type ? 40:tab == .image && image==nil ? 0:32 }
    private func arrange() {
        guard isViewLoaded else { return }
        let w:CGFloat=880,inner=w-48,toolbar:CGFloat=114.1015625,boardY=toolbar+toolbarHeight+4,footer=boardY+300+8+25.796875
        preferredContentSize=NSSize(width:w,height:footer+64)
        controls["title"]?.frame=NSRect(x:24,y:24,width:inner,height:26.1015625)
        controls["tabs"]?.frame=NSRect(x:24,y:66.1015625,width:inner,height:40)
        let edges:[CGFloat]=[0,277.3359375,554.6640625,832]
        for (i,b) in tabButtons.enumerated() { b.frame=NSRect(x:edges[i],y:0,width:edges[i+1]-edges[i],height:40) }
        penGroup.frame=NSRect(x:24,y:toolbar+1,width:153.9375,height:30)
        penButtons[0].frame=NSRect(x:2,y:2,width:88.9609375,height:26); penButtons[1].frame=NSRect(x:90.9609375,y:2,width:60.9765625,height:26)
        fontLabel.frame=NSRect(x:32,y:toolbar+11.9453125,width:84.1796875,height:16.1015625)
        fontButton.frame=NSRect(x:120.1796875,y:toolbar+4,width:fontButton.intrinsicContentSize.width,height:32)
        let actionY=toolbar+(tab == .type ? 4:0)
        colorButton.frame=NSRect(x:656.171875,y:actionY,width:158.828125,height:32)
        controls["divider"]?.frame=NSRect(x:819,y:actionY+6,width:1,height:20); clear.frame=NSRect(x:824,y:actionY,width:32,height:32)
        board.frame=NSRect(x:24,y:boardY,width:inner,height:300)
        let inputHeight=Self.inputHeights[fontIndex]
        input.frame=NSRect(x:73,y:boardY+238-inputHeight,width:734,height:inputHeight)
        let counterWidth=(counter.text as NSString).size(withAttributes:[.font:LuminAssets.font(12,420)]).width
        counter.frame=NSRect(x:807-counterWidth,y:boardY+238,width:counterWidth,height:18)
        errorLabel.frame=NSRect(x:73,y:boardY+238,width:241.0859375,height:18)
        repeatButton.frame=NSRect(x:24,y:boardY+308,width:226.2734375,height:20)
        cancel.frame=NSRect(x:693.859375,y:footer,width:84.8984375,height:40); save.frame=NSRect(x:786.7578125,y:footer,width:69.2421875,height:40)
        imageButton.frame=NSRect(x:856-imageButton.intrinsicContentSize.width,y:toolbar,width:imageButton.intrinsicContentSize.width,height:32)
        board.needsDisplay=true
    }
    private func refresh() {
        guard isViewLoaded else { return }
        tabButtons.forEach{$0.selected=$0.tab==tab}
        penGroup.isHidden=tab != .draw; penButtons[0].active=handwriting; penButtons[1].active = !handwriting
        let typed=tab == .type
        fontLabel.isHidden = !typed; fontButton.isHidden = !typed; fontButton.title=Self.fontNames[fontIndex]
        colorButton.isHidden=tab == .image; controls["divider"]?.isHidden=tab == .image; clear.isHidden=tab == .image
        clear.isEnabled = tab == .draw ? !board.strokes.isEmpty:!text.isEmpty
        imageButton.isHidden=tab != .image || image==nil
        board.tab=tab; board.image=image; board.handwriting=handwriting; board.color=color; board.strokeWidth=CGFloat(strokeWidth)
        input.isHidden = !typed; counter.isHidden = !typed; errorLabel.isHidden = !typed || !hasError
        let size:CGFloat=fontIndex<3 ? 48:24,font=LuminAssets.signatureFont(Self.families[fontIndex],size:size,bold:strokeWidth>=6)
        input.font=font; input.textColor=color; input.placeholderAttributedString=NSAttributedString(string:"Type your Signature here",attributes:[.font:font,.foregroundColor:PodTheme.color(0x757575)])
        counter.text="\(text.utf16.count)/50"; colorButton.currentColor=color
        save.isEnabled=count<limit && (tab == .draw ? !board.strokes.isEmpty:tab == .image ? image != nil:!text.isEmpty && !hasError)
        arrange(); onResize?()
    }
    func controlTextDidChange(_ notification:Notification) { text=input.stringValue; refresh() }
    func setText(_ value:String) { input.stringValue=value; text=value; refresh() }
    func chooseFont(_ index:Int) { guard Self.families.indices.contains(index) else { return }; fontIndex=index; refresh() }
    func setImage(_ value:NSImage?) { image=value; refresh() }
    func changeTab(_ next:Tab) { popup?.close(); tab=next; text=""; input.stringValue=""; image=nil; fontIndex=0; refresh() }
    @objc private func selectTab(_ sender:NSButton) { if let next=Tab(rawValue:sender.tag) { changeTab(next) } }
    @objc private func selectPen(_ sender:NSButton) { handwriting=sender.tag==0; board.strokes=[]; onPenModeChange?(handwriting); refresh() }
    @objc private func clearDraft() { if tab == .draw { board.strokes=[] } else if tab == .type { text=""; input.stringValue="" } else { image=nil }; refresh() }
    @objc private func showFonts() {
        if popup?.isShown==true && popup?.contentViewController is LuminSignatureFontMenu { popup?.close(); return }; popup?.close()
        let menu=LuminSignatureFontMenu(selected:fontIndex),pop=LuminPopper(); _ = menu.view; pop.contentViewController=menu; pop.alignment = .start; pop.gap=8; pop.initialResponder=menu.rows[fontIndex]; pop.keepsAnchorInteractive=true
        menu.onChoose={ [weak self,weak pop] index in self?.chooseFont(index); pop?.close() }; pop.onKeyDown={ [weak menu] in menu?.handleKey($0) ?? false }; popup=pop
        pop.show(relativeTo:fontButton.bounds,of:fontButton)
    }
    @objc private func showColors() {
        if popup?.isShown==true && popup?.contentViewController is LuminSignatureColorMenu { popup?.close(); return }; popup?.close()
        let menu=LuminSignatureColorMenu(color:color,width:strokeWidth,showsWidth:tab == .draw),pop=LuminPopper(); pop.contentViewController=menu; pop.alignment = .center; pop.gap=8; pop.keepsAnchorInteractive=true
        menu.onChange={ [weak self] color,width in self?.color=color; self?.strokeWidth=width; self?.refresh() }
        colorButton.selected=true; pop.onClose={ [weak self] in self?.colorButton.selected=false }; popup=pop
        pop.show(relativeTo:colorButton.bounds,of:colorButton)
    }
    @objc private func browse() {
        guard let window=view.window else { return }
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.png,.jpeg]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        panel.beginSheetModal(for:window) { [weak self] response in guard response == .OK,let url=panel.url,let image=NSImage(contentsOf:url) else { return }; self?.setImage(image) }
    }
    private func saveDraft() {
        guard save.isEnabled else { return }
        var preview=LuminSignaturePreview(); preview.color=color
        if tab == .type { preview.text=text; preview.family=Self.families[fontIndex] }
        else if tab == .image { preview.image=image }
        else { preview.strokes=board.strokes; preview.width=handwriting ? 8:CGFloat(strokeWidth)*3 }
        onSave?(preview)
    }
    func dismissPickers() { popup?.close() }
    func handleKey(_ event:NSEvent)->Bool {
        guard event.window === view.window,event.keyCode==48 else { return false }
        var order:[NSView]=[tabButtons[tab.rawValue]]
        if tab == .draw { order += penButtons }
        if tab == .type { order.append(fontButton) }
        if tab == .image { order.append(image==nil ? board:imageButton) } else { order += [colorButton,clear] }
        if tab == .type { order.append(input) }; order += [repeatButton,cancel,save]
        let enabled=order.filter{!$0.isHiddenOrHasHiddenAncestor && (($0 as? NSControl)?.isEnabled ?? true)}
        let focused=view.window?.firstResponder,current=enabled.firstIndex{($0 as? NSTextField)?.currentEditor() === focused || $0 === focused}
        let step=event.modifierFlags.contains(.shift) ? -1:1,index=current.map{($0+step+enabled.count)%enabled.count} ?? (step>0 ? 0:enabled.count-1)
        view.window?.makeFirstResponder(enabled[index]); return true
    }
}

private final class LuminSignatureTabButton:NSButton {
    let tab:LuminSignatureDialog.Tab
    var selected=false { didSet { setAccessibilityValue(selected ? "Selected":"Not selected"); needsDisplay=true } }
    override var isFlipped:Bool { true }
    init(_ tab:LuminSignatureDialog.Tab) { self.tab=tab; super.init(frame:.zero); title=tab.title; setAccessibilityLabel(title); isBordered=false; setButtonType(.momentaryPushIn) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect:NSRect) {
        if selected { LuminLegacyStyle.selected.setFill(); NSBezierPath(roundedRect:bounds,xRadius:20,yRadius:20).fill() }
        let color=selected ? PodTheme.selectedText:LuminLegacyStyle.variant,attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,520),.foregroundColor:color],size=(title as NSString).size(withAttributes:attrs),x=(bounds.width-24-4-size.width)/2
        if let image=LuminAssets.icon(tab.glyph) { LuminAssets.tinted(image,color).draw(in:NSRect(x:x,y:8,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:x+28,y:11.9453125,width:size.width,height:16.1015625),withAttributes:attrs)
    }
}
private final class LuminSignaturePenButton:NSButton {
    var active=false { didSet { setAccessibilityValue(active ? "Selected":"Not selected"); needsDisplay=true } }
    override func draw(_ rect:NSRect) {
        if active { NSGraphicsContext.saveGraphicsState(); let shadow=NSShadow(); shadow.shadowOffset=NSSize(width:0,height:1); shadow.shadowBlurRadius=2; shadow.shadowColor=NSColor.black.withAlphaComponent(0.12); shadow.set(); NSColor.white.setFill(); NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill(); NSGraphicsContext.restoreGraphicsState() }
        let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(12,420),.foregroundColor:PodTheme.color(active ? 0x102D42:0x868E96)],size=(title as NSString).size(withAttributes:attrs)
        (title as NSString).draw(in:NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height),withAttributes:attrs)
    }
}
private final class LuminSignatureFontButton:NSButton {
    override var intrinsicContentSize:NSSize { NSSize(width:(title as NSString).size(withAttributes:[.font:LuminAssets.font(12,460)]).width+32,height:32) }
    override func draw(_ rect:NSRect) {
        (title as NSString).draw(in:NSRect(x:8,y:9.1015625,width:bounds.width-32,height:13.796875),withAttributes:[.font:LuminAssets.font(12,460),.foregroundColor:LuminLegacyStyle.variant])
        if let caret=LuminAssets.icon("pdf-icon-sm_down_stroke",size:20) { LuminAssets.tinted(caret,LuminLegacyStyle.variant).draw(in:NSRect(x:bounds.width-24,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}
private final class LuminSignatureColorButton:NSButton {
    var currentColor=NSColor.black { didSet { needsDisplay=true } }
    var selected=false { didSet { needsDisplay=true } }
    var glyph="pdf-icon-md_circle_filled",hasCaret=true
    override init(frame:NSRect) { super.init(frame:frame); title="Change Color"; isBordered=false; setButtonType(.momentaryPushIn); setAccessibilityLabel(title) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect:NSRect) {
        if selected { LuminLegacyStyle.secondaryContainer.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill() }
        if let image=LuminAssets.icon(glyph) { LuminAssets.tinted(image,glyph=="pdf-icon-md_circle_filled" ? currentColor:LuminLegacyStyle.text).draw(in:NSRect(x:8,y:4,width:24,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        (title as NSString).draw(in:NSRect(x:36,y:7.9453125,width:bounds.width-36-(hasCaret ? 32:8),height:16.1015625),withAttributes:[.font:LuminAssets.font(14,520),.foregroundColor:LuminLegacyStyle.text])
        if hasCaret,let caret=LuminAssets.icon("pdf-icon-sm_down_stroke",size:20) { LuminAssets.tinted(caret,PodTheme.text).draw(in:NSRect(x:bounds.width-28,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

private final class LuminSignatureBoard:NSView {
    var tab:LuminSignatureDialog.Tab = .draw { didSet { updateAccessibleMode() } }
    var image:NSImage? { didSet { if image != nil { dragActive=false }; updateAccessibleMode() } }
    var handwriting=true,color=NSColor.black,strokeWidth:CGFloat=3
    var strokes:[[NSPoint]]=[] { didSet { needsDisplay=true } }
    var onDrawingChange:(()->Void)?,onBrowse:(()->Void)?
    var onImageDrop:((NSImage)->Void)?
    private var drawing=false
    private var dragActive=false { didSet { needsDisplay=true } }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); setAccessibilityElement(true); registerForDraggedTypes([.fileURL]); updateAccessibleMode() }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect:NSRect) {
        let outer=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8); LuminSignatureStyle.board.setFill(); outer.fill()
        NSGraphicsContext.saveGraphicsState(); outer.addClip()
        let height:CGFloat=tab == .image ? (image==nil ? 236:200):300
        let border=NSBezierPath(roundedRect:NSRect(x:0.5,y:0.5,width:bounds.width-1,height:height-1),xRadius:8,yRadius:8); LuminLegacyStyle.outline.setStroke(); border.lineWidth=1; border.stroke()
        if tab == .draw {
            if strokes.isEmpty {
                let text="Draw your signature here",attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(20,460),.foregroundColor:LuminSignatureStyle.hint],size=(text as NSString).size(withAttributes:attrs),iconWidth:CGFloat=23.6796875,x=(bounds.width-iconWidth-8-size.width)/2
                if let icon=LuminAssets.icon("pdf-icon-md_pen") { LuminAssets.tinted(icon,LuminSignatureStyle.hint).draw(in:NSRect(x:x,y:215,width:iconWidth,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
                let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=30; paragraph.maximumLineHeight=30
                var textAttrs=attrs; textAttrs[.paragraphStyle]=paragraph
                (text as NSString).draw(in:NSRect(x:x+iconWidth+8,y:212,width:size.width,height:30),withAttributes:textAttrs)
                LuminLegacyStyle.outline.setStroke(); let line=NSBezierPath(); line.move(to:NSPoint(x:41,y:250.5)); line.line(to:NSPoint(x:bounds.width-41,y:250.5)); line.lineWidth=1; line.stroke()
            } else {
                color.setStroke(); color.setFill()
                for points in strokes where !points.isEmpty {
                    let width=handwriting ? CGFloat(8):strokeWidth*3
                    if points.count==1 { NSBezierPath(ovalIn:NSRect(x:points[0].x-width/2,y:points[0].y-width/2,width:width,height:width)).fill() }
                    else { let path=NSBezierPath(); path.move(to:points[0]); points.dropFirst().forEach{path.line(to:$0)}; path.lineWidth=width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke() }
                }
            }
        } else if tab == .type {
            LuminLegacyStyle.outline.setStroke(); let line=NSBezierPath(); line.move(to:NSPoint(x:49,y:231.5)); line.line(to:NSPoint(x:bounds.width-49,y:231.5)); line.lineWidth=1; line.stroke()
        } else if let image {
            NSGraphicsContext.saveGraphicsState(); NSRect(x:1,y:1,width:bounds.width-2,height:198).clip()
            LuminSignatureStyle.checker.setFill()
            for x in stride(from:CGFloat(1),through:bounds.width-1,by:10) { for y in stride(from:CGFloat(1),through:199,by:10) where (Int((x-1)/10)+Int((y-1)/10))%2==1 { NSRect(x:x,y:y,width:10,height:10).fill() } }
            let scale=min((bounds.width-98)/image.size.width,150/image.size.height),size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:NSRect(x:(bounds.width-size.width)/2,y:25+(150-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil); NSGraphicsContext.restoreGraphicsState()
        } else if dragActive {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect:NSRect(x:0,y:0,width:bounds.width,height:236),xRadius:8,yRadius:8).addClip()
            NSColor.black.withAlphaComponent(0.68).setFill(); NSRect(x:0,y:0,width:bounds.width,height:236).fill()
            if let icon=LuminAssets.bitmap("Signature/drop-image") { icon.draw(in:NSRect(x:(bounds.width-44)/2,y:81.5,width:44,height:44),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,420),.foregroundColor:LuminSignatureStyle.dragForeground],label="Drop your image here",size=(label as NSString).size(withAttributes:attrs)
            (label as NSString).draw(in:NSRect(x:(bounds.width-size.width)/2,y:133.5,width:size.width,height:21),withAttributes:attrs); NSGraphicsContext.restoreGraphicsState()
        } else {
            if let icon=LuminAssets.bitmap("Signature/image-upload") { icon.draw(in:NSRect(x:(bounds.width-44)/2,y:69,width:44,height:44),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=21; paragraph.maximumLineHeight=21
            let text="Drag and drop image files (JPG, JPEG or PNG)",attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,420),.foregroundColor:LuminSignatureStyle.hint,.paragraphStyle:paragraph],size=(text as NSString).size(withAttributes:attrs)
            (text as NSString).draw(in:NSRect(x:(bounds.width-size.width)/2,y:121,width:size.width,height:21),withAttributes:attrs)
            let browse=NSMutableAttributedString(string:"or ",attributes:attrs); var link=attrs; link[.foregroundColor]=PodTheme.accent; link[.underlineStyle]=NSUnderlineStyle.single.rawValue; browse.append(NSAttributedString(string:"browse file",attributes:link))
            browse.draw(in:NSRect(x:(bounds.width-browse.size().width)/2,y:146,width:browse.size().width,height:21))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func resetCursorRects() { super.resetCursorRects(); if tab == .draw { addCursorRect(bounds,cursor:.crosshair) } else if tab == .image && image==nil { addCursorRect(NSRect(x:0,y:0,width:bounds.width,height:236),cursor:.pointingHand) } }
    private func updateAccessibleMode() {
        setAccessibilityRole(tab == .image && image==nil ? .button:.group)
        setAccessibilityLabel(tab == .draw ? "Draw your signature here":tab == .type ? "Typed signature preview":image==nil ? "Drag and drop image files (JPG, JPEG or PNG) or browse file":"Signature image preview")
        window?.invalidateCursorRects(for:self)
    }
    override func accessibilityPerformPress()->Bool { guard tab == .image,image==nil else { return false }; onBrowse?(); return true }
    private func draggedURL(_ sender:NSDraggingInfo)->URL? {
        guard tab == .image,image==nil,let url=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true])?.first as? URL,["png","jpeg","jpg"].contains(url.pathExtension.lowercased()) else { return nil }; return url
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { dragActive=draggedURL(sender) != nil; return dragActive ? .copy:[] }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation { dragActive=draggedURL(sender) != nil; return dragActive ? .copy:[] }
    override func draggingExited(_ sender:NSDraggingInfo?) { dragActive=false }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool { defer { dragActive=false }; guard let url=draggedURL(sender),let image=NSImage(contentsOf:url) else { return false }; onImageDrop?(image); return true }
    override func mouseDown(with event:NSEvent) {
        if tab == .image { if image==nil { onBrowse?() }; return }
        guard tab == .draw else { return }; drawing=true; strokes.append([convert(event.locationInWindow,from:nil)]); onDrawingChange?()
    }
    override func mouseDragged(with event:NSEvent) { guard drawing,!strokes.isEmpty else { return }; var points=strokes.removeLast(); points.append(convert(event.locationInWindow,from:nil)); strokes.append(points); onDrawingChange?() }
    override func mouseUp(with event:NSEvent) { drawing=false; onDrawingChange?() }
    override func keyDown(with event:NSEvent) { if tab == .image && [36,49].contains(event.keyCode) { onBrowse?() } else { super.keyDown(with:event) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

private final class LuminSignaturePanelSurface:PodSurfaceView {
    var size=NSSize.zero
    override var isFlipped:Bool { true }
    override var fittingSize:NSSize { size }
}
final class LuminSignatureFontMenu:NSViewController {
    private(set) var rows:[LuminSignatureFontRow]=[]
    private var focused:Int
    let selected:Int
    var onChoose:((Int)->Void)?
    init(selected:Int) { self.selected=selected; focused=selected; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminSignaturePanelSurface(); root.surface=PodTheme.raised; root.size=NSSize(width:196.7265625,height:208)
        for i in 0..<6 {
            let row=LuminSignatureFontRow(index:i); row.selected=i==selected; row.frame=NSRect(x:8,y:8+CGFloat(i)*32,width:180.7265625,height:32); row.onChoose={ [weak self] in self?.onChoose?(i) }; root.addSubview(row); rows.append(row)
        }
        view=root; preferredContentSize=root.size
    }
    func handleKey(_ event:NSEvent)->Bool {
        guard event.window === view.window else { return false }
        switch event.keyCode { case 125:focused=(focused+1)%6;case 126:focused=(focused+5)%6;case 115:focused=0;case 119:focused=5;case 36,49:rows[focused].performClick(nil); return true;case 48:return true;default:return false }
        view.window?.makeFirstResponder(rows[focused]); rows.enumerated().forEach{$0.element.keyboardFocused=$0.offset==focused}; return true
    }
}
final class LuminSignatureFontRow:NSButton {
    let index:Int
    var selected=false { didSet { needsDisplay=true } }
    var keyboardFocused=false { didSet { needsDisplay=true } }
    var onChoose:(()->Void)?
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    init(index:Int) { self.index=index; super.init(frame:.zero); title=LuminSignatureDialog.fontNames[index]; font=LuminAssets.signatureFont(LuminSignatureDialog.families[index],size:14); isBordered=false; setButtonType(.momentaryPushIn); target=self; action=#selector(choose); setAccessibilityLabel(title) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { onChoose?() }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); tracking=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8)
        if selected { LuminLegacyStyle.selected.setFill(); path.fill() }
        if hovered || keyboardFocused || isHighlighted { LuminLegacyStyle.text.withAlphaComponent(0.08).setFill(); path.fill() }
        if selected,let image=LuminAssets.icon("pdf-icon-md_tick") { LuminAssets.tinted(image,PodTheme.selectedText).draw(in:NSRect(x:8,y:4,width:23.8359375,height:24),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=21; paragraph.maximumLineHeight=21
        (title as NSString).draw(in:NSRect(x:39.8359375,y:5.5,width:132.890625,height:21),withAttributes:[.font:font!,.foregroundColor:LuminLegacyStyle.text,.paragraphStyle:paragraph])
    }
}

final class LuminSignatureColorMenu:NSViewController {
    private(set) var color:NSColor,width:Double
    let showsWidth:Bool
    var onChange:((NSColor,Double)->Void)?
    private let slider:LuminSlider
    private let input=NSTextField()
    private var swatches:[SwatchButton]=[]
    private var custom:LuminPopper?
    private let picker=LuminPaletteColorPickerButton()
    init(color:NSColor,width:Double,showsWidth:Bool) { self.color=color; self.width=width; self.showsWidth=showsWidth; slider=LuminSlider(value:width,min:1,max:20,sourcePalette:true); super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminSignaturePanelSurface(); root.surface=LuminLegacyStyle.surface; root.size=NSSize(width:270,height:showsWidth ? 88:48)
        if showsWidth {
            let row=LuminPaletteValueRow(slider:slider,input:input,unit:"pt"); row.frame=NSRect(x:8,y:8,width:254,height:32); root.addSubview(row)
            slider.setAccessibilityLabel("Stroke width"); input.setAccessibilityLabel("Stroke width points"); slider.target=self; slider.action=#selector(changeWidth); input.target=self; input.action=#selector(changeWidth)
        }
        let row=LuminPaletteColorRow(); row.frame=NSRect(x:8,y:showsWidth ? 48:8,width:254,height:32)
        for hex:UInt32 in [0x000000,0xD73027,0x4575B4,0x5AB4AC,0xFEE090,0xE0F3F8,0xFFFFFF] {
            let button=SwatchButton(); button.swatch=PodTheme.color(hex); button.isBordered=false; button.target=self; button.action=#selector(chooseColor); button.setAccessibilityLabel(String(format:"#%06X",hex)); row.addSubview(button); swatches.append(button)
        }
        picker.image=LuminAssets.bitmap("color-picker"); picker.isBordered=false; picker.target=self; picker.action=#selector(showCustom); picker.setAccessibilityLabel("Custom color"); row.addSubview(picker); row.picker=picker; row.swatches=swatches; root.addSubview(row)
        view=root; preferredContentSize=root.size; refresh()
    }
    private func refresh() {
        slider.doubleValue=width; input.stringValue=String(format:"%g",width)
        if !swatches.contains(where:{$0.swatch==color}) { let values=swatches.dropFirst().compactMap{$0.swatch}+[color]; for (button,value) in zip(swatches,values) { button.swatch=value } }
        swatches.forEach{$0.selected=$0.swatch==color; $0.needsDisplay=true}
    }
    @objc private func changeWidth(_ sender:NSControl) { let value=sender.doubleValue; guard value>=1,value<=20 else { refresh(); return }; width=value.rounded(); refresh(); onChange?(color,width) }
    @objc private func chooseColor(_ sender:SwatchButton) { guard let color=sender.swatch else { return }; self.color=color; refresh(); onChange?(color,width) }
    @objc private func showCustom() { custom?.close(); custom=LuminColorPicker.present(from:picker,color:color) { [weak self] color in guard let self else { return }; self.color=color; refresh(); onChange?(color,width) } }
}
