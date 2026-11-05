import AppKit

private final class LuminShareRoot:NSView {
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override func mouseDown(with event:NSEvent) {} // Card gaps are inside the modal, not backdrop.
}
final class LuminShareDialog:NSViewController {
    enum State:String { case main,link,settings }
    enum Scope { case restricted,anyone }
    let filename:String,link:String
    private(set) var state:State = .main,scope:Scope = .restricted
    private var committedScope:Scope = .restricted,committedRole="Viewer",publicRole="Viewer"
    private var exportSelection=0,committedExport=0,bulkSelected=false,bulkRole=0
    private(set) var controls:[String:NSView]=[:]
    private var popup:LuminPopper?
    var onResize:(()->Void)?
    var onFocus:((NSResponder?)->Void)?
    var onCopyLink:(()->Void)?
    var initialResponder:NSResponder? { (controls["invite"] as? LuminShareInput)?.input ?? controls["back"] }
    var linkDescription:String { scope == .restricted ? "Only shared people can access with link":"Anyone on the internet can \(publicRole == "Editor" ? "edit":publicRole == "Commenter" ? "comment":"view") with link" }
    init(filename:String,link:String) { self.filename=filename; self.link=link; super.init(nibName:nil,bundle:nil); title="Share" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() { view=LuminShareRoot(); view.setAccessibilityElement(true); view.setAccessibilityRole(.sheet); view.setAccessibilityLabel("Share"); rebuild() }
    func switchTo(_ state:State) {
        popup?.close(); self.state=state
        if state == .link { scope=committedScope; publicRole=committedRole }
        if state == .settings { exportSelection=committedExport; bulkSelected=false; bulkRole=0 }
        if isViewLoaded { rebuild() }
    }
    func setScope(_ scope:Scope) { self.scope=scope; rebuild() }
    func setPublicRole(_ role:String) { publicRole=role; rebuild() }
    func cancelDraft() { scope=committedScope; publicRole=committedRole; exportSelection=committedExport; switchTo(.main); onFocus?(controls["slack"]) }
    func commitLinkDraft() { committedScope=scope; committedRole=publicRole; switchTo(.main) }
    func toggleBulk() { bulkSelected.toggle(); rebuild(); onFocus?(controls["group"]) }
    func dismissMenus() { popup?.close() }
    private func add(_ key:String,_ child:NSView,_ frame:NSRect) { child.frame=frame; view.addSubview(child); controls[key]=child }
    @discardableResult private func label(_ key:String,_ text:String,_ frame:NSRect,size:CGFloat=14,weight:Double=420,line:CGFloat=20,color:NSColor=PodTheme.text,headline:Bool=false)->LuminTextLabel {
        let label=LuminTextLabel(text,font:headline ? LuminAssets.headline(size):LuminAssets.font(size,weight),lineHeight:line,color:color); add(key,label,frame); return label
    }
    @discardableResult private func button(_ key:String,_ text:String,_ frame:NSRect,style:LuminShareButton.Style = .text,small:Bool=false,action:@escaping ()->Void)->LuminShareButton {
        let button=LuminShareButton(text,style:style); if small { button.size=14; button.horizontalPadding=12; button.imageSize=20; button.iconSlot=20; button.iconGap=4 }; button.onPress=action; add(key,button,frame); return button
    }
    private func paper(_ key:String,_ frame:NSRect,surface:NSColor=PodTheme.raised,radius:CGFloat=16) { let paper=LuminDialogPaper(); paper.surface=surface; paper.radius=radius; add(key,paper,frame) }
    private func divider(_ key:String,_ frame:NSRect) { let divider=PodSurfaceView(); divider.surface=PodTheme.border; add(key,divider,frame) }
    private func rebuild() {
        view.subviews.forEach{$0.removeFromSuperview()}; controls=[:]
        let height:CGFloat=state == .main ? 330:state == .link ? 314:368
        preferredContentSize=NSSize(width:640,height:height); view.frame.size=preferredContentSize
        switch state { case .main:buildMain(); case .link:buildLink(); case .settings:buildSettings() }
        view.layoutSubtreeIfNeeded(); onResize?(); onFocus?(initialResponder)
    }
    private func buildMain() {
        scope=committedScope; publicRole=committedRole
        paper("topPanel",NSRect(x:0,y:0,width:640,height:238)); paper("bottomPanel",NSRect(x:0,y:246,width:640,height:84))
        let title="Share \"\(filename)\"",titleWidth=min(341.34375,LuminHeaderMenuRow.width(title,font:LuminAssets.headline(20)))
        label("title",title,NSRect(x:24,y:24,width:titleWidth,height:28),size:20,weight:500,line:28,headline:true).truncates=true
        let slack=button("slack","Share in Slack",NSRect(x:413.34375,y:16,width:155.65625,height:40),action:{})
        slack.bitmap="Share/slack-logo"; slack.horizontalPadding=8
        divider("headerDivider",NSRect(x:575,y:24,width:1,height:24))
        let settings=button("settings","",NSRect(x:584,y:16,width:40,height:40)) { [weak self] in self?.switchTo(.settings) }; settings.bitmap="Share/gear"; settings.setAccessibilityLabel("Share settings")
        let invite=LuminShareInput(search:true); add("invite",invite,NSRect(x:24,y:68,width:592,height:40))
        label("peopleHeading","People with access",NSRect(x:24,y:116,width:592,height:36),color:PodTheme.lowText)
        let owner=NSView(); add("ownerRow",owner,NSRect(x:24,y:152,width:592,height:54))
        let avatar=NSImageView(); avatar.image=Bundle.main.url(forResource:"Pod",withExtension:"icns").flatMap{NSImage(contentsOf:$0)} ?? NSImage(contentsOfFile:"macos/Resources/Pod.icns"); avatar.imageScaling = .scaleProportionallyUpOrDown; avatar.setAccessibilityLabel("You"); add("avatar",avatar,NSRect(x:32,y:163,width:32,height:32))
        label("ownerName","You",NSRect(x:72,y:160,width:420,height:20),weight:500)
        label("ownerDetail",filename,NSRect(x:72,y:182,width:420,height:16),size:12,line:16,color:PodTheme.lowText).truncates=true
        label("ownerRole","Doc owner",NSRect(x:504.09375,y:161,width:103.90625,height:36),weight:500).horizontalInset=16
        label("linkHeading","Share link",NSRect(x:24,y:262,width:323.734375,height:28),size:20,weight:500,line:28,headline:true)
        // The source inline-flow advance is266.3984375; CoreText measures266.5.
        let description=linkDescription,width=scope == .restricted ? CGFloat(266.3984375):LuminHeaderMenuRow.width(description,font:LuminAssets.font(14,420))
        label("linkDescription",description,NSRect(x:24,y:294,width:width,height:20))
        let change=button("change","Change",NSRect(x:28+width,y:295.5,width:53.3359375,height:17),style:.change,small:true) { [weak self] in self?.switchTo(.link) }; change.weight=700
        button("copy","Copy link",NSRect(x:513.2890625,y:268,width:102.7109375,height:40),style:.tonal) { [weak self] in self?.onCopyLink?() }
    }
    private func backAndTitle(_ title:String) {
        let back=button("back","",NSRect(x:14,y:18,width:40,height:40)) { [weak self] in self?.cancelDraft() }; back.glyph="kiwi-icon-ph-arrow-left"; back.setAccessibilityLabel("Back")
        label("title",title,NSRect(x:60,y:24,width:LuminHeaderMenuRow.width(title,font:LuminAssets.headline(20)),height:28),size:20,weight:500,line:28,headline:true)
    }
    private func buildLink() {
        paper("panel",NSRect(x:0,y:0,width:640,height:314)); backAndTitle("Share with others")
        divider("divider1",NSRect(x:24,y:68,width:592,height:1))
        label("linkLabel","Share link",NSRect(x:24,y:85,width:592,height:20),weight:500)
        let input=LuminShareInput(search:false); input.input.stringValue=link; add("input",input,NSRect(x:24,y:113,width:490.125,height:32))
        button("copy","Copy link",NSRect(x:530.125,y:113,width:85.875,height:32),style:.outlined,small:true) { [weak self] in self?.onCopyLink?() }
        divider("divider2",NSRect(x:24,y:161,width:592,height:1))
        let title=scope == .restricted ? "Restricted":"Anyone with the link",width=LuminHeaderMenuRow.width(title,font:LuminAssets.font(14,500))+48
        let scopeButton=button("scope",title,NSRect(x:12,y:178,width:width,height:32),small:true) { [weak self] in self?.showMenu(.scope,anchor:"scope") }; scopeButton.arrow=true
        if scope == .anyone {
            let width=LuminHeaderMenuRow.width(publicRole,font:LuminAssets.font(14,500))+48
            let role=button("publicRole",publicRole,NSRect(x:616-width,y:178,width:width,height:32),small:true) { [weak self] in self?.showMenu(.publicRole,anchor:"publicRole") }; role.arrow=true
        }
        label("description",linkDescription,NSRect(x:24,y:214,width:592,height:20),color:PodTheme.secondaryText)
        button("done","Done",NSRect(x:496,y:250,width:120,height:40),style:.filled) { [weak self] in self?.commitLinkDraft() }
    }
    private func buildSettings() {
        paper("panel",NSRect(x:0,y:0,width:640,height:368)); backAndTitle("Share settings")
        label("exportLabel","Who can export, print or copy the document",NSRect(x:24,y:71,width:295.75,height:20),weight:500)
        let titles=["Anyone with document access","Sharers and editors","Sharers, editors and commenters"]
        let selector=button("export",titles[exportSelection],NSRect(x:24,y:97,width:592,height:40),style:.selector) { [weak self] in self?.showMenu(.export,anchor:"export") }; selector.weight=420; selector.leadingBitmap=["Share/export-world","Share/pencil","Share/comment"][exportSelection]; selector.arrow=true
        label("bulkTitle","Bulk update permissions",NSRect(x:24,y:153,width:592,height:24),size:16,weight:500,line:24)
        paper("bulkPanel",NSRect(x:24,y:185,width:592,height:103),surface:PodTheme.chrome,radius:8)
        let group=LuminShareCheckbox(); group.isOn=bulkSelected; group.onToggle={ [weak self] in self?.toggleBulk() }; add("group",group,NSRect(x:32,y:195,width:160.375,height:32))
        divider("bulkDivider",NSRect(x:40,y:235,width:560,height:1))
        label("bulkDescription","Users in the selected group(s):",NSRect(x:40,y:250,width:204.2734375,height:20))
        let title=["Can view","Can comment","Can edit","Can share"][bulkRole],width=LuminHeaderMenuRow.width(title,font:LuminAssets.font(14,500))+48
        let permission=button("permission",title,NSRect(x:600-width,y:244,width:width,height:32),small:true) { [weak self] in self?.showMenu(.bulk,anchor:"permission") }; permission.bitmap="Share/caret"; permission.imageSize=14; permission.isEnabled=bulkSelected
        button("cancel","Cancel",NSRect(x:376.390625,y:304,width:84.8984375,height:40),style:.outlined) { [weak self] in self?.cancelDraft() }
        let save=button("save","Save changes",NSRect(x:477.2890625,y:304,width:138.7109375,height:40),style:.filled) { [weak self] in guard let self else { return }; committedExport=exportSelection; switchTo(.main) }; save.isEnabled=bulkSelected || exportSelection != committedExport
    }
    private func showMenu(_ kind:LuminShareMenu.Kind,anchor:String) {
        guard let sender=controls[anchor] else { return }; popup?.close()
        let selection=kind == .export ? exportSelection:kind == .bulk ? bulkRole:0
        let menu=LuminShareMenu(kind:kind,selection:selection),pop=LuminPopper(); pop.contentViewController=menu; pop.alignment=menu.alignment; pop.gap=menu.gap
        pop.onKeyDown={ [weak menu] event in menu?.handleKey(event) ?? false }
        pop.onEscape={ [weak self,weak sender] in self?.onFocus?(sender) }
        menu.onChoose={ [weak self,weak pop] index in
            pop?.close(); guard let self else { return }
            switch kind { case .scope:scope=index==0 ? .restricted:.anyone; case .publicRole:publicRole=["Viewer","Commenter","Editor"][index]; case .bulk:bulkRole=index; case .export:exportSelection=index }
            rebuild(); onFocus?(controls[anchor])
        }
        popup=pop; let rect=kind == .export ? sender.bounds.insetBy(dx:1,dy:1):sender.bounds
        pop.show(relativeTo:rect,of:sender,preferredEdge:menu.edge)
    }
    func handleKey(_ event:NSEvent)->Bool {
        guard event.keyCode==48 else { return false }
        let keys=state == .main ? ["slack","settings","invite","change","copy"]:state == .link ? ["back","input","copy","scope","publicRole","done"]:["back","export","group","permission","cancel","save"]
        let targets=keys.compactMap{controls[$0]}.compactMap{view -> NSView? in if let input=view as? LuminShareInput { return input.input }; if let control=view as? NSControl,!control.isEnabled { return nil }; return view }
        guard !targets.isEmpty else { return true }
        let responder=view.window?.firstResponder,current=targets.firstIndex { target in target === responder || (target as? NSTextField)?.currentEditor() === responder }
        let index=current.map{($0+(event.modifierFlags.contains(.shift) ? targets.count-1:1))%targets.count} ?? 0
        controls.values.compactMap{$0 as? LuminShareButton}.forEach{$0.keyboardFocused=false}
        (targets[index] as? LuminShareButton)?.keyboardFocused=true
        view.window?.makeFirstResponder(targets[index]); return true
    }
}
