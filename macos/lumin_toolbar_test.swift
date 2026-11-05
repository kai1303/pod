import AppKit

private func rectangle(_ values:[Double])->NSRect { NSRect(x:values[0],y:values[1],width:values[2],height:values[3]) }
private func close(_ a:NSRect,_ b:NSRect)->Bool { abs(a.minX-b.minX)<0.02 && abs(a.minY-b.minY)<0.02 && abs(a.width-b.width)<0.02 && abs(a.height-b.height)<0.02 }
private func matches(_ color:NSColor,_ css:String)->Bool {
    if css.hasPrefix("#"),let value=UInt32(css.dropFirst(),radix:16) { return color.usingColorSpace(.sRGB)==PodTheme.color(value).usingColorSpace(.sRGB) }
    let values=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard values.count>=3,let rgb=color.usingColorSpace(.sRGB) else { return false }
    let alpha=values.count==4 ? values[3]:1
    if abs(rgb.alphaComponent-alpha)>0.001 { return false }; if alpha==0 { return true }
    return zip([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],values.prefix(3)).allSatisfy{abs($0.0*255-$0.1)<0.1}
}

@main
enum LuminToolbarTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/main-toolbar-layout-fixture.json"))) as! [String:Any]
        let variants=fixture["variants"] as! [[String:Any]]
        let roles=fixture["legacyRoles"] as! [String:[String:String]]
        let sign=(try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/main-toolbar-source-rules.json"))) as! [String:Any])["signSecurely"] as! [String:Any]
        for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",.darkAqua)] {
            NSAppearance(named:appearance)!.performAsCurrentDrawingAppearance {
                precondition(matches(LuminLegacyStyle.secondaryContainer,roles[name]!["le_main_secondary_container"]!))
                precondition(matches(LuminLegacyStyle.onSecondaryContainer,roles[name]!["le_main_on_secondary_container"]!))
                precondition(matches(LuminLegacyStyle.disabled,roles[name]!["le_disable_on_container"]!))
                let brand=sign[name] as! [String:String]
                precondition(matches(LuminLegacyStyle.signContainer,brand["background"]!) && matches(LuminLegacyStyle.signText,brand["foreground"]!))
            }
        }
        for variant in variants {
            let mode=variant["mode"] as! String,viewport=variant["viewport"] as! [String:Double]
            let source=variant["toolbar"] as! [String:Any]
            let bar=LuminMainToolbar(); bar.frame=rectangle(source["rect"] as! [Double]); bar.viewportWidth=CGFloat(viewport["width"]!); bar.setMode(mode); bar.layoutSubtreeIfNeeded()
            let common=variant["common"] as! [String:Any],tools=variant["tools"] as! [String:Any]
            precondition(close(bar.commonFrame,rectangle(common["frame"] as! [Double])),"\(mode)/\(viewport["width"]!): common \(bar.commonFrame)")
            precondition(close(bar.toolsFrame,rectangle(tools["frame"] as! [Double])),"\(mode)/\(viewport["width"]!): tools \(bar.toolsFrame), expected \(tools["frame"]!)")
            let sourceButtons=variant["buttons"] as! [[String:Any]]
            let buttons=bar.sourceButtons.sorted{$0.convert($0.bounds,to:bar).minX < $1.convert($1.bounds,to:bar).minX}
            precondition(buttons.count==sourceButtons.count,"\(mode): source buttons \(sourceButtons.count), native \(buttons.count)")
            for (button,expected) in zip(buttons,sourceButtons) {
                precondition(close(button.convert(button.bounds,to:bar),rectangle(expected["rect"] as! [Double])),"\(mode): \(button.identifier?.rawValue ?? "?") frame \(button.convert(button.bounds,to:bar)); source \(expected["rect"]!)")
                precondition(button.isEnabled == !(expected["disabled"] as! Bool),"Keep source availability for \(button.title)")
                NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                    // Live resize samples can catch a color transition. Verify its final
                    // shipped role rather than reproducing a .98-alpha intermediate frame.
                    let color:String
                    if !button.isEnabled { color=roles["dark"]!["le_disable_on_container"]! }
                    else if button.kind == .sign { color=(sign["dark"] as! [String:String])["foreground"]! }
                    else if button.kind == .more { color="rgb(178, 202, 214)" }
                    else { color=roles["dark"]![button.isSelected ? "le_main_on_secondary_container":"le_main_on_surface_variant"]! }
                    precondition(matches(button.cssForeground,color),"\(mode): \(button.title) source foreground role")
                    let background=button.kind == .sign ? (sign["dark"] as! [String:String])["background"]!:button.isSelected ? roles["dark"]!["le_main_secondary_container"]!:"rgba(0, 0, 0, 0)"
                    precondition(matches(button.cssBackground,background),"\(mode): \(button.title) source background role")
                }
                if let glyph=(expected["glyphs"] as! [[String:String]]).first?["class"]?.split(separator:" ").first(where:{$0.hasPrefix("pdf-icon-") || $0.hasPrefix("kiwi-icon-")}) {
                    precondition(button.glyphName==String(glyph),"Use the source glyph for \(button.title)")
                    precondition(button.image != nil,"Load the original glyph asset for \(button.title)")
                }
            }
            precondition(bar.button("Select")?.isSelected==true)
            bar.selectTool("Draw"); bar.setHistory(undo:true,redo:false)
            precondition(bar.button("Select")?.isSelected==false)
            if mode != "Security" { precondition(bar.button("Undo")?.isEnabled==true && bar.button("Redo")?.isEnabled==false) }
        }
        precondition(LuminToolbarCollapse.count(viewport:1512,left:418,baseline:878,count:8)==1)
        precondition(LuminToolbarCollapse.count(viewport:1180,left:418,baseline:878,count:8)==7)
        precondition(LuminToolbarCollapse.count(viewport:1180,left:418,baseline:1020,count:10)==10)
        precondition(LuminToolbarCollapse.count(viewport:900,left:418,baseline:1020,count:10)==nil)
        precondition(LuminToolbarCollapse.count(viewport:2000,left:418,baseline:1020,count:10)==0)
        let narrowed=LuminMainToolbar(); narrowed.frame=NSRect(x:0,y:0,width:1104,height:48); narrowed.viewportWidth=1240; narrowed.setMode("Mark up"); narrowed.rightPanelWidth=300; narrowed.layoutSubtreeIfNeeded()
        precondition(narrowed.button("More tools") != nil,"An opened panel participates in the source width budget")
        let menu=LuminToolbarMenu.thumbnails(); _ = menu.view
        precondition(menu.preferredContentSize==NSSize(width:226,height:80))
        precondition(menu.rows.map{$0.command.title}==["Thumbnails","Outlines"])
        precondition(menu.rows.map{$0.frame.height}==[32,32])
        precondition(LuminAssets.icon("kiwi-icon-bookmark-lg") != nil)
        let overflow=LuminToolbarMenu.overflow(mode:"Mark up"); _ = overflow.view
        precondition(overflow.preferredContentSize==NSSize(width:280,height:416))
        precondition(overflow.rows.map{$0.command.title}==["Comment","Measure","Type","Draw","Highlight","Text tools","Shape","Eraser","Image","Perform OCR"])
        precondition(overflow.options.count==6)
        precondition(overflow.options[0].frame==NSRect(x:236,y:12,width:32,height:32))
        precondition(LuminAssets.bitmap("Toolbar/sign-logo") != nil && LuminAssets.bitmap("Toolbar/sign-caret") != nil && LuminAssets.bitmap("Toolbar/premium") != nil)
        let rail=LuminUtilityRail(); rail.frame=NSRect(x:0,y:0,width:56,height:778)
        let utility=fixture["utility"] as! [String:Any],buttons=utility["buttons"] as! [[String:Any]],dividers=utility["dividers"] as! [[String:Any]]
        precondition(rail.buttons.map{$0.frame}==buttons.map{rectangle($0["rect"] as! [Double])})
        precondition(rail.dividers.map{$0.frame}==dividers.map{rectangle($0["rect"] as! [Double])})
        precondition(rail.buttons[0].imageSize==28 && rail.buttons[0].preservesImageColors && rail.buttons[6].preservesImageColors)
        let placed=LuminPopper.placement(anchor:NSRect(x:804,y:700,width:32,height:32),size:NSSize(width:280,height:416),viewport:NSRect(x:0,y:0,width:900,height:834),gap:4,crossAxisOffset:12)
        precondition(placed.minX==568,"More tools follows the source cross-axis offset12")
        print("Lumin main toolbar: all source mode/viewport rectangles, split buttons, history/selection, exact collapse arithmetic, original assets and thumbnails/overflow structures passed")
    }
}
