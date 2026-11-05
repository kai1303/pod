import AppKit

private func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
private func close(_ a:CGFloat,_ b:CGFloat)->Bool { abs(a-b)<0.03 }
@main enum LuminSignatureTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/signature-layout-fixture.json"))) as! [String:Any]
        let menu=LuminSignatureMenu(); _ = menu.view
        let source=fixture["emptyMenu"] as! [String:Any],size=source["size"] as! [Double]
        precondition(close(menu.preferredContentSize.width,size[0]) && close(menu.preferredContentSize.height,size[1]),"Empty Signature: native \(menu.preferredContentSize), source \(size)")
        menu.view.frame=NSRect(origin:.zero,size:menu.preferredContentSize); menu.view.layoutSubtreeIfNeeded()
        let add=descendants(menu.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Add Signature"}!
        precondition(add.frame.size==NSSize(width:344,height:48),"Source Add Signature is inside12px scroll-area padding")
        func compare(_ a:NSRect,_ b:NSRect,_ label:String) {
            precondition(zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{close($0,$1)},"\(label): native \(a), DOM \(b)")
        }
        let states=fixture["states"] as! [String:[String:Any]]
        func sourceRect(_ state:String,_ predicate:([String:Any])->Bool)->NSRect {
            let node=(states[state]!["nodes"] as! [[String:Any]]).first(where:predicate)!,r=node["rect"] as! [Double]
            return NSRect(x:r[0],y:r[1],width:r[2],height:r[3])
        }
        let dialog=LuminSignatureDialog(); _ = dialog.view
        func check(_ state:String) {
            let size=states[state]!["size"] as! [Double]
            precondition(close(dialog.preferredContentSize.width,size[0]) && close(dialog.preferredContentSize.height,size[1]))
            dialog.view.frame=NSRect(origin:.zero,size:dialog.preferredContentSize); dialog.view.layoutSubtreeIfNeeded()
            compare(dialog.controls["board"]!.frame,sourceRect(state){($0["class"] as? String)?.contains("__canvasContainer")==true},"board")
            compare(dialog.repeatButton.frame,sourceRect(state){$0["tag"] as? String=="LABEL"},"repeat control")
            if dialog.tab == .type {
                compare(dialog.input.frame,sourceRect(state){$0["tag"] as? String=="INPUT" && $0["type"] as? String=="text"},"typed input")
                let counter=dialog.controls["counter"]!
                compare(counter.frame,sourceRect(state){($0["text"] as? String)?.hasSuffix("/50")==true},"counter")
            }
            let sourceTabs=(states[state]!["nodes"] as! [[String:Any]]).filter{$0["role"] as? String=="tab"}
            for (tab,node) in zip(LuminSignatureDialog.Tab.allCases,sourceTabs) {
                let b=dialog.controls["tab."+tab.title]!,r=node["rect"] as! [Double]
                compare(b.convert(b.bounds,to:dialog.view),NSRect(x:r[0],y:r[1],width:r[2],height:r[3]),"\(tab) tab")
            }
        }
        check("draw-handwriting"); precondition(!dialog.save.isEnabled && dialog.input.isHidden)
        precondition((dialog.controls["tabs"] as! LuminDialogPaper).radius==20 && (dialog.controls["penGroup"] as! LuminDialogPaper).radius==8,"Paint rounded source surfaces directly; a layer radius alone does not clip a rectangular drawRect background")
        compare(dialog.controls["Handwriting"]!.convert(dialog.controls["Handwriting"]!.bounds,to:dialog.view),sourceRect("draw-handwriting"){$0["tag"] as? String=="BUTTON" && $0["text"] as? String=="Handwriting"},"Handwriting")
        dialog.changeTab(.type); check("type-empty"); precondition(dialog.input.font?.pointSize==48 && dialog.input.font?.fontName=="DrSugiyama-Regular")
        dialog.chooseFont(1); dialog.setText("Sample"); check("type-synthetic-draft"); precondition(dialog.save.isEnabled && !dialog.hasError)
        dialog.setText(String(repeating:"A",count:51)); check("type-too-long"); precondition(!dialog.save.isEnabled && dialog.hasError && !dialog.controls["error"]!.isHidden)
        dialog.setText(String(repeating:"😀",count:26)); precondition(dialog.hasError && (dialog.controls["counter"] as! LuminTextLabel).text=="52/50","Source counter and validation use UTF16 length")
        dialog.setText("   "); precondition(dialog.save.isEnabled && !dialog.hasError,"Whitespace follows the shipped raw-nonempty/trimmed-limit rule")
        (dialog.controls["clear"] as! NSButton).performClick(nil); precondition(dialog.text.isEmpty && !dialog.save.isEnabled)
        let metrics=fixture["fontMetrics"] as! [[String:Any]]
        for (i,metric) in metrics.enumerated() {
            dialog.chooseFont(i); let r=metric["rect"] as! [Double]
            compare(dialog.input.frame,NSRect(x:r[0],y:r[1],width:r[2],height:r[3]),"\(LuminSignatureDialog.fontNames[i]) metrics")
            precondition(dialog.input.font!.fontName==LuminSignatureDialog.families[i]+"-Regular" && dialog.input.font!.pointSize==(i<3 ? 48:24),"Use the original font file, not a system cursive substitute")
        }
        dialog.changeTab(.image); check("image-empty"); precondition(!dialog.save.isEnabled && dialog.input.isHidden)
        dialog.setImage(NSImage(size:NSSize(width:100,height:30))); precondition(dialog.save.isEnabled && !dialog.controls["changeImage"]!.isHidden)
        let changeImage=dialog.controls["changeImage"] as! LuminShareButton
        precondition(changeImage.style == .filled && changeImage.glyph==nil && changeImage.size==14 && changeImage.weight==500)
        precondition(close(changeImage.frame.maxX,856) && changeImage.frame.height==32,"Source image action is a plain right-aligned medium filled button")
        dialog.changeTab(.type); precondition(dialog.fontIndex==0 && dialog.image==nil && dialog.text.isEmpty)
        var saved:LuminSignaturePreview?; dialog.onSave={saved=$0}; dialog.setText("Sample"); dialog.save.performClick(nil); precondition(saved?.text=="Sample")
        let fontMenu=LuminSignatureFontMenu(selected:0); _ = fontMenu.view
        precondition(fontMenu.preferredContentSize==NSSize(width:196.7265625,height:208) && fontMenu.rows.count==6)
        for (i,row) in fontMenu.rows.enumerated() { precondition(row.font?.fontName==LuminSignatureDialog.families[i]+"-Regular"); compare(row.frame,NSRect(x:8,y:8+CGFloat(i)*32,width:180.7265625,height:32),"font row") }
        for showsWidth in [true,false] {
            let colors=LuminSignatureColorMenu(color:.black,width:3,showsWidth:showsWidth); _ = colors.view; colors.view.frame=NSRect(origin:.zero,size:colors.preferredContentSize); colors.view.layoutSubtreeIfNeeded()
            precondition(colors.preferredContentSize==NSSize(width:270,height:showsWidth ? 88:48))
            let picker=descendants(colors.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Custom color"}!
            compare(picker.convert(picker.bounds,to:colors.view),NSRect(x:230,y:showsWidth ? 48:8,width:32,height:32),"Signature picker target")
        }
        for key in ["pdf-icon-md_pen","pdf-icon-md_image","pdf-icon-md_font_size","pdf-icon-md_tick"] { precondition(LuminAssets.icon(key) != nil) }
        let repeated=LuminSignatureRepeatButton(); repeated.performClick(nil); precondition(repeated.isOn)
        for (appearance,board,inverse) in [(NSAppearance.Name.aqua,[249,249,250],[255,255,255]),(.darkAqua,[193,199,206],[25,28,29])] {
            NSAppearance(named:appearance)!.performAsCurrentDrawingAppearance {
                func rgb(_ c:NSColor)->[Int] { let c=c.usingColorSpace(.sRGB)!; return[c.redComponent,c.greenComponent,c.blueComponent].map{Int(($0*255).rounded())} }
                precondition(rgb(LuminSignatureStyle.board)==board && rgb(LuminSignatureStyle.inverseOnSurface)==inverse,"Separate legacy Signature and Kiwi checkbox roles")
            }
        }
        let full=LuminSignatureDialog(count:100); _ = full.view; full.changeTab(.type); full.setText("Sample"); precondition(!full.save.isEnabled)
        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:1200,height:800),styleMask:[.titled],backing:.buffered,defer:false); owner.isReleasedWhenClosed=false
        let background=NSView(),backgroundButton=NSButton(title:"Background action",target:nil,action:nil); background.addSubview(backgroundButton); owner.contentView?.addSubview(background)
        let originalChildrenCount=owner.accessibilityChildren()?.count
        let modal=LuminModal(); modal.show(dialog,in:owner.contentView!,initialResponder:nil)
        precondition(background.isAccessibilityHidden() && backgroundButton.isAccessibilityHidden(),"Modal accessibility must hide descendants of non-accessible background containers as well")
        let overlay=owner.contentView!.subviews.last!
        func mouse(_ point:NSPoint)->NSEvent { NSEvent.mouseEvent(with:.leftMouseDown,location:overlay.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)! }
        overlay.mouseDown(with:mouse(NSPoint(x:dialog.view.frame.minX+10,y:dialog.view.frame.minY+10)))
        precondition(modal.isShown,"An unhandled blank/title click inside the paper must not bubble into backdrop dismissal")
        overlay.mouseDown(with:mouse(NSPoint(x:1,y:1))); precondition(!modal.isShown,"Actual backdrop clicks close the modal")
        precondition(!background.isAccessibilityHidden() && !backgroundButton.isAccessibilityHidden(),"Restore prior descendant accessibility flags on close")
        precondition(owner.accessibilityChildren()?.count==originalChildrenCount && !(owner.accessibilityChildren()?.isEmpty ?? true),"Closing must resume AppKit's automatic window hierarchy rather than install an empty children override")
        owner.close()
        print("Lumin Signature: source menu/dialog/tab/control frames, six original fonts, Type validation/draft states and nested palette geometry passed")
    }
}
