import AppKit

final class LuminExploreMenu:NSViewController,NSTextFieldDelegate {
    let searchBox=LuminExploreSearchBox()
    var searchInput:NSTextField { searchBox.input }
    let resultScroll=NSScrollView()
    private let document=LuminExploreDocument()
    private let engine:LuminExploreSearch
    private let mode:String
    private let canUndo:Bool,canRedo:Bool
    private var showGuideline:Bool
    private let guideline=LuminExploreGuideline()
    private var rows:[LuminExploreRow]=[]
    private var pendingSearch:DispatchWorkItem?
    private(set) var visibleCommands:[LuminExploreCommand]=[]
    private(set) var visibleGroupTitles:[String]=[]
    private var query=""
    private var searchSelection:NSRange?
    var onChoose:((LuminExploreCommand)->Void)?
    var onDismissGuideline:(()->Void)?
    var darkPage=false
    var focusedCommandKey:String? { rows.first{$0.window?.firstResponder === $0}?.command.key }
    func toolbarMode(for command:LuminExploreCommand)->String? { engine.group(for:command)?.toolbarMode }

    init(mode:String,canUndo:Bool,canRedo:Bool,showGuideline:Bool,isLight:Bool=false) {
        self.mode=mode; self.canUndo=canUndo; self.canRedo=canRedo; self.showGuideline=showGuideline
        engine=LuminExploreSearch(mode:mode,isLight:isLight)
        super.init(nibName:nil,bundle:nil); title="Explore"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root=LuminExploreRoot(frame:NSRect(x:0,y:0,width:336,height:516)); root.onLayout={ [weak self] in self?.layoutContents() }
        searchInput.delegate=self; searchInput.target=self; searchInput.action=#selector(searchReturn)
        searchBox.setAccessibilityLabel("Quick Search"); root.addSubview(searchBox)
        guideline.onDismiss={ [weak self] in guard let self else { return }; showGuideline=false; guideline.isHidden=true; onDismissGuideline?(); view.needsLayout=true }
        root.addSubview(guideline)
        resultScroll.drawsBackground=false; resultScroll.hasVerticalScroller=true; resultScroll.autohidesScrollers=true; resultScroll.scrollerStyle = .overlay; resultScroll.borderType = .noBorder; resultScroll.documentView=document
        root.addSubview(resultScroll); view=root; preferredContentSize=NSSize(width:336,height:516); rebuild(); layoutContents()
    }
    private func layoutContents() {
        searchBox.frame=NSRect(x:16,y:16,width:max(0,view.bounds.width-32),height:32)
        guideline.isHidden = !showGuideline; guideline.frame=NSRect(x:16,y:56,width:max(0,view.bounds.width-32),height:94)
        let top:CGFloat=showGuideline ? 162:60
        resultScroll.frame=NSRect(x:16,y:top,width:max(0,view.bounds.width-32),height:max(0,view.bounds.height-top-16))
    }
    func search(_ value:String) { pendingSearch?.cancel(); query=value; searchInput.stringValue=value; rebuild() }
    func cancelSearch() { pendingSearch?.cancel(); pendingSearch=nil }
    func retainSearchSelection()->NSRange? {
        if let editor=searchInput.currentEditor() as? NSTextView { searchSelection=editor.selectedRange() }
        return searchSelection
    }
    func restoreSearchSelection(_ selection:NSRange?) {
        guard let selection,let editor=searchInput.currentEditor() as? NSTextView else { return }
        let count=(editor.string as NSString).length,start=min(selection.location,(editor.string as NSString).length)
        editor.setSelectedRange(NSRange(location:start,length:min(selection.length,count-start)))
    }
    deinit { pendingSearch?.cancel() }
    func controlTextDidChange(_ notification:Notification) {
        pendingSearch?.cancel(); let value=searchInput.stringValue
        let work=DispatchWorkItem { [weak self] in self?.search(value) }; pendingSearch=work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:work)
    }
    func controlTextDidBeginEditing(_ notification:Notification) { searchBox.focused=true }
    func controlTextDidEndEditing(_ notification:Notification) {
        searchBox.focused=false
        if let editor=notification.userInfo?["NSFieldEditor"] as? NSTextView { searchSelection=editor.selectedRange() }
    }
    @objc private func searchReturn() { }
    private func enabled(_ command:LuminExploreCommand)->Bool {
        if command.key=="undo" { return canUndo }; if command.key=="redo" { return canRedo }
        if mode=="Organize" && ["summaryDocument","askAboutDocument","redactSensitiveInfo"].contains(command.key) { return false }
        return command.disabled != true
    }
    private func rebuild() {
        document.subviews.forEach{$0.removeFromSuperview()}; rows=[]; visibleCommands=[]; visibleGroupTitles=[]
        var y:CGFloat=0
        func append(_ command:LuminExploreCommand) {
            let row=LuminExploreRow(command:command,query:query); row.isEnabled=enabled(command); row.darkPage=darkPage; row.onChoose={ [weak self] command in
                guard let self else { return }
                if command.key=="darkPage" { darkPage.toggle(); rows.forEach{$0.darkPage=self.darkPage} }
                onChoose?(command)
            }
            row.frame=NSRect(x:0,y:y,width:304,height:row.height(for:304)); document.addSubview(row); rows.append(row); visibleCommands.append(command); y += row.frame.height
        }
        if query.isEmpty {
            for group in engine.groups where !group.searchOnly {
                let commands=group.commands.filter{engine.isActive($0)}
                guard !commands.isEmpty else { continue }
                if y>0 { y += 12 }
                let label=NSTextField(labelWithString:group.title); label.font=LuminAssets.font(12,500); label.textColor=PodTheme.lowText; label.frame=NSRect(x:8,y:y+4,width:288,height:16); document.addSubview(label)
                visibleGroupTitles.append(group.title); y += 24
                commands.forEach(append)
            }
        } else {
            engine.results(query).forEach(append)
            if mode != "Organize" { append(LuminExploreCommand(key:"searchChatbot",title:"Ask for \"\(query)\" in Lumin AI",bitmap:"Explore/query-chatbot")) }
            append(LuminExploreCommand(key:"searchDocument",title:"Search for \"\(query)\" in this document",bitmap:"Explore/query-document"))
        }
        document.frame=NSRect(x:0,y:0,width:304,height:y)
        resultScroll.contentView.scroll(to:.zero); resultScroll.reflectScrolledClipView(resultScroll.contentView)
        view.needsLayout=true
    }
    func handleKey(_ event:NSEvent)->Bool {
        let index=rows.firstIndex{$0.window?.firstResponder === $0}
        let enabledRows=rows.indices.filter{rows[$0].isEnabled}
        guard !enabledRows.isEmpty else { return false }
        let next:Int
        switch event.keyCode {
        case 125,126:
            if let index,let offset=enabledRows.firstIndex(of:index) { next=enabledRows[(offset+(event.keyCode==125 ? 1:enabledRows.count-1))%enabledRows.count] }
            else { next=enabledRows[0] }
        case 115,119:
            guard index != nil else { return false }; next=event.keyCode==115 ? enabledRows[0]:enabledRows.last!
        case 36,76:
            guard let index else { return false }; rows[index].performClick(nil); return true
        default:return false
        }
        view.window?.makeFirstResponder(rows[next]); rows[next].scrollToVisible(rows[next].bounds); return true
    }
}

private final class LuminExploreRoot:PodSurfaceView {
    var onLayout:(()->Void)?
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:336,height:516) }
    override init(frame:NSRect) { super.init(frame:frame); surface=PodTheme.raised }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); onLayout?() }
}
private final class LuminExploreDocument:NSView { override var isFlipped:Bool { true } }

final class LuminExploreSearchBox:NSView {
    let input=NSTextField()
    var focused=false { didSet { needsDisplay=true } }
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        input.cell=LuminExploreInputCell(textCell:"")
        input.isEditable=true; input.isSelectable=true; input.cell?.usesSingleLineMode=true
        input.isBordered=false; input.isBezeled=false; input.drawsBackground=false; input.focusRingType = .none
        input.font=LuminAssets.font(14,420); input.textColor=PodTheme.text; input.setAccessibilityLabel("Search tools")
        input.placeholderAttributedString=NSAttributedString(string:"Search",attributes:[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.lowText])
        addSubview(input)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); input.frame=NSRect(x:27,y:0,width:max(0,bounds.width-32),height:32) }
    override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(input) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        (focused ? PodTheme.secondary:PodTheme.border).setStroke(); let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:8,yRadius:8); outline.lineWidth=1; outline.stroke()
        if let image=LuminAssets.icon("kiwi-icon-ph-magnifying-glass",size:20) { LuminAssets.tinted(image,PodTheme.onSecondaryContainer).draw(in:NSRect(x:5,y:6,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
}

private final class LuminExploreInputCell:NSTextFieldCell {
    override func drawingRect(forBounds rect:NSRect)->NSRect { NSRect(x:rect.minX,y:rect.midY-10,width:rect.width,height:20) }
    override func edit(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,event:NSEvent?) { super.edit(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,event:event) }
    override func select(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,start selStart:Int,length selLength:Int) { super.select(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,start:selStart,length:selLength) }
}

final class LuminExploreRow:NSButton {
    let command:LuminExploreCommand
    private let query:String
    var onChoose:((LuminExploreCommand)->Void)?
    var darkPage=false { didSet { toggle?.state=darkPage ? .on:.off; toggle?.needsDisplay=true } }
    private var toggle:LuminExploreToggle?
    private var hovered=false
    private var area:NSTrackingArea?
    private let sourceIcon:NSImage?
    var iconWidth:CGFloat { command.icon==nil ? 24:(sourceIcon?.size.width ?? 24) }
    var textLeft:CGFloat { 16+iconWidth }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override var canBecomeKeyView:Bool { false }
    init(command:LuminExploreCommand,query:String) {
        self.command=command; self.query=query
        sourceIcon=command.icon.flatMap{LuminAssets.icon($0,naturalWidth:true)} ?? command.bitmap.flatMap{LuminAssets.bitmap($0)}
        super.init(frame:.zero)
        title=command.title; isBordered=false; setButtonType(.momentaryPushIn); focusRingType = .none; target=self; action=#selector(choose)
        setAccessibilityLabel(command.title); setAccessibilityRole(.menuItem)
        if command.isSwitch==true { let control=LuminExploreToggle(); control.target=self; control.action=#selector(choose); control.setAccessibilityLabel("Dark page"); addSubview(control); toggle=control }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private var trailingWidth:CGFloat {
        if command.isSwitch==true { return 44 }
        if let shortcut=command.shortcut { return max(18,(shortcut as NSString).size(withAttributes:[.font:LuminAssets.font(14,420)]).width+8)+8 }
        return command.trailingIcon==nil ? 0:24
    }
    private func label()->NSAttributedString {
        let paragraph=NSMutableParagraphStyle(); paragraph.minimumLineHeight=20; paragraph.maximumLineHeight=20; paragraph.lineBreakMode = .byWordWrapping
        let alpha:CGFloat=isEnabled ? 1:0.38
        let text=NSMutableAttributedString(string:command.title,attributes:[.font:LuminAssets.font(14,500),.foregroundColor:PodTheme.text.withAlphaComponent(alpha),.paragraphStyle:paragraph])
        if !query.isEmpty && ["searchChatbot","searchDocument"].contains(command.key) { let range=(text.string as NSString).range(of:"\"\(query)\""); if range.location != NSNotFound { text.addAttribute(.foregroundColor,value:PodTheme.lowText.withAlphaComponent(alpha),range:range) } }
        return text
    }
    private func labelSize(_ width:CGFloat)->NSSize { label().boundingRect(with:NSSize(width:max(1,width-textLeft-8-trailingWidth-(command.premium==true ? 24:0)),height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading]).size }
    func height(for width:CGFloat)->CGFloat { max(40,ceil(labelSize(width).height)+16) }
    override func layout() { super.layout(); toggle?.frame=NSRect(x:bounds.width-44,y:(bounds.height-20)/2,width:36,height:20) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let area { removeTrackingArea(area) }; let next=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(next); area=next }
    override func mouseEntered(with event:NSEvent) { hovered=true; needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false; needsDisplay=true }
    override var isHighlighted:Bool { didSet { needsDisplay=true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    @objc private func choose() { if isEnabled { onChoose?(command) } }
    override func draw(_ rect:NSRect) {
        if isEnabled && (hovered || isHighlighted) { PodTheme.text.withAlphaComponent(isHighlighted ? 0.12:0.08).setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill() }
        let alpha:CGFloat=isEnabled ? 1:0.38
        if let icon=sourceIcon { let image=command.colored==true ? icon:LuminAssets.tinted(icon,PodTheme.text); image.draw(in:NSRect(x:8,y:(bounds.height-24)/2,width:iconWidth,height:24),from:.zero,operation:.sourceOver,fraction:alpha,respectFlipped:true,hints:nil) }
        let text=label(),size=labelSize(bounds.width)
        text.draw(with:NSRect(x:textLeft,y:(bounds.height-size.height)/2,width:max(1,bounds.width-textLeft-8-trailingWidth-(command.premium==true ? 24:0)),height:size.height),options:.usesLineFragmentOrigin)
        if command.premium==true,let badge=LuminAssets.bitmap("Explore/premium") { let width=(command.title as NSString).size(withAttributes:[.font:LuminAssets.font(14,500)]).width; badge.draw(in:NSRect(x:min(textLeft+width+8,bounds.width-24),y:(bounds.height-16)/2,width:16,height:16)) }
        if let shortcut=command.shortcut {
            let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(14,420),.foregroundColor:PodTheme.lowText.withAlphaComponent(alpha)]
            let size=(shortcut as NSString).size(withAttributes:attrs),right:CGFloat=command.key=="presenterMode" ? 8:12
            (shortcut as NSString).draw(in:NSRect(x:bounds.width-right-size.width,y:(bounds.height-size.height)/2,width:size.width,height:size.height),withAttributes:attrs)
        } else if let name=command.trailingIcon,let image=LuminAssets.icon(name,size:16) { LuminAssets.tinted(image,PodTheme.secondaryText).draw(in:NSRect(x:bounds.width-24,y:(bounds.height-16)/2,width:16,height:16)) }
    }
}

private final class LuminExploreToggle:NSButton {
    override init(frame:NSRect) { super.init(frame:frame); isBordered=false; setButtonType(.momentaryPushIn); setAccessibilityRole(.checkBox) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect:NSRect) {
        let track=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:10,yRadius:10)
        (state == .on ? PodTheme.text:PodTheme.chrome).setFill(); track.fill(); PodTheme.outline.setStroke(); track.lineWidth=1; track.stroke()
        (state == .on ? PodTheme.chrome:PodTheme.secondaryText).setFill(); NSBezierPath(ovalIn:NSRect(x:state == .on ? 18:2,y:2,width:16,height:16)).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
}

private final class LuminExploreGuideline:NSView {
    var onDismiss:(()->Void)?
    private let close=NSButton()
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); close.isBordered=false; close.image=LuminAssets.icon("kiwi-icon-ph-x",size:16); close.imageScaling = .scaleProportionallyDown; close.contentTintColor=PodTheme.secondary; close.target=self; close.action=#selector(dismiss); close.setAccessibilityLabel("Dismiss Quick Search tip"); addSubview(close)
        setAccessibilityLabel("Quick Search is now available. Tip: Press Option + / to open Quick Search and quickly access any feature you need.")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); close.frame=NSRect(x:bounds.width-32,y:4,width:24,height:24) }
    @objc private func dismiss() { onDismiss?() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); close.contentTintColor=PodTheme.secondary; needsDisplay=true }
    override func draw(_ rect:NSRect) {
        PodTheme.informationContainer.setFill(); NSBezierPath(roundedRect:bounds,xRadius:8,yRadius:8).fill()
        let badge=NSRect(x:8,y:8,width:36.6875,height:16); PodTheme.information.setFill(); NSBezierPath(roundedRect:badge,xRadius:2,yRadius:2).fill()
        ("NEW" as NSString).draw(in:badge.insetBy(dx:4,dy:0),withAttributes:[.font:LuminAssets.font(12,500),.foregroundColor:PodTheme.onInformation])
        ("Quick Search is now available" as NSString).draw(in:NSRect(x:8,y:36,width:bounds.width-16,height:16),withAttributes:[.font:LuminAssets.font(12,500),.foregroundColor:PodTheme.text])
        let attrs:[NSAttributedString.Key:Any]=[.font:LuminAssets.font(12,420),.foregroundColor:PodTheme.secondaryText]
        var x:CGFloat=8,y:CGFloat=52
        func text(_ value:String) { let width=(value as NSString).size(withAttributes:attrs).width; if x+width>bounds.width-8 { x=8; y += 18 }; (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:attrs); x += width }
        func keycap(_ value:String) {
            let font=LuminAssets.font(12,500),width=(value as NSString).size(withAttributes:[.font:font]).width+10
            let frame=NSRect(x:x,y:y,width:width,height:18); PodTheme.secondaryText.setStroke(); let path=NSBezierPath(roundedRect:frame.insetBy(dx:0.5,dy:0.5),xRadius:2,yRadius:2); path.lineWidth=1; path.stroke()
            (value as NSString).draw(in:frame.insetBy(dx:5,dy:1),withAttributes:[.font:font,.foregroundColor:PodTheme.secondaryText]); x += width
        }
        text("Tip: Press "); keycap("Option"); text(" + "); keycap("/")
        for word in " to open Quick Search and quickly access any feature you need.".components(separatedBy:" ").enumerated() { if word.offset==0 { text(" ") } else { text(word.element+" ") } }
    }
}
