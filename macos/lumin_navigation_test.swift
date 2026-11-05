import AppKit

private func rect(_ a:[Double])->NSRect { NSRect(x:a[0],y:a[1],width:a[2],height:a[3]) }
private func near(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.03} }
private func rgb(_ c:NSColor)->[Int] { let c=c.usingColorSpace(.sRGB)!; return[c.redComponent,c.greenComponent,c.blueComponent].map{Int(($0*255).rounded())} }
@main enum LuminNavigationTests {
    static func main() {
        _ = NSApplication.shared
        let f=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/expanded-navigation-layout-fixture.json"))) as! [String:Any]
        let rail=rect(f["rail"] as! [Double]),nav=LuminExpandedNavigation(frame:NSRect(origin:.zero,size:rail.size))
        nav.documents=[LuminNavigationDocument(id:"current",title:"Sample.pdf",thumbnail:nil,selected:true)]; nav.layoutSubtreeIfNeeded()
        let panel=f["panel"] as! [String:Any]
        precondition(near(nav.uploadArea.frame,rect(panel["rect"] as! [Double]).offsetBy(dx:-rail.minX,dy:-rail.minY)))
        let cloud=panel["cloud"] as! [String:Any],caption=panel["caption"] as! [String:Any],button=panel["button"] as! [String:Any]
        precondition(near(nav.uploadArea.cloudRect.offsetBy(dx:nav.uploadArea.frame.minX,dy:nav.uploadArea.frame.minY),rect(cloud["rect"] as! [Double]).offsetBy(dx:-rail.minX,dy:-rail.minY)))
        precondition(near(nav.uploadArea.captionRect.offsetBy(dx:nav.uploadArea.frame.minX,dy:nav.uploadArea.frame.minY),rect(caption["rect"] as! [Double]).offsetBy(dx:-rail.minX,dy:-rail.minY)))
        precondition(near(nav.uploadArea.button.frame.offsetBy(dx:nav.uploadArea.frame.minX,dy:nav.uploadArea.frame.minY),rect(button["rect"] as! [Double]).offsetBy(dx:-rail.minX,dy:-rail.minY)))
        let enter=NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
        nav.uploadArea.mouseEntered(with:enter); precondition(abs(nav.uploadArea.hoverOverlayColor.alphaComponent-0.08)<0.0001)
        nav.uploadArea.mouseExited(with:enter); precondition(nav.uploadArea.hoverOverlayColor.alphaComponent==0)
        let history=f["history"] as! [String:Any],row=nav.rows[0],sourceRow=history["row"] as! [String:Any]
        precondition(near(row.convert(row.bounds,to:nav),rect(sourceRow["rect"] as! [Double]).offsetBy(dx:0,dy:-56)))
        precondition(row.thumbnailRect==NSRect(x:8,y:8,width:24,height:24))
        precondition(row.textRect==NSRect(x:40,y:10,width:156,height:20))
        precondition(row.newTabButton.frame==NSRect(x:208,y:4,width:32,height:32))
        precondition(row.newTabButton.alphaValue==0)
        NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
            precondition(rgb(row.background)==[8,113,145] && rgb(row.foreground)==[225,226,228])
            precondition(rgb(nav.uploadArea.borderColor)==[140,145,148] && rgb(nav.uploadArea.button.foreground)==[178,202,214])
        }
        for (appearance,popover,foreground,accent,muted) in [(NSAppearance.Name.aqua,[255,255,255],[10,10,10],[245,245,245],[115,115,115]),(.darkAqua,[23,23,23],[250,250,250],[64,64,64],[163,163,163])] {
            NSAppearance(named:appearance)!.performAsCurrentDrawingAppearance {
                precondition(rgb(LuminNavigationStyle.popover)==popover && rgb(LuminNavigationStyle.foreground)==foreground)
                precondition(rgb(LuminNavigationStyle.accent)==accent && rgb(LuminNavigationStyle.muted)==muted)
            }
        }
        let menu=LuminUploadMenu(); _ = menu.view
        precondition(menu.view.layer?.borderWidth==1 && abs((menu.view.layer?.borderColor?.alpha ?? 0)-0.1)<0.0001,"Source Radix surface has a foreground/10 edge")
        menu.rows[0].focused=true
        NSAppearance(named:.aqua)!.performAsCurrentDrawingAppearance { precondition(rgb(menu.rows[0].foreground)==[23,23,23]) }
        let sourceMenu=f["uploadMenu"] as! [String:Any],menuRect=rect(sourceMenu["rect"] as! [Double])
        precondition(menu.preferredContentSize==menuRect.size)
        for (row,source) in zip(menu.rows,sourceMenu["rows"] as! [[String:Any]]) {
            precondition(row.title==source["title"] as! String && row.sourceImage != nil)
            precondition(near(row.frame,rect(source["rect"] as! [Double]).offsetBy(dx:-menuRect.minX,dy:-menuRect.minY)))
            let icon=(source["icons"] as! [[String:Any]])[0]
            precondition(near(row.iconRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),rect(icon["rect"] as! [Double]).offsetBy(dx:-menuRect.minX,dy:-menuRect.minY)))
        }
        let header=LuminDocumentHeader(); header.frame=NSRect(x:0,y:0,width:1512,height:56); header.navigationExpanded=true; header.layoutSubtreeIfNeeded()
        precondition(header.navigation.isHidden && !header.navigationBack.isHidden && !header.navigationClose.isHidden)
        let buttons=f["headerButtons"] as! [[String:Any]]
        precondition(near(header.navigationBack.frame,rect(buttons[0]["rect"] as! [Double])))
        precondition(near(header.navigationClose.frame,rect(buttons[1]["rect"] as! [Double])))
        precondition(header.titleBox.frame.minX==288)
        let layout=LuminViewerLayout(viewport:NSSize(width:1512,height:834),focus:false,navigationExpanded:true)
        precondition(layout.toolbar==rect(f["toolbar"] as! [Double]) && layout.canvas==rect(f["canvas"] as! [Double]))
        let empty=LuminExpandedNavigation(frame:NSRect(x:0,y:0,width:276,height:778)); empty.layoutSubtreeIfNeeded()
        let emptyTitle=empty.subviews.compactMap{$0 as? NSTextField}.first{$0.stringValue=="Recent documents"}!
        precondition(emptyTitle.frame==NSRect(x:25,y:119,width:226,height:16),"Empty-state source border/padding/title box model")
        for key in LuminNavigationAssets.keys { precondition(LuminNavigationAssets.image(key) != nil) }
        print("Lumin expanded navigation: source header/rail/document/upload frames, original SVGs and distinct Radix light/dark roles passed")
    }
}
