import AppKit
import CoreText

private func matchesCSS(_ color:NSColor,_ css:String,opacity:CGFloat=1)->Bool {
    let v=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard v.count>=3,let c=color.usingColorSpace(.sRGB) else { return false }
    let alpha=(v.count==4 ? v[3]:1)*opacity
    return abs(c.alphaComponent-alpha)<0.001 && (alpha==0 || zip([c.redComponent*255,c.greenComponent*255,c.blueComponent*255],v.prefix(3)).allSatisfy{abs($0-$1)<0.1})
}
private func rect(_ v:[Double])->NSRect { NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
private func close(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.025} }
@main enum LuminShareTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/share-dialog-layout-fixture.json"))) as! [String:Any]
        let dialog=LuminShareDialog(filename:"Building Event-Driven Microservices.pdf",link:"Local document")
        _ = dialog.view
        precondition((dialog.controls["invite"] as! LuminShareInput).input.stringValue.isEmpty,"Invite input starts empty, with the source placeholder")
        for state in fixture["views"] as! [[String:Any]] {
            dialog.switchTo(LuminShareDialog.State(rawValue:state["name"] as! String)!)
            let expected=rect(state["rect"] as! [Double]); precondition(dialog.view.frame.size==expected.size)
            for (key,data) in state["controls"] as! [String:[String:Any]] {
                guard let view=dialog.controls[key] else { preconditionFailure("Missing source control \(state["name"]!)/\(key)") }
                precondition(close(view.frame,rect(data["rect"] as! [Double])),"\(state["name"]!)/\(key): \(view.frame); source \(data["rect"]!)")
                NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                    let styles=data["styles"] as! [String:String]
                    if let label=view as? LuminTextLabel {
                        precondition(matchesCSS(label.color,styles["color"]!),"Source label role \(key)")
                        precondition(label.font.pointSize==CGFloat(Double(styles["fontSize"]!.replacingOccurrences(of:"px",with:""))!))
                    } else if let button=view as? LuminShareButton {
                        precondition(matchesCSS(button.cssForeground,styles["color"]!,opacity:button.isEnabled ? 1:0.38),"Source button role \(key)")
                        precondition(matchesCSS(button.cssBackground,styles["backgroundColor"]!),"Source button surface \(key)")
                    } else if let surface=view as? PodSurfaceView { precondition(matchesCSS(surface.surface,data["paintColor"] as? String ?? styles["backgroundColor"]!),"Source painted surface \(key)") }
                }
            }
        }
        let font=LuminAssets.headline(20)
        precondition(font.fontName=="PPAgrandir-Medium")
        let fontURL=CTFontCopyAttribute(font as CTFont,kCTFontURLAttribute) as! URL
        precondition(fontURL.lastPathComponent=="PPAgrandir-Medium.otf")
        dialog.switchTo(.link); dialog.setScope(.anyone)
        precondition(dialog.controls["publicRole"] != nil && dialog.view.frame.height==314)
        dialog.setPublicRole("Editor"); precondition(dialog.linkDescription.contains("edit"))
        dialog.cancelDraft(); dialog.switchTo(.link); precondition(dialog.scope == .restricted)
        dialog.setScope(.anyone); dialog.commitLinkDraft(); precondition(dialog.state == .main && dialog.linkDescription.contains("view"))
        dialog.switchTo(.settings); precondition((dialog.controls["save"] as! NSButton).isEnabled==false)
        dialog.toggleBulk(); precondition((dialog.controls["save"] as! NSButton).isEnabled && (dialog.controls["permission"] as! NSButton).isEnabled)
        for data in fixture["menus"] as! [[String:Any]] {
            let kind=LuminShareMenu.Kind(rawValue:data["name"] as! String)!,menu=LuminShareMenu(kind:kind,selection:0); _ = menu.view
            let sourceRows=data["rows"] as! [[String:Any]]
            precondition(menu.rows.count==sourceRows.count)
            for (row,expected) in zip(menu.rows,sourceRows) {
                let offset=kind == .export ? NSPoint(x:8,y:8):.zero
                precondition(close(row.frame,rect(expected["rect"] as! [Double]).offsetBy(dx:offset.x,dy:offset.y)))
                precondition(close(row.textRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),rect(expected["labelRect"] as! [Double]).offsetBy(dx:offset.x,dy:offset.y)),"\(kind)/\(row.title): label \(row.textRect)")
                precondition(close(row.iconRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),rect(expected["iconRect"] as! [Double]).offsetBy(dx:offset.x,dy:offset.y)))
                precondition(row.sourceImage != nil && row.title==expected["title"] as! String)
            }
        }
        let roleAnchor=NSRect(x:957.59375,y:364,width:94.40625,height:32)
        let roleFrame=LuminPopper.placement(anchor:roleAnchor,size:NSSize(width:180,height:136),viewport:NSRect(x:0,y:0,width:1512,height:834),alignment:.end,gap:8,edge:.minY)
        precondition(close(roleFrame,NSRect(x:872,y:404,width:180,height:136)),"Share public-role menu opens above its trigger")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1240,height:900),styleMask:[.titled],backing:.buffered,defer:false)
        let root=NSView(frame:NSRect(x:0,y:0,width:1240,height:900)),background=NSButton(title:"Background",target:nil,action:nil)
        root.addSubview(background); window.contentView=root
        window.makeFirstResponder(background)
        let modal=LuminModal(); modal.show(dialog,in:root,initialResponder:nil)
        precondition(background.isAccessibilityHidden() && modal.isShown)
        precondition(close(dialog.view.frame,LuminModal.placement(size:dialog.preferredContentSize,viewport:root.bounds)))
        modal.close(); precondition(!background.isAccessibilityHidden() && !modal.isShown && dialog.view.superview==nil && window.firstResponder === background)
        print("Lumin Share: source dialog/menu frames, original headline/icons, local drafts and modal lifecycle passed")
    }
}
