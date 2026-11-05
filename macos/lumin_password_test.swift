import AppKit

@main enum LuminPasswordTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/password-layout-fixture.json"))) as! [String:Any]
        func rect(_ r:NSRect,_ values:[Double]) { precondition(zip([r.minX,r.minY,r.width,r.height],values).allSatisfy{abs($0-$1)<0.05},"Source frame mismatch: \(r) versus \(values)") }
        let menu=LuminPasswordMenu(); _=menu.view
        precondition(menu.preferredContentSize==NSSize(width:200,height:80))
        let rows=fixture["row_frames"] as! [[Double]]
        for (row,frame) in zip(menu.rows,rows) { rect(row.frame,frame) }
        precondition(menu.rows[0].item.glyph=="pdf-icon-set-password" && menu.rows[1].item.glyph=="pdf-icon-remove-password")
        precondition(menu.rows[0].isEnabled && !menu.rows[1].isEnabled)
        rect(menu.rows[0].iconRect,fixture["set_icon"] as! [Double]); rect(menu.rows[0].textRect,fixture["set_text"] as! [Double]); rect(menu.rows[0].premiumRect!,fixture["set_premium"] as! [Double])
        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:1512,height:834),styleMask:[.titled],backing:.buffered,defer:false); owner.isReleasedWhenClosed=false
        owner.contentView!.addSubview(menu.view)
        let down=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:125)!
        precondition(menu.handleKey(down) && menu.focusedIndex==0)
        precondition(menu.handleKey(down) && menu.focusedIndex==0,"Keyboard skips disabled Remove password")
        var pressed=false; menu.onSet={pressed=true}
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:owner.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        precondition(menu.handleKey(enter) && pressed)
        let gate=LuminPremiumGate(kind:.modal); _=gate.view
        precondition(gate.preferredContentSize==NSSize(width:480,height:213))
        for (name,frame) in fixture["gate_controls"] as! [String:[Double]] { rect(gate.controls[name]!.frame,frame) }
        let heading=gate.controls["heading"] as! LuminTextLabel
        precondition(heading.font.pointSize==20 && heading.lineHeight==28 && heading.font.fontName.contains("Agrandir"))
        let modal=LuminModal(); modal.show(gate,in:owner.contentView!,initialResponder:nil)
        precondition(menu.view.isAccessibilityHidden() && gate.view.frame.midX==756 && gate.view.frame.midY==417)
        modal.close(); precondition(!menu.view.isAccessibilityHidden())
        let editFixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/edit-text-layout-fixture.json"))) as! [String:Any]
        let editGate=LuminPremiumGate(kind:.editText); _=editGate.view
        precondition(editGate.preferredContentSize==NSSize(width:480,height:229))
        for (name,frame) in editFixture["controls"] as! [String:[Double]] { rect(editGate.controls[name]!.frame,frame) }
        precondition((editGate.controls["heading"] as! LuminTextLabel).text==editFixture["title"] as! String)
        precondition((editGate.controls["message"] as! LuminTextLabel).text==editFixture["message"] as! String)
        precondition((editGate.controls["artwork"] as! NSImageView).image != nil && !(editGate.controls["artwork"] as! NSImageView).image!.isTemplate,"Original magic artwork retains its colors")
        owner.close()
        print("Lumin password:200x80 source menu, original glyphs/premium badge, disabled keyboard skipping and480x213 modal layout passed")
    }
}
