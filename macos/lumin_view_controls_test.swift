import AppKit

private func key(_ code:UInt16,_ text:String="")->NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)! }
private func rect(_ values:[Double])->NSRect { NSRect(x:values[0],y:values[1],width:values[2],height:values[3]) }

@main
enum LuminViewControlsTests {
    static func main() {
        _ = NSApplication.shared
        let source=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/view-controls-layout-fixture.json"))) as! [String:Any]
        let gridSource=source["view"] as! [String:Any],zoomSource=source["zoom"] as! [String:Any]
        let colors=source["legacyColors"] as! [String:[String:String]]
        let roles:[(NSColor,String)]=[(LuminLegacyStyle.text,"le_main_on_surface"),(LuminLegacyStyle.variant,"le_main_on_surface_variant"),(LuminLegacyStyle.primary,"le_main_primary"),(LuminLegacyStyle.selected,"le_main_primary_container"),(LuminLegacyStyle.container,"le_main_surface_container"),(LuminLegacyStyle.outline,"le_main_outline_variant")]
        for (appearance,name) in [(NSAppearance.Name.aqua,"light"),(.darkAqua,"dark")] {
            NSAppearance(named:appearance)!.performAsCurrentDrawingAppearance {
                for (color,role) in roles {
                    let rgb=color.usingColorSpace(.sRGB)!
                    let hex=String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
                    precondition(hex==colors[name]![role]!,"Keep source legacy role \(name).\(role)")
                }
            }
        }
        let grid=LuminViewControlsMenu(state:LuminViewState())
        _ = grid.view; grid.view.layoutSubtreeIfNeeded()
        precondition(grid.preferredContentSize==rect(gridSource["frame"] as! [Double]).size)
        let expected=gridSource["buttons"] as! [[String:Any]]
        precondition(grid.buttons.count==5)
        for (button,value) in zip(grid.buttons,expected) {
            precondition(button.identifier?.rawValue==value["key"] as? String)
            precondition(button.frame==rect(value["rect"] as! [Double]))
            precondition(button.glyphName==value["icon"] as! String && LuminAssets.icon(button.glyphName) != nil)
        }
        precondition(grid.state.displayMode=="Continuous")
        let headings=grid.view.subviews.compactMap{$0 as? NSTextField}
        let sourceHeadings=gridSource["labels"] as! [[String:Any]]
        for (heading,value) in zip(headings,sourceHeadings) { precondition(heading.frame==rect(value["rect"] as! [Double]) && heading.font?.pointSize==14) }
        let hoverEvent=key(0)
        grid.buttons[1].mouseEntered(with:hoverEvent)
        precondition(grid.buttons[1].isSelected && grid.buttons[1].cssBackground.alphaComponent==0.08,"Source hover replaces the selected teal background")
        precondition(grid.buttons[1].cssForeground.usingColorSpace(.sRGB)==LuminLegacyStyle.text.usingColorSpace(.sRGB))
        grid.buttons[1].mouseExited(with:hoverEvent)
        precondition(grid.buttons[1].cssBackground==LuminLegacyStyle.selected)
        var changes:[String]=[]; grid.onChange={changes.append($0.displayMode)}
        grid.buttons[4].performClick(nil)
        precondition(grid.state.displayMode=="Cover" && grid.buttons[1].isSelected && grid.buttons[4].isSelected)
        grid.buttons[0].performClick(nil)
        precondition(grid.state.displayMode=="CoverFacing" && grid.buttons[4].isSelected && !grid.buttons[1].isSelected)
        precondition(changes==["Cover","CoverFacing"],"Changing transition preserves layout and vice versa")
        let reopened=LuminViewControlsMenu(state:grid.state); _ = reopened.view
        precondition(reopened.buttons[0].isSelected && reopened.buttons[4].isSelected)
        let zoom=LuminZoomMenu(); _ = zoom.view
        precondition(zoom.preferredContentSize==rect(zoomSource["frame"] as! [Double]).size)
        let expectedRows=zoomSource["rows"] as! [[String:Any]]
        precondition(zoom.rows.map{$0.title+($0.shortcut ?? "")}==expectedRows.map{$0["text"] as! String})
        for (row,value) in zip(zoom.rows,expectedRows) { precondition(row.frame==rect(value["rect"] as! [Double])) }
        let separators=zoomSource["separators"] as! [[String:Any]]
        precondition(zoom.separators.map{$0.frame}==separators.map{rect($0["rect"] as! [Double])})
        var chosen:LuminZoomAction?
        zoom.onChoose={chosen=$0}
        precondition(zoom.handleKey(key(125)) && zoom.handleKey(key(36)) && chosen == .fitWidth)
        zoom.rows[6].performClick(nil); precondition(chosen == .zoomIn && chosen?.closesMenu==false)
        zoom.rows[3].performClick(nil); precondition(chosen == .percent(100) && chosen?.closesMenu==true)
        precondition(zoom.handleKey(key(6,"z")) && zoom.handleKey(key(36)) && chosen == .zoomIn)
        precondition(zoom.handleKey(key(6,"z")) && zoom.handleKey(key(36)) && chosen == .zoomOut,"Repeated-character source typeahead cycles matching rows")
        precondition(LuminZoomAction.zoomOut.closesMenu==false && LuminZoomAction.fitHeight.closesMenu)
        let field=LuminZoomField(); field.frame=rect((zoomSource["field"] as! [String:Any])["rect"] as! [Double]); field.layoutSubtreeIfNeeded()
        precondition(field.intrinsicContentSize==NSSize(width:68,height:32))
        precondition(field.input.frame==rect((zoomSource["input"] as! [String:Any])["rect"] as! [Double]))
        field.percentage=267; precondition(field.input.stringValue=="267%")
        field.input.stringValue="12x5.5"; field.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
        precondition(field.input.stringValue=="125.5%","Source NumericFormat filters letters and appends the percent suffix")
        var committed:Double?; field.onCommit={committed=$0}
        field.input.stringValue="125.5%"; field.commit(); precondition(committed==125.5 && field.input.stringValue=="126%","Source zoomUpdated rounds the displayed percentage")
        field.input.stringValue="10000%"; field.commit(); precondition(committed==9999)
        field.input.stringValue="0%"; field.commit(); precondition(committed==5)
        field.input.stringValue="bad"; field.commit(); precondition(field.input.stringValue=="5%","Invalid nonnumeric drafts preserve the current finite preview")
        precondition(LuminZoomAction.stepped(80,increase:true)==87.5)
        precondition(LuminZoomAction.stepped(150,increase:false)==137.5)
        precondition(LuminZoomAction.stepped(267,increase:true)==317)
        precondition(LuminZoomAction.stepped(5,increase:false)==5)
        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false); owner.isReleasedWhenClosed=false
        owner.contentView?.addSubview(field)
        var opens=0; field.onOpen={opens += 1}
        owner.makeFirstResponder(field.input)
        precondition(opens>0,"Focusing the field opens its menu before typing")
        let responder=owner.firstResponder
        let pop=LuminPopper(); pop.contentViewController=zoom; pop.takesKeyFocus=false; pop.keepsAnchorInteractive=true; pop.alignment = .start; pop.gap=8
        pop.show(relativeTo:field.bounds,of:field)
        precondition(pop.isShown && owner.firstResponder === responder,"Opening zoom choices must preserve the editable owner field")
        pop.close(); owner.close()
        print("Lumin viewer controls: source DOM/CSS geometry, original glyphs, independent view states, exact zoom rows, draft/step behavior and editable popup focus passed")
    }
}
