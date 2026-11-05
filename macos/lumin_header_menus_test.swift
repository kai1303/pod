import AppKit

private func matchesCSS(_ color:NSColor,_ css:String)->Bool {
    let values=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard values.count>=3,let rgb=color.usingColorSpace(.sRGB) else { return false }
    return zip([rgb.redComponent*255,rgb.greenComponent*255,rgb.blueComponent*255],values.prefix(3)).allSatisfy{abs($0-$1)<0.1} && abs(rgb.alphaComponent-(values.count==4 ? values[3]:1))<0.001
}
private func rectangle(_ v:[Double])->NSRect { NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
private func close(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.02} }
private func key(_ code:UInt16)->NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }

@main enum LuminHeaderMenusTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/header-menus-layout-fixture.json"))) as! [String:Any]
        for variant in fixture["variants"] as! [[String:Any]] {
            let kind=LuminHeaderMenu.Kind(rawValue:variant["kind"] as! String)!, menu=LuminHeaderMenu(kind:kind,darkAppearance:true,darkPage:false,starred:false)
            _ = menu.view
            let sourceRect=rectangle(variant["sourceRect"] as! [Double])
            precondition(close(menu.view.bounds,NSRect(origin:.zero,size:sourceRect.size)))
            let viewport=variant["viewport"] as! [Double], trigger=rectangle(variant["triggerRect"] as! [Double])
            let anchor=NSRect(x:trigger.minX,y:viewport[1]-trigger.maxY,width:trigger.width,height:trigger.height)
            var placed=LuminPopper.placement(anchor:anchor,size:sourceRect.size,viewport:NSRect(x:0,y:0,width:viewport[0],height:viewport[1]),alignment:menu.alignment,gap:menu.gap)
            if kind == .help { placed=LuminPopper.pixelAligned(placed,scale:2) }
            precondition(close(placed,NSRect(x:sourceRect.minX,y:viewport[1]-sourceRect.maxY,width:sourceRect.width,height:sourceRect.height)),"Source placement for \(kind)")
            let rows=variant["rows"] as! [[String:Any]]
            precondition(rows.count==menu.rows.count)
            for (row,source) in zip(menu.rows,rows) {
                precondition(row.title==source["title"] as! String)
                NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                    let styles=source["styles"] as! [String:String]
                    precondition(matchesCSS(row.cssForeground,styles["color"]!) && matchesCSS(row.cssBackground,styles["backgroundColor"]!))
                }
                precondition(close(row.frame,rectangle(source["rect"] as! [Double])),"\(kind): \(row.title) frame")
                precondition(close(row.textRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),rectangle(source["labelRect"] as! [Double])),"\(kind): \(row.title) text \(row.textRect)")
                if let glyph=source["glyph"] as? String { precondition(row.item.glyph==glyph && row.sourceImage != nil) }
                if let bitmap=source["bitmap"] as? String { precondition(row.item.bitmap==bitmap && row.sourceImage != nil) }
                if let icon=source["iconRect"] as? [Double] { precondition(close(row.iconRect.offsetBy(dx:row.frame.minX,dy:row.frame.minY),rectangle(icon))) }
            }
            let dividers=variant["dividers"] as! [[Double]]
            precondition(dividers.count==menu.dividers.count)
            for (native,source) in zip(menu.dividers,dividers) { precondition(close(native.frame,rectangle(source))) }
            precondition(menu.alignment == (kind == .share ? .end:.center) && menu.gap==8)
            precondition(menu.handleKey(key(125))); precondition(menu.focusedIndex==0 && menu.rows[0].keyboardFocused)
            precondition(menu.handleKey(key(126))); precondition(menu.focusedIndex==menu.rows.count-1)
            precondition(menu.handleKey(key(115))); precondition(menu.focusedIndex==0)
            var selected=""; menu.onChoose={selected=$0}; _=menu.handleKey(key(36)); precondition(selected==menu.rows[0].item.key)
        }
        let menu=LuminHeaderMenu(kind:.file,darkAppearance:true,darkPage:false,starred:false); _ = menu.view
        let dark=menu.rows.first{$0.item.key=="darkPage"}!
        precondition(dark.toggle?.frame==NSRect(x:244,y:6,width:36,height:20))
        precondition(menu.view.accessibilityChildren()?.count==13)
        precondition(menu.view.accessibilityChildren()?.allSatisfy{$0 is NSButtonCell}==true)
        let focusWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:304,height:451),styleMask:[.titled],backing:.buffered,defer:false)
        focusWindow.contentView=menu.view
        focusWindow.makeFirstResponder(menu.rows[0]); _=menu.handleKey(key(48))
        precondition(focusWindow.firstResponder === dark.toggle)
        _=menu.handleKey(key(125)); precondition(focusWindow.firstResponder === menu.rows[8])
        focusWindow.contentView=nil
        dark.performClick(nil); precondition(menu.darkPage && dark.toggle?.isOn==true)
        _=menu.handleKey(key(48)); precondition(dark.toggle?.keyboardFocused==true && menu.rows.allSatisfy{!$0.keyboardFocused})
        let badge=fixture["badge"] as! [String:Any],desktop=menu.rows.last!
        NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
            let styles=badge["styles"] as! [String:String]
            precondition(matchesCSS(PodTheme.badgeYellow,styles["backgroundColor"]!) && matchesCSS(PodTheme.onBadgeYellow,styles["color"]!))
        }
        precondition(close(desktop.badgeRect!.offsetBy(dx:desktop.frame.minX,dy:desktop.frame.minY),rectangle(badge["rect"] as! [Double])))
        menu.rows[0].performClick(nil); precondition(menu.starred && menu.rows[0].title=="Remove from starred" && menu.rows[0].sourceImage != nil)
        let light=LuminHeaderMenu(kind:.file,darkAppearance:false,darkPage:true,starred:true); _ = light.view
        precondition(light.rows.first?.title=="Remove from starred")
        precondition(light.rows.contains{$0.title=="Dark Mode"})
        precondition(light.rows.first{$0.item.key=="darkPage"}?.toggle?.isOn==true)
        print("Lumin header menus: exact source rows, labels/icons/dividers, assets, placement rules, keyboard and switch states passed")
    }
}
