import AppKit

private func matchesCSS(_ color:NSColor,_ css:String,alpha:CGFloat=1)->Bool {
    let values=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard values.count>=3,let rgb=color.usingColorSpace(.sRGB) else { return false }
    return zip([rgb.redComponent*255,rgb.greenComponent*255,rgb.blueComponent*255],values.prefix(3)).allSatisfy{abs($0-$1)<0.1} && abs(rgb.alphaComponent-alpha)<0.001
}

private func rectangle(_ v:[Double])->NSRect { NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
private func close(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.02} }

@main enum LuminFooterTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/footer-dock-layout-fixture.json"))) as! [String:Any]
        let source=fixture["elements"] as! [[String:Any]]
        let dock=LuminFooterDock(); dock.update(page:1,total:324,percentage:267,available:true)
        dock.frame=NSRect(origin:.zero,size:dock.intrinsicContentSize); dock.layoutSubtreeIfNeeded()
        precondition(close(dock.bounds,NSRect(origin:.zero,size:rectangle(fixture["rect"] as! [Double]).size)))
        let native:[NSView]=[dock,dock.zoomOut,dock.zoomField,dock.zoomIn,dock.divider,dock.firstPage,dock.previousPage,dock.pageField,dock.totalLabel,dock.nextPage,dock.lastPage]
        let rows=source.filter{($0["tag"] as! String) != "I"}
        precondition(rows.count==native.count)
        for (view,expected) in zip(native,rows) {
            let rect=view===dock ? view.bounds:view.convert(view.bounds,to:dock)
            precondition(close(rect,rectangle(expected["rect"] as! [Double])),"Source dock frame: \(rect), expected \(expected["rect"]!)")
        }
        let buttons=[dock.zoomOut,dock.zoomIn,dock.firstPage,dock.previousPage,dock.nextPage,dock.lastPage]
        let sourceButtons=source.filter{($0["tag"] as! String)=="BUTTON"}
        let glyphs=source.filter{($0["tag"] as! String)=="I"}
        for (button,row,glyph) in zip(zip(buttons,sourceButtons),glyphs).map({($0.0.0,$0.0.1,$0.1)}) {
            precondition(button.image != nil)
            NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                let styles=row["styles"] as! [String:String]
                precondition(matchesCSS(button.cssForeground,styles["color"]!,alpha:button.isEnabled ? 1:0.38))
            }
            precondition(button.isEnabled == !(row["disabled"] as! Bool))
            precondition((glyph["cls"] as! String).contains(button.glyphName))
            precondition(button.glyphRect==NSRect(x:6,y:6,width:20,height:20))
        }
        precondition(dock.alphaValue==0.7)
        dock.setActive(true); precondition(dock.alphaValue==1)
        dock.setActive(false); precondition(dock.alphaValue==0.7)
        dock.previewZoom(5); precondition(!dock.zoomOut.isEnabled && dock.zoomIn.isEnabled)
        dock.previewZoom(267)
        var selected=0; dock.onPage={selected=$0}
        dock.pageField.input.stringValue="325"; dock.pageField.commit(); precondition(selected==1 && dock.pageField.input.stringValue=="1")
        dock.pageField.input.stringValue="2"; dock.pageField.commit(); precondition(selected==2)
        var zoom=0.0; dock.onZoom={zoom=$0}
        dock.zoomField.input.stringValue="10000%"; dock.zoomField.commit(); precondition(zoom==267 && dock.zoomField.input.stringValue=="267%")
        dock.zoomField.input.stringValue="50%"; dock.zoomField.commit(); precondition(zoom==50)
        dock.update(page:324,total:324,percentage:5,available:true)
        precondition(!dock.zoomOut.isEnabled && dock.zoomIn.isEnabled && dock.previousPage.isEnabled && !dock.nextPage.isEnabled && !dock.lastPage.isEnabled)
        dock.update(page:1,total:1,percentage:9999,available:false)
        precondition(buttons.allSatisfy{!$0.isEnabled} && !dock.pageField.input.isEnabled && !dock.zoomField.input.isEnabled)
        print("Lumin footer: source DOM frames, original glyphs, input validation and states passed")
    }
}
