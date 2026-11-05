import AppKit

@main enum LuminViewerLayoutTests {
    static func main() {
        _ = NSApplication.shared
        let page=PageInfo(box:NSRect(x:0,y:0,width:612,height:792),mediaBox:NSRect(x:0,y:0,width:612,height:792),rotation:0,runs:[],annotations:[])
        let organizer=OrganizerPreview(frame:NSRect(x:0,y:0,width:1000,height:796)); organizer.pages=[page,page]
        organizer.layout()
        let buttons=organizer.subviews.compactMap{$0 as? NSButton}
        precondition(buttons.count==2)
        organizer.layout()
        precondition(zip(buttons,organizer.subviews).allSatisfy{$0 === $1},"Repeated layout must retain page buttons; rebuilding them dirties AppKit constraints indefinitely")
        organizer.frame.size.width=640; organizer.layout()
        precondition(buttons[1].frame.minX>buttons[0].frame.minX)
        organizer.pages=[page]; organizer.layout(); precondition(organizer.subviews.count==1)

        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:1512,height:834),styleMask:[.titled],backing:.buffered,defer:false); owner.isReleasedWhenClosed=false
        let chrome=ViewerChrome(); chrome.rail.frame=NSRect(x:0,y:0,width:80,height:778); owner.contentView?.addSubview(chrome.rail)
        func wait(_ seconds:TimeInterval) { RunLoop.current.run(until:Date(timeIntervalSinceNow:seconds)) }
        func railMenu()->LuminModeMenu? { owner.childWindows?.compactMap{$0.contentViewController as? LuminModeMenu}.first }
        let fillButton=chrome.rail.buttons[1]
        fillButton.onHover?(true); wait(0.46)
        precondition(railMenu()?.mode=="Fill & Sign" && chrome.mode=="Popular","Hover opens the host menu without selecting its mode")
        fillButton.onHover?(false); railMenu()?.onHover?(true); wait(0.15)
        precondition(railMenu() != nil,"Crossing from the target into its menu cancels the100ms close")
        railMenu()?.rows.first{$0.entry.key=="type"}?.performClick(nil)
        precondition(chrome.mode=="Fill & Sign" && !chrome.typeToolbar.isHidden,"Menu Type selects its host mode and opens the real Type strip")
        precondition(railMenu()==nil)
        let popularButton=chrome.rail.buttons[0]
        popularButton.onHover?(true); wait(0.46); precondition(railMenu()?.mode=="Popular")
        let signatureMenu=railMenu()!,signatureRow=signatureMenu.rows.first{$0.entry.key=="signature"}!
        signatureMenu.view.window?.makeFirstResponder(signatureRow); signatureRow.performClick(nil)
        let nestedWindow=signatureMenu.view.window!.childWindows!.first!
        precondition(nestedWindow.isVisible && railMenu() === signatureMenu,"Signature keeps its rail menu parent open")
        let childDown=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:nestedWindow.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
        precondition(!signatureMenu.handleKey(childDown),"Keys in the child Signature picker must not advance the parent rail menu")
        popularButton.onHover?(false); signatureMenu.onHover?(false); wait(0.15); precondition(railMenu() === signatureMenu,"Nested Signature retains the parent when the pointer leaves it")
        nestedWindow.close(); signatureMenu.onHover?(false); wait(0.15); precondition(railMenu()==nil)
        popularButton.onHover?(true); popularButton.onHover?(false); wait(0.46); precondition(railMenu()==nil,"Leaving before400ms cancels opening")
        let securityButton=chrome.rail.buttons[4]
        securityButton.onHover?(true); securityButton.performClick(nil); wait(0.46)
        precondition(chrome.mode=="Security" && railMenu()==nil,"Clicking suppresses the pending hover menu until pointer exit")
        securityButton.onHover?(false); chrome.rail.buttons[3].onHover?(true); wait(0.46); precondition(railMenu()==nil,"Edit text has no rail hover menu")
        chrome.setNavigationExpanded(true); chrome.rail.frame.size.width=276; chrome.rail.layoutSubtreeIfNeeded()
        precondition(chrome.rail.buttons.allSatisfy{$0.isHidden} && chrome.rail.focusButton.isHidden && !chrome.rail.expandedPanel.isHidden)
        precondition(chrome.toolbar.expandedNavigation)
        chrome.rail.expandedPanel.uploadArea.button.performClick(nil)
        let upload=owner.childWindows?.compactMap{$0.contentViewController as? LuminUploadMenu}.first
        precondition(upload != nil && upload!.view.layer?.cornerRadius==10,"Upload has its own source Radix shell")
        for _ in 0..<6 {
            let down=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:upload!.view.window!.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
            precondition(upload!.handleKey(down))
        }
        precondition(upload!.focusedIndex==3,"Upload arrows stop at the last row, unlike the ordinary rail menu")
        let tab=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:upload!.view.window!.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:48)!
        precondition(upload!.handleKey(tab) && upload!.focusedIndex==3)
        let trigger=chrome.rail.expandedPanel.uploadArea.button
        trigger.performClick(nil)
        precondition(owner.childWindows?.isEmpty != false,"The open Upload trigger toggles its menu closed")
        trigger.performClick(nil)
        chrome.setNavigationExpanded(false)
        precondition(owner.childWindows?.isEmpty != false && chrome.rail.expandedPanel.isHidden && !chrome.rail.buttons[0].isHidden)
        chrome.rail.buttons[0].performClick(nil)
        chrome.toolbar.frame=NSRect(x:0,y:730,width:1512,height:48); owner.contentView?.addSubview(chrome.toolbar); chrome.toolbar.layoutSubtreeIfNeeded()
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
        chrome.toolbar.button("Highlight options")!.performClick(nil)
        var highlight=owner.childWindows!.first!.contentViewController as! LuminHighlightMenu
        let freehand=descendants(highlight.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Freehand highlight"}!
        var chosen:MarkupKind?; chrome.onMarkup={chosen=$0}; freehand.performClick(nil)
        precondition(chosen == .freehandHighlight && chrome.toolbar.button("Highlight")!.isSelected)
        chrome.toolbar.button("Highlight options")!.performClick(nil)
        highlight=owner.childWindows!.first!.contentViewController as! LuminHighlightMenu
        precondition(highlight.current == .freehandHighlight,"Highlight retains its selected kind after reopening")
        var propertiesAnchor:NSButton?
        chrome.onStyle={ kind,button in precondition(kind == .freehandHighlight); propertiesAnchor=button }
        let properties=descendants(highlight.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Freehand highlight options"}!
        properties.performClick(nil)
        precondition(propertiesAnchor === properties && properties.window === highlight.view.window && properties.window!.isVisible,"Properties retain the parent and use the actual32px menu trigger")
        chrome.toolbar.button("Signature")!.performClick(nil)
        let signature=owner.childWindows!.compactMap{$0.contentViewController as? LuminSignatureMenu}.first!
        (signature.controls["add"] as! NSButton).performClick(nil)
        let signatureOverlay=owner.contentView!.subviews.last!,signatureRoot=signatureOverlay.subviews.last!
        precondition(descendants(signatureRoot).compactMap{$0 as? LuminTextLabel}.contains{$0.text=="Create New Signature (0/100)"},"Real Add Signature opens the source creation UI")
        descendants(signatureRoot).compactMap{$0 as? NSButton}.first{$0.title=="Cancel"}!.performClick(nil)
        precondition(signatureOverlay.superview==nil && chrome.toolbar.button("Select")!.isSelected,"Cancel returns to the default desktop tool")
        chrome.toolbar.button("Signature")!.performClick(nil)
        let secondSignature=owner.childWindows!.compactMap{$0.contentViewController as? LuminSignatureMenu}.first!
        (secondSignature.controls["add"] as! NSButton).performClick(nil)
        let secondOverlay=owner.contentView!.subviews.last!
        let outside=NSEvent.mouseEvent(with:.leftMouseDown,location:secondOverlay.convert(NSPoint(x:1,y:1),to:nil),modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        secondOverlay.mouseDown(with:outside)
        precondition(secondOverlay.superview==nil && chrome.toolbar.button("Select")!.isSelected,"Backdrop dismissal shares the same default-tool cleanup")
        chrome.rail.buttons[1].performClick(nil); chrome.toolbar.layoutSubtreeIfNeeded()
        owner.contentView?.addSubview(chrome.typeToolbar); chrome.typeToolbar.frame=NSRect(x:80,y:650,width:1372,height:40)
        chrome.toolbar.button("Date")!.performClick(nil)
        precondition(!chrome.typeToolbar.isHidden && chrome.typeToolbar.state.family=="Helvetica","Date opens the shared text strip with its independent source Helvetica default, not a generic format picker")
        precondition(chrome.toolbar.button("Date")!.isSelected)
        chrome.toolbar.button("Stamp")!.performClick(nil)
        precondition(owner.childWindows!.last!.contentViewController is LuminPremiumGate && !chrome.typeToolbar.isHidden && chrome.toolbar.button("Date")!.isSelected,"Gated Stamp preserves Date and displays the actual source upgrade panel")
        let gateWindow=owner.childWindows!.last!
        let gateEscape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:gateWindow.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        precondition(!chrome.typeToolbar.handleEscape(gateEscape) && !chrome.typeToolbar.isHidden,"Date must not consume Escape belonging to the child gate window")
        chrome.toolbar.button("Stamp")!.performClick(nil); precondition(owner.childWindows?.isEmpty != false)
        chrome.toolbar.button("Date")!.performClick(nil)
        precondition(chrome.typeToolbar.isHidden && chrome.toolbar.button("Select")!.isSelected,"Clicking the active Date button returns to Select")
        chrome.rail.buttons[4].performClick(nil); chrome.toolbar.layoutSubtreeIfNeeded()
        chrome.toolbar.button("Password protection")!.performClick(nil)
        let passwordMenu=owner.childWindows!.last!.contentViewController as! LuminPasswordMenu
        precondition(passwordMenu.preferredContentSize==NSSize(width:200,height:80))
        let passwordDown=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:passwordMenu.view.window!.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
        precondition(passwordMenu.handleKey(passwordDown) && passwordMenu.rows[0].keyboardFocused)
        passwordMenu.rows[0].performClick(nil)
        let passwordOverlay=owner.contentView!.subviews.last!
        precondition(passwordMenu.view.superview === owner.contentView && passwordMenu.view.isAccessibilityHidden(),"The actual menu stays below the modal backdrop and outside its accessible hierarchy")
        precondition(owner.childWindows?.isEmpty != false,"The background menu must not float above an in-window modal")
        let backdropClick=NSEvent.mouseEvent(with:.leftMouseDown,location:passwordOverlay.convert(NSPoint(x:1,y:1),to:nil),modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        passwordOverlay.mouseDown(with:backdropClick)
        precondition(owner.childWindows!.last!.contentViewController === passwordMenu && passwordOverlay.superview==nil && !passwordMenu.view.isAccessibilityHidden(),"Dismissing the source modal restores its unchanged password menu")
        precondition(passwordMenu.focusedIndex==nil && passwordMenu.rows.allSatisfy{!$0.keyboardFocused},"The modal takes focus away from the menu row; its focus ring must not remain painted on restoration")
        chrome.toolbar.button("Password protection")!.performClick(nil)
        precondition(owner.childWindows?.isEmpty != false && chrome.toolbar.button("Select")!.isSelected)
        chrome.toolbar.button("Redaction")!.performClick(nil)
        let redactionOverlay=owner.contentView!.subviews.last!
        precondition(descendants(redactionOverlay).compactMap{$0 as? LuminTextLabel}.contains{$0.text=="Upgrade to access"},"The current source profile gates Redaction instead of exposing an invented options panel")
        let redactionBackdrop=NSEvent.mouseEvent(with:.leftMouseDown,location:redactionOverlay.convert(NSPoint(x:1,y:1),to:nil),modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        redactionOverlay.mouseDown(with:redactionBackdrop); precondition(redactionOverlay.superview==nil)
        chrome.rail.buttons[4].onHover?(false); chrome.rail.buttons[4].onHover?(true); wait(0.46)
        railMenu()!.rows.first{$0.entry.key=="configureAccess"}!.performClick(nil)
        precondition(owner.childWindows?.isEmpty != false,"Rail Set password opens its gated action directly, rather than the toolbar's two-row menu")
        owner.contentView!.subviews.last!.mouseDown(with:redactionBackdrop)
        chrome.rail.buttons[6].performClick(nil)
        let explorePassword=owner.childWindows!.last!.contentViewController as! LuminExploreMenu
        descendants(explorePassword.view).compactMap{$0 as? LuminExploreRow}.first{$0.command.key=="configureAccess"}!.performClick(nil)
        precondition(owner.childWindows?.isEmpty != false,"Explore Set password shares the direct modal action")
        owner.contentView!.subviews.last!.mouseDown(with:redactionBackdrop)
        chrome.rail.buttons[0].performClick(nil); chrome.toolbar.layoutSubtreeIfNeeded()
        chrome.toolbar.button("Type")!.performClick(nil)
        let textBold=descendants(chrome.typeToolbar).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Bold"}!
        textBold.performClick(nil)
        let textFamily=descendants(chrome.typeToolbar).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Font family"}!
        textFamily.performClick(nil)
        chrome.rail.buttons[3].performClick(nil)
        precondition(chrome.mode=="Popular" && !chrome.typeToolbar.isHidden && chrome.typeToolbar.state.bold,"Gated Edit text preserves the active mode, tool and Type style instead of selecting an inaccessible preview toolbar")
        let editOverlay=owner.contentView!.subviews.last!
        precondition(owner.childWindows?.isEmpty != false,"Formatting dropdowns close before an in-window access dialog")
        let rootEscape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        precondition(!chrome.typeToolbar.handleEscape(rootEscape),"The preserved Type strip must not consume the modal's Escape")
        editOverlay.mouseDown(with:redactionBackdrop)
        precondition(!chrome.typeToolbar.isHidden && chrome.typeToolbar.state.bold && chrome.mode=="Popular")
        chrome.rail.buttons[6].performClick(nil)
        let editSearch=owner.childWindows!.last!.contentViewController as! LuminExploreMenu
        editSearch.searchInput.stringValue="edit"
        precondition(editSearch.view.window!.makeFirstResponder(editSearch.searchInput))
        (editSearch.searchInput.currentEditor() as! NSTextView).setSelectedRange(NSRange(location:2,length:0))
        editSearch.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:editSearch.searchInput))
        let editResult=descendants(editSearch.view).compactMap{$0 as? LuminExploreRow}.first{$0.command.key=="editContent"}!
        precondition(editSearch.view.window!.makeFirstResponder(editResult))
        editResult.performClick(nil)
        let editSearchOverlay=owner.contentView!.subviews.last!
        precondition(editSearch.view.superview === owner.contentView && editSearch.view.isAccessibilityHidden(),"Explore remains dimmed below its Edit content modal")
        wait(0.35)
        precondition(editSearch.visibleCommands.contains{$0.key=="searchDocument" && $0.title.contains("edit")},"Staging a retained Explore panel must not cancel its pending search update")
        editSearchOverlay.mouseDown(with:redactionBackdrop)
        precondition(owner.childWindows!.last!.contentViewController === editSearch && chrome.mode=="Popular" && !chrome.typeToolbar.isHidden,"Closing Edit content restores the same Explore panel and editor state")
        precondition(editSearch.searchInput.stringValue=="edit" && editSearch.view.window!.firstResponder === editSearch.searchInput.currentEditor(),"The retained search text and focused field survive modal dismissal")
        precondition((editSearch.searchInput.currentEditor() as! NSTextView).selectedRange()==NSRange(location:2,length:0),"Restoring focus preserves the existing caret instead of selecting all query text")
        chrome.rail.buttons[1].performClick(nil); chrome.toolbar.layoutSubtreeIfNeeded()
        owner.contentView!.addSubview(chrome.formBuilderPanel); chrome.formBuilderPanel.frame=NSRect(x:1094,y:0,width:360,height:730)
        var formVisibility:[Bool]=[]; chrome.onFormVisibility={formVisibility.append($0)}
        chrome.toolbar.button("Prepare form")!.performClick(nil)
        let formMenu=owner.childWindows!.last!.contentViewController as! LuminFormBuilderMenu
        precondition(formMenu.preferredContentSize==NSSize(width:266,height:80))
        formMenu.rows[0].performClick(nil)
        precondition(chrome.formBuilderActive && !chrome.formBuilderPanel.isHidden && owner.childWindows?.isEmpty != false)
        precondition(chrome.toolbar.button("Prepare form")!.isSelected && !chrome.toolbar.button("Thumbnails")!.isEnabled && !chrome.toolbar.button("Read aloud")!.isEnabled)
        chrome.formBuilderPanel.tabs[1].performClick(nil)
        precondition(chrome.formBuilderPanel.selectedKind == .checkbox && !chrome.formBuilderPanel.apply.isEnabled && !chrome.toolbar.button("Select")!.isSelected)
        chrome.formBuilderPanel.cancel.performClick(nil)
        precondition(!chrome.formBuilderActive && chrome.formBuilderPanel.isHidden && chrome.toolbar.button("Thumbnails")!.isEnabled && formVisibility==[true,false])
        chrome.rail.buttons[6].performClick(nil)
        let formSearch=owner.childWindows!.last!.contentViewController as! LuminExploreMenu
        descendants(formSearch.view).compactMap{$0 as? LuminExploreRow}.first{$0.command.key=="customizeFields"}!.performClick(nil)
        precondition(chrome.mode=="Fill & Sign" && chrome.formBuilderActive && !chrome.formBuilderPanel.isHidden,"Explore Prepare form enters the actual side panel rather than the toolbar menu")
        chrome.rail.buttons[0].performClick(nil); precondition(!chrome.formBuilderActive && chrome.formBuilderPanel.isHidden,"Leaving the form mode restores canvas space")
        owner.close()

        let canvas=PageCanvas(),scroll=NSScrollView(frame:NSRect(x:0,y:0,width:1100,height:796))
        scroll.contentView=LuminCanvasClipView(); scroll.scrollerStyle = .overlay; scroll.documentView=canvas
        canvas.page=page; canvas.zoom=0.95; canvas.resizeToViewport()
        let expected=LuminCanvasLayout(pageSize:page.displaySize,zoom:0.95,viewport:scroll.contentSize)
        precondition(canvas.frame.size==expected.documentSize && canvas.pageRect==expected.imageFrame)
        let pdfRect=NSRect(x:72,y:100,width:120,height:20),display=page.displayRect(pdfRect)
        precondition(canvas.viewRect(pdfRect)==NSRect(x:expected.imageFrame.minX+display.minX*0.95,y:expected.imageFrame.minY+display.minY*0.95,width:display.width*0.95,height:display.height*0.95),"Source page spacing must preserve annotation coordinate transforms")
        print("Lumin viewer layout: stable organizer controls, real rail hover lifecycle/routing and actual canvas/annotation geometry passed")
    }
}
