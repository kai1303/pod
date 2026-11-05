import AppKit

private func descendants(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(descendants) }
private func button(_ v:NSView,_ name:String)->NSButton { descendants(v).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()==name}! }

@main enum LuminDateTests {
    static func main() {
        _ = NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:100,y:100,width:1372,height:500),styleMask:[.titled],backing:.buffered,defer:false); window.isReleasedWhenClosed=false
        let bar=LuminTypeToolbar(); bar.frame=NSRect(x:0,y:400,width:1372,height:40); window.contentView!.addSubview(bar)
        bar.open(for:.date); bar.layoutSubtreeIfNeeded()
        precondition(LuminAssets.previewFont("Helvetica",size:14).familyName=="Helvetica")
        precondition(bar.state.family=="Helvetica" && bar.state.size==12 && bar.fontChoices.count==19)
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/date-layout-fixture.json"))) as! [String:Any]
        let frames=fixture["controls"] as! [String:[Double]]
        for (name,a) in frames {
            let b=button(bar,name),r=b.frame
            precondition(zip([r.minX,r.minY,r.width,r.height],a).allSatisfy{abs($0-$1)<0.05},"Source Date control frame: \(name): \(r)")
        }
        button(bar,"Font family").performClick(nil)
        let menu=window.childWindows!.last!.contentViewController as! LuminTypeChoiceMenu
        precondition(menu.choices.count==19 && menu.choices.first?.value=="Helvetica")
        precondition(abs(menu.preferredContentSize.width-227.484375)<0.01 && menu.preferredContentSize.height==316)
        let inter=descendants(menu.view).compactMap{$0 as? NSButton}.first{$0.title=="Inter"}!
        inter.performClick(nil); button(bar,"Bold").performClick(nil)
        precondition(bar.fontChoices.count==18 && bar.state.bold)
        bar.open(); precondition(bar.state.family=="Inter" && !bar.state.bold,"Text and Date retain independent engine style previews")
        button(bar,"Italic").performClick(nil)
        bar.open(for:.date); precondition(bar.state.family=="Inter" && bar.state.bold && !bar.state.italic)
        bar.dismiss(); bar.open(); precondition(bar.state.italic && !bar.state.bold)
        bar.dismiss()
        let gate=LuminPremiumGate(); let view=gate.view; view.frame=NSRect(origin:.zero,size:gate.preferredContentSize); view.layoutSubtreeIfNeeded()
        precondition(gate.preferredContentSize==NSSize(width:304,height:230))
        let source=fixture["gate_controls"] as! [String:[Double]]
        for (name,a) in source {
            let r=gate.controls[name]!.frame
            precondition(zip([r.minX,r.minY,r.width,r.height],a).allSatisfy{abs($0-$1)<0.01},"Source premium gate frame: \(name)")
        }
        precondition((view as! LuminDialogPaper).radius==16 && gate.upgrade.title=="Upgrade now")
        precondition(LuminAssets.bitmap("Premium/three-stars") != nil)
        window.close()
        print("Lumin Date/premium gate: source toolbar frames, dynamic font fallback, isolated style contexts and304x230 gate geometry passed")
    }
}
