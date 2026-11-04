import AppKit
import UniformTypeIdentifiers

@main
final class PodApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private let worker=DispatchQueue(label:"com.pod.engine",qos:.userInitiated)
    private var engine: Engine?
    private var loaded: LoadedPDF?
    private var fileURL: URL?
    private var pendingURL: URL?
    private var savedBytes: Data?
    private var history: [Data]=[]
    private var future: [Data]=[]
    private var pageIndex=0
    private var zoom: CGFloat=0.95
    private var busy=false
    private var selection: Int?
    private let canvas=PageCanvas()
    private let scroll=NSScrollView()
    private let table=NSTableView()
    private let fileLabel=NSTextField(labelWithString:"Welcome to Pod")
    private let status=NSTextField(labelWithString:"Opening the sample…")
    private let pageLabel=NSTextField(labelWithString:"")
    private let selectionLabel=NSTextField(wrappingLabelWithString:"Select a line on the page to edit it.")
    private let replacement=NSTextField(string:"")
    private let details=NSTextField(wrappingLabelWithString:"")
    private let zoomLabel=NSTextField(labelWithString:"95%")
    private var applyButton: NSButton!
    private var saveButton: NSButton!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var openButton: NSButton!
    private var sampleButton: NSButton!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var zoomOutButton: NSButton!
    private var zoomInButton: NSButton!
    private var fitButton: NSButton!
    private let spinner=NSProgressIndicator()
    private let inspector=NSStackView()
    private var textInspectorViews:[NSView]=[]
    private var markupTool:MarkupKind?
    private var markupStyle=MarkupStyle()
    private var selectedMarkup:UInt32?
    private var palette:NSPopover?
    private var markupButtons:[NSButton]=[]
    private var toolButtons:[NSButton]=[]
    private var toolStyles:[MarkupKind:MarkupStyle]=[:]
    private let annotationText=NSTextField(string:"")
    private var commentsVisible=false
    private var disabledInspectorControls:[(NSControl,Bool)]=[]

    private var dirty: Bool { loaded?.bytes != savedBytes }

    static func main() {
        let app=NSApplication.shared
        let delegate=PodApp(); app.delegate=delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        configureWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        if let url=pendingURL { pendingURL=nil; openURL(url) } else { openSample() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { canDiscard() ? .terminateNow : .terminateCancel }
    func windowShouldClose(_ sender:NSWindow) -> Bool { canDiscard() }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        if let name=filenames.first {
            let url=URL(fileURLWithPath:name)
            if window == nil || busy { pendingURL=url } else { openURL(url) }
        }
        sender.reply(toOpenOrPrint:.success)
    }
    private func button(_ title:String,_ image:String?=nil,_ action:Selector) -> NSButton {
        let button=NSButton(title:title,target:self,action:action)
        button.bezelStyle = .rounded
        if let image { button.image=NSImage(systemSymbolName:image,accessibilityDescription:title); button.imagePosition = .imageLeading }
        button.toolTip=title; button.setAccessibilityLabel(title)
        return button
    }
    private func label(_ string:String,_ size:CGFloat=12,_ color:NSColor = .secondaryLabelColor) -> NSTextField {
        let label=NSTextField(wrappingLabelWithString:string); label.font = .systemFont(ofSize:size); label.textColor=color
        return label
    }
    private func configureMenus() {
        let main=NSMenu(); NSApp.mainMenu=main
        func menu(_ title:String) -> NSMenu { let item=NSMenuItem(); main.addItem(item); let menu=NSMenu(title:title); item.submenu=menu; return menu }
        func add(_ menu:NSMenu,_ title:String,_ action:Selector,_ key:String="") { let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item) }
        let app=menu("Pod"); add(app,"About Pod",#selector(about)); app.addItem(.separator()); add(app,"Quit Pod",#selector(quit),"q")
        let file=menu("File"); add(file,"Open…",#selector(openFile),"o"); add(file,"Open Sample",#selector(openSample)); add(file,"Save a Copy…",#selector(saveCopy),"s")
        let edit=menu("Edit"); add(edit,"Undo PDF Edit",#selector(undoEdit),"z"); add(edit,"Redo PDF Edit",#selector(redoEdit),"Z"); edit.addItem(.separator())
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(NSMenuItem(title:title,action:action,keyEquivalent:key))
        }
        let view=menu("View"); add(view,"Zoom In",#selector(zoomIn),"+"); add(view,"Zoom Out",#selector(zoomOut),"-"); add(view,"Fit Page",#selector(fitPage),"0")
    }
    private func configureWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Pod"; window.minSize=NSSize(width:1160,height:680); window.center(); window.delegate=self
        window.titlebarAppearsTransparent=true; window.backgroundColor = .windowBackgroundColor
        let root=NSView(); window.contentView=root
        let header=NSStackView(); header.orientation = .horizontal; header.spacing=10; header.edgeInsets=NSEdgeInsets(top:10,left:16,bottom:10,right:16)
        openButton=button("Open","folder",#selector(openFile)); sampleButton=button("Sample",nil,#selector(openSample))
        undoButton=button("","arrow.uturn.backward",#selector(undoEdit)); undoButton.toolTip="Undo PDF edit"; undoButton.setAccessibilityLabel("Undo PDF edit")
        redoButton=button("","arrow.uturn.forward",#selector(redoEdit)); redoButton.toolTip="Redo PDF edit"; redoButton.setAccessibilityLabel("Redo PDF edit")
        saveButton=button("Save a Copy","square.and.arrow.down",#selector(saveCopy))
        fileLabel.font = .systemFont(ofSize:13,weight:.medium); fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentHuggingPriority(.defaultLow,for:.horizontal)
        for view in [openButton!,sampleButton!,fileLabel,undoButton!,redoButton!,saveButton!] { header.addArrangedSubview(view) }
        let sidebar=NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .active
        let sidebarTitle=label("PAGES",10); sidebarTitle.font = .systemFont(ofSize:10,weight:.semibold)
        let sidebarScroll=NSScrollView(); sidebarScroll.hasVerticalScroller=true; sidebarScroll.drawsBackground=false
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("page")); column.width=140; table.addTableColumn(column)
        table.headerView=nil; table.rowHeight=60; table.intercellSpacing=NSSize(width:0,height:8); table.dataSource=self; table.delegate=self; table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular; table.setAccessibilityLabel("Document pages"); sidebarScroll.documentView=table
        let sidebarNote=label("LOCAL BY DESIGN\nYour files stay on this Mac.",10)
        for view in [sidebarTitle,sidebarScroll,sidebarNote] { sidebar.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([sidebarTitle.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:20),sidebarTitle.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:18),sidebarScroll.topAnchor.constraint(equalTo:sidebarTitle.bottomAnchor,constant:16),sidebarScroll.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:8),sidebarScroll.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-8),sidebarScroll.bottomAnchor.constraint(equalTo:sidebarNote.topAnchor,constant:-20),sidebarNote.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:18),sidebarNote.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-12),sidebarNote.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-20)])
        scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.autohidesScrollers=true; scroll.documentView=canvas; scroll.drawsBackground=false
        canvas.onSelect={ [weak self] id in self?.select(id) }
        canvas.onAnnotationSelect={ [weak self] id in self?.selectAnnotation(id) }
        canvas.onCreate={ [weak self] marks in self?.createAnnotations(marks) }
        canvas.onUpdate={ [weak self] mark in self?.mutateAnnotations([mark]) }
        canvas.onDelete={ [weak self] id in self?.mutateAnnotations([],deleting:[id]) }

        inspector.orientation = .vertical; inspector.alignment = .leading; inspector.spacing=18; inspector.edgeInsets=NSEdgeInsets(top:24,left:20,bottom:24,right:20)
        let inspectorTitle=label("Text inspector",17,.labelColor); inspectorTitle.font = .systemFont(ofSize:17,weight:.semibold)
        selectionLabel.font = .systemFont(ofSize:12); selectionLabel.textColor = .secondaryLabelColor
        replacement.placeholderString="Replacement text"; replacement.font = .monospacedSystemFont(ofSize:12,weight:.regular); replacement.delegate=self; replacement.target=self; replacement.action=#selector(applyEdit); replacement.setAccessibilityLabel("Replacement text")
        applyButton=button("Replace text",nil,#selector(applyEdit)); applyButton.bezelColor = .systemTeal
        details.font = .systemFont(ofSize:11); details.textColor = .secondaryLabelColor
        let note=label("Keep replacements within the original line width. Pod preserves the position of the text that follows.",11)
        let divider=NSBox(); divider.boxType = .separator
        let support=label("EARLY PREVIEW",10); support.font = .systemFont(ofSize:10,weight:.semibold)
        let scope=label("Simple Courier PDFs are supported today. Use Mark up for shapes, highlights, drawing, text and comments. More fonts and scanned pages are still to come.",11)
        for view in [inspectorTitle,selectionLabel,replacement,applyButton!,details,note,divider,support,scope] {
            inspector.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant:220).isActive=true
        }
        let spacer=NSView(); inspector.addArrangedSubview(spacer); spacer.setContentHuggingPriority(.defaultLow,for:.vertical)
        textInspectorViews=inspector.arrangedSubviews
        let body=NSView()
        for view in [sidebar,scroll,inspector] { body.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo:body.leadingAnchor),sidebar.topAnchor.constraint(equalTo:body.topAnchor),sidebar.bottomAnchor.constraint(equalTo:body.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant:164),scroll.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),scroll.topAnchor.constraint(equalTo:body.topAnchor),scroll.bottomAnchor.constraint(equalTo:body.bottomAnchor),scroll.trailingAnchor.constraint(equalTo:inspector.leadingAnchor),inspector.widthAnchor.constraint(equalToConstant:308),inspector.topAnchor.constraint(equalTo:body.topAnchor),inspector.bottomAnchor.constraint(equalTo:body.bottomAnchor),inspector.trailingAnchor.constraint(equalTo:body.trailingAnchor)])
        let footer=NSStackView(); footer.orientation = .horizontal; footer.spacing=10; footer.edgeInsets=NSEdgeInsets(top:8,left:16,bottom:8,right:16)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped=false; spinner.widthAnchor.constraint(equalToConstant:16).isActive=true
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor; status.setContentHuggingPriority(.defaultLow,for:.horizontal); status.lineBreakMode = .byTruncatingTail
        prevButton=button("","chevron.left",#selector(previousPage)); prevButton.setAccessibilityLabel("Previous page")
        nextButton=button("","chevron.right",#selector(nextPage)); nextButton.setAccessibilityLabel("Next page")
        zoomOutButton=button("−",nil,#selector(zoomOut)); zoomInButton=button("+",nil,#selector(zoomIn)); fitButton=button("Fit",nil,#selector(fitPage))
        zoomLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); zoomLabel.alignment = .center; zoomLabel.widthAnchor.constraint(equalToConstant:42).isActive=true
        pageLabel.font = .systemFont(ofSize:11)
        for view in [spinner,status,prevButton!,pageLabel,nextButton!,zoomOutButton!,zoomLabel,zoomInButton!,fitButton!] { footer.addArrangedSubview(view) }
        let markupBar=makeMarkupToolbar()
        for view in [header,markupBar,body,footer] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:root.leadingAnchor),header.trailingAnchor.constraint(equalTo:root.trailingAnchor),header.topAnchor.constraint(equalTo:root.topAnchor),header.heightAnchor.constraint(equalToConstant:54),markupBar.topAnchor.constraint(equalTo:header.bottomAnchor),markupBar.leadingAnchor.constraint(equalTo:root.leadingAnchor),markupBar.trailingAnchor.constraint(equalTo:root.trailingAnchor),markupBar.heightAnchor.constraint(equalToConstant:48),body.topAnchor.constraint(equalTo:markupBar.bottomAnchor),body.leadingAnchor.constraint(equalTo:root.leadingAnchor),body.trailingAnchor.constraint(equalTo:root.trailingAnchor),body.bottomAnchor.constraint(equalTo:footer.topAnchor),footer.leadingAnchor.constraint(equalTo:root.leadingAnchor),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor),footer.heightAnchor.constraint(equalToConstant:42)])
        updateControls()
    }
    func windowDidResize(_ notification:Notification) { canvas.resizeToViewport() }
    func numberOfRows(in tableView:NSTableView) -> Int { loaded?.pages.count ?? 0 }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let cell=NSTableCellView(); let text=NSTextField(labelWithString:"▤    Page \(row+1)"); text.font = .systemFont(ofSize:13,weight:.medium); text.frame=NSRect(x:10,y:21,width:126,height:20); cell.addSubview(text); cell.textField=text
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) { if table.selectedRow >= 0 && table.selectedRow != pageIndex { navigate(table.selectedRow) } }
    private func setBusy(_ value:Bool,_ message:String?=nil) {
        if value && !busy {
            func disable(_ view:NSView) {
                if let control=view as? NSControl { disabledInspectorControls.append((control,control.isEnabled)); control.isEnabled=false }
                for child in view.subviews { disable(child) }
            }
            disable(inspector)
            if let view=palette?.contentViewController?.view { disable(view) }
        } else if !value {
            for (control,enabled) in disabledInspectorControls { control.isEnabled=enabled }
            disabledInspectorControls=[]
        }
        busy=value; if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }; if let message { status.stringValue=message }; updateControls() }
    private func updateControls() {
        guard applyButton != nil else { return }
        let available=loaded != nil && !busy
        openButton.isEnabled = !busy; sampleButton.isEnabled = !busy; saveButton.isEnabled=available; table.isEnabled = !busy
        applyButton.isEnabled=available && selection != nil; replacement.isEnabled=available && selection != nil
        undoButton.isEnabled=available && !history.isEmpty; redoButton.isEnabled=available && !future.isEmpty
        prevButton.isEnabled=available && pageIndex>0; nextButton.isEnabled=available && pageIndex+1<(loaded?.pages.count ?? 0)
        zoomOutButton.isEnabled=available && zoom>0.4; zoomInButton.isEnabled=available && zoom<2; fitButton.isEnabled=available
        for button in markupButtons { button.isEnabled=available }
        canvas.interactionEnabled=available
        window?.isDocumentEdited=dirty
    }
    private func select(_ id:Int?) {
        selection=id; canvas.selected=id; canvas.needsDisplay=true
        if id != nil { selectedMarkup=nil; canvas.annotationSelection=nil }
        if let id,let run=loaded?.pages[pageIndex].runs.first(where:{$0.id==id}) {
            selectionLabel.stringValue="Selected text"; replacement.stringValue=run.text; details.stringValue="Courier · \(String(format:"%.0f",run.size)) pt\nPage \(pageIndex+1) · Text run \(id+1)"
        } else { selectionLabel.stringValue="Select a line on the page to edit it."; replacement.stringValue=""; details.stringValue="" }
        updateControls(); refreshInspector()
    }
    private func show(_ document:LoadedPDF,page:Int) {
        loaded=document; pageIndex=page
        canvas.configure(document.pixels,page:document.pages[page],zoom:zoom)
        table.reloadData(); table.selectRowIndexes(IndexSet(integer:page),byExtendingSelection:false)
        pageLabel.stringValue="\(page+1) / \(document.pages.count)"; zoomLabel.stringValue="\(Int((zoom*100).rounded()))%"
        fileLabel.stringValue=fileURL?.lastPathComponent ?? "Welcome to Pod.pdf"
        window.title="\(fileLabel.stringValue) — Pod"; window.representedURL=fileURL
        selectedMarkup=nil; canvas.annotationSelection=nil
        select(nil); setBusy(false,"\(document.pages.count) pages · \(ByteCountFormatter.string(fromByteCount:Int64(document.bytes.count),countStyle:.file)) · Rendered in \(Int(document.elapsedMS.rounded())) ms")
        if let url=pendingURL { pendingURL=nil; openURL(url) }
    }
    private var pixelWidth:Int {
        let width=loaded?.pages[pageIndex].box.width ?? 612
        return min(2400,max(240,Int(width*zoom*(window?.backingScaleFactor ?? 2))))
    }
    private func perform(_ message:String,work:@escaping (Engine) throws -> LoadedPDF,done:@escaping (LoadedPDF)->Void) {
        guard !busy else { return }; setBusy(true,message)
        worker.async { [weak self] in
            guard let self else { return }
            let result:Result<LoadedPDF,Error>=Result { if self.engine == nil { self.engine=try Engine() }; return try work(self.engine!) }
            DispatchQueue.main.async {
                switch result {
                case .success(let value): done(value)
                case .failure(let error):
                    self.setBusy(false,"Could not complete the operation")
                    if self.loaded != nil { self.table.selectRowIndexes(IndexSet(integer:self.pageIndex),byExtendingSelection:false) }
                    self.showError(error)
                }
            }
        }
    }
    private func canDiscard() -> Bool {
        if busy { NSSound.beep(); return false }
        guard loaded != nil && dirty else { return true }
        let alert=NSAlert(); alert.messageText="Discard unsaved changes?"; alert.informativeText="Save a copy first if you want to keep your edits."; alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    private func openURL(_ url:URL, sample:Bool=false) {
        guard !busy,canDiscard() else { return }
        let width=min(2400,max(240,Int(612*zoom*(window.backingScaleFactor))))
        perform("Opening \(url.lastPathComponent)…",work:{ engine in try engine.load(Engine.read(url),page:0,width:width) },done:{ [self] document in
            fileURL=sample ? nil : url; savedBytes=document.bytes; history=[]; future=[]; show(document,page:0); scroll.contentView.scroll(to:.zero)
        })
    }
    @objc private func openFile() {
        guard !busy else { return }; let panel=NSOpenPanel(); panel.allowedContentTypes=[.pdf]; panel.allowsMultipleSelection=false
        panel.beginSheetModal(for:window) { [weak self] result in if result == .OK,let url=panel.url { self?.openURL(url) } }
    }
    @objc private func openSample() { if let url=Bundle.main.url(forResource:"Welcome to Pod",withExtension:"pdf") { openURL(url,sample:true) } }
    private func navigate(_ page:Int, at candidateZoom:CGFloat?=nil) {
        guard !busy,let document=loaded,document.pages.indices.contains(page) else { return }
        let targetZoom=candidateZoom ?? zoom
        let width=min(2400,max(240,Int(document.pages[page].box.width*targetZoom*window.backingScaleFactor)))
        perform("Rendering page \(page+1)…",work:{ try $0.load(document.bytes,page:page,width:width) },done:{ [self] result in zoom=targetZoom; show(result,page:page); scroll.contentView.scroll(to:.zero) })
    }
    @objc private func previousPage() { navigate(pageIndex-1) }
    @objc private func nextPage() { navigate(pageIndex+1) }
    private func changeZoom(_ value:CGFloat) { guard !busy,loaded != nil else { return }; navigate(pageIndex,at:min(2,max(0.4,value))) }
    @objc private func zoomIn() { changeZoom(zoom+0.15) }
    @objc private func zoomOut() { changeZoom(zoom-0.15) }
    @objc private func fitPage() { guard let page=loaded?.pages[pageIndex] else { return }; changeZoom(min((scroll.contentSize.width-56)/page.box.width,(scroll.contentSize.height-56)/page.box.height)) }
    private func appendHistory(_ bytes:Data,to stack:inout [Data]) {
        stack.append(bytes)
        while stack.count>20 || (stack.count>1 && stack.reduce(0,{$0+$1.count})>64*1024*1024) { stack.removeFirst() }
    }
    @objc private func applyEdit() {
        guard !busy,let document=loaded,let run=selection else { return }
        let text=replacement.stringValue, page=pageIndex, width=pixelWidth
        perform("Updating text…",work:{ engine in let edited=try engine.replace(document.bytes,page:page,run:run,text:text); return try engine.load(edited,page:page,width:width) },done:{ [self] result in
            appendHistory(document.bytes,to:&history); future=[]; show(result,page:page); select(run)
        })
    }
    @objc private func undoEdit() { restore(undo:true) }
    @objc private func redoEdit() { restore(undo:false) }
    private func restore(undo:Bool) {
        guard !busy,let document=loaded,let bytes=(undo ? history.last : future.last) else { return }
        let page=pageIndex,width=pixelWidth
        perform(undo ? "Undoing…" : "Redoing…",work:{ try $0.load(bytes,page:page,width:width) },done:{ [self] result in
            if undo { history.removeLast(); appendHistory(document.bytes,to:&future) } else { future.removeLast(); appendHistory(document.bytes,to:&history) }
            show(result,page:page)
        })
    }
    @objc private func saveCopy() {
        guard !busy,let document=loaded else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.pdf]; panel.nameFieldStringValue=(fileURL?.deletingPathExtension().lastPathComponent ?? "Welcome to Pod")+" edited.pdf"
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self,result == .OK,let url=panel.url else { return }
            if let source=self.fileURL,source.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL {
                self.showError(EngineError(message:"Choose a different filename to preserve your original PDF.")); return
            }
            // Exclusive creation also rejects hard-link aliases and avoids overwriting existing files.
            self.setBusy(true,"Saving a copy…")
            self.worker.async {
                let result:Result<Void,Error>=Result { try document.bytes.write(to:url,options:.withoutOverwriting) }
                DispatchQueue.main.async {
                    self.setBusy(false)
                    switch result {
                    case .success: self.savedBytes=document.bytes; self.updateControls(); self.status.stringValue="Saved \(url.lastPathComponent)"
                    case .failure(let error): self.showError(error)
                    }
                }
            }
        }
    }
    private func showError(_ error:Error) { let alert=NSAlert(); alert.messageText="Pod couldn’t complete that"; alert.informativeText=error.localizedDescription; alert.alertStyle = .warning; alert.beginSheetModal(for:window) }
    private func makeMarkupToolbar() -> NSStackView {
        let bar=NSStackView(); bar.orientation = .horizontal; bar.spacing=8; bar.edgeInsets=NSEdgeInsets(top:8,left:16,bottom:8,right:16)
        let title=label("MARK UP",10); title.font = .systemFont(ofSize:10,weight:.semibold); bar.addArrangedSubview(title)
        let select=button("Select","cursorarrow",#selector(selectTool)); bar.addArrangedSubview(select); markupButtons.append(select)
        let erase=button("Eraser","eraser",#selector(eraserTool)); bar.addArrangedSubview(erase); markupButtons.append(erase)
        for (title,kind,tag) in [("Shape",MarkupKind.rectangle,0),("Text tools",.underline,1),("Highlight",.highlight,2),("Draw",.ink,3),("Type",.freeText,4),("Add comment",.comment,5)] {
            let split=NSStackView(); split.spacing=0
            let main=button(title,kind.symbol,#selector(toolPicked)); main.tag=Int(kind.rawValue); toolButtons.append(main)
            let more=button("⌄",nil,#selector(openPalette)); more.tag=tag; more.toolTip="\(title) options"; more.setAccessibilityLabel("\(title) options")
            more.widthAnchor.constraint(equalToConstant:24).isActive=true
            split.addArrangedSubview(main); split.addArrangedSubview(more); bar.addArrangedSubview(split); markupButtons += [main,more]
        }
        let space=NSView(); space.setContentHuggingPriority(.defaultLow,for:.horizontal); bar.addArrangedSubview(space)
        let comments=button("","text.bubble",#selector(toggleComments)); comments.setAccessibilityLabel("Comments panel"); bar.addArrangedSubview(comments); markupButtons.append(comments)
        return bar
    }
    @objc private func selectTool() { palette?.close(); markupTool=nil; canvas.tool=nil; canvas.erasing=false; commentsVisible=false; toolButtons.forEach{$0.contentTintColor=nil}; refreshInspector(); status.stringValue="Select text to edit, or an annotation to move and resize." }
    @objc private func eraserTool() { selectTool(); canvas.erasing=true; status.stringValue="Click an annotation to remove it. Original page content is preserved." }
    @objc private func toolPicked(_ sender:NSButton) { if let kind=MarkupKind(rawValue:UInt32(sender.tag)) { chooseTool(kind) } }
    private func chooseTool(_ kind:MarkupKind) {
        markupTool=kind; markupStyle = toolStyles[kind] ?? .initial(for:kind); canvas.tool=kind;
        for (index,button) in toolButtons.enumerated() {
            let group = kind.isShape ? 0 : ([.underline,.squiggly,.strikeout].contains(kind) ? 1:([.highlight,.freehandHighlight].contains(kind) ? 2:(kind == .ink ? 3:(kind == .freeText ? 4:5))))
            button.contentTintColor=index == group ? .systemTeal:nil
            if index == group { button.tag=Int(kind.rawValue); button.image=NSImage(systemSymbolName:kind.symbol,accessibilityDescription:kind.title) }
        }
 canvas.erasing=false; canvas.annotationStyle=markupStyle
        selectedMarkup=nil; canvas.annotationSelection=nil; selection=nil; canvas.selected=nil; commentsVisible=false
        status.stringValue=kind.hint; refreshInspector()
    }
    @objc private func openPalette(_ sender:NSButton) {
        let groups:[[MarkupKind]]=[Array(MarkupKind.allCases.prefix(10)),[.underline,.squiggly,.strikeout],[.highlight,.freehandHighlight],[.ink],[.freeText],[.comment]]
        let group=groups[sender.tag]
        let current=markupTool.flatMap{group.contains($0) ? $0:nil} ?? group[0]
        if markupTool != current { chooseTool(current) }
        let content=MarkupPalette(kinds:group,current:current,style:markupStyle)
        content.onChoose={ [weak self] kind in self?.chooseTool(kind); return self?.markupStyle ?? .initial(for:kind) }
        content.onStyle={ [weak self] style in self?.setMarkupStyle(style) }
        palette?.close(); let pop=NSPopover(); pop.behavior = .transient; pop.contentViewController=content; palette=pop; pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY)
    }
    private func setMarkupStyle(_ style:MarkupStyle) {
        guard !busy else { return }
        markupStyle=style; canvas.annotationStyle=style
        if let tool=markupTool { toolStyles[tool]=style }
        inspector.arrangedSubviews.compactMap{$0 as? MarkupStyleView}.forEach{$0.setStyle(style)}
        (palette?.contentViewController as? MarkupPalette)?.setStyle(style)
        if let id=selectedMarkup,var mark=loaded?.pages[pageIndex].annotations.first(where:{$0.id==id}) { mark.style=style; mutateAnnotations([mark]) }
    }
    private func selectAnnotation(_ id:UInt32?) {
        selectedMarkup=id; canvas.annotationSelection=id
        if let id,let mark=loaded?.pages[pageIndex].annotations.first(where:{$0.id==id}) {
            markupTool=nil; canvas.tool=nil; canvas.erasing=false; selection=nil; canvas.selected=nil; markupStyle=mark.style
        }
        refreshInspector()
    }
    private func refreshInspector() {
        guard !textInspectorViews.isEmpty else { return }
        for view in inspector.arrangedSubviews { inspector.removeArrangedSubview(view); view.removeFromSuperview() }
        func add(_ view:NSView) { inspector.addArrangedSubview(view); if !(view is MarkupStyleView) { view.widthAnchor.constraint(equalToConstant:220).isActive=true } }
        if commentsVisible {
            add(label("Comments",17,.labelColor))
            let comments=loaded?.pages[pageIndex].annotations.filter{$0.kind == .comment} ?? []
            if comments.isEmpty { add(label("No comments on this page. Choose Add comment, then click on the page.",12)) }
            for comment in comments {
                let b=button(comment.text.isEmpty ? "Empty comment":comment.text,"text.bubble",#selector(commentSelected)); b.tag=Int(comment.id); b.lineBreakMode = .byTruncatingTail; add(b)
            }
        } else if let id=selectedMarkup,let mark=loaded?.pages[pageIndex].annotations.first(where:{$0.id==id}) {
            add(label(mark.kind.title,17,.labelColor)); add(label("Drag to move. Drag the corner handle to resize.",11))
            if mark.kind.isText {
                annotationText.stringValue=mark.text; annotationText.placeholderString=mark.kind == .comment ? "Comment":"Text"; annotationText.setAccessibilityLabel("Annotation text"); annotationText.target=self; annotationText.action=#selector(updateAnnotationText)
                add(annotationText); add(button("Update text",nil,#selector(updateAnnotationText)))
            }
            let style=MarkupStyleView(kind:mark.kind,style:mark.style); style.onChange={ [weak self,weak style] value in
                guard let self,let style,self.inspector.arrangedSubviews.contains(where:{$0 === style}) else { return }
                self.setMarkupStyle(value)
            }; add(style)
            add(button("Delete annotation","trash",#selector(deleteAnnotation)))
        } else if let tool=markupTool {
            add(label(tool.title,17,.labelColor)); add(label(tool.hint,12))
            let style=MarkupStyleView(kind:tool,style:markupStyle); style.onChange={ [weak self,weak style] value in
                guard let self,let style,self.inspector.arrangedSubviews.contains(where:{$0 === style}) else { return }
                self.setMarkupStyle(value)
            }; add(style)
            if tool.isTextMarkup { add(label("Text markup follows complete text runs in this preview.",11)) }
            if tool == .freeText { add(label("Courier regular · printable English text",11)) }
        } else {
            for view in textInspectorViews { inspector.addArrangedSubview(view) }
            return
        }
        let spacer=NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.vertical); inspector.addArrangedSubview(spacer)
    }
    @objc private func toggleComments() { commentsVisible.toggle(); refreshInspector() }
    @objc private func commentSelected(_ sender:NSButton) { commentsVisible=false; selectAnnotation(UInt32(sender.tag)); canvas.needsDisplay=true }
    @objc private func updateAnnotationText() {
        guard let id=selectedMarkup,var mark=loaded?.pages[pageIndex].annotations.first(where:{$0.id==id}) else { return }
        mark.text=annotationText.stringValue; mutateAnnotations([mark])
    }
    @objc private func deleteAnnotation() { if let id=selectedMarkup { mutateAnnotations([],deleting:[id]) } }
    private func createAnnotations(_ marks:[Markup]) {
        guard !busy,!marks.isEmpty else { return }
        if marks.count==1,marks[0].kind.isText {
            let alert=NSAlert(); alert.messageText=marks[0].kind == .comment ? "Add a comment":"Add text"
            alert.informativeText=marks[0].kind == .comment ? "Your comment will be saved inside this PDF.":"Enter text for this box. Courier regular is supported."
            let input=NSTextField(frame:NSRect(x:0,y:0,width:320,height:26)); input.setAccessibilityLabel("New annotation text"); alert.accessoryView=input; alert.addButton(withTitle:"Add"); alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:window) { [weak self] result in
                guard result == .alertFirstButtonReturn,!input.stringValue.isEmpty else { return }
                var mark=marks[0]; mark.text=input.stringValue; self?.mutateAnnotations([mark])
            }
            alert.window.makeFirstResponder(input)
        } else { mutateAnnotations(marks) }
    }
    private func mutateAnnotations(_ marks:[Markup],deleting:[UInt32]=[]) {
        guard !busy,let document=loaded else { return }
        let page=pageIndex,width=pixelWidth
        perform("Updating annotations…",work:{ engine in let bytes=try engine.annotate(document.bytes,page:page,marks:marks,deleting:deleting); return try engine.load(bytes,page:page,width:width) },done:{ [self] result in
            appendHistory(document.bytes,to:&history); future=[]; show(result,page:page)
            if let mark=marks.last {
                let id=mark.id == 0 ? result.pages[page].annotations.last?.id:mark.id
                if mark.kind.isText || mark.id != 0 { selectAnnotation(id) }
            }
        })
    }
    @objc private func about() { let alert=NSAlert(); alert.messageText="Pod"; alert.informativeText="A small, native PDF workspace.\n\nOwn Zig engine and CPU renderer. Native macOS interface.\n\nEarly preview: uncompressed PDFs using standard Courier text and supported vector graphics."; alert.beginSheetModal(for:window) }
    @objc private func quit() { NSApp.terminate(nil) }
}
