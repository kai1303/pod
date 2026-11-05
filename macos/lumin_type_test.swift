import AppKit
import CoreText

private func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
private func button(_ view:NSView,_ label:String)->NSButton { descendants(view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()==label} ?? { fatalError("Missing button \(label)") }() }
private func field(_ view:NSView,_ label:String)->NSTextField { descendants(view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()==label} ?? { fatalError("Missing field \(label)") }() }
private func send(_ input:NSTextField,_ text:String) { input.stringValue=text; _=input.sendAction(input.action,to:input.target) }
private func rgb(_ color:NSColor)->[Int] { let c=color.usingColorSpace(.sRGB)!; return [c.redComponent,c.greenComponent,c.blueComponent].map{Int(($0*255).rounded())} }

@main
enum LuminTypeTests {
    static func main() {
        _ = NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:100,y:100,width:1000,height:700),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let bar=LuminTypeToolbar(); bar.frame=NSRect(x:0,y:600,width:1000,height:40); window.contentView?.addSubview(bar); bar.open(); bar.layoutSubtreeIfNeeded()
        precondition(bar.fittingSize.height==40)
        let family=button(bar,"Font family"),size=button(bar,"Font size")
        precondition(family.frame.width==108 && size.frame.width==78)
        precondition(family.frame.minX==9 && size.frame.minX==126)
        button(bar,"Bold").performClick(nil); button(bar,"Italic").performClick(nil)
        precondition(bar.state.bold && bar.state.italic && !bar.state.underline)
        button(bar,"Bold").performClick(nil); precondition(!bar.state.bold && bar.state.italic)
        precondition(LuminTypeToolbar.families.count==18)
        for choice in LuminTypeToolbar.families {
            let font=LuminAssets.previewFont(choice.value,size:14,weight:500)
            let url=CTFontCopyAttribute(font,kCTFontURLAttribute) as? URL
            precondition(url?.path.contains("/Lumin/")==true,"Font preview must resolve the original bundled file")
        }
        family.performClick(nil)
        let fontWindow=window.childWindows!.last!
        precondition(abs(fontWindow.frame.width-211.5234375)<0.5 && fontWindow.frame.height==316,"The native window may snap the source fractional width to a screen pixel")
        let fontRows=descendants(fontWindow.contentView!).compactMap{$0 as? PodButton}
        precondition(fontRows.count==18 && fontRows.first?.title=="Arimo" && fontRows.last?.title=="Vollkorn")
        let fontMenu=fontWindow.contentViewController as! LuminTypeChoiceMenu
        let down=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:fontWindow.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
        for _ in 0..<18 { precondition(fontMenu.handleKey(down)) }
        let fontScroll=descendants(fontWindow.contentView!).compactMap{$0 as? NSScrollView}.first!
        precondition(fontScroll.contentView.bounds.minY>0,"Keyboard navigation must reveal the last font in the 300px viewport")
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:fontWindow.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        precondition(fontMenu.handleKey(enter)); precondition(bar.state.family=="Vollkorn")
        size.performClick(nil)
        let sizeWindow=window.childWindows!.last!
        let sizeRows=descendants(sizeWindow.contentView!).compactMap{$0 as? PodButton}
        precondition(sizeRows.count==41 && sizeRows.first?.title=="5pt" && sizeRows.last?.title=="45pt")
        sizeRows.last!.performClick(nil); precondition(bar.state.size==45)
        button(bar,"Text frame").performClick(nil)
        let frameMenu=window.childWindows!.last!
        button(frameMenu.contentView!,"Custom color").performClick(nil)
        let customWindow=frameMenu.childWindows!.last!
        send(field(customWindow.contentView!,"G"),"128")
        button(customWindow.contentView!,"Confirm").performClick(nil)
        precondition(bar.state.fill.map(rgb)==[0,128,0])
        button(bar,"Text frame").performClick(nil); button(bar,"Text frame").performClick(nil)
        let reopened=window.childWindows!.last!
        let selectedCustom=button(reopened.contentView!,"#008000") as! SwatchButton
        precondition(selectedCustom.selected,"Reopened palettes must retain and select the current custom color")
        bar.dismiss()

        let picker=LuminColorPicker(color:PodTheme.color(0x123456))
        let view=picker.view; view.frame=NSRect(x:0,y:0,width:205,height:297.7421875); view.layoutSubtreeIfNeeded()
        precondition(picker.preferredContentSize==NSSize(width:205,height:297.7421875))
        precondition(field(view,"HEX").stringValue=="#123456" && field(view,"HEX").frame.width==157,"Opaque colors start with the source Hex field")
        send(field(view,"HEX"),"#abc"); precondition(field(view,"HEX").stringValue=="#AABBCC")
        send(field(view,"HEX"),"#12#456"); precondition(field(view,"HEX").stringValue=="#AABBCC")
        send(field(view,"HEX"),"#123456")
        button(view,"Switch color format").performClick(nil)
        precondition(field(view,"R").stringValue=="18" && field(view,"G").stringValue=="52" && field(view,"B").stringValue=="86")
        precondition(field(view,"R").frame.height==21)
        let confirm=button(view,"Confirm"),cancel=button(view,"Cancel")
        precondition(confirm.frame.size==NSSize(width:189,height:32) && cancel.frame.minY-confirm.frame.maxY==8)
        window.contentView?.addSubview(view); view.appearance=NSAppearance(named:.darkAqua)
        view.displayIfNeeded()
        let pixels=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:pixels)
        try! pixels.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"test-out/lumin-picker-rgb.png"))
        let scale=CGFloat(pixels.pixelsWide)/view.bounds.width
        let sample=pixels.colorAt(x:Int(100*scale),y:Int(210*scale))!
        let background=[sample.redComponent,sample.greenComponent,sample.blueComponent].map{Int(($0*255).rounded())}
        precondition(zip(background,[40,43,44]).allSatisfy{abs($0-$1)<=2},"Hue painting must stay inside its strip: \(background)")
        var committed:NSColor?; var cancelled=false
        picker.onConfirm={committed=$0}; picker.onCancel={cancelled=true}
        send(field(view,"R"),"200"); precondition(committed==nil)
        button(view,"Switch color format").performClick(nil)
        precondition(descendants(view).compactMap{$0 as? NSTextField}.contains{$0.accessibilityLabel()=="H"})
        button(view,"Switch color format").performClick(nil)
        precondition(field(view,"HEX").stringValue=="#C83456")
        button(view,"Switch color format").performClick(nil)
        precondition(field(view,"R").stringValue=="200","RGB/HSL switching must preserve the draft")
        send(field(view,"G"),"bad"); precondition(field(view,"G").stringValue=="52","Reject invalid channel values")
        cancel.performClick(nil); precondition(cancelled && committed==nil,"Cancel must not apply the draft")
        confirm.performClick(nil); precondition(committed.map(rgb)==[200,52,86],"Confirm applies the exact RGB draft")
        window.close()
        print("Lumin Type/picker: source geometry, font assets, 18/41 menu options, scrolling, retained custom color, Hex/RGB/HSL and draft/confirm/cancel passed")
    }
}
