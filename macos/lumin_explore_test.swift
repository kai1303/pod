import AppKit
import CoreText

private func allViews(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(allViews) }
private func key(_ code:UInt16)->NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }

@main
enum LuminExploreTests {
    static func main() {
        _ = NSApplication.shared
        let search=LuminExploreSearch(mode:"Popular")
        precondition(search.libraryVersion=="6.6.2")
        precondition(search.results("type").map{$0.title}==["Type"])
        precondition(search.results("rect").map{$0.title}==["Select","Invoice extraction","Split & Extract","Shape"],"Keep source Fuse ordering before alias matches")
        precondition(search.results("tye").isEmpty && search.results("zzzznonexistent").isEmpty)
        let space=search.results(" ").map{$0.title}
        let capture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/explore-search-fixtures.json"))) as! [String:Any]
        let expected=(capture["queries"] as! [String:[String]])[" "]!
        precondition(space==expected,"Whitespace source mismatch: actual \(space); expected \(expected)")
        precondition(search.normalize("Crème Æß 中文")=="Creme AEss 中文")
        for command in search.groups.flatMap({$0.commands}).filter({$0.renders}) {
            if let icon=command.icon { precondition(LuminAssets.icon(icon) != nil,"Missing \(icon)") }
            else if let bitmap=command.bitmap { precondition(LuminAssets.bitmap(bitmap) != nil,"Missing \(bitmap)") }
            else { fatalError("Missing original icon for \(command.title)") }
        }
        let medium=LuminAssets.font(14,500)
        precondition((CTFontCopyAttribute(medium,kCTFontURLAttribute) as? URL)?.lastPathComponent=="Inter-Medium.ttf","Source weight500 uses static Inter Medium")
        precondition(medium.fontName=="Inter-Medium")
        let variable=LuminAssets.font(14,420)
        precondition((CTFontCopyAttribute(variable,kCTFontURLAttribute) as? URL)?.lastPathComponent=="Inter-VariableFont.ttf")
        let css=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/explore-layout-fixture.json"))) as! [String:Any]
        func sourceRect(_ key:String)->NSRect { let v=css[key] as! [Double]; return NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
        let styles=css["styles"] as! [String:[String:String]]
        func checkColor(_ color:NSColor,_ role:String,_ property:String) {
            NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                let rgb=color.usingColorSpace(.sRGB)!
                let value="rgb(\(Int((rgb.redComponent*255).rounded())), \(Int((rgb.greenComponent*255).rounded())), \(Int((rgb.blueComponent*255).rounded())))"
                precondition(value==styles[role]![property]!,"\(role).\(property) differs from live CSS: \(value)")
            }
        }
        checkColor(PodTheme.raised,"menu","background")
        checkColor(PodTheme.text,"input","color")
        checkColor(PodTheme.onSecondaryContainer,"glyph","color")
        checkColor(PodTheme.informationContainer,"guideline","background")
        checkColor(PodTheme.secondary,"close","color")

        let menu=LuminExploreMenu(mode:"Popular",canUndo:false,canRedo:false,showGuideline:true)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:336,height:516),styleMask:[.borderless],backing:.buffered,defer:false); window.isReleasedWhenClosed=false; window.contentViewController=menu; menu.view.layoutSubtreeIfNeeded()
        precondition(menu.preferredContentSize==sourceRect("menuFrame").size)
        precondition(menu.searchBox.frame==sourceRect("searchFrame"))
        precondition(menu.searchInput.isEditable && menu.searchInput.isSelectable && menu.searchInput.cell!.usesSingleLineMode,"The custom source-styled cell must remain an editable single-line search input")
        precondition(menu.searchInput.frame==sourceRect("inputFrame"),"Source input fills the 32px search box beside the 20px glyph")
        precondition(menu.resultScroll.frame==sourceRect("resultsFrame"))
        precondition(menu.visibleCommands.count==56 && menu.visibleGroupTitles.count==10)
        let agreement=allViews(menu.view).compactMap{$0 as? LuminExploreRow}.first{$0.command.key=="agreementGen"}!
        precondition(agreement.frame==sourceRect("firstRowFrame"))
        precondition(abs(agreement.iconWidth-sourceRect("firstIconFrame").width)<0.01 && abs(agreement.textLeft-sourceRect("firstLabelFrame").minX)<0.01,"Preserve source icon-font advance and label offset")
        menu.search("type"); menu.view.layoutSubtreeIfNeeded()
        precondition(menu.visibleCommands.map{$0.title}==["Type","Ask for \"type\" in Lumin AI","Search for \"type\" in this document"])
        precondition(menu.visibleGroupTitles.isEmpty)
        var selected:String?
        menu.onChoose={selected=$0.key}
        window.makeFirstResponder(menu.searchInput)
        precondition(!menu.handleKey(key(36)) && selected==nil,"Enter in the search input does not submit/select a tool")
        precondition(menu.handleKey(key(125))); precondition(menu.handleKey(key(36)) && selected=="type")
        menu.search("undo"); window.makeFirstResponder(menu.searchInput)
        precondition(menu.handleKey(key(125)) && menu.focusedCommandKey=="searchChatbot","Keyboard navigation skips the disabled Undo command")
        menu.search("zzzznonexistent"); menu.view.layoutSubtreeIfNeeded()
        let rows=allViews(menu.view).compactMap{$0 as? LuminExploreRow}
        precondition(rows.map{$0.frame.height}==[40,56],"Long query actions wrap into source 56px rows")
        menu.search("")
        window.makeFirstResponder(menu.searchInput)
        precondition(menu.handleKey(key(126)))
        precondition(menu.handleKey(key(119))) // End
        precondition(menu.focusedCommandKey=="quickSearchConvertGeneric")
        precondition(menu.handleKey(key(125)) && menu.focusedCommandKey=="agreementGen","Arrow navigation wraps")
        let close=allViews(menu.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Dismiss Quick Search tip"}!
        close.performClick(nil); menu.view.layoutSubtreeIfNeeded()
        precondition(menu.resultScroll.frame==NSRect(x:16,y:60,width:304,height:440))
        let organize=LuminExploreSearch(mode:"Organize")
        precondition(organize.results("view").contains{$0.key=="gridView"} && !organize.results("view").contains{$0.key=="viewControl"})
        let viewport=NSRect(x:0,y:0,width:1512,height:778)
        let placed=LuminPopper.placement(anchor:NSRect(x:4,y:216,width:72,height:58),size:NSSize(width:336,height:516),viewport:viewport,alignment:.center,gap:5,edge:.maxX,inset:5)
        precondition(placed==NSRect(x:81,y:5,width:336,height:516),"Explore flips beside the rail and clamps to the source 5px viewport inset")
        window.close()
        print("Lumin Explore: original assets/fonts, exact Fuse6.6.2/alias sequences, default/filter geometry, wrapping, keyboard selection and right-side placement passed")
    }
}
