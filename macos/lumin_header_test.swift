import AppKit

private func matchesCSS(_ color:NSColor,_ css:String,alpha:CGFloat=1)->Bool {
    let values=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard values.count>=3,let rgb=color.usingColorSpace(.sRGB) else { return false }
    return zip([rgb.redComponent*255,rgb.greenComponent*255,rgb.blueComponent*255],values.prefix(3)).allSatisfy{abs($0-$1)<0.1} && abs(rgb.alphaComponent-alpha)<0.001
}

@main enum LuminHeaderTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/header-layout-fixture.json"))) as! [String:Any]
        let elements=fixture["elements"] as! [[String:Any]]
        let header=LuminDocumentHeader(); header.frame=NSRect(x:0,y:0,width:1512,height:56); header.layoutSubtreeIfNeeded()
        let controls=[("open_viewer_navigation",header.navigation),("file-menu",header.fileMenu),("Share",header.share),("help_center_button",header.help),("notification_button",header.notifications)]
        for (role,control) in controls {
            let source=elements.first{$0["role"] as? String==role}!,v=source["rect"] as! [Double]
            for (actual,expected) in zip([control.frame.minX,control.frame.minY,control.frame.width,control.frame.height],v) { precondition(abs(actual-expected)<0.02,"Header \(role): \(control.frame), source \(v)") }
            precondition(control.image != nil)
            NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                let styles=source["styles"] as! [String:String]
                precondition(matchesCSS(control.cssForeground,styles["color"]!),"Header source foreground: \(role)")
                if role=="file-menu" || role=="Share" { precondition(matchesCSS(control.cssBackground,styles["backgroundColor"]!)) }
            }
        }
        precondition(header.shareOptions.frame==NSRect(x:1331,y:8,width:40,height:40))
        precondition(header.identity.frame==NSRect(x:1468,y:10,width:36,height:36))
        precondition(header.share.glyphName=="pdf-icon-md_not_shared")
        precondition(header.shareOptions.glyphName=="pdf-icon-md_arrow_down")
        precondition(header.titleBox.frame.minX==76 && header.titleBox.frame.height==32)
        precondition(header.titleField.font!.pointSize==14)
        header.documentName="Local file.pdf"; precondition(header.titleField.stringValue=="Local file")
        header.documentName="Draft.PDF"; precondition(header.titleField.stringValue=="Draft")
        header.frame.size.width=1160; header.needsLayout=true; header.layoutSubtreeIfNeeded()
        precondition(header.identity.frame.maxX==1152 && header.titleBox.frame.maxX<=580)
        print("Lumin header: source control frames, original glyphs, title layout and local identity passed")
    }
}
