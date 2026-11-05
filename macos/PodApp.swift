import AppKit
import UniformTypeIdentifiers

@main
final class PodApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private let worker=DispatchQueue(label:"com.pod.engine",qos:.userInitiated)
    private var reactEditor:ReactEditor?
    private let navigationPreviews = NavigationPreviews()
    private var viewRotation = 0
    private var legacyEditorRoot:NSView?
    private var reactLastImage:NSImage?
    private var reactDisplayName:String?
    private var engine: Engine?
    private var loaded: LoadedPDF?
    private var fileURL: URL?
    private var pendingURL: URL?
    private var savedBytes: Data?
    private var history = PDFEditHistory()
    private var pageIndex=0
    private var zoom: CGFloat=0.95
    private var queuedStrokes:[(mark:Markup,draftID:Int?)]=[]
    private var afterInkCommit: (() -> Void)?
    private var acceptingStrokes=false
    private var updatingAnnotations=false
    private var busy=false
    private var selection: Int?
    private let canvas=PageCanvas()
    private let scroll=NSScrollView()
    private let table=NSTableView()
    private let fileLabel=NSTextField(labelWithString:"Welcome to Pod")
    private let status=NSTextField(labelWithString:"Opening the sample…")
    private let footerDock=LuminFooterDock()
    private let documentHeader=LuminDocumentHeader()
    private let utilityRail=LuminUtilityRail()
    private let focusRestore=LuminFocusRestore()
    private var focusMode=false
    private var headerHeight:NSLayoutConstraint?
    private var modeRailWidth:NSLayoutConstraint?
    private var utilityRailWidth:NSLayoutConstraint?
    private var headerPopup:LuminPopper?
    private var headerStarred=false
    private var shareDialog:LuminShareDialog?
    private var shareModal:LuminModal?
    private let selectionLabel=NSTextField(wrappingLabelWithString:"Select a line on the page to edit it.")
    private let replacement=NSTextField(string:"")
    private let details=NSTextField(wrappingLabelWithString:"")
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
    private let pagesButton=NSPopUpButton(frame:.zero,pullsDown:true)
    private let spinner=NSProgressIndicator()
    private let inspector=PodSurfaceStack()
    private let viewerChrome=ViewerChrome()
    private let organizer=OrganizerPreview()
    private var inspectorWidth:NSLayoutConstraint?
    private var canvasTop:NSLayoutConstraint?
    private var thumbnailWidth:NSLayoutConstraint?
    private var thumbnailPanel:NSView?
    private var designSystemWindow:NSWindow?
    private var selectButton:PodButton!
    private var eraseButton:PodButton!
    private var commentsButton:PodButton!
    private var textInspectorViews:[NSView]=[]
    private var markupTool:MarkupKind?
    private var markupStyle=MarkupStyle()
    private var selectedMarkup:UInt32?
    private var editContext=UUID()
    private var selectedSharedStroke:DrawingStroke? {
        guard let session=drawingSession,let id=canvas.selectedSharedInk else { return nil }
        return canvas.sharedDrawings.first { $0.id==id && $0.page==pageIndex && $0.owner==session.owner && !$0.removed }
    }
    private var selectedAnnotationMark:Markup? {
        if drawingSession != nil { return selectedSharedStroke?.markup }
        guard let id=selectedMarkup else { return nil }
        return loaded?.pages[pageIndex].annotations.first { $0.id==id }
    }
    private var pageComments:[(id:String,text:String)] {
        if let session=drawingSession {
            return canvas.sharedDrawings.filter{$0.owner==session.owner && !$0.text.isEmpty}.map{($0.id.uuidString,$0.text)}
        }
        let marks=loaded?.pages[pageIndex].annotations ?? []
        return marks.filter{$0.kind == .comment || ($0.kind == .ink && !$0.text.isEmpty)}.map{(String($0.id),$0.text)}
    }
    private func clearAnnotationSelection() {
        selectedMarkup=nil
        canvas.annotationSelection=nil
        canvas.selectedSharedInk=nil
        editContext=UUID()
    }
    private var palette:LuminPopper?
    private var markupButtons:[NSButton]=[]
    private var toolButtons:[NSButton]=[]
    private var toolStyles:[MarkupKind:MarkupStyle]=[:]
    private let annotationText=NSTextField(string:"")
    private let annotationLink=NSTextField(string:"")
    private var drawShortcutMonitor:Any?
    private var commentsVisible=false
    private var disabledInspectorControls:[(NSControl,Bool)]=[]

    private var drawingSession:DrawingSession?
    private var savedDrawingRevision=0
    private var savePanelOpen=false
    private var pendingDrawingURL:URL?
    private var shareButton:NSButton!
    private let peerStatus=NSTextField(labelWithString:"")
    private var dirty: Bool { canvas.hasPendingInk || loaded?.bytes != savedBytes || (drawingSession.map{$0.board.revision != savedDrawingRevision} ?? false) }

    static func main() {
        let app=NSApplication.shared
        let delegate=PodApp(); app.delegate=delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        configureWindow()
        drawShortcutMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self,event.window === self.window,self.window.attachedSheet==nil,
                  self.loaded != nil,!self.busy,!event.isARepeat,
                  event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty,
                  self.window.firstResponder === self.canvas || self.window.firstResponder === self.window ||
                    (self.reactEditor==nil && !(self.window.firstResponder is NSText)) else { return event }
            if [51,117].contains(event.keyCode),self.selectedAnnotationMark?.inkLocked==false {
                self.deleteAnnotation(); return nil
            }
            guard event.charactersIgnoringModifiers?.lowercased()=="f" else { return event }
            if self.markupTool != .ink { self.chooseTool(.ink) }; self.viewerChrome.toolbar.selectTool("Draw"); return nil
        }
        if ProcessInfo.processInfo.environment["POD_REACT_SMOKE"] == "1" && ProcessInfo.processInfo.environment["POD_REQUIRE_METAL"] != "1" { window.orderBack(nil) } else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
        if let url=pendingURL { pendingURL=nil; openURL(url) } else { openSample() }
        if ProcessInfo.processInfo.environment["POD_REACT_SMOKE"] == "1" { runReactSmokeCheck() }
    }
    deinit { if let drawShortcutMonitor { NSEvent.removeMonitor(drawShortcutMonitor) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { canDiscard() ? .terminateNow : .terminateCancel }
    func windowShouldClose(_ sender:NSWindow) -> Bool { canDiscard() }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        if let name=filenames.first {
            let url=URL(fileURLWithPath:name)
            if window == nil || busy || savePanelOpen { pendingURL=url } else { openURL(url) }
        }
        sender.reply(toOpenOrPrint:.success)
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        guard let url=urls.first else { return }
        if url.scheme=="pod" {
            if window==nil || busy || savePanelOpen { pendingDrawingURL=url } else { joinDrawing(url) }
        } else if url.isFileURL {
            if window==nil || busy || savePanelOpen { pendingURL=url } else { openURL(url) }
        }
    }
    private func button(_ title:String,_ image:String?=nil,_ action:Selector) -> PodButton {
        let button=PodButton(title:title,target:self,action:action)
        if let image { button.image=LuminAssets.tool(title) ?? NSImage(systemSymbolName:image,accessibilityDescription:title); button.imagePosition = .imageLeading }
        button.toolTip=title; button.setAccessibilityLabel(title)
        return button
    }
    private func label(_ string:String,_ size:CGFloat=12,_ color:NSColor = PodTheme.secondaryText) -> NSTextField {
        let label=NSTextField(wrappingLabelWithString:string); label.font = .systemFont(ofSize:size); label.textColor=color
        return label
    }
    private func configureMenus() {
        let main=NSMenu(); NSApp.mainMenu=main
        func menu(_ title:String) -> NSMenu { let item=NSMenuItem(); main.addItem(item); let menu=NSMenu(title:title); item.submenu=menu; return menu }
        func add(_ menu:NSMenu,_ title:String,_ action:Selector,_ key:String="") { let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item) }
        let app=menu("Pod"); add(app,"About Pod",#selector(about)); app.addItem(.separator()); add(app,"Quit Pod",#selector(quit),"q")
        let file=menu("File"); add(file,"Open…",#selector(openFile),"o"); add(file,"Open Sample",#selector(openSample)); add(file,"Save a Copy…",#selector(saveCopy),"s")
        let sharing=menu("Collaborate")
        add(sharing,"Share Drawing…",#selector(shareDrawing)); add(sharing,"Join Drawing…",#selector(joinDrawingPrompt))
        add(sharing,"Reconnect",#selector(reconnectDrawing)); add(sharing,"End Drawing Session",#selector(endDrawing))
        let edit=menu("Edit"); add(edit,"Undo PDF Edit",#selector(undoEdit),"z"); add(edit,"Redo PDF Edit",#selector(redoEdit),"Z"); edit.addItem(.separator())
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(NSMenuItem(title:title,action:action,keyEquivalent:key))
        }
        let pages=menu("Pages"); populatePagesMenu(pages)
        let view=menu("View"); add(view,"Design System",#selector(showDesignSystem))
    }
    private func configureWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Pod"; window.minSize=NSSize(width:1160,height:680); window.center(); window.delegate=self
        window.titlebarAppearsTransparent=true; window.backgroundColor = PodTheme.chrome
        let root=PodSurfaceView(); window.contentView=root
        let header=documentHeader
        openButton=button("Open","folder",#selector(openFile)); sampleButton=button("Sample",nil,#selector(openSample))
        undoButton=button("","arrow.uturn.backward",#selector(undoEdit)); undoButton.toolTip="Undo PDF edit"; undoButton.setAccessibilityLabel("Undo PDF edit")
        redoButton=button("","arrow.uturn.forward",#selector(redoEdit)); redoButton.toolTip="Redo PDF edit"; redoButton.setAccessibilityLabel("Redo PDF edit")
        saveButton=button("Save a Copy","square.and.arrow.down",#selector(saveCopy))
        shareButton=header.share
        fileLabel.stringValue="Welcome to Pod.pdf"
        pagesButton.addItem(withTitle:"Pages"); populatePagesMenu(pagesButton.menu!)
        pagesButton.setAccessibilityLabel("Page tools"); pagesButton.toolTip="Merge, split, reorder, rotate and crop pages"
        header.onAction={ [weak self] sender in self?.headerPicked(sender) }
        let sidebar=PodSurfaceView(); sidebar.surface=PodTheme.chrome; sidebar.isHidden=true; thumbnailPanel=sidebar
        let sidebarTitle=label("PAGES",10); sidebarTitle.font = .systemFont(ofSize:10,weight:.semibold)
        let sidebarScroll=NSScrollView(); sidebarScroll.hasVerticalScroller=true; sidebarScroll.drawsBackground=false
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("page")); column.width=140; table.addTableColumn(column)
        table.headerView=nil; table.rowHeight=60; table.intercellSpacing=NSSize(width:0,height:8); table.dataSource=self; table.delegate=self; table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular; table.setAccessibilityLabel("Document pages"); sidebarScroll.documentView=table
        let sidebarNote=label("LOCAL BY DESIGN\nShare directly when you choose.",10)
        for view in [sidebarTitle,sidebarScroll,sidebarNote] { sidebar.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([sidebarTitle.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:20),sidebarTitle.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:18),sidebarScroll.topAnchor.constraint(equalTo:sidebarTitle.bottomAnchor,constant:16),sidebarScroll.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:8),sidebarScroll.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-8),sidebarScroll.bottomAnchor.constraint(equalTo:sidebarNote.topAnchor,constant:-20),sidebarNote.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:18),sidebarNote.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-12),sidebarNote.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-20)])
        scroll.contentView=LuminCanvasClipView(); scroll.scrollerStyle = .overlay
        scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.autohidesScrollers=true; scroll.documentView=canvas; scroll.drawsBackground=false
        canvas.onSelect={ [weak self] id in self?.select(id) }
        canvas.onAnnotationSelect={ [weak self] id in self?.selectAnnotation(id) }
        canvas.onSelectSharedInk={ [weak self] id in self?.selectSharedInk(id) }
        canvas.onUpdateSharedInk={ [weak self] id,mark in
            guard let self,id==self.selectedSharedStroke?.id else { return }
            self.updateSelectedMark(mark)
        }
        canvas.onEraseAnnotations={ [weak self] updates,deleting in self?.mutateAnnotations(updates,deleting:deleting) }
        canvas.onEraseSharedGroup={ [weak self] updates,deleting in
            guard let self else { return }
            do { try self.drawingSession?.erase(updates:updates,deleting:deleting) } catch { self.showError(error) }
        }
        canvas.onEraseLimit={ [weak self] in self?.showError(EngineError(message:"This cut would exceed the PDF ink point limit. Erase a smaller section.")) }
        canvas.onInkLift={ [weak self] in self?.updateControls() }
        canvas.onCreate={ [weak self] marks in self?.createAnnotations(marks) }
        canvas.onUpdate={ [weak self] mark in self?.mutateAnnotations([mark]) }
        canvas.onDelete={ [weak self] id in self?.mutateAnnotations([],deleting:[id]) }
        canvas.onCursor={ [weak self] point,drawing in guard let self else { return }; self.drawingSession?.updateCursor(point,page:self.pageIndex,drawing:drawing) }
        canvas.onDraft={ [weak self] mark in guard let self else { return }; self.drawingSession?.preview(mark,page:self.pageIndex) }
        canvas.onEraseShared={ [weak self] id in
            guard let self else { return }; do { try self.drawingSession?.remove(id) } catch { self.showError(error) }
        }

        inspector.orientation = .vertical; inspector.alignment = .leading; inspector.spacing=PodMetrics.section; inspector.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        let inspectorTitle=label("Text inspector",17,PodTheme.text); inspectorTitle.font = .systemFont(ofSize:17,weight:.semibold)
        selectionLabel.font = PodTypography.body; selectionLabel.textColor = PodTheme.secondaryText
        replacement.placeholderString="Replacement text"; replacement.font = .monospacedSystemFont(ofSize:12,weight:.regular); replacement.delegate=self; replacement.target=self; replacement.action=#selector(applyEdit); replacement.setAccessibilityLabel("Replacement text")
        applyButton=button("Replace text",nil,#selector(applyEdit)); (applyButton as? PodButton)?.emphasis = .primary
        details.font = .systemFont(ofSize:11); details.textColor = PodTheme.secondaryText
        let note=label("Keep replacements within the original line width. Pod preserves the position of the text that follows.",11)
        let divider=NSBox(); divider.boxType = .separator
        let support=label("EARLY PREVIEW",10); support.font = .systemFont(ofSize:10,weight:.semibold)
        let scope=label("Simple Courier PDFs are supported today. Use Mark up for shapes, highlights, drawing, text and comments. More fonts and scanned pages are still to come.",11)
        for view in [inspectorTitle,selectionLabel,replacement,applyButton!,details,note,divider,support,scope] {
            inspector.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant:PodMetrics.paletteContent).isActive=true
        }
        let spacer=NSView(); inspector.addArrangedSubview(spacer); spacer.setContentHuggingPriority(.defaultLow,for:.vertical)
        textInspectorViews=inspector.arrangedSubviews
        let body=NSView()
        for view in [sidebar,scroll,inspector] { body.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        thumbnailWidth=sidebar.widthAnchor.constraint(equalToConstant:0); thumbnailWidth?.isActive=true
        inspectorWidth=inspector.widthAnchor.constraint(equalToConstant:0); inspectorWidth?.isActive=true; inspector.isHidden=true
        canvasTop=scroll.topAnchor.constraint(equalTo:body.topAnchor); canvasTop?.isActive=true
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo:body.leadingAnchor),sidebar.topAnchor.constraint(equalTo:body.topAnchor),sidebar.bottomAnchor.constraint(equalTo:body.bottomAnchor),scroll.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:body.bottomAnchor),scroll.trailingAnchor.constraint(equalTo:inspector.leadingAnchor),inspector.topAnchor.constraint(equalTo:body.topAnchor),inspector.bottomAnchor.constraint(equalTo:body.bottomAnchor),inspector.trailingAnchor.constraint(equalTo:body.trailingAnchor)])
        let footer=footerDock
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped=false
        status.font = PodTypography.caption; status.textColor=PodTheme.secondaryText
        prevButton=footer.previousPage; nextButton=footer.nextPage
        zoomOutButton=footer.zoomOut; zoomInButton=footer.zoomIn
        zoomOutButton.target=self; zoomOutButton.action=#selector(zoomOut)
        zoomInButton.target=self; zoomInButton.action=#selector(zoomIn)
        fitButton=button("Fit",nil,#selector(fitPage))
        footer.onPage={ [weak self] page in self?.navigate(page-1) }
        footer.onZoom={ [weak self] value in self?.viewerChrome.updateZoomPercentage(value) }
        _ = makeMarkupToolbar() // Retain existing tool targets for the viewer chrome.
        let markupBar=viewerChrome.toolbar
        let typeBar=viewerChrome.typeToolbar; typeBar.translatesAutoresizingMaskIntoConstraints=false; body.addSubview(typeBar)
        NSLayoutConstraint.activate([typeBar.leadingAnchor.constraint(equalTo:body.leadingAnchor),typeBar.trailingAnchor.constraint(equalTo:body.trailingAnchor),typeBar.topAnchor.constraint(equalTo:body.topAnchor)])
        viewerChrome.onTypeVisibility={ [weak self] visible in self?.canvasTop?.constant=visible ? 40:0; self?.window.contentView?.layoutSubtreeIfNeeded(); self?.canvas.resizeToViewport() }
        viewerChrome.onTypeChange={ [weak self] state in guard let self else { return }; var style=markupStyle; style.stroke=state.textColor; style.fill=state.fill; style.opacity=state.opacity; style.fontSize=Double(state.size); setMarkupStyle(style) }
        viewerChrome.onMarkup={ [weak self] kind in self?.chooseTool(kind) }
        viewerChrome.onStyle={ [weak self] kind,sender in
            guard let self else { return }; chooseTool(kind)
            let content=MarkupPalette(kinds:[kind],current:kind,style:markupStyle)
            content.onStyle={ [weak self] style in self?.setMarkupStyle(style) }
            palette?.close(); let pop=LuminPopper(); pop.contentViewController=content; palette=pop
            // The legacy Highlight properties stay attached to their32px menu trigger.
            pop.alignment = .center; pop.gap=8
            pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY)
        }
        viewerChrome.onNavigationClose={ [weak self] in self?.setNavigationExpanded(false) }
        viewerChrome.onFocusMode={ [weak self] in guard let self else { return }; setFocusMode(!focusMode) }
        focusRestore.onRestore={ [weak self] in self?.setFocusMode(false) }
        viewerChrome.onAction={ [weak self] title,sender in self?.viewerAction(title,sender) ?? false }
        viewerChrome.onZoomPreview={ [weak self] value in self?.footerDock.previewZoom(value) }
        viewerChrome.onMode={ [weak self] mode in
            guard let self else { return }; palette?.close(); organizer.pages=loaded?.pages ?? []; organizer.isHidden=mode != "Organize"; scroll.isHidden=mode == "Organize"; organizer.needsDisplay=true
            if mode == "Organize" { inspector.isHidden=true; inspectorWidth?.constant=0 }; updateControls()
        }
        organizer.requestPreviews = { [weak self] range in
            guard let self, !organizer.isHidden else { return }
            for index in range {
                _ = navigationPreviews.thumbnail(page: index + 1) { [weak self] png in
                    guard let self, !organizer.isHidden, let png, let image = NSImage(data: png) else { return }
                    organizer.installPreview(image, page: index)
                }
            }
        }
        organizer.isHidden=true; organizer.translatesAutoresizingMaskIntoConstraints=false; body.addSubview(organizer)
        NSLayoutConstraint.activate([organizer.leadingAnchor.constraint(equalTo:scroll.leadingAnchor),organizer.trailingAnchor.constraint(equalTo:scroll.trailingAnchor),organizer.topAnchor.constraint(equalTo:scroll.topAnchor),organizer.bottomAnchor.constraint(equalTo:scroll.bottomAnchor)])
        let formPanel=viewerChrome.formBuilderPanel; formPanel.translatesAutoresizingMaskIntoConstraints=false; body.addSubview(formPanel)
        NSLayoutConstraint.activate([formPanel.widthAnchor.constraint(equalToConstant:360),formPanel.trailingAnchor.constraint(equalTo:body.trailingAnchor),formPanel.topAnchor.constraint(equalTo:body.topAnchor),formPanel.bottomAnchor.constraint(equalTo:body.bottomAnchor)])
        viewerChrome.onFormVisibility={ [weak self] visible in
            guard let self else { return }
            if visible { palette?.close(); clearAnnotationSelection(); selection=nil; canvas.selected=nil; commentsVisible=false }
            utilityRail.buttons.first{$0.title=="Comments"}?.isEnabled = !visible
            refreshInspector(); window.contentView?.layoutSubtreeIfNeeded(); canvas.resizeToViewport()
        }
        let modeRail=viewerChrome.rail
        let utility=utilityRail; utility.onAction={ [weak self] sender in self?.utilityPicked(sender) }
        for view in [modeRail,utility] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        let initialLayout=LuminViewerLayout(viewport:root.bounds.size,focus:false)
        headerHeight=header.heightAnchor.constraint(equalToConstant:initialLayout.header.height)
        modeRailWidth=modeRail.widthAnchor.constraint(equalToConstant:initialLayout.toolbar.minX)
        utilityRailWidth=utility.widthAnchor.constraint(equalToConstant:root.bounds.width-initialLayout.toolbar.maxX)
        let railConstraints=[modeRail.leadingAnchor.constraint(equalTo:root.leadingAnchor),modeRail.topAnchor.constraint(equalTo:header.bottomAnchor),modeRail.bottomAnchor.constraint(equalTo:root.bottomAnchor),modeRailWidth!,utility.trailingAnchor.constraint(equalTo:root.trailingAnchor),utility.topAnchor.constraint(equalTo:header.bottomAnchor),utility.bottomAnchor.constraint(equalTo:root.bottomAnchor),utilityRailWidth!]
        for view in [header,markupBar,body,footer] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:root.leadingAnchor),header.trailingAnchor.constraint(equalTo:root.trailingAnchor),header.topAnchor.constraint(equalTo:root.topAnchor),headerHeight!,markupBar.topAnchor.constraint(equalTo:header.bottomAnchor),markupBar.leadingAnchor.constraint(equalTo:modeRail.trailingAnchor),markupBar.trailingAnchor.constraint(equalTo:utility.leadingAnchor),markupBar.heightAnchor.constraint(equalToConstant:PodMetrics.toolbar),body.topAnchor.constraint(equalTo:markupBar.bottomAnchor),body.leadingAnchor.constraint(equalTo:modeRail.trailingAnchor,constant:initialLayout.canvas.minX-initialLayout.toolbar.minX),body.trailingAnchor.constraint(equalTo:utility.leadingAnchor,constant:initialLayout.canvas.maxX-initialLayout.toolbar.maxX),body.bottomAnchor.constraint(equalTo:root.bottomAnchor),footer.centerXAnchor.constraint(equalTo:root.centerXAnchor),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16),footer.heightAnchor.constraint(equalToConstant:44)])
        NSLayoutConstraint.activate(railConstraints)
        root.addSubview(focusRestore); focusRestore.translatesAutoresizingMaskIntoConstraints=false; focusRestore.isHidden=true
        NSLayoutConstraint.activate([focusRestore.leadingAnchor.constraint(equalTo:root.leadingAnchor),focusRestore.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-(root.bounds.height-initialLayout.restore.maxY)),focusRestore.widthAnchor.constraint(equalToConstant:initialLayout.restore.width),focusRestore.heightAnchor.constraint(equalToConstant:initialLayout.restore.height)])
        window.initialFirstResponder=canvas
        viewerChrome.fit(width:window.contentView?.bounds.width ?? 1240)
        installReactEditor()
        updateControls()
    }
    private func setNavigationExpanded(_ value:Bool) {
        guard shareModal?.isShown != true,!focusMode,let root=window.contentView else { return }
        headerPopup?.close(); palette?.close(); viewerChrome.setNavigationExpanded(value); documentHeader.navigationExpanded=value
        let layout=LuminViewerLayout(viewport:root.bounds.size,focus:false,navigationExpanded:value)
        modeRailWidth?.constant=layout.toolbar.minX; root.layoutSubtreeIfNeeded(); viewerChrome.fit(width:root.bounds.width); canvas.resizeToViewport(); organizer.needsDisplay=true
    }
    private func setFocusMode(_ value:Bool) {
        guard shareModal?.isShown != true,!busy,(!value || !viewerChrome.rail.navigationExpanded),let root=window.contentView else { return }
        headerPopup?.close(); palette?.close(); focusMode=value
        let layout=LuminViewerLayout(viewport:root.bounds.size,focus:value)
        headerHeight?.constant=layout.header.height; modeRailWidth?.constant=layout.toolbar.minX; utilityRailWidth?.constant=root.bounds.width-layout.toolbar.maxX
        documentHeader.isHidden=value; viewerChrome.rail.isHidden=value; utilityRail.isHidden=value; focusRestore.isHidden = !value
        root.layoutSubtreeIfNeeded(); viewerChrome.fit(width:root.bounds.width); canvas.resizeToViewport(); organizer.needsDisplay=true
        window.makeFirstResponder(value ? focusRestore.button:viewerChrome.rail.focusButton)
    }
    func windowDidResize(_ notification:Notification) { window?.contentView?.layoutSubtreeIfNeeded(); viewerChrome.fit(width:window?.contentView?.bounds.width ?? 1240); canvas.resizeToViewport(); organizer.needsDisplay=true }
    func numberOfRows(in tableView:NSTableView) -> Int { loaded?.pages.count ?? 0 }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let cell = PageThumbnailCell()
        let text = NSTextField(labelWithString: "Page \(row+1)")
        text.frame = NSRect(x: 57, y: 20, width: 83, height: 20)
        cell.addSubview(text)
        cell.textField = text
        if reactEditor == nil, thumbnailPanel?.isHidden == false {
            let image = NSImageView(frame: NSRect(x: 6, y: 3, width: 45, height: 54))
            image.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(image)
            cell.cancelPreview = navigationPreviews.thumbnail(page: row+1) { [weak image] png in
                image?.image = png.flatMap(NSImage.init(data:))
            }
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) { if table.selectedRow >= 0 && table.selectedRow != pageIndex { navigate(table.selectedRow) } }
    private func setBusy(_ value:Bool,_ message:String?=nil) {
        navigationPreviews.deferRendering(value)
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
        defer { publishReactState() }
        guard applyButton != nil else { return }
        let available=loaded != nil && !busy && (drawingSession==nil || drawingSession?.base != nil)
        pagesButton.isEnabled=available && drawingSession==nil
        openButton.isEnabled = !busy && drawingSession==nil; sampleButton.isEnabled = !busy && drawingSession==nil; saveButton.isEnabled=available; table.isEnabled = available
        applyButton.isEnabled=available && selection != nil && drawingSession==nil; replacement.isEnabled=available && selection != nil && drawingSession==nil
        undoButton.isEnabled=available && (canvas.hasPendingInk || (drawingSession.map{$0.board.canUndo($0.owner)} ?? !history.undo.isEmpty))
        redoButton.isEnabled=available && (drawingSession.map{$0.board.canRedo($0.owner)} ?? !history.redo.isEmpty)
        viewerChrome.rail.expandedPanel.uploadArea.button.isEnabled = !busy && drawingSession==nil
        viewerChrome.rail.focusButton.isEnabled = !busy; focusRestore.button.isEnabled = !busy
        shareButton.isEnabled=available; documentHeader.shareOptions.isEnabled=available; documentHeader.fileMenu.isEnabled = !busy
        documentHeader.documentStatus.toolTip=peerStatus.stringValue.isEmpty ? status.stringValue:peerStatus.stringValue
        prevButton.isEnabled=available && pageIndex>0; nextButton.isEnabled=available && pageIndex+1<(loaded?.pages.count ?? 0)
        footerDock.update(page:pageIndex+1,total:loaded?.pages.count ?? 1,percentage:Double((zoom*100).rounded()),available:available); fitButton.isEnabled=available
        for button in markupButtons { button.isEnabled=available }
        if drawingSession != nil {
            for button in markupButtons { button.isEnabled=available && (button === selectButton || button === eraseButton || button.action == #selector(toolPicked) && button.tag==Int(MarkupKind.ink.rawValue) || button.action == #selector(openPalette) && button.tag==3) }
        }
        viewerChrome.history(undo:undoButton.isEnabled,redo:redoButton.isEnabled)
        canvas.interactionEnabled=(available || acceptingStrokes) && ["Mark up","Popular","Fill & Sign"].contains(viewerChrome.mode)
        window?.isDocumentEdited=dirty
    }
    private func select(_ id:Int?) {
        selection=id; canvas.selected=id; canvas.needsDisplay=true
        if id != nil { clearAnnotationSelection() }
        if let id,let run=loaded?.pages[pageIndex].runs.first(where:{$0.id==id}) {
            selectionLabel.stringValue="Selected text"; replacement.stringValue=run.text; details.stringValue="Courier · \(String(format:"%.0f",run.size)) pt\nPage \(pageIndex+1) · Text run \(id+1)"
        } else { selectionLabel.stringValue="Select a line on the page to edit it."; replacement.stringValue=""; details.stringValue="" }
        updateControls(); refreshInspector()
    }
    private var metalDisabled = ProcessInfo.processInfo.environment["POD_RENDERER"] == "cpu"
    private func workerEngine() throws -> Engine {
        if let engine { return engine }
        let useCPU = ProcessInfo.processInfo.environment["POD_RENDERER"] == "cpu"
        let created = try Engine(metal: useCPU ? nil : MetalPageRenderer())
        engine = created
        return created
    }
    private func recoverMetalDisplay() {
        guard !metalDisabled else { return }
        metalDisabled = true
        // Replace the worker-owned renderer before any subsequent loads.
        worker.async { [weak self] in self?.engine = try? Engine() }
        if !busy, loaded != nil { navigate(pageIndex) }
    }
    private func show(_ document:LoadedPDF,page:Int,completingAnnotation:Bool=false,draftID:Int?=nil, animateInk:Bool=false, pageEdit:Bool=false) {
        navigationPreviews.update(document, changedPage: completingAnnotation || pageEdit ? page : nil) { [weak host = reactEditor] state in host?.setState(state) }
        var fadingInk: [Markup] = []
        if animateInk, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, pageIndex == page, let previous = loaded?.pages[page],
           previous.box == document.pages[page].box, previous.rotation == document.pages[page].rotation {
            let next = document.pages[page].annotations
            let oldInk = Dictionary(previous.annotations.filter { $0.kind == .ink }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let newInk = Dictionary(next.filter { $0.kind == .ink }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, old) in oldInk {
                guard let new = newInk[id] else { fadingInk.append(old); continue }
                if old.points != new.points || old.inkPathStarts != new.inkPathStarts ||
                    old.style.width != new.style.width || old.style.stroke != new.style.stroke || old.style.opacity != new.style.opacity {
                    fadingInk.append(contentsOf: [old, new])
                }
            }
            fadingInk += newInk.values.filter { oldInk[$0.id] == nil }
        }
        loaded=document; pageIndex=page; organizer.pages=document.pages; organizer.needsDisplay=true
        canvas.onMetalFailure = { [weak self] in self?.recoverMetalDisplay() }
        canvas.configure(document.pixels,page:document.pages[page],zoom:zoom,metalPage:metalDisabled ? nil : document.metalPage,viewRotation:viewRotation,completingAnnotation:completingAnnotation,draftID:draftID,fadingInk:fadingInk)
        table.reloadData(); table.selectRowIndexes(IndexSet(integer:page),byExtendingSelection:false)
        if thumbnailPanel?.isHidden == false { table.scrollRowToVisible(page) }
        footerDock.update(page:page+1,total:document.pages.count,percentage:Double((zoom*100).rounded()),available:!busy)
        viewerChrome.updateZoomPercentage(Double((zoom*100).rounded()))
        fileLabel.stringValue=reactDisplayName ?? drawingSession?.name ?? fileURL?.lastPathComponent ?? "Welcome to Pod.pdf"
        documentHeader.documentName=fileLabel.stringValue
        let navigationID=fileURL?.absoluteString ?? "sample"
        let thumbnail=page==0 ? canvas.image:viewerChrome.rail.expandedPanel.documents.first(where:{$0.id==navigationID})?.thumbnail
        viewerChrome.rail.expandedPanel.documents=[LuminNavigationDocument(id:navigationID,title:fileLabel.stringValue,thumbnail:thumbnail,selected:true)]
        window.title="\(fileLabel.stringValue) — Pod"; window.representedURL=fileURL
        clearAnnotationSelection()
        select(nil); setBusy(false,"\(document.pages.count) pages · \(ByteCountFormatter.string(fromByteCount:Int64(document.bytes.count),countStyle:.file)) · Rendered in \(Int(document.elapsedMS.rounded())) ms")
        refreshSharedDrawing()
        resumePendingOpen()
        if !updatingAnnotations,metalDisabled,document.metalPage != nil,!busy { navigate(page) }
    }
    private var pixelWidth:Int {
        let width=loaded?.pages[pageIndex].displaySize.width ?? 612
        return min(2400,max(240,Int(width*zoom*(window?.backingScaleFactor ?? 2))))
    }
    private func perform(_ message:String,work:@escaping (Engine) throws -> LoadedPDF,done:@escaping (LoadedPDF)->Void,failed:((Error)->Void)?=nil) {
        guard !busy else { return }; setBusy(true,message)
        worker.async { [weak self] in
            guard let self else { return }
            let result:Result<LoadedPDF,Error>=Result { try work(self.workerEngine()) }
            DispatchQueue.main.async {
                switch result {
                case .success(let value): done(value)
                case .failure(let error):
                    self.setBusy(false,"Could not complete the operation")
                    if self.loaded != nil { self.table.selectRowIndexes(IndexSet(integer:self.pageIndex),byExtendingSelection:false) }
                    failed?(error); self.showError(error)
                }
            }
        }
    }
    // Keep the action ordered after the last pen lift even inside its grouping window.
    private func waitForInk(_ action: @escaping () -> Void) -> Bool {
        let pending = canvas.hasPendingInk
        if pending { canvas.finishInk() }
        guard updatingAnnotations, pending || acceptingStrokes else { return false }
        if afterInkCommit == nil { afterInkCommit = action }
        return true
    }
    private func canDiscard() -> Bool {
        canvas.finishInk()
        if busy || savePanelOpen { NSSound.beep(); return false }
        guard loaded != nil && dirty else { return true }
        let alert=NSAlert(); alert.messageText="Discard unsaved changes?"; alert.informativeText="Save a copy first if you want to keep your edits."; alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    private func openURL(_ url:URL, sample:Bool=false) {
        if waitForInk({ [weak self] in self?.openURL(url,sample:sample) }) { return }
        guard drawingSession==nil else { showError(DrawingError(message:"End the drawing session before opening another PDF.")); return }
        guard !busy,canDiscard() else { return }
        let width=min(2400,max(240,Int(612*zoom*(window.backingScaleFactor))))
        perform("Opening \(url.lastPathComponent)…",work:{ engine in try engine.openPage(Engine.read(url),page:0,width:width) },done:{ [self] document in
            viewRotation=0; reactDisplayName=nil; fileURL=sample ? nil : url; savedBytes=document.bytes; history=PDFEditHistory(); show(document,page:0); scroll.contentView.scroll(to:.zero)
        })
    }
    @objc private func openFile() {
        guard !busy else { return }; let panel=NSOpenPanel(); panel.allowedContentTypes=[.pdf]; panel.allowsMultipleSelection=false
        panel.beginSheetModal(for:window) { [weak self] result in if result == .OK,let url=panel.url { self?.openURL(url) } }
    }
    @objc private func openSample() { if let url=Bundle.main.url(forResource:"Welcome to Pod",withExtension:"pdf") { openURL(url,sample:true) } }
    private func navigate(_ page:Int, at candidateZoom:CGFloat?=nil) {
        if waitForInk({ [weak self] in self?.navigate(page,at:candidateZoom) }) { return }
        guard !busy,drawingSession==nil || drawingSession?.base != nil,let document=loaded,document.pages.indices.contains(page) else { return }
        let targetZoom=candidateZoom ?? zoom
        let width=min(2400,max(240,Int(document.pages[page].displaySize.width*targetZoom*window.backingScaleFactor)))
        // Flattened curves remain sufficiently fine at smaller scales. Hairlines
        // are one device pixel wide, so rebuild their geometry at each scale.
        if page == pageIndex, candidateZoom != nil, !metalDisabled, let scene = document.metalPage,
           width <= scene.width, !scene.hairlines {
            zoom = targetZoom
            show(document, page: page)
            scroll.contentView.scroll(to: .zero)
            return
        }
        perform("Rendering page \(page+1)…",work:{ try $0.turnPage(document,page:page,width:width) },done:{ [self] result in zoom=targetZoom; show(result,page:page); scroll.contentView.scroll(to:.zero) })
    }
    @objc private func previousPage() { navigate(pageIndex-1) }
    @objc private func nextPage() { navigate(pageIndex+1) }
    private func changeZoom(_ value:CGFloat) { guard !busy,loaded != nil else { return }; navigate(pageIndex,at:min(3,max(0.1,value))) }
    @objc private func zoomIn() { changeZoom(zoom+0.15) }
    @objc private func zoomOut() { changeZoom(zoom-0.15) }
    @objc private func fitPage() { guard let page=canvas.page else { return }; changeZoom(min((scroll.contentSize.width-56)/page.displaySize.width,(scroll.contentSize.height-56)/page.displaySize.height)) }
    @objc private func applyEdit() {
        guard drawingSession==nil,!busy,let document=loaded,let run=selection else { return }
        let text=replacement.stringValue, page=pageIndex, width=pixelWidth
        perform("Updating text…",work:{ engine in let edited=try engine.replace(document.bytes,page:page,run:run,text:text); return try engine.openPage(edited,page:page,width:width) },done:{ [self] result in
            history.record(before:document.bytes); show(result,page:page,pageEdit:true); select(run)
        })
    }
    @objc private func undoEdit() {
        if waitForInk({ [weak self] in self?.undoEdit() }) { return }
        if let session=drawingSession { guard !busy else { return }; do { try session.undo() } catch { showError(error) } }
        else { restore(undo:true) }
    }
    @objc private func redoEdit() {
        if waitForInk({ [weak self] in self?.redoEdit() }) { return }
        if let session=drawingSession { guard !busy else { return }; do { try session.redo() } catch { showError(error) } }
        else { restore(undo:false) }
    }
    private func restore(undo:Bool) {
        guard !busy,let document=loaded,let revision=(undo ? history.undo.last : history.redo.last) else { return }
        let page=pageIndex,width=pixelWidth,priorSelection=selectedMarkup
        perform(undo ? "Undoing…" : "Redoing…",work:{ engine in try engine.openPage(revision.bytes(using:engine),page:page,width:width,clampPage:true) },done:{ [self] result in
            history.didRestore(undoing:undo,leaving:document.bytes)
            show(result,page:result.pageIndex,animateInk:true)
            if result.pageIndex==page,let id=priorSelection,result.pages[page].annotations.contains(where:{$0.id==id}) { selectAnnotation(id) }
        })
    }
    @objc private func saveCopy() {
        if waitForInk({ [weak self] in self?.saveCopy() }) { return }
        guard !busy,!savePanelOpen,loaded != nil,drawingSession==nil || drawingSession?.base != nil else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.pdf]; panel.nameFieldStringValue=(reactDisplayName.map{($0 as NSString).deletingPathExtension} ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Welcome to Pod")+" edited.pdf"
        savePanelOpen=true
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self else { return }
            self.savePanelOpen=false
            guard result == .OK,let url=panel.url,let document=self.loaded,!self.busy else { self.resumePendingOpen(); return }
            let session=self.drawingSession,board=session?.board
            if let session,session.base != document.bytes { self.showError(DrawingError(message:"The shared document changed. Try saving again after synchronization.")); return }
            if let source=self.fileURL,source.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL {
                self.showError(EngineError(message:"Choose a different filename to preserve your original PDF.")); return
            }
            // Exclusive creation also rejects hard-link aliases and avoids overwriting existing files.
            self.setBusy(true,"Saving a copy…")
            self.worker.async {
                let result:Result<Void,Error>=Result {
                    let bytes:Data
                    if let board { bytes=try board.export(document.bytes,using:self.workerEngine()) }
                    else { bytes=document.bytes }
                    try bytes.write(to:url,options:.withoutOverwriting)
                }
                DispatchQueue.main.async {
                    self.setBusy(false)
                    switch result {
                    case .success: self.savedBytes=document.bytes; if self.drawingSession === session { self.savedDrawingRevision=board?.revision ?? 0 }; self.updateControls(); self.status.stringValue="Saved \(url.lastPathComponent)"; self.resumePendingOpen()
                    case .failure(let error): self.showError(error)
                    }
                }
            }
        }
    }
    private func populatePagesMenu(_ menu:NSMenu) {
        for (title,action) in [("Merge PDF…",#selector(mergePDF)),("Extract Pages…",#selector(extractPages)),("Split into Separate Pages…",#selector(splitPages)),("Reorder Pages…",#selector(reorderPages)),("Move Page Earlier",#selector(movePageEarlier)),("Move Page Later",#selector(movePageLater)),("Rotate Clockwise",#selector(rotateClockwise)),("Rotate Counterclockwise",#selector(rotateCounterclockwise)),("Crop Page…",#selector(cropPage)),("Reset Page Crop",#selector(resetCrop))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:""); item.target=self; menu.addItem(item)
        }
    }
    func validateMenuItem(_ item:NSMenuItem) -> Bool {
        let actions:[Selector]=[#selector(mergePDF),#selector(extractPages),#selector(splitPages),#selector(reorderPages),#selector(movePageEarlier),#selector(movePageLater),#selector(rotateClockwise),#selector(rotateCounterclockwise),#selector(cropPage),#selector(resetCrop)]
        if let action=item.action,actions.contains(action) {
            guard drawingSession==nil,!busy,let document=loaded else { return false }
            if action == #selector(movePageEarlier) { return pageIndex>0 }
            if action == #selector(movePageLater) { return pageIndex+1<document.pages.count }
            return true
        }
        return true
    }
    private func changePages(_ message:String,page:Int?=nil,edit:@escaping(Engine,Data)throws->Data) {
        if waitForInk({ [weak self] in self?.changePages(message,page:page,edit:edit) }) { return }
        guard drawingSession==nil,!busy,let document=loaded else { return }
        let target=page ?? pageIndex,width=pixelWidth
        perform(message,work:{ engine in
            try engine.openPage(edit(engine,document.bytes),page:target,width:width,clampPage:true)
        },done:{ [self] result in
            history.record(before:document.bytes); show(result,page:result.pageIndex)
        })
    }
    @objc private func mergePDF() {
        guard !busy,loaded != nil else { return }
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.pdf]; panel.allowsMultipleSelection=false
        panel.message="Append every page from another PDF to this document."
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self,result == .OK,let url=panel.url else { return }
            self.changePages("Merging \(url.lastPathComponent)…") { engine,bytes in try engine.merge(bytes,with:Engine.read(url)) }
        }
    }
    private func pageSelection(_ title:String,initial:String,explanation:String) -> [Int]? {
        guard !busy,let document=loaded else { return nil }
        let alert=NSAlert(); alert.messageText=title; alert.informativeText=explanation+"\nUse page numbers or ranges, such as 1, 3-5."
        let field=NSTextField(string:initial); field.frame=NSRect(x:0,y:0,width:320,height:24); field.setAccessibilityLabel("Page numbers")
        alert.accessoryView=field; alert.addButton(withTitle:"Continue"); alert.addButton(withTitle:"Cancel"); alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        do { return try PageSelection.parse(field.stringValue,count:document.pages.count) } catch { showError(error); return nil }
    }
    @objc private func reorderPages() {
        guard !busy,let document=loaded,let indices=pageSelection("Reorder pages",initial:"1-\(document.pages.count)",explanation:"List every page once, in the new order.") else { return }
        guard indices.count==document.pages.count else { showError(EngineError(message:"Include every page exactly once to reorder the document. Use Extract Pages to create a smaller PDF.")); return }
        let target=indices.firstIndex(of:pageIndex) ?? 0
        changePages("Reordering pages…",page:target) { try $0.selectPages($1,indices:indices) }
    }
    private func movePage(_ delta:Int) {
        guard !busy,let document=loaded,document.pages.indices.contains(pageIndex+delta) else { return }
        var indices=Array(document.pages.indices); indices.swapAt(pageIndex,pageIndex+delta)
        changePages("Moving page…",page:pageIndex+delta) { try $0.selectPages($1,indices:indices) }
    }
    @objc private func movePageEarlier() { movePage(-1) }
    @objc private func movePageLater() { movePage(1) }
    @objc private func rotateClockwise() { let page=pageIndex; changePages("Rotating page…") { try $0.rotate($1,page:page,degrees:90) } }
    @objc private func rotateCounterclockwise() { let page=pageIndex; changePages("Rotating page…") { try $0.rotate($1,page:page,degrees:-90) } }
    @objc private func cropPage() {
        guard !busy,let document=loaded else { return }
        let page=pageIndex,info=document.pages[page]
        let alert=NSAlert(); alert.messageText="Crop page \(page+1)"; alert.informativeText="Set margins in points (72 points = 1 inch), relative to the original unrotated page. Cropping hides content; it does not permanently remove it."
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8
        let values=[info.box.minX-info.mediaBox.minX,info.mediaBox.maxX-info.box.maxX,info.mediaBox.maxY-info.box.maxY,info.box.minY-info.mediaBox.minY]
        var fields:[NSTextField]=[]
        for (name,value) in zip(["Left","Right","Top","Bottom"],values) {
            let row=NSStackView(); let nameLabel=NSTextField(labelWithString:name); nameLabel.widthAnchor.constraint(equalToConstant:70).isActive=true
            let field=NSTextField(string:String(format:"%.2f",value)); field.widthAnchor.constraint(equalToConstant:160).isActive=true; field.setAccessibilityLabel("\(name) margin in points")
            row.addArrangedSubview(nameLabel); row.addArrangedSubview(field); stack.addArrangedSubview(row); fields.append(field)
        }
        stack.frame=NSRect(x:0,y:0,width:260,height:120); alert.accessoryView=stack
        alert.addButton(withTitle:"Crop Page"); alert.addButton(withTitle:"Cancel"); alert.window.initialFirstResponder=fields.first
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let margins=fields.compactMap{Double($0.stringValue.trimmingCharacters(in:.whitespacesAndNewlines))}
        guard margins.count==4,margins.allSatisfy({$0.isFinite && $0>=0}),margins[0]+margins[1]<info.mediaBox.width,margins[2]+margins[3]<info.mediaBox.height else { showError(EngineError(message:"Use nonnegative margins that leave some page width and height.")); return }
        let box=CGRect(x:info.mediaBox.minX+margins[0],y:info.mediaBox.minY+margins[3],width:info.mediaBox.width-margins[0]-margins[1],height:info.mediaBox.height-margins[2]-margins[3])
        changePages("Cropping page…") { try $0.crop($1,page:page,box:box) }
    }
    @objc private func resetCrop() {
        guard !busy,let document=loaded else { return }
        let page=pageIndex,box=document.pages[page].mediaBox
        changePages("Resetting crop…") { try $0.crop($1,page:page,box:box) }
    }
    @objc private func extractPages() {
        if waitForInk({ [weak self] in self?.extractPages() }) { return }
        guard !busy,let document=loaded,let indices=pageSelection("Extract pages",initial:"\(pageIndex+1)",explanation:"Create a new PDF containing these pages. The open document stays intact.") else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.pdf]; panel.nameFieldStringValue="Extracted pages.pdf"
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self,response == .OK,let url=panel.url else { return }
            self.exportPages("Extracting pages…") { engine in
                let bytes=try engine.selectPages(document.bytes,indices:indices)
                try bytes.write(to:url,options:.withoutOverwriting)
                return "Saved \(indices.count) pages to \(url.lastPathComponent)"
            }
        }
    }
    @objc private func splitPages() {
        if waitForInk({ [weak self] in self?.splitPages() }) { return }
        guard !busy,let document=loaded else { return }
        let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; panel.canCreateDirectories=true
        panel.message="Create a new folder here with one PDF per page. Existing files stay intact."; panel.prompt="Split Pages"
        panel.beginSheetModal(for:window) { [weak self] response in
            guard let self,response == .OK,let directory=panel.url else { return }
            self.exportPages("Splitting \(document.pages.count) pages…") { engine in
                let destination=try engine.splitPages(document.bytes,to:directory)
                return "Saved \(document.pages.count) PDFs in \(destination.lastPathComponent)"
            }
        }
    }
    private func exportPages(_ message:String,work:@escaping(Engine)throws->String) {
        guard drawingSession==nil,!busy,loaded != nil else { return }; setBusy(true,message)
        worker.async { [weak self] in
            guard let self else { return }
            let result:Result<String,Error>=Result { try work(self.workerEngine()) }
            DispatchQueue.main.async {
                self.setBusy(false)
                switch result { case .success(let text): self.status.stringValue=text; self.resumePendingOpen()
                case .failure(let error): self.status.stringValue="Export failed"; self.showError(error) }
            }
        }
    }
    private func resumePendingOpen() {
        guard !busy,!updatingAnnotations,!savePanelOpen,window != nil,window.attachedSheet==nil else { return }
        if let url=pendingDrawingURL { pendingDrawingURL=nil; joinDrawing(url) }
        else if let url=pendingURL { pendingURL=nil; openURL(url) }
    }
    private func showError(_ error:Error) { let alert=NSAlert(); alert.messageText="Pod couldn’t complete that"; alert.informativeText=error.localizedDescription; alert.alertStyle = .warning; alert.beginSheetModal(for:window) { [weak self] _ in self?.resumePendingOpen() } }
    private func makeMarkupToolbar() -> NSStackView {
        let bar=PodSurfaceStack(); bar.bottomBorder=true; bar.orientation = .horizontal; bar.spacing=8; bar.edgeInsets=NSEdgeInsets(top:8,left:16,bottom:8,right:16)
        let title=label("MARK UP",10); title.font = .systemFont(ofSize:10,weight:.semibold); bar.addArrangedSubview(title)
        selectButton=button("Select","cursorarrow",#selector(selectTool)); selectButton.isSelected=true; bar.addArrangedSubview(selectButton); markupButtons.append(selectButton)
        eraseButton=button("Eraser","eraser",#selector(eraserTool)); bar.addArrangedSubview(eraseButton); markupButtons.append(eraseButton)
        for (title,kind,tag) in [("Shape",MarkupKind.rectangle,0),("Text tools",.underline,1),("Highlight",.highlight,2),("Draw",.ink,3),("Type",.freeText,4),("Add comment",.comment,5)] {
            let split=NSStackView(); split.spacing=0
            let main=button(title,kind.symbol,#selector(toolPicked)); main.tag=Int(kind.rawValue); toolButtons.append(main)
            let more=button("⌄",nil,#selector(openPalette)); more.tag=tag; more.toolTip="\(title) options"; more.setAccessibilityLabel("\(title) options")
            more.widthAnchor.constraint(equalToConstant:24).isActive=true
            split.addArrangedSubview(main); split.addArrangedSubview(more); bar.addArrangedSubview(split); markupButtons += [main,more]
        }
        let space=NSView(); space.setContentHuggingPriority(.defaultLow,for:.horizontal); bar.addArrangedSubview(space)
        commentsButton=button("","text.bubble",#selector(toggleComments)); commentsButton.setAccessibilityLabel("Comments panel"); bar.addArrangedSubview(commentsButton); markupButtons.append(commentsButton)
        return bar
    }
    private func viewerAction(_ title:String,_ sender:NSButton)->Bool {
        switch title {
        case "Open file": openFile(); return true
        case "Thumbnails": thumbnailPanel?.isHidden.toggle(); thumbnailWidth?.constant=thumbnailPanel?.isHidden == false ? 164:0; table.reloadData(); table.scrollRowToVisible(pageIndex); return true
        case "Select": selectTool(); return true
        case "Undo": undoEdit(); return true
        case "Redo": redoEdit(); return true
        case "Eraser": eraserTool(); return true
        case "Eraser options":
            eraserTool()
            let content=LuminEraserPalette(size:canvas.eraserWidth)
            content.onChange={ [weak self] size in self?.canvas.eraserWidth=size; self?.publishReactState() }
            palette?.close(); let pop=LuminPopper(); pop.contentViewController=content; palette=pop
            pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY); return true
        default: break
        }
        let groups=["Shape","Text tools","Highlight","Draw","Type","Add comment"]
        let name=title.replacingOccurrences(of:" options",with:"")
        if let index=groups.firstIndex(of:name) {
            if title.hasSuffix(" options") { sender.tag=index; openPalette(sender) }
            else { toolButtons[index].performClick(nil) }
            return true
        }
        return false
    }
    private func showSourceShare() {
        guard let root=window.contentView else { return }; headerPopup?.close(); shareModal?.close()
        let dialog=LuminShareDialog(filename:fileLabel.stringValue,link:fileURL?.absoluteString ?? fileLabel.stringValue)
        _ = dialog.view
        let modal=LuminModal(); shareDialog=dialog; shareModal=modal
        dialog.onResize={ [weak modal] in modal?.layout() }
        dialog.onFocus={ [weak self] responder in self?.window.makeFirstResponder(responder) }
        modal.onKeyDown={ [weak dialog] event in dialog?.handleKey(event) ?? false }
        modal.onClose={ [weak self,weak dialog] in dialog?.dismissMenus(); self?.shareDialog=nil; self?.shareModal=nil }
        window.makeFirstResponder(documentHeader.share)
        modal.show(dialog,in:root,initialResponder:dialog.initialResponder)
    }
    private func headerPicked(_ sender:NSButton) {
        if sender === documentHeader.navigation { setNavigationExpanded(!viewerChrome.rail.navigationExpanded); return }
        if sender === documentHeader.navigationClose { setNavigationExpanded(false); return }
        if sender === documentHeader.navigationBack { return } // Dashboard navigation is deferred with cloud functionality.
        if sender === documentHeader.share { showSourceShare(); return }
        let kind:LuminHeaderMenu.Kind
        if sender === documentHeader.fileMenu { kind = .file }
        else if sender === documentHeader.shareOptions { kind = .share }
        else if sender === documentHeader.help { kind = .help }
        else { return }
        if headerPopup?.isShown==true,(headerPopup?.contentViewController as? LuminHeaderMenu)?.kind==kind { headerPopup?.close(); return }
        headerPopup?.close()
        let dark=window.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let menu=LuminHeaderMenu(kind:kind,darkAppearance:dark,darkPage:viewerChrome.darkPage,starred:headerStarred,fullScreen:window.styleMask.contains(.fullScreen))
        let pop=LuminPopper(); pop.contentViewController=menu; pop.alignment=menu.alignment; pop.gap=menu.gap; pop.keepsAnchorInteractive=true; pop.roundsPlacementToBackingPixels=kind == .help
        pop.onKeyDown={ [weak menu] event in menu?.handleKey(event) ?? false }
        pop.onEscape={ [weak self,weak sender] in self?.window.makeFirstResponder(sender) }
        menu.onChoose={ [weak self,weak menu,weak pop] key in
            guard let self,let menu else { return }
            if key=="darkPage" { viewerChrome.setDarkPagePreview(menu.darkPage); return }
            if key=="starred" { headerStarred=menu.starred; return }
            pop?.close()
            switch key {
            case "download","copy":saveCopy()
            case "appearance":NSApp.appearance=NSAppearance(named:dark ? .aqua:.darkAqua)
            case "fullScreen":window.toggleFullScreen(nil)
            default:status.stringValue="\(menu.rows.first(where:{$0.item.key==key})?.title ?? key) · UI preview"
            }
        }
        headerPopup=pop; pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY)
    }
    @objc private func utilityPicked(_ sender:NSButton) {
        switch sender.identifier?.rawValue {
        case "Comments": toggleComments()
        case "Download": saveCopy()
        default: status.stringValue="\(sender.identifier?.rawValue ?? "Tool") · UI preview"
        }
    }
    @objc private func selectTool() { canvas.panning=false; clearAnnotationSelection(); palette?.close(); markupTool=nil; canvas.tool=nil; canvas.erasing=false; commentsVisible=false; toolButtons.forEach{($0 as? PodButton)?.isSelected=false}; selectButton.isSelected=true; eraseButton.isSelected=false; commentsButton.isSelected=false; refreshInspector(); status.stringValue=drawingSession==nil ? "Select text to edit, or an annotation to move and resize.":"Select one of your drawings to edit it." }
    @objc private func eraserTool() { selectTool(); canvas.erasing=true; selectButton.isSelected=false; eraseButton.isSelected=true; status.stringValue=drawingSession == nil ? "Drag across ink to erase it.":"Drag across your ink to erase it."; refreshInspector() }
    @objc private func toolPicked(_ sender:NSButton) { if let kind=MarkupKind(rawValue:UInt32(sender.tag)) { if kind == .ink && markupTool == .ink { selectTool(); DispatchQueue.main.async { [weak self] in if self?.markupTool==nil { self?.viewerChrome.toolbar.selectTool("Select") } } } else { chooseTool(kind) } } }
    private func chooseTool(_ kind:MarkupKind) {
        guard drawingSession==nil || kind == .ink else { return }
        canvas.panning=false; markupTool=kind; markupStyle = toolStyles[kind] ?? .initial(for:kind); canvas.tool=kind;
        for (index,button) in toolButtons.enumerated() {
            let group = kind.isShape ? 0 : ([.underline,.squiggly,.strikeout].contains(kind) ? 1:([.highlight,.freehandHighlight].contains(kind) ? 2:(kind == .ink ? 3:(kind == .freeText ? 4:5))))
            (button as? PodButton)?.isSelected=index == group
            if index == group { button.tag=Int(kind.rawValue); button.image=LuminAssets.markup(kind) }
        }
        selectButton.isSelected=false; eraseButton.isSelected=false; commentsButton.isSelected=false
        canvas.erasing=false; canvas.annotationStyle=markupStyle
        clearAnnotationSelection(); selection=nil; canvas.selected=nil; commentsVisible=false
        status.stringValue=kind.hint; refreshInspector()
    }
    @objc private func openPalette(_ sender:NSButton) {
        guard drawingSession==nil || sender.tag==3 else { return }
        let groups:[[MarkupKind]]=[Array(MarkupKind.allCases.prefix(10)),[.underline,.squiggly,.strikeout],[.highlight,.freehandHighlight],[.ink],[.freeText],[.comment]]
        let group=groups[sender.tag]
        let current=markupTool.flatMap{group.contains($0) ? $0:nil} ?? group[0]
        if markupTool != current { chooseTool(current) }
        let content=MarkupPalette(kinds:group,current:current,style:markupStyle)
        content.onChoose={ [weak self] kind in self?.chooseTool(kind); return self?.markupStyle ?? .initial(for:kind) }
        content.onStyle={ [weak self] style in self?.setMarkupStyle(style) }
        palette?.close(); let pop=LuminPopper(); pop.contentViewController=content; palette=pop
            let anchor=(sender as? LuminToolbarButton)?.sourcePopoverAnchor ?? sender
            pop.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.maxY)
    }
    private func setMarkupStyle(_ style:MarkupStyle) {
        guard !busy,selectedAnnotationMark?.inkLocked != true else { return }
        markupStyle=style; canvas.annotationStyle=style
        if let tool=markupTool { toolStyles[tool]=style }
        inspector.arrangedSubviews.compactMap{$0 as? MarkupStyleView}.forEach{$0.setStyle(style)}
        (palette?.contentViewController as? MarkupPalette)?.setStyle(style)
        if var mark=selectedAnnotationMark { mark.style=style; updateSelectedMark(mark) }
    }
    private func selectAnnotation(_ id:UInt32?) {
        guard drawingSession==nil else { return }
        clearAnnotationSelection()
        if let id,loaded?.pages[pageIndex].annotations.contains(where:{$0.id==id})==true {
            selectedMarkup=id; canvas.annotationSelection=id
        }
        applyAnnotationSelection()
    }
    private func selectSharedInk(_ id:UUID?) {
        clearAnnotationSelection()
        canvas.selectedSharedInk=id
        if selectedSharedStroke==nil { canvas.selectedSharedInk=nil }
        applyAnnotationSelection()
    }
    private func applyAnnotationSelection() {
        if let mark=selectedAnnotationMark {
            markupTool=nil; canvas.tool=nil; canvas.erasing=false; selectButton.isSelected=true; eraseButton.isSelected=false; toolButtons.forEach{($0 as? PodButton)?.isSelected=false}; selection=nil; canvas.selected=nil; markupStyle=mark.style
        }
        refreshInspector()
    }
    private func refreshInspector() {
        defer { publishReactState() }
        guard !textInspectorViews.isEmpty else { return }
        if viewerChrome.formBuilderActive {
            inspector.isHidden=true; inspectorWidth?.constant=364; viewerChrome.toolbar.rightPanelWidth=0; return
        }
        let visible=commentsVisible || selectedAnnotationMark != nil || selection != nil
        inspector.isHidden = !visible; inspectorWidth?.constant=visible ? PodMetrics.palette:0
        viewerChrome.toolbar.rightPanelWidth=visible ? PodMetrics.palette:0
        for view in inspector.arrangedSubviews { inspector.removeArrangedSubview(view); view.removeFromSuperview() }
        func add(_ view:NSView) { inspector.addArrangedSubview(view); if !(view is MarkupStyleView) { view.widthAnchor.constraint(equalToConstant:PodMetrics.paletteContent).isActive=true } }
        if drawingSession != nil && markupTool==nil && selectedAnnotationMark==nil && !commentsVisible {
            add(label("Shared drawing",17,PodTheme.text))
            add(label("Select one of your strokes to edit it. Undo and redo affect only your changes.",12))
        } else if commentsVisible {
            add(label("Comments",17,PodTheme.text))
            let comments=pageComments
            if comments.isEmpty { add(label(drawingSession==nil ? "No comments on this page. Choose Add comment, then click on the page.":"Select one of your drawings to leave a comment.",12)) }
            for comment in comments {
                let b=button(comment.text.isEmpty ? "Empty comment":comment.text,"text.bubble",#selector(commentSelected)); b.identifier=NSUserInterfaceItemIdentifier(comment.id); b.lineBreakMode = .byTruncatingTail; add(b)
            }
        } else if let mark=selectedAnnotationMark {
            add(label(mark.kind.title,17,PodTheme.text))
            if mark.inkLocked {
                add(label("This drawing is locked.",11))
                if !mark.text.isEmpty { add(label(mark.text,12)) }
                if !mark.link.isEmpty { add(button("Open link","arrow.up.right.square",#selector(openAnnotationLink))) }
                return
            }
            add(label("Drag to move. Drag the corner handle to resize.",11))
            if mark.hasEditableText {
                annotationText.stringValue=mark.text; annotationText.placeholderString=mark.kind == .comment || mark.kind == .ink ? "Comment":"Text"; annotationText.setAccessibilityLabel(mark.kind == .ink ? "Drawing comment":"Annotation text"); annotationText.target=self; annotationText.action=#selector(updateAnnotationText)
                add(annotationText); add(button(mark.kind == .ink ? "Save comment":"Update text",nil,#selector(updateAnnotationText)))
            }
            let style=MarkupStyleView(kind:mark.kind,style:mark.style); style.onChange={ [weak self,weak style] value in
                guard let self,let style,self.inspector.arrangedSubviews.contains(where:{$0 === style}) else { return }
                self.setMarkupStyle(value)
            }; add(style)
            if mark.kind == .ink {
                add(button("Rotate drawing clockwise","rotate.right",#selector(rotateDrawing)))
                annotationLink.stringValue=mark.link; annotationLink.placeholderString="https://…"; annotationLink.setAccessibilityLabel("Hyperlink")
                annotationLink.target=self; annotationLink.action=#selector(updateAnnotationLink)
                add(annotationLink); add(button("Save link",nil,#selector(updateAnnotationLink)))
                if !mark.link.isEmpty { add(button("Open link","arrow.up.right.square",#selector(openAnnotationLink))) }
            }
            add(button("Delete annotation","trash",#selector(deleteAnnotation)))
        } else if let tool=markupTool {
            add(label(tool.title,17,PodTheme.text)); add(label(tool.hint,12))
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
    @objc private func toggleComments() { commentsVisible.toggle(); commentsButton.isSelected=commentsVisible; refreshInspector() }
    private func selectPageComment(_ id:String) {
        guard pageComments.contains(where:{$0.id==id}) else { return }
        commentsVisible=false; commentsButton.isSelected=false
        if drawingSession != nil,let sharedID=UUID(uuidString:id) { selectSharedInk(sharedID) }
        else if let localID=UInt32(id) { selectAnnotation(localID) }
        canvas.needsDisplay=true
    }
    @objc private func commentSelected(_ sender:NSButton) {
        if let id=sender.identifier?.rawValue { selectPageComment(id) }
    }
    @objc private func rotateDrawing() {
        guard let mark=selectedAnnotationMark,mark.kind == .ink else { return }
        updateSelectedMark(mark.rotated(by: -.pi/2))
    }
    @objc private func openAnnotationLink() {
        guard let mark=selectedAnnotationMark,mark.kind == .ink,
              let url=URL(string:mark.link),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host?.isEmpty==false else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func updateAnnotationLink() {
        guard var mark=selectedAnnotationMark,mark.kind == .ink,!mark.inkLocked else { return }
        let link=annotationLink.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        if !link.isEmpty {
            guard link.utf8.count<=2048,let url=URLComponents(string:link),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host?.isEmpty==false else {
                showError(EngineError(message:"Enter a complete http or https address.")); return
            }
        }
        guard mark.link != link else { return }; mark.link=link; updateSelectedMark(mark)
    }
    @objc private func updateAnnotationText() {
        guard var mark=selectedAnnotationMark,!mark.inkLocked,mark.hasEditableText,mark.text != annotationText.stringValue else { return }
        mark.text=annotationText.stringValue; updateSelectedMark(mark)
    }
    private func updateSelectedMark(_ mark:Markup) {
        guard !busy,selectedAnnotationMark?.inkLocked==false else { return }
        if let session=drawingSession,let stroke=selectedSharedStroke {
            do { try session.update(stroke.id,mark:mark) } catch {
                markupStyle=stroke.markup.style; refreshInspector(); showError(error)
            }
        } else if selectedMarkup==mark.id { mutateAnnotations([mark]) }
    }
    @objc private func deleteAnnotation() {
        guard !busy,selectedAnnotationMark?.inkLocked==false else { return }
        if let session=drawingSession,let stroke=selectedSharedStroke {
            do { try session.remove(stroke.id) } catch { showError(error) }
        } else if let id=selectedMarkup { mutateAnnotations([],deleting:[id]) }
    }
    private func createAnnotations(_ marks:[Markup]) {
        guard !marks.isEmpty else { return }
        if busy {
            if acceptingStrokes,marks.count == 1,marks[0].kind.isFreehand {
                queuedStrokes.append((marks[0],canvas.retainAnnotationDraft(marks[0])))
            }
            return
        }
        if let session=drawingSession {
            do { for mark in marks { try session.add(mark,page:pageIndex) } } catch { showError(error) }
            return
        }
        if marks.count==1,marks[0].kind.isText {
            let alert=NSAlert(); alert.messageText=marks[0].kind == .comment ? "Add a comment":"Add text"
            alert.informativeText=marks[0].kind == .comment ? "Your comment will be saved inside this PDF.":"Enter text for this box. Courier regular is supported."
            let input=NSTextField(frame:NSRect(x:0,y:0,width:320,height:26)); input.setAccessibilityLabel("New annotation text"); alert.accessoryView=input; alert.addButton(withTitle:"Add"); alert.addButton(withTitle:"Cancel")
            alert.beginSheetModal(for:window) { [weak self] result in
                guard result == .alertFirstButtonReturn,!input.stringValue.isEmpty else { return }
                var mark=marks[0]; mark.text=input.stringValue; self?.mutateAnnotations([mark])
            }
            alert.window.makeFirstResponder(input)
        } else { mutateAnnotations(marks,draftID:canvas.retainAnnotationDraft(marks[0])) }
    }
    private func mutateAnnotations(_ marks:[Markup],deleting:[UInt32]=[],draftID:Int?=nil) {
        guard drawingSession==nil,!busy,let document=loaded else { return }
        let page=pageIndex,width=pixelWidth
        let animateInk = !deleting.isEmpty || canvas.erasing || (marks.contains { $0.id != 0 } && !canvas.isTransformCommit)
        updatingAnnotations=true
        acceptingStrokes = marks.count == 1 && marks[0].id == 0 && marks[0].kind.isFreehand && canvas.tool == marks[0].kind
        // Keep the editor in place while native controls and document writes are locked.
        reactEditor?.setState(["annotationPending":true,"status":"Updating annotations…"])
        perform("Updating annotations…",work:{ engine in let bytes=try engine.annotate(document.bytes,page:page,marks:marks,deleting:deleting); return try engine.openPage(bytes,page:page,width:width) },done:{ [self] result in
            defer { finishAnnotationUpdate() }
            let stroke = marks.count == 1 && marks[0].id == 0 && marks[0].kind.isFreehand && deleting.isEmpty ? marks[0] : nil
            history.record(before:document.bytes,stroke:stroke,page:page)
            show(result,page:page,completingAnnotation:true,draftID:draftID,animateInk:animateInk)
            if let mark=marks.last {
                let id=mark.id == 0 ? result.pages[page].annotations.last?.id:mark.id
                if !canvas.erasing && (mark.kind.isText || mark.id != 0) { selectAnnotation(id) }
            }
        },failed:{ [self] _ in
            afterInkCommit=nil; canvas.discardDraft(draftID); finishAnnotationUpdate()
        })
    }
    private func finishAnnotationUpdate() {
        acceptingStrokes=false
        if !queuedStrokes.isEmpty {
            let next=queuedStrokes.removeFirst()
            mutateAnnotations([next.mark],draftID:next.draftID)
            return
        }
        updatingAnnotations=false
        updateControls()
        if let action = afterInkCommit {
            afterInkCommit = nil
            action()
        }
        resumePendingOpen()
        if metalDisabled,loaded?.metalPage != nil,!busy { navigate(pageIndex) }
    }
    private func refreshSharedCursor() {
        canvas.remoteCursor=drawingSession?.remoteCursor.flatMap{$0.page==pageIndex ? $0:nil}
        canvas.needsDisplay=true
    }
    private var displayedDrawingRevision: Int?
    private func refreshSharedDrawing(animateChanges: Bool = false) {
        refreshSharedCursor()
        let previous=selectedSharedStroke
        let revision = drawingSession?.board.revision
        let revisionChanged = revision != displayedDrawingRevision
        displayedDrawingRevision = revision
        let records = drawingSession?.board.records.filter { $0.page == pageIndex } ?? []
        let visible = records.filter { !$0.removed }
        if animateChanges && revisionChanged && !canvas.isTransformCommit && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let previous = canvas.sharedDrawings
            let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            let newIDs = Set(visible.map(\.id))
            var changed = previous.filter { !newIDs.contains($0.id) }.map(\.markup)
            let retired = Dictionary(grouping: records.filter(\.removed), by: \.owner).mapValues { Set($0.map(\.order)) }
            for new in visible {
                if let old = oldByID[new.id] {
                    if old.version != new.version, old.points != new.points || old.inkPathStarts != new.inkPathStarts ||
                        old.color != new.color || old.width != new.width || old.opacity != new.opacity {
                        changed.append(contentsOf: [old.markup, new.markup])
                    }
                } else if retired[new.owner]?.contains(new.order) == true {
                    // A shared undo restores the same stacking position with a fresh ID.
                    changed.append(new.markup)
                }
            }
            canvas.fadeInkChange(changed, previousShared: previous)
        }
        canvas.sharedDrawings = visible
        if canvas.selectedSharedInk != nil,previous != selectedSharedStroke { selectSharedInk(canvas.selectedSharedInk) }
        canvas.sharedPreview=drawingSession?.remotePreview.flatMap{$0.page==pageIndex ? $0:nil}
        canvas.needsDisplay=true; updateControls()
    }
    private func attachDrawing(_ session:DrawingSession) {
        drawingSession=session; savedDrawingRevision=0; canvas.collaborating=true; canvas.drawingOwner=session.owner
        history=PDFEditHistory(); palette?.close(); chooseTool(.ink)
        session.onChange={ [weak self,weak session] in
            guard let self,let session,self.drawingSession === session else { return }; self.refreshSharedDrawing(animateChanges:true)
        }
        session.onPresenceChange={ [weak self,weak session] in
            guard let self,let session,self.drawingSession === session else { return }; self.refreshSharedCursor()
        }
        session.onStatus={ [weak self,weak session] value in
            guard let self,let session,self.drawingSession === session else { return }
            self.peerStatus.stringValue=value; self.peerStatus.toolTip=value; self.updateControls()
        }
        session.onDocument={ [weak self,weak session] bytes,name,completion in
            guard let self,let session,self.drawingSession === session,!self.busy else { completion(.failure(DrawingError(message:"Pod is busy. Reconnect to try again."))); return }
            self.perform("Opening shared PDF…",work:{ try $0.load(bytes,page:0,width:1000) },done:{ [weak self,weak session] document in
                guard let self,let session,self.drawingSession === session else { completion(.failure(DrawingError(message:"Session ended."))); return }
                self.fileURL=nil; self.savedBytes=nil; self.history=PDFEditHistory(); self.show(document,page:0)
                self.fileLabel.stringValue=name; self.documentHeader.documentName=name; self.window.title="\(name) — Shared drawing — Pod"
                completion(.success(document.pages.map(\.box))); self.refreshSharedDrawing()
            },failed:{ completion(.failure($0)) })
        }
        peerStatus.stringValue=session.status; refreshSharedDrawing()
    }
    @objc private func shareDrawing() {
        if waitForInk({ [weak self] in self?.shareDrawing() }) { return }
        guard !busy,!savePanelOpen,let document=loaded else { return }
        if let session=drawingSession {
            if session.owner == .host { showInvitation(session.invite) }
            else { showError(DrawingError(message:"This session already has two Macs. The host can copy its invitation.")) }
            return
        }
        let alert=NSAlert(); alert.messageText="Share drawing directly"
        alert.informativeText="Enter this Mac’s address that the other Mac can reach. On the same network, use its LAN address. Across the internet, use a reachable public address and an open or forwarded port. No relay is used."
        let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=8; stack.frame=NSRect(x:0,y:0,width:380,height:72)
        let address=NSTextField(string:DrawingNetworkAddress.localAddress()); address.placeholderString="Reachable address"; address.setAccessibilityLabel("Host address")
        let port=NSTextField(string:"48672"); port.placeholderString="Port"; port.setAccessibilityLabel("Listening port")
        for field in [address,port] { stack.addArrangedSubview(field); field.widthAnchor.constraint(equalToConstant:380).isActive=true }
        alert.accessoryView=stack; alert.addButton(withTitle:"Start Sharing"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            guard let number=UInt16(port.stringValue) else { throw DrawingError(message:"Enter a port from 1 to 65535.") }
            let invite=try DrawingInvite(host:address.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),port:number)
            let session=DrawingSession(invite:invite,owner:.host)
            try session.host(document:document,name:fileLabel.stringValue); attachDrawing(session); showInvitation(invite)
        } catch { showError(error) }
    }
    private func showInvitation(_ invite:DrawingInvite) {
        let alert=NSAlert(); alert.messageText="Invite another Mac"
        alert.informativeText="Open this link in Pod on the other Mac, or paste it into Collaborate → Join Drawing. Anyone with this link can join. Keep this app running; End Drawing Session revokes the link."
        let field=NSTextField(string:invite.url.absoluteString); field.frame=NSRect(x:0,y:0,width:480,height:54); field.isEditable=false; field.isSelectable=true; field.lineBreakMode = .byCharWrapping; field.setAccessibilityLabel("Drawing invitation")
        alert.accessoryView=field; alert.addButton(withTitle:"Copy Link"); alert.addButton(withTitle:"Close")
        if alert.runModal() == .alertFirstButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(invite.url.absoluteString,forType:.string) }
    }
    @objc private func joinDrawingPrompt() {
        guard !busy,!savePanelOpen else { return }
        let alert=NSAlert(); alert.messageText="Join a drawing session"; alert.informativeText="Paste the invitation from the other Pod app."
        let field=NSTextField(string:""); field.frame=NSRect(x:0,y:0,width:440,height:26); field.placeholderString="pod://draw…"; field.setAccessibilityLabel("Drawing invitation")
        alert.accessoryView=field; alert.addButton(withTitle:"Join"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url=URL(string:field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)) else { showError(DrawingError(message:"Invalid invitation.")); return }
        joinDrawing(url)
    }
    private func joinDrawing(_ url:URL) {
        if waitForInk({ [weak self] in self?.joinDrawing(url) }) { return }
        guard !busy,!savePanelOpen else { pendingDrawingURL=url; return }
        do {
            let invite=try DrawingInvite(url:url)
            if let session=drawingSession {
                if session.invite==invite && session.owner == .guest { session.reconnect() }
                else { showError(DrawingError(message:"End the current drawing session before joining another.")) }
                return
            }
            guard canDiscard() else { return }
            let session=DrawingSession(invite:invite,owner:.guest); attachDrawing(session); session.join()
        } catch { showError(error) }
    }
    @objc private func reconnectDrawing() {
        guard !busy,let session=drawingSession else { return }
        session.reconnect()
    }
    @objc private func endDrawing() {
        if waitForInk({ [weak self] in self?.endDrawing() }) { return }
        guard !busy,!savePanelOpen,let session=drawingSession else { return }
        let detach={ [self] in
            clearAnnotationSelection(); session.stop(); drawingSession=nil; canvas.collaborating=false; canvas.sharedDrawings=[]; canvas.sharedPreview=nil; canvas.remoteCursor=nil; peerStatus.stringValue=""; history=PDFEditHistory(); savedDrawingRevision=0; canvas.needsDisplay=true; updateControls()
        }
        guard let base=session.base else { detach(); return }
        session.stop()
        let board=session.board,page=pageIndex,width=pixelWidth
        let wasSaved=board.revision==savedDrawingRevision && loaded?.bytes==savedBytes
        perform("Finishing shared drawing…",work:{ engine in try engine.openPage(board.export(base,using:engine),page:page,width:width) },done:{ [self] document in
            detach(); if wasSaved { savedBytes=document.bytes }; show(document,page:page)
        })
    }
    @objc private func showDesignSystem() {
        if designSystemWindow == nil {
            let gallery=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:760),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            gallery.title="Pod Design System"; gallery.isReleasedWhenClosed=false; gallery.minSize=NSSize(width:900,height:760)
            gallery.contentViewController=DesignSystemGallery(); gallery.center(); designSystemWindow=gallery
        }
        designSystemWindow?.makeKeyAndOrderFront(nil)
    }
    // Runs only in the separately launched sample-document test process.
    private func runReactSmokeCheck() {
        let deadline=Date().addingTimeInterval(45)
        var phase = -3
        var finishThirdStroke:(()->Void)?
        var beforeMove: Markup?
        var beforeErase: Markup?
        var deletedInkPoint = CGPoint.zero
        func overlayAlpha(at point: CGPoint) -> CGFloat {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 9, pixelsHigh: 9, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let context = NSGraphicsContext.current!.cgContext
            context.clear(CGRect(x: 0, y: 0, width: 9, height: 9))
            context.translateBy(x: 4 - point.x, y: 4 - point.y)
            canvas.drawOverlays()
            return bitmap.colorAt(x: 4, y: 4)!.alphaComponent
        }
        var overlayCleared:(()->Bool)?
        var actionStart = CACurrentMediaTime()
        let requireMetal = ProcessInfo.processInfo.environment["POD_REQUIRE_METAL"] == "1"
        func send(_ type: NSEvent.EventType, _ location: CGPoint) {
            let e=NSEvent.mouseEvent(with:type,location:canvas.convert(location,to:nil),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with:e)
            case .leftMouseDragged: canvas.mouseDragged(with:e)
            default: canvas.mouseUp(with:e)
            }
        }
        func check() {
            guard Date()<deadline else { fputs("FAIL: native React smoke phase \(phase)\n",stderr); exit(1) }
            guard let host=reactEditor else { fputs("FAIL: React editor not installed\n",stderr); exit(1) }
            if !busy,let document=loaded {
                switch phase {
                case -3:
                    let bytes = document.bytes
                    let initialSize = document.pages[pageIndex].displaySize
                    rotateView()
                    guard !dirty, loaded?.bytes == bytes, canvas.page?.displaySize == CGSize(width: initialSize.height, height: initialSize.width),
                          viewRotation == 270 else { fputs("FAIL: view rotation mutated the PDF or lost its geometry\n", stderr); exit(1) }
                    for _ in 0..<3 { rotateView() }
                    print("PASS: counterclockwise view rotation preserves PDF bytes and edit history")
                    phase = -2
                case -2:
                    host.webView.evaluateJavaScript("""
                        (() => {
                            if (!document.querySelector('.editor-page-icon img')?.naturalWidth) return false;
                            const pan = document.querySelector('[aria-label="Pan"]:enabled');
                            if (!pan) return false;
                            pan.click();
                            return true;
                        })()
                        """) { value, _ in if phase == -2, value as? Bool == true { phase = -1 } }
                case -1:
                    if canvas.panning {
                        print("PASS: engine thumbnail loaded in WKWebView and toolbar activated native Pan")
                        phase = 0
                    }
                case 0:
                    guard !requireMetal || canvas.didPresentMetal else { break }
                    let chooseDraw = """
                    (() => {
                        const button = document.querySelector('button[aria-label="Draw"]:enabled')
                        if (!window.__POD_STATE__?.canSave || !button) return false
                        button.click()
                        return true
                    })()
                    """
                    host.webView.evaluateJavaScript(chooseDraw) { value,_ in
                        if phase == 0, value as? Bool == true {
                            if requireMetal { print(String(format: "Sample open to Metal frame callback: %.1f ms", (self.canvas.presentationTime - actionStart) * 1000)) }
                            phase = 1
                        }
                    }
                case 1:
                    if canvas.tool == .ink { phase=2; host.webView.evaluateJavaScript("document.querySelector('[aria-label=\"Next page\"]').click()",completionHandler:nil) }
                case 2:
                    if pageIndex==1 {
                        phase=3
                        host.webView.evaluateJavaScript("""
                            window.__annotationStates=[];
                            window.addEventListener('pod:state',e=>window.__annotationStates.push([!!e.detail.busy,!!e.detail.annotationPending]));
                            true
                            """,completionHandler:nil)
                        // Observe the actual overlay on release, before the main queue can apply the worker result.
                        let visible=canvas.pageRect.intersection(canvas.visibleRect)
                        let box=CGRect(x:visible.midX-30,y:visible.midY-20,width:60,height:40)
                        func displayedInk() -> Data? {
                            guard let overlay=canvas.subviews.first(where:{ $0 is PageOverlayView }),let layer=overlay.layer else { return nil }
                            // Read the AppKit backing layer to catch a missing redraw during drag.
                            window.displayIfNeeded()
                            CATransaction.flush()
                            let w=Int(ceil(layer.bounds.width)),h=Int(ceil(layer.bounds.height))
                            guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                            layer.render(in:ctx)
                            return Data(bytes:ctx.data!,count:w*h*4)
                        }
                        func snapshot()->Data {
                            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:80,pixelsHigh:70,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
                            NSColor.white.setFill(); NSRect(x:0,y:0,width:80,height:70).fill()
                            let transform=NSAffineTransform()
                            transform.translateX(by:5-box.minX,yBy:5-box.minY); transform.concat()
                            self.canvas.drawOverlays()
                            NSGraphicsContext.restoreGraphicsState()
                            return Data(bytes:rep.bitmapData!,count:rep.bytesPerRow*rep.pixelsHigh)
                        }
                        var eventTime = ProcessInfo.processInfo.systemUptime
                        func event(_ type:NSEvent.EventType,_ point:CGPoint)->NSEvent {
                            NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:eventTime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                        }
                        let backingBefore=displayedInk()
                        let empty=snapshot(),end=CGPoint(x:box.maxX,y:box.maxY)
                        overlayCleared={snapshot()==empty}
                        canvas.mouseDown(with:event(.leftMouseDown,box.origin))
                        canvas.mouseDragged(with:event(.leftMouseDragged,end))
                        if requireMetal && (backingBefore == nil || displayedInk()==backingBefore) {
                            fputs("FAIL: held stroke never reached the visible ink layer\n",stderr); exit(1)
                        }
                        let drawn=snapshot()
                        canvas.mouseUp(with:event(.leftMouseUp,end))
                        guard canvas.hasPendingInk,drawn != empty,snapshot()==drawn else { fputs("FAIL: annotation preview disappeared before the new page was ready\n",stderr); exit(1) }
                        let second=CGPoint(x:box.minX,y:box.maxY)
                        canvas.mouseDown(with:event(.leftMouseDown,second))
                        canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:box.maxX,y:box.minY)))
                        guard snapshot() != drawn else { fputs("FAIL: second stroke invisible during first commit\n",stderr); exit(1) }
                        canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:box.maxX,y:box.minY)))
                        eventTime += 0.2
                        canvas.mouseDown(with:event(.leftMouseDown,box.origin))
                        canvas.mouseDragged(with:event(.leftMouseDragged,second))
                        finishThirdStroke={ self.canvas.mouseUp(with:event(.leftMouseUp,second)) }

                    }
                case 3:
                    if document.pages[pageIndex].annotations.count == 1, let finish=finishThirdStroke {
                        let group=document.pages[pageIndex].annotations[0]
                        guard group.inkPathStarts == [0,2] else { fputs("FAIL: quick strokes did not reopen as two separate paths in one annotation\n",stderr); exit(1) }
                        finishThirdStroke=nil; finish()
                        break
                    }
                    if document.pages[pageIndex].annotations.count == 2,history.undo.count==2,
                       !requireMetal || canvas.didPresentMetal {
                        guard overlayCleared?()==true else { fputs("FAIL: stale draft after the edited page appeared\n",stderr); exit(1) }
                        let marks=document.pages[pageIndex].annotations
                        selectAnnotation(marks[0].id)
                        let stale=editContext.uuidString
                        selectAnnotation(marks[1].id)
                        reactCommand("deleteAnnotation",["context":stale])
                        reactCommand("style",["context":stale,"width":19.0])
                        guard !busy,!updatingAnnotations,selectedMarkup==marks[1].id,markupStyle.width==marks[1].style.width else {
                            fputs("FAIL: stale inspector command affected a different drawing\n",stderr); exit(1)
                        }
                        chooseTool(.ink)
                        phase=4
                        host.webView.evaluateJavaScript("""
                            (() => {
                                const states=window.__annotationStates;
                                if (!states.some(s=>s[1]) || states.some(s=>s[0]) || window.__POD_STATE__.annotationPending) return false;
                                document.querySelector('[aria-label="Undo"]').click(); return true;
                            })()
                            """) { ok,_ in
                                if ok as? Bool != true { fputs("FAIL: annotation triggered a global loading state\n",stderr); exit(1) }
                            }
                    }
                case 4:
                    if document.pages[pageIndex].annotations.count == 1,!history.redo.isEmpty,canvas.image != nil,!scroll.isHidden,
                       !requireMetal || canvas.didPresentMetal {
                        let group = document.pages[pageIndex].annotations[0]
                        beforeMove = group
                        selectTool()
                        let start = canvas.viewRect(CGRect(origin:group.points[0],size:.zero)).origin
                        let end = CGPoint(x:start.x+16,y:start.y+12)
                        phase=8
                        send(.leftMouseDown,start)
                        send(.leftMouseDragged,end)
                        send(.leftMouseUp,end)
                    }
                case 8:
                    if let old=beforeMove, let moved=document.pages[pageIndex].annotations.first,
                       moved.id==old.id, moved.points != old.points {
                        let dx=moved.points[0].x-old.points[0].x,dy=moved.points[0].y-old.points[0].y
                        guard moved.inkPathStarts==old.inkPathStarts, moved.points.count==old.points.count,
                              zip(moved.points,old.points).allSatisfy({abs(($0.x-$1.x)-dx)<0.001 && abs(($0.y-$1.y)-dy)<0.001}) else {
                            fputs("FAIL: moving a grouped annotation changed its relative paths\n",stderr); exit(1)
                        }
                        phase=9
                        let frame=canvas.viewRect(moved.geometryBounds).insetBy(dx:-2,dy:-2)
                        let knob=CGPoint(x:frame.midX,y:frame.minY-20)
                        let side=CGPoint(x:frame.maxX+20,y:frame.midY)
                        send(.leftMouseDown,knob)
                        send(.leftMouseDragged,side)
                        send(.leftMouseUp,side)
                        beforeMove=moved
                    }
                case 9:
                    if let old=beforeMove, let rotated=document.pages[pageIndex].annotations.first,
                       rotated.id==old.id, rotated.points != old.points {
                        guard rotated.inkPathStarts == old.inkPathStarts,
                              abs(rotated.geometryBounds.width-old.geometryBounds.height)<0.01 else {
                            fputs("FAIL: rotation handle did not rotate the group about its center\n",stderr); exit(1)
                        }
                        chooseTool(.ink)
                        let visible=canvas.pageRect.intersection(canvas.visibleRect)
                        let tap=CGPoint(x:visible.midX,y:visible.midY)
                        send(.leftMouseDown,tap)
                        send(.leftMouseUp,tap)
                        phase=10
                        undoEdit()
                    }
                case 10:
                    if document.pages[pageIndex].annotations.count==1, !history.redo.isEmpty {
                        let mark=document.pages[pageIndex].annotations[0]
                        beforeErase=mark
                        eraserTool()
                        canvas.eraserWidth=8
                        let box=canvas.viewRect(mark.geometryBounds)
                        let start=CGPoint(x:box.midX,y:box.minY-6), end=CGPoint(x:box.midX,y:box.maxY+6)
                        phase=11
                        send(.leftMouseDown,start); send(.leftMouseDragged,end); send(.leftMouseUp,end)
                    }
                case 11:
                    if let mark=document.pages[pageIndex].annotations.first, mark.inkPathStarts.count==4 {
                        guard canvas.erasing, mark.id==beforeErase?.id,
                              !mark.hitTest(CGPoint(x:mark.geometryBounds.midX,y:mark.geometryBounds.midY),tolerance:0) else {
                            fputs("FAIL: eraser changed annotation identity, left ink in the cut or lost eraser mode\n",stderr); exit(1)
                        }
                        phase=12; undoEdit()
                    }
                case 12:
                    if let original=beforeErase, let mark=document.pages[pageIndex].annotations.first, mark.points==original.points {
                        guard mark.inkPathStarts==original.inkPathStarts else { fputs("FAIL: erase undo lost path boundaries\n",stderr); exit(1) }
                        selectTool()
                        let hit=canvas.viewRect(CGRect(origin:mark.points[0],size:.zero)).origin
                        send(.leftMouseDown,hit); send(.leftMouseUp,hit)
                        guard canvas.annotationSelection==mark.id else { fputs("FAIL: restored ink cannot be selected\n",stderr); exit(1) }
                        phase=13
                        let deletion=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"\u{7F}",charactersIgnoringModifiers:"\u{7F}",isARepeat:false,keyCode:51)!
                        canvas.keyDown(with:deletion)
                    }
                case 13:
                    if document.pages[pageIndex].annotations.isEmpty { phase=14; undoEdit() }
                case 14:
                    if document.pages[pageIndex].annotations.first?.points==beforeErase?.points { phase=15; redoEdit() }
                case 15:
                    if document.pages[pageIndex].annotations.isEmpty {
                        do {
                            let invite=try DrawingInvite(host:"127.0.0.1",port:UInt16.random(in:49152...65535))
                            let session=DrawingSession(invite:invite,owner:.host)
                            try session.host(document:document,name:"Ink editing test")
                            attachDrawing(session)
                            guard let mark=beforeErase else { preconditionFailure("Missing ink fixture") }
                            try session.add(mark,page:pageIndex)
                            let id=session.board.visible[0].id
                            selectTool()
                            let hit=canvas.viewRect(CGRect(origin:mark.points[0],size:.zero)).origin
                            send(.leftMouseDown,hit)
                            send(.leftMouseDragged,CGPoint(x:hit.x+8,y:hit.y))
                            send(.leftMouseUp,CGPoint(x:hit.x+8,y:hit.y))
                            let moved=session.board.visible[0]
                            guard canvas.selectedSharedInk==id, moved.id==id, moved.markup.points != mark.points else {
                                preconditionFailure("Shared canvas selection did not move the original ink")
                            }
                            eraserTool()
                            let bounds=canvas.viewRect(moved.markup.geometryBounds)
                            let cut=CGPoint(x:bounds.midX,y:bounds.midY)
                            send(.leftMouseDown,cut); send(.leftMouseUp,cut)
                            guard session.board.visible[0].inkPathStarts.count==4 else { preconditionFailure("Shared eraser failed to split grouped paths") }
                            undoEdit()
                            guard session.board.visible[0].points==moved.points else { preconditionFailure("Shared undo did not restore the gesture") }
                            selectTool()
                            let start=canvas.viewRect(CGRect(origin:moved.markup.points[0],size:.zero)).origin
                            send(.leftMouseDown,start); send(.leftMouseUp,start)
                            deleteAnnotation()
                            guard session.board.visible.isEmpty, canvas.selectedSharedInk==nil else { preconditionFailure("Shared delete left stale selection") }
                            deletedInkPoint = start
                            let alpha = overlayAlpha(at: start)
                            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                                precondition(alpha == 0, "Reduce Motion should skip the delete fade")
                            } else {
                                precondition(alpha > 0, "Deleted ink should still be fading out in the overlay")
                            }
                            phase = 17
                        } catch { fputs("FAIL: shared ink editor: \(error)\n",stderr); exit(1) }
                    }
                case 17:
                    if overlayAlpha(at: deletedInkPoint) == 0 {
                        print("PASS: deleted ink is immediately removed from the document and its overlay clears after the transition")
                        phase = 16
                        endDrawing()
                    }
                case 16:
                    if drawingSession==nil {
                        if requireMetal {
                            phase=5; actionStart=CACurrentMediaTime(); changeZoom(2)
                        } else {
                            print("PASS: freehand creation, move, rotate, partial erase in place, one-step restoration, whole-group Delete and undo/redo")
                            exit(0)
                        }
                    }
                case 5:
                    if zoom == 2, canvas.didPresentMetal {
                        print(String(format: "200%% zoom to Metal frame callback: %.1f ms", (canvas.presentationTime - actionStart) * 1000))
                        phase = 6
                        actionStart = CACurrentMediaTime()
                        scroll.contentView.scroll(to: CGPoint(x: 0, y: 115))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                case 6:
                    if scroll.contentView.bounds.minY > 0, canvas.didPresentMetal {
                        print(String(format: "Scroll to Metal frame callback: %.1f ms", (canvas.presentationTime - actionStart) * 1000))
                        phase = 7
                        changeZoom(1)
                    }
                case 7:
                    if zoom == 1, canvas.didPresentMetal {
                        print("PASS: Metal presented the edited page, zoomed viewport, scrolled viewport and reused scene at lower zoom")
                        exit(0)
                    }
                default:break
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:check)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:check)
    }
    private func installReactEditor() {
        guard ProcessInfo.processInfo.environment["POD_USE_LEGACY_UI"] != "1",let resources=Bundle.main.resourceURL?.appendingPathComponent("Web"),FileManager.default.fileExists(atPath:resources.appendingPathComponent("index.html").path) else { return }
        legacyEditorRoot=window.contentView
        let host=ReactEditor(resources:resources,canvas:scroll)
        reactEditor=host; window.contentView=host
        host.onPagePreview = { [weak self] url, done in
            guard let self else { done(nil); return {} }
            return self.navigationPreviews.request(url, completion: done)
        }
        host.onCommand={ [weak self] command,data in self?.reactCommand(command,data) }
        host.onViewportChange={ [weak self] in self?.canvas.resizeToViewport(); self?.publishReactState() }
        window.initialFirstResponder=canvas
    }
    private func rotateView() {
        if waitForInk({ [weak self] in self?.rotateView() }) { return }
        guard !busy, let document = loaded else { return }
        viewRotation = (viewRotation + 270) % 360
        show(document, page: pageIndex)
    }
    private func reactHex(_ value:NSColor)->String {
        let color=value.usingColorSpace(.sRGB) ?? .black
        return String(format:"#%02X%02X%02X",Int((color.redComponent*255).rounded()),Int((color.greenComponent*255).rounded()),Int((color.blueComponent*255).rounded()))
    }
    private func reactColor(_ value:Any?)->NSColor? {
        guard let text=value as? String,text.range(of:"^#[0-9a-fA-F]{6}$",options:.regularExpression) != nil,let n=UInt32(text.dropFirst(),radix:16) else { return nil }
        return NSColor(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
    }
    private func publishReactState() {
        guard let host=reactEditor,!updatingAnnotations else { return }
        let selected=selectedAnnotationMark
        let selectedID:Any=selectedSharedStroke?.id.uuidString as Any? ?? selectedMarkup.map{Int($0)} as Any? ?? NSNull()
        var state:[String:Any]=[
            "documentName":fileLabel.stringValue,"page":pageIndex+1,"totalPages":loaded?.pages.count ?? 0,
            "busy":busy,"annotationPending":false,"dirty":dirty,"canUndo":undoButton?.isEnabled ?? false,"canRedo":redoButton?.isEnabled ?? false,
            "canSave":saveButton?.isEnabled ?? false,"canOpen":openButton?.isEnabled ?? false,"canReplace":applyButton?.isEnabled ?? false,
            "status":status.stringValue,"zoom":Int((zoom*100).rounded()),"viewRotation":viewRotation,"tool":canvas.panning ? "Pan":canvas.erasing ? "Eraser":(markupTool?.title ?? "Select"),
            "collaborating":drawingSession != nil,"selectedText":selection == nil ? NSNull():replacement.stringValue as Any,
            "selectedKind":selected?.kind.title as Any? ?? NSNull(),"annotationLink":selected?.kind == .ink ? selected!.link as Any:NSNull(),
            "annotationText":selected?.hasEditableText == true ? selected!.text as Any:NSNull(),"selectedAnnotation":selectedID,
            "editContext":editContext.uuidString,"selectionLocked":selected?.inkLocked ?? false,"eraserWidth":canvas.eraserWidth,
            "style":["stroke":reactHex(markupStyle.stroke),"fill":markupStyle.fill.map{reactHex($0)} as Any? ?? NSNull(),"width":markupStyle.width,"opacity":markupStyle.opacity,"fontSize":markupStyle.fontSize],
            "comments":pageComments.map{["id":$0.id,"text":$0.text]}
        ]
        let rect=canvas.pageRect.offsetBy(dx:-scroll.contentView.bounds.minX,dy:-scroll.contentView.bounds.minY)
        state["imageFrame"]=["x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height]
        if let image=canvas.image,image !== reactLastImage,let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) {
            state["image"]="data:image/png;base64,"+png.base64EncodedString(); reactLastImage=image
        }
        host.setState(state)
    }
    private func reactCommand(_ command:String,_ data:[String:Any]) {
        defer { publishReactState() }
        if command=="theme" { window.appearance=NSAppearance(named:(data["dark"] as? Bool ?? false) ? .darkAqua:.aqua); return }
        guard !busy else { return }
        if ["style","annotationText","annotationLink","deleteAnnotation","rotateDrawing","eraserWidth","selectAnnotation"].contains(command) {
            guard data["context"] as? String==editContext.uuidString else { return }
        }
        switch command {
        case "eraserWidth":
            if canvas.erasing,let size=data["width"] as? Int,[8,16,24,32].contains(size) { canvas.eraserWidth=CGFloat(size) }
        case "open":openFile()
        case "sample":openSample()
        case "save":saveCopy()
        case "undo":undoEdit()
        case "redo":redoEdit()
        case "rotateView":rotateView()
        case "rotate":rotateClockwise()
        case "merge":mergePDF()
        case "extract":extractPages()
        case "split":splitPages()
        case "crop":cropPage()
        case "resetCrop":resetCrop()
        case "moveEarlier":movePageEarlier()
        case "moveLater":movePageLater()
        case "shareDrawing":shareDrawing()
        case "joinDrawing":joinDrawingPrompt()
        case "endDrawing":endDrawing()
        case "page":if let page=data["page"] as? Int,page>0 { navigate(page-1) }
        case "tool":
            guard let name=data["name"] as? String else { return }
            if name=="Pan" { selectTool(); canvas.panning=true } else if name=="Select" { selectTool() } else if name=="Eraser" { eraserTool() } else if let kind=MarkupKind.allCases.first(where:{$0.title==name}),markupTool != kind { chooseTool(kind) }
        case "style":
            var style=markupStyle
            if let color=reactColor(data["stroke"]) { style.stroke=color }
            if data["fill"] is NSNull { style.fill=nil } else if let color=reactColor(data["fill"]) { style.fill=color }
            if let value=data["width"] as? Double,value.isFinite { style.width=min(64,max(0.1,value)) }
            if let value=data["opacity"] as? Double,value.isFinite { style.opacity=min(1,max(0,value)) }
            if let value=data["fontSize"] as? Double,value.isFinite { style.fontSize=min(144,max(6,value)) }
            setMarkupStyle(style)
        case "replaceText":if let text=data["text"] as? String,text.utf8.count<=1_048_576 { replacement.stringValue=text; applyEdit() }
        case "annotationText":if let text=data["text"] as? String { if text.utf8.count<=4096 { annotationText.stringValue=text; updateAnnotationText() } else { showError(EngineError(message:"The comment must fit in 4096 UTF-8 bytes.")) } }
        case "annotationLink":if let link=data["link"] as? String { annotationLink.stringValue=link; updateAnnotationLink() }
        case "rotateDrawing":rotateDrawing()
        case "deleteAnnotation":deleteAnnotation()
        case "selectAnnotation":
            if let id=data["id"] as? String { selectPageComment(id) }
            else if let id=data["id"] as? Int { selectPageComment(String(id)) }
        case "rename":if let name=data["name"] as? String,name.count<=128,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { reactDisplayName=name.lowercased().hasSuffix(".pdf") ? name:name+".pdf"; fileLabel.stringValue=reactDisplayName!; documentHeader.documentName=fileLabel.stringValue; window.title=fileLabel.stringValue+" — Pod" }
        default:break
        }
    }
    @objc private func about() { let alert=NSAlert(); alert.messageText="Pod"; alert.informativeText="A small, native PDF workspace.\n\nOwn Zig engine and CPU renderer. Native macOS interface.\n\nEarly preview: uncompressed PDFs using standard Courier text and supported vector graphics."; alert.beginSheetModal(for:window) }
    @objc private func quit() { NSApp.terminate(nil) }
}
