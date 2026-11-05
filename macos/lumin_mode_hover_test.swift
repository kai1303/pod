import AppKit

private func box(_ v:[Double])->NSRect { NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
private func near(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.15} }
private func rgb(_ color:NSColor)->[CGFloat] { let c=color.usingColorSpace(.sRGB)!;return[c.redComponent*255,c.greenComponent*255,c.blueComponent*255] }
@main enum LuminModeHoverTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/mode-hover-layout-fixture.json"))) as! [String:Any]
        let modes=["popular":"Popular","fill-sign":"Fill & Sign","markup":"Mark up","security":"Security","organize":"Organize"]
        let anchors=fixture["anchors"] as! [String:[Double]]
        for variant in fixture["variants"] as! [[String:Any]] {
            let key=variant["name"] as! String,mode=modes[key]!,source=variant["menu"] as! [String:Any],frame=box(source["rect"] as! [Double])
            let menu=LuminModeMenu(mode:mode); _ = menu.view
            precondition(menu.preferredContentSize==frame.size)
            let rows=variant["rows"] as! [[String:Any]]
            precondition(menu.rows.count==rows.count)
            for (row,data) in zip(menu.rows,rows) {
                precondition(row.entry.title==data["text"] as! String)
                precondition(row.isEnabled == !(data["disabled"] as! Bool))
                precondition(row.entry.glyph==(data["glyph"] as! String).split(separator:" ").first(where:{$0.hasPrefix("pdf-icon-") || $0.hasPrefix("kiwi-icon-")}).map(String.init))
                precondition(row.sourceImage != nil)
                precondition(row.iconPaintRect.size==NSSize(width:24,height:24),"A shrunk flex box must not scale the24px source glyph")
                precondition(near(row.frame,box(data["rect"] as! [Double])))
                precondition(near(row.iconRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),box(data["icon"] as! [Double])))
                if let label=data["label"] as? [Double] { precondition(near(row.labelRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),box(label)),"\(mode):\(row.title) label geometry") }
                let badges=data["images"] as! [[String:Any]]
                if let badge=badges.first { precondition(near(row.premiumRect!.offsetBy(dx:row.frame.minX,dy:row.frame.minY),box(badge["rect"] as! [Double]))) }
                precondition((row.premiumRect != nil) == !badges.isEmpty)
                NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                    precondition(rgb(row.labelColor).map{Int($0.rounded())}==[225,226,228])
                    precondition(rgb(row.iconColor).map{Int($0.rounded())} == (row.entry.legacyHighlight ? [227,229,232]:[225,226,228]))
                }
                precondition(row.contentOpacity == (row.isEnabled ? 1:0.38))
            }
            if let footer=variant["footer"] as? [String:Any] {
                precondition(near(menu.signFooter!.frame,box(footer["rect"] as! [Double])))
                let button=footer["button"] as! [String:Any]
                precondition(near(menu.signFooter!.button.frame.offsetBy(dx:menu.signFooter!.frame.minX,dy:menu.signFooter!.frame.minY),box(button["rect"] as! [Double])))
            } else { precondition(menu.signFooter==nil) }
            let anchor=box(anchors[key]!),viewport=NSRect(x:0,y:0,width:1512,height:834)
            let nativeAnchor=NSRect(x:anchor.minX,y:834-anchor.maxY,width:anchor.width,height:anchor.height)
            let placement=LuminPopper.placement(anchor:nativeAnchor,size:frame.size,viewport:viewport,gap:5,edge:.maxX,inset:5,crossAxisOffset:-24,sideAlignment:.start)
            precondition(near(placement,NSRect(x:frame.minX,y:834-frame.maxY,width:frame.width,height:frame.height)))
        }
        precondition(LuminModeMenu.entries(for:"Edit text").isEmpty && LuminModeMenu.entries(for:"Explore").isEmpty)
        let form=LuminModeMenu(mode:"Fill & Sign"); _ = form.view
        precondition(form.headingFrame==NSRect(x:8,y:296,width:264,height:40))
        precondition(form.separatorFrames==[NSRect(x:0,y:296,width:280,height:1),NSRect(x:0,y:424,width:280,height:1)])
        print("Lumin mode hover: five source menu structures, original glyphs, mixed rows, premium/disabled roles, form/sign sections and right-start placement passed")
    }
}
