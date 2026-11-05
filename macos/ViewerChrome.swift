import AppKit

// Chrome interactions are independent of PDF operations so unimplemented tools can be reviewed.
final class ViewerChrome:NSObject {
    static let modes=["Popular","Fill & Sign","Mark up","Edit text","Security","Organize","Explore"]
    let rail=LuminModeRail()
    let toolbar=LuminMainToolbar()
    let typeToolbar=LuminTypeToolbar()
    let formBuilderPanel=LuminFormBuilderPanel(frame:.zero)
    private(set) var formBuilderActive=false
    var onFormVisibility:((Bool)->Void)?
    var zoomField:LuminZoomField { toolbar.zoomField }
    var onZoomPreview:((Double)->Void)?
    private var viewState=LuminViewState()
    func updateZoomPercentage(_ value:Double) { zoomField.percentage=value }
    var onTypeVisibility:((Bool)->Void)?
    var onTypeChange:((LuminTypeState)->Void)?
    private var modeButtons:[LuminModeButton]=[]
    private var popup:LuminPopper?
    private var undoAvailable=false,redoAvailable=false
    private var shortcutMonitor:Any?
    private var hoverOpen:DispatchWorkItem?
    private var hoverClose:DispatchWorkItem?
    private var hoverSuppressed:String?
    private var nestedModePopup:LuminPopper?
    private var highlightKind:MarkupKind = .highlight
    private let signatureModal=LuminModal()
    private let premiumModal=LuminModal()
    private var modalShown:Bool { signatureModal.isShown || premiumModal.isShown }
    private var signatureDialog:LuminSignatureDialog?
    private var signaturePreviews:[LuminSignaturePreview]=[]
    private var repeatsSignature=false,handwritingSignature=true
    private(set) var darkPage=false
    func setDarkPagePreview(_ value:Bool) { darkPage=value }
    func history(undo:Bool,redo:Bool) { undoAvailable=undo; redoAvailable=redo; toolbar.setHistory(undo:undo,redo:redo) }
    private(set) var mode="Popular"
    var onAction:((String,NSButton)->Bool)?
    var onMode:((String)->Void)?
    var onFocusMode:(()->Void)?
    var onNavigationClose:(()->Void)?
    var onMarkup:((MarkupKind)->Void)?
    var onStyle:((MarkupKind,NSButton)->Void)?

    override init() {
        super.init()
        typeToolbar.isHidden=true
        formBuilderPanel.isHidden=true
        formBuilderPanel.onCancel={ [weak self] in self?.setFormBuilderVisible(false) }
        formBuilderPanel.onFieldChoice={ [weak self] kind in self?.markTool(kind.title) }
        zoomField.onOpen={ [weak self] in self?.showZoom() }
        zoomField.onCommit={ [weak self] value in self?.onZoomPreview?(value) }
        typeToolbar.onChange={ [weak self] state in guard let self,typeToolbar.purpose == .text else { return }; onTypeChange?(state) }
        typeToolbar.canCloseOnEscape={ [weak self] in self?.modalShown != true }
        typeToolbar.onClose={ [weak self] in
            guard let self else { return }; hideType()
            markTool("Select")
            _ = onAction?("Select",NSButton())
        }
        modeButtons=rail.buttons
        rail.expandedPanel.onDocument={ [weak self] _ in self?.onNavigationClose?() }
        rail.expandedPanel.onUpload={ [weak self] key in guard let self else { return }; _ = onAction?(key=="device" ? "Open file":"Upload from \(key)",rail.expandedPanel.uploadArea.button) }
        rail.onFocusMode={ [weak self] in guard let self,!rail.navigationExpanded else { return }; self.hoverOpen?.cancel(); self.popup?.close(); self.onFocusMode?() }
        for b in modeButtons {
            b.target=self; b.action=#selector(pickMode)
            b.onHover={ [weak self,weak b] entered in guard let b else { return }; self?.hoverMode(b,entered:entered) }
        }
        toolbar.onAction={ [weak self] sender in self?.activate(sender) }
        rebuild()
        shortcutMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self,NSApp.modalWindow==nil,!modalShown,let owner=rail.window else { return event }
            let explore=event.modifierFlags.contains(.option) && event.keyCode==44
            let focus=event.modifierFlags.contains(.command) && event.keyCode==42
            guard explore || focus else { return event }
            var target=event.window
            while target != nil && target !== owner { target=target?.parent }
            guard target === owner else { return event }
            if rail.navigationExpanded { return event }
            if focus { popup?.close(); onFocusMode?() } else { showExplore(modeButtons.last!) }; return nil
        }
    }
    deinit { hoverOpen?.cancel(); hoverClose?.cancel(); nestedModePopup?.close(); if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) } }
    func setNavigationExpanded(_ value:Bool) { hoverOpen?.cancel(); hoverClose?.cancel(); popup?.close(); rail.navigationExpanded=value; toolbar.expandedNavigation=value; modeButtons.forEach{$0.menuHovered=false} }
    func fit(width:CGFloat) { toolbar.viewportWidth=width; toolbar.needsLayout=true }
    private func rebuild() { modeButtons.forEach{$0.selected=Self.modes[$0.tag]==mode}; toolbar.setMode(mode) }
    @objc private func pickMode(_ sender:NSButton) {
        let next=Self.modes[sender.tag]
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverSuppressed=next
        if next=="Edit text" { showPremiumModal(sender,kind:.editText); return }
        if next=="Explore" { showExplore(sender); return }
        if next != mode { setFormBuilderVisible(false) }
        mode=next; popup?.close(); hideType(); rebuild(); onMode?(mode)
    }
    private func hoverMode(_ button:LuminModeButton,entered:Bool) {
        hoverOpen?.cancel()
        if !entered {
            if hoverSuppressed==button.title { hoverSuppressed=nil }
            if (popup?.contentViewController as? LuminModeMenu)?.mode==button.title { scheduleHoverClose() }
            return
        }
        guard !modalShown,button.title != "Edit text",hoverSuppressed != button.title,!button.isHiddenOrHasHiddenAncestor,!(popup?.isShown==true && popup?.contentViewController is LuminExploreMenu) else { return }
        if (popup?.contentViewController as? LuminModeMenu)?.mode==button.title && popup?.isShown==true { hoverClose?.cancel(); return }
        let work=DispatchWorkItem { [weak self,weak button] in
            guard let self,let button,button.window != nil,!button.isHiddenOrHasHiddenAncestor else { return }
            if button.title=="Explore" { showExplore(button) } else { showModeMenu(button) }
        }
        hoverOpen=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    private func scheduleHoverClose() {
        hoverClose?.cancel(); guard nestedModePopup?.isShown != true else { return }
        let work=DispatchWorkItem { [weak self] in guard let self,popup?.contentViewController is LuminModeMenu else { return }; popup?.close() }
        hoverClose=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.1,execute:work)
    }
    private func showModeMenu(_ button:LuminModeButton) {
        hoverClose?.cancel(); popup?.close()
        let menu=LuminModeMenu(mode:button.title),pop=LuminPopper()
        pop.contentViewController=menu; pop.gap=5; pop.crossAxisOffset = -24; pop.sideAlignment = .start; pop.viewportInset=5
        menu.onHover={ [weak self,weak menu] entered in
            guard let self,let menu,popup?.contentViewController === menu else { return }
            if entered { hoverClose?.cancel() } else { scheduleHoverClose() }
        }
        menu.onChoose={ [weak self,weak menu,weak pop] row in
            guard let self,let menu else { return }; hoverClose?.cancel()
            if row.entry.key=="signature" {
                if mode != menu.mode { mode=menu.mode; hideType(); rebuild(); onMode?(mode) }
                let child=LuminPopper(); child.contentViewController=makeSignatureMenu(row); nestedModePopup?.close(); nestedModePopup=child
                child.onClose={ [weak self] in self?.nestedModePopup=nil }
                child.show(relativeTo:row.bounds,of:row); return
            }
            pop?.close()
            let title=row.entry.key=="comment" ? "Add comment":row.entry.title
            let command=LuminExploreCommand(key:row.entry.key,title:title,icon:row.entry.glyph,premium:row.entry.premium)
            chooseExplore(command,from:button,toolbarMode:menu.mode)
        }
        pop.onKeyDown={ [weak menu] in menu?.handleKey($0) ?? false }
        pop.onClose={ [weak self,weak button] in
            self?.hoverClose?.cancel(); self?.nestedModePopup?.close(); self?.nestedModePopup=nil
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self,weak button] in
                guard let button,(self?.popup?.contentViewController as? LuminModeMenu)?.mode != button.title || self?.popup?.isShown != true else { return }
                button.menuHovered=false
            }
        }
        modeButtons.forEach{$0.menuHovered=false}; button.menuHovered=true; popup=pop
        pop.show(relativeTo:button.bounds,of:button,preferredEdge:.maxX)
    }
    private func hideType() { typeToolbar.dismiss(); onTypeVisibility?(false) }
    private func markTool(_ title:String,_ sender:NSButton?=nil) { toolbar.selectTool(title) }
    private func openType() {
        popup?.close(); onMarkup?(.freeText); typeToolbar.open(); onTypeVisibility?(true)
        markTool("Type")
    }
    private func openDate() {
        popup?.close()
        if !typeToolbar.isHidden && typeToolbar.purpose == .date {
            hideType(); markTool("Select"); _ = onAction?("Select",NSButton()); return
        }
        // Date placement is deferred; leave the canvas in Select while its source UI is open.
        _ = onAction?("Select",NSButton())
        typeToolbar.open(for:.date); onTypeVisibility?(true); markTool("Date")
    }
    @objc private func activate(_ sender:NSButton) {
        let title=sender.identifier?.rawValue ?? sender.title
        if title=="Date" || title=="Date options" { openDate(); return }
        if title=="Stamp" { showPremiumGate(sender); return }
        if title=="Prepare form" { showFormBuilderMenu(sender); return }
        if title=="Password protection" { showPasswordMenu(sender); return }
        if title=="Redaction" { showPremiumModal(sender); return }
        if title=="View controls" { showViewControls(sender); return }
        if title=="Thumbnails options" { showThumbnails(sender); return }
        if title=="More tools" { showMoreTools(sender); return }
        if title=="Type" || title=="Type options" {
            openType()
            return
        }
        if ["Select","Eraser","Shape","Text tools","Highlight","Draw","Add comment","Signature","Prepare form","Measure"].contains(title.replacingOccurrences(of:" options",with:"")) { hideType() }
        if title=="Highlight options" {
            let menu=LuminHighlightMenu(current:highlightKind)
            menu.onChoose={ [weak self] kind in self?.highlightKind=kind; self?.markTool("Highlight"); self?.popup?.close(); self?.onMarkup?(kind) }
            menu.onOptions={ [weak self] kind,button in self?.highlightKind=kind; self?.markTool("Highlight"); self?.onStyle?(kind,button) }
            present(menu,sender); return
        }
        if onAction?(title,sender)==true {
            if ["Select","Eraser","Shape","Text tools","Highlight","Draw","Type","Add comment"].contains(title) || title.hasSuffix(" options") {
                markTool(title.replacingOccurrences(of:" options",with:""),sender)
            }
            return
        }
        markTool(title.replacingOccurrences(of:" options",with:""))
        showPanel(title.replacingOccurrences(of:" options",with:""),sender)
    }
    private func showExplore(_ sender:NSButton,reusing existing:LuminExploreMenu?=nil) {
        hoverOpen?.cancel()
        if existing==nil,popup?.isShown==true && popup?.contentViewController is LuminExploreMenu { popup?.close(); return }
        popup?.close()
        let isLight=sender.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .aqua
        let menu=existing ?? LuminExploreMenu(mode:mode,canUndo:undoAvailable,canRedo:redoAvailable,showGuideline:!UserDefaults.standard.bool(forKey:"Pod.closedQuickSearchGuideline"),isLight:isLight)
        menu.darkPage=darkPage
        menu.onDismissGuideline={ UserDefaults.standard.set(true,forKey:"Pod.closedQuickSearchGuideline") }
        menu.onChoose={ [weak self,weak sender,weak menu] command in
            guard let self,let sender else { return }
            if command.key=="darkPage" { darkPage=menu?.darkPage ?? false; return }
            if command.key=="editContent" { showPremiumModal(sender,kind:.editText,restoring:menu); return }
            let toolbarMode=menu?.toolbarMode(for:command)
            popup?.close()
            if command.key=="darkMode" { sender.window?.appearance=NSAppearance(named:isLight ? .darkAqua:.aqua); return }
            chooseExplore(command,from:sender,toolbarMode:toolbarMode)
        }
        let pop=LuminPopper(); pop.contentViewController=menu; pop.gap=5; pop.viewportInset=5; pop.initialResponder=menu.searchInput; pop.focusDelay=existing==nil ? 0.2:0
        pop.onKeyDown={ [weak menu] event in menu?.handleKey(event) ?? false }
        pop.onClose={ [weak self,weak menu] in menu?.cancelSearch(); self?.modeButtons.last?.selected=false }
        popup=pop; modeButtons.last?.selected=true
        pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxX)
    }
    private func chooseExplore(_ command:LuminExploreCommand,from sender:NSButton,toolbarMode:String?) {
        guard command.disabled != true else { return }
        if command.key=="editContent" { showPremiumModal(sender,kind:.editText); return }
        if let toolbarMode,toolbarMode != mode { setFormBuilderVisible(false) }
        if let toolbarMode { mode=toolbarMode; hideType(); rebuild(); onMode?(mode) }
        if command.key=="configureAccess" { showPremiumModal(sender); return }
        if command.key=="type" { openType(); return }
        if command.key=="customizeFields" { setFormBuilderVisible(!formBuilderActive); return }
        if command.key=="autoDetectFields" { return } // Detection processing is deferred with PDF functionality.
        if command.key=="freehandHighlight" { highlightKind = .freehandHighlight; markTool("Highlight"); onMarkup?(.freehandHighlight); return }
        let title=["textHighlight":"Highlight","configureAccess":"Password protection","removeAccess":"Password protection","customizeFields":"Prepare form","mergeDocs":"Merge","cropPages":"Crop","insertBlankPages":"Insert","commentHistory":"Comments","searchDocument":"Search","searchChatbot":"Lumin AI","signSecurely":"Sign securely"][command.key] ?? command.title
        if onAction?(title,sender)==true { if ["Shape","Text tools","Highlight","Draw","Add comment","Eraser","Select"].contains(title) { markTool(title) }; return }
        if command.key=="pan" { markTool("Pan"); return }
        showPanel(title,sender)
    }
    private func present(_ content:NSViewController,_ sender:NSButton) {
        popup?.close(); let pop=LuminPopper(); pop.contentViewController=content; popup=pop
        let anchor=(sender as? LuminToolbarButton)?.sourcePopoverAnchor ?? sender
        pop.show(relativeTo:anchor.bounds,of:anchor,preferredEdge:.maxY)
    }
    private func makeSignatureMenu(_ sender:NSButton)->LuminSignatureMenu {
        let menu=LuminSignatureMenu(repeatsSignature:repeatsSignature,previews:signaturePreviews)
        menu.onAddSignature={ [weak self] in self?.showSignatureCreation(sender) }
        menu.onRepeatChange={ [weak self] in self?.repeatsSignature=$0 }
        menu.onSelect={ [weak self] _ in self?.popup?.close(); self?.nestedModePopup?.close(); self?.markTool("Signature") }
        menu.onDelete={ [weak self] id in self?.signaturePreviews.removeAll{$0.id==id} }
        return menu
    }
    private func showSignatureCreation(_ sender:NSButton) {
        guard let root=rail.window?.contentView else { return }
        hoverOpen?.cancel(); hoverClose?.cancel(); nestedModePopup?.close(); popup?.close()
        let dialog=LuminSignatureDialog(count:signaturePreviews.count,repeatsSignature:repeatsSignature,handwriting:handwritingSignature)
        signatureDialog=dialog
        dialog.onRepeatChange={ [weak self] in self?.repeatsSignature=$0 }
        dialog.onPenModeChange={ [weak self] in self?.handwritingSignature=$0 }
        dialog.onResize={ [weak self] in self?.signatureModal.layout() }
        dialog.onCancel={ [weak self] in self?.signatureModal.close() }
        dialog.onSave={ [weak self] preview in self?.signaturePreviews.append(preview); self?.signatureModal.close(); self?.markTool("Signature") }
        signatureModal.onClose={ [weak self,weak dialog] in
            dialog?.dismissPickers()
            guard let self else { return }; signatureDialog=nil; markTool("Select"); _ = onAction?("Select",toolbar.button("Select") ?? NSButton())
        }
        signatureModal.onKeyDown={ [weak dialog] in dialog?.handleKey($0) ?? false }
        _ = dialog.view
        signatureModal.show(dialog,in:root,initialResponder:dialog.controls["tab.Draw"])
    }
    private func showThumbnails(_ sender:NSButton) {
        if popup?.isShown==true && popup?.contentViewController?.title=="Thumbnails options" { popup?.close(); return }
        popup?.close()
        let menu=LuminToolbarMenu.thumbnails()
        menu.onChoose={ [weak self] name,button in
            guard let self else { return }; toolbar.setThumbnailMode(name); popup?.close()
            if name=="Thumbnails" { _ = onAction?(name,button) }
        }
        let anchor:NSView=(sender.superview as? LuminToolbarSplit) ?? sender
        let pop=LuminPopper(); pop.contentViewController=menu; pop.alignment = .start; pop.gap=8
        pop.onKeyDown={ [weak menu] event in menu?.handleKey(event) ?? false }
        popup=pop; pop.show(relativeTo:anchor.bounds,of:anchor)
    }
    private func showMoreTools(_ sender:NSButton) {
        if popup?.isShown==true && popup?.contentViewController?.title=="More tools" { popup?.close(); return }
        popup?.close()
        let menu=LuminToolbarMenu.overflow(mode:mode)
        menu.onChoose={ [weak self] _,button in self?.activate(button) }
        menu.onOptions={ [weak self] _,button in self?.activate(button) }
        let pop=LuminPopper(); pop.contentViewController=menu; pop.gap=4; pop.crossAxisOffset=12
        pop.onKeyDown={ [weak menu] event in menu?.handleKey(event) ?? false }
        popup=pop; pop.show(relativeTo:sender.bounds,of:sender)
    }
    private func showZoom() {
        if popup?.isShown==true && popup?.contentViewController is LuminZoomMenu { return }
        popup?.close()
        let menu=LuminZoomMenu()
        menu.onChoose={ [weak self] action in
            guard let self else { return }
            switch action {
            case .percent(let value):zoomField.percentage=value
            case .zoomIn:zoomField.percentage=LuminZoomAction.stepped(zoomField.percentage,increase:true)
            case .zoomOut:zoomField.percentage=LuminZoomAction.stepped(zoomField.percentage,increase:false)
            case .fitWidth,.fitHeight:break // UI-first phase; PDF fit/layout callbacks are separate.
            }
            onZoomPreview?(zoomField.percentage)
            if action.closesMenu { popup?.close() }
        }
        let pop=LuminPopper(); pop.contentViewController=menu; pop.alignment = .start; pop.gap=8; pop.takesKeyFocus=false; pop.keepsAnchorInteractive=true
        pop.onKeyDown={ [weak self,weak menu] event in
            guard let self,let menu else { return false }
            if event.keyCode==48 {
                if event.window === zoomField.window && zoomField.input.currentEditor() != nil && !event.modifierFlags.contains(.shift) { menu.focusRow(0); return true }
                if event.window === menu.view.window {
                    menu.clearKeyboardFocus()
                    zoomField.window?.makeKey()
                    let target:NSView?=event.modifierFlags.contains(.shift) ? zoomField.input:toolbar.button("View controls")
                    zoomField.window?.makeFirstResponder(target); return true
                }
            }
            // Source MenuList is a sibling of the input: typing-field arrows/Home/End do not reach it.
            guard event.window === menu.view.window else { return false }
            return menu.handleKey(event)
        }
        pop.onClose={ [weak self] in
            guard let self else { return }; zoomField.commit()
            if zoomField.input.currentEditor() != nil { zoomField.window?.makeFirstResponder(nil) }
        }
        popup=pop; pop.show(relativeTo:zoomField.bounds,of:zoomField)
    }
    private func showViewControls(_ sender:NSButton) {
        if popup?.isShown==true && popup?.contentViewController is LuminViewControlsMenu { popup?.close(); return }
        popup?.close()
        let menu=LuminViewControlsMenu(state:viewState)
        menu.onChange={ [weak self] state in self?.viewState=state }
        let pop=LuminPopper(); pop.contentViewController=menu; pop.alignment = .start; pop.gap=8
        if let button=sender as? LuminToolbarButton { button.isSelected=true; pop.onClose={ [weak button] in button?.isSelected=false } }
        popup=pop; pop.show(relativeTo:sender.bounds,of:sender)
    }
    private func showPremiumGate(_ sender:NSButton) {
        if popup?.isShown==true && popup?.contentViewController is LuminPremiumGate { popup?.close(); return }
        popup?.close(); let gate=LuminPremiumGate(),pop=LuminPopper()
        pop.contentViewController=gate; pop.cornerRadius=16; pop.alignment = .center; pop.gap=0; pop.keepsAnchorInteractive=true
        popup=pop; pop.show(relativeTo:sender.bounds,of:sender)
    }
    private func showFormBuilderMenu(_ sender:NSButton) {
        if popup?.isShown==true,popup?.contentViewController is LuminFormBuilderMenu { popup?.close(); return }
        popup?.close()
        let menu=LuminFormBuilderMenu(),pop=LuminPopper()
        menu.onPrepare={ [weak self] in guard let self else { return }; setFormBuilderVisible(!formBuilderActive) }
        menu.onAutoDetect={ [weak self] in self?.popup?.close() }
        pop.contentViewController=menu; pop.alignment = .center; pop.gap=8; pop.keepsAnchorInteractive=true
        pop.onKeyDown={ [weak menu] in menu?.handleKey($0) ?? false }
        popup=pop; pop.show(relativeTo:sender.bounds,of:sender)
    }
    private func setFormBuilderVisible(_ value:Bool) {
        guard value != formBuilderActive else { return }
        popup?.close(); nestedModePopup?.close(); hideType()
        formBuilderActive=value; formBuilderPanel.isHidden = !value; formBuilderPanel.reset()
        toolbar.setFormBuilderActive(value); markTool("Select")
        _ = onAction?("Select",toolbar.button("Select") ?? NSButton())
        onFormVisibility?(value)
    }
    private func showPasswordMenu(_ sender:NSButton,reusing existing:LuminPasswordMenu?=nil) {
        if existing==nil,popup?.isShown==true,popup?.contentViewController is LuminPasswordMenu { popup?.close(); return }
        popup?.close()
        let menu=existing ?? LuminPasswordMenu(),pop=LuminPopper()
        menu.onSet={ [weak self,weak sender,weak menu] in guard let sender,let menu else { return }; self?.showPremiumModal(sender,restoring:menu) }
        pop.contentViewController=menu; pop.alignment = .center; pop.gap=8; pop.keepsAnchorInteractive=true
        pop.onKeyDown={ [weak menu] in menu?.handleKey($0) ?? false }
        if let button=sender as? LuminToolbarButton { button.isSelected=true; pop.onClose={ [weak button] in button?.isSelected=false } }
        popup=pop; pop.show(relativeTo:sender.bounds,of:sender)
    }
    private func showPremiumModal(_ sender:NSButton,kind:LuminPremiumGate.Kind = .modal,restoring menu:NSViewController?=nil) {
        guard let root=rail.window?.contentView,let owner=root.window else { return }
        hoverOpen?.cancel(); hoverClose?.cancel(); nestedModePopup?.close()
        typeToolbar.dismissPopovers()
        let backgroundFrame=popup?.frame.map{ root.convert(owner.convertFromScreen($0),from:nil) }
        let searchSelection=(menu as? LuminExploreMenu)?.retainSearchSelection()
        // Explore is still open behind the dialog; keep its pending search work alive.
        if menu is LuminExploreMenu { popup?.onClose=nil }
        popup?.close(); premiumModal.close()
        if let menu,let backgroundFrame {
            // Keep the real menu under the backdrop rather than above it in a separate panel.
            (menu as? LuminPasswordMenu)?.clearFocus()
            menu.view.frame=backgroundFrame; menu.view.autoresizingMask=[.minXMargin,.minYMargin]; root.addSubview(menu.view)
            (sender as? LuminToolbarButton)?.isSelected=true
            if menu is LuminExploreMenu { modeButtons.last?.selected=true }
        }
        let gate=LuminPremiumGate(kind:kind); _=gate.view
        premiumModal.backdropOpacity=0.5
        premiumModal.onKeyDown={ [weak gate] event in
            guard event.keyCode==48,let gate else { return false }; gate.view.window?.makeFirstResponder(gate.upgrade); return true
        }
        premiumModal.onClose={ [weak self,weak sender,weak root,weak menu] in
            guard let self else { return }; premiumModal.onClose=nil
            menu?.view.removeFromSuperview()
            if let menu,let sender,sender.window === root?.window {
                if let password=menu as? LuminPasswordMenu { showPasswordMenu(sender,reusing:password) }
                if let explore=menu as? LuminExploreMenu { showExplore(sender,reusing:explore); explore.restoreSearchSelection(searchSelection); return }
            }
            if let sender { sender.window?.makeFirstResponder(sender) }
        }
        premiumModal.show(gate,in:root,initialResponder:nil)
    }
    private func showPanel(_ title:String,_ sender:NSButton) {
        if title=="View controls" { showViewControls(sender); return }
        if title=="Zoom" { showZoom(); return }
        if title=="Type" { openType(); return }
        if title=="Prepare form" { setFormBuilderVisible(!formBuilderActive); return }
        if title=="Edit content" { showPremiumModal(sender,kind:.editText); return }
        if title=="Signature" { present(makeSignatureMenu(sender),sender); return }
        if title=="Date" { openDate(); return }
        if title=="Stamp" { showPremiumGate(sender); return }
        if title=="Password protection" { showPasswordMenu(sender); return }
        if title=="Redaction" { showPremiumModal(sender); return }
        if title=="Eraser" {
            present(LuminEraserPalette(),sender); return
        }
        popup?.close()
        let vc=NSViewController(); let surface=PodSurfaceStack(); surface.surface=PodTheme.raised; surface.orientation = .vertical; surface.alignment = .leading; surface.spacing=16; surface.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16); vc.view=surface
        func add(_ view:NSView) { surface.addArrangedSubview(view); view.widthAnchor.constraint(equalToConstant:268).isActive=true }
        func text(_ value:String,_ heading:Bool=false) { let t=NSTextField(wrappingLabelWithString:value); t.font=heading ? PodTypography.section:PodTypography.control; t.textColor=heading ? PodTheme.text:PodTheme.secondaryText; add(t) }
        func choices(_ labels:[String]) { let p=NSPopUpButton(); p.addItems(withTitles:labels); add(p) }
        func slider(_ name:String,_ value:Double) { text(name); let s=NSSlider(value:value,minValue:0,maxValue:100,target:nil,action:nil); add(s) }
        text(title,true)
        switch title {
        case "Signature","Sign securely": add(PodChoiceGroup(labels:["Draw","Type","Upload"],selectedIndex:0)); let area=PodSurfaceView(); area.surface=PodTheme.canvas; area.heightAnchor.constraint(equalToConstant:100).isActive=true; add(area); text("Add your signature"); add(NSButton(checkboxWithTitle:"Place signature multiple times",target:nil,action:nil))
        case "Bates numbering": choices(["Add page numbers","Remove page numbers"]); choices(["Bottom center","Bottom right","Top right"]); let field=NSTextField(string:"1"); field.setAccessibilityLabel("Starting number"); add(field)
        case "Measure": choices(["Distance","Angle","Perimeter","Polygon area","Rectangle area","Circle area"]); add(NSButton(checkboxWithTitle:"Snapping",target:nil,action:nil)); choices(["Scale: 1:1","Add new scale"]); slider("Border width",1); slider("Opacity",100)
        case "Eraser": slider("Eraser size",20)
        case "Edit content","Type","Add text": choices(["Inter","Helvetica","Courier"]); choices(["12 pt","14 pt","16 pt","18 pt","24 pt"]); add(PodChoiceGroup(labels:["Bold","Italic","Underline"],selectedIndex:0)); slider("Opacity",100)
        case "Image","Merge","Perform OCR":
            let area=PodSurfaceView(); area.surface=PodTheme.canvas; area.heightAnchor.constraint(equalToConstant:100).isActive=true; add(area)
            text(title=="Image" ? "Choose an image to insert":"Choose a PDF")
            if title=="Perform OCR" { choices(["English","Vietnamese","French","German"]); choices(["Current page","All pages"]) }
        case "Split & Extract": choices(["Extract pages","Split into separate files"]); let field=NSTextField(); field.placeholderString="Pages, e.g. 1, 3–5"; add(field)
        case "Select pages": let field=NSTextField(); field.placeholderString="All, 1–324"; add(field)
        case "Thumbnail size": slider("Thumbnail size",50)
        case "Crop": text("Margins"); for name in ["Top","Right","Bottom","Left"] { let field=NSTextField(); field.placeholderString=name+" (pt)"; add(field) }
        case "Insert": choices(["Blank page","From a PDF"]); choices(["After current page","Before current page"])
        case "Read aloud": add(PodChoiceGroup(labels:["Play","Pause","Stop"],selectedIndex:0)); slider("Speed",50)
        default: text("\(title) options"); choices(["Default"])
        }
        text("UI preview")
        let pop=LuminPopper(); pop.contentViewController=vc; popup=pop
        pop.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY)
    }
}

final class PageThumbnailCell: NSTableCellView {
    var cancelPreview: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelPreview?(); cancelPreview = nil }
    }
}

final class OrganizerPreview:NSView {
    override var isFlipped:Bool { true }
    var pages: [PageInfo] = [] {
        didSet { previews.removeAll(); requestedCount = 0; needsLayout = true; needsDisplay = true }
    }
    var requestPreviews: ((Range<Int>) -> Void)?
    private var previews: [Int: NSImage] = [:]
    private var requestedCount = 0
    func installPreview(_ image: NSImage, page: Int) {
        previews[page] = image
        needsDisplay = true
    }
    private var pageButtons:[NSButton]=[]
    override func layout() {
        super.layout()
        let columns=max(1,Int((bounds.width-48)/220)), cellWidth=(bounds.width-48)/CGFloat(columns)
        let visibleRows = max(0, Int(floor((bounds.height - 28) / 294)) + 1)
        let frames=pages.indices.prefix(visibleRows * columns).map { index in
            let rect=CGRect(x:24+CGFloat(index%columns)*cellWidth+(cellWidth-176)/2,y:28+CGFloat(index/columns)*294,width:176,height:254)
            return rect
        }
        if !isHidden, frames.count > requestedCount {
            let pending = requestedCount..<frames.count
            requestedCount = frames.count
            requestPreviews?(pending)
        }
        // Keep existing controls: rebuilding on every layout causes an AppKit constraint loop.
        while pageButtons.count>frames.count { pageButtons.removeLast().removeFromSuperview() }
        while pageButtons.count<frames.count {
            let b=NSButton(title:"",target:self,action:#selector(pickPage)); b.isTransparent=true; addSubview(b); pageButtons.append(b)
        }
        for (index,rect) in frames.enumerated() {
            let b=pageButtons[index]; b.tag=index; if b.frame != rect { b.frame=rect }
            b.setAccessibilityLabel("Select page \(index+1)"); b.setAccessibilityValue(selected.contains(index) ? "Selected":"Not selected")
        }
    }
    @objc private func pickPage(_ sender:NSButton) { let index=sender.tag; if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }; sender.setAccessibilityValue(selected.contains(index) ? "Selected":"Not selected"); needsDisplay=true }
    private var selected:Set<Int>=[]
    private var cards:[CGRect]=[]
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        PodTheme.canvas.setFill(); bounds.fill(); cards=[]
        let columns=max(1,Int((bounds.width-48)/220)), width:CGFloat=176, height:CGFloat=230
        for index in pages.indices {
            let cellWidth=(bounds.width-48)/CGFloat(columns)
            let rect=CGRect(x:24+CGFloat(index%columns)*cellWidth+(cellWidth-width)/2,y:28+CGFloat(index/columns)*(height+64),width:width,height:height)
            if rect.minY>bounds.height { break }; cards.append(rect)
            NSColor.white.setFill(); NSBezierPath(roundedRect:rect,xRadius:2,yRadius:2).fill()
            if selected.contains(index) { PodTheme.focus.setStroke(); let outline=NSBezierPath(roundedRect:rect.insetBy(dx:-4,dy:-4),xRadius:6,yRadius:6); outline.lineWidth=2; outline.stroke() }
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
            if let image = previews[index], image.size.width > 0, image.size.height > 0 {
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
            let checkbox=CGRect(x:rect.minX,y:rect.maxY+12,width:14,height:14)
            (selected.contains(index) ? PodTheme.accent:PodTheme.border).setFill(); NSBezierPath(roundedRect:checkbox,xRadius:3,yRadius:3).fill()
            ("\(index+1)" as NSString).draw(at:NSPoint(x:rect.midX-4,y:rect.maxY+12),withAttributes:[.font:PodTypography.control,.foregroundColor:PodTheme.text])
            NSImage(systemSymbolName:"ellipsis",accessibilityDescription:"More page actions")?.draw(in:CGRect(x:rect.maxX-16,y:rect.maxY+12,width:16,height:16))
        }
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        if let index=cards.firstIndex(where:{$0.insetBy(dx:-8,dy:-24).contains(point)}) { if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }; needsDisplay=true }
    }
}
