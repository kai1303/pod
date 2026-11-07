import AppKit

private func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
private func close(_ a:CGFloat,_ b:CGFloat)->Bool { abs(a-b)<0.03 }
@main enum LuminCorePaletteTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/core-palettes-layout-fixture.json"))) as! [String:Any]
        let palettes=fixture["palettes"] as! [String:[String:Any]]
        func topRect(_ view:NSView,in root:NSView)->NSRect {
            let r=view.convert(view.bounds,to:root)
            return root.isFlipped ? r:NSRect(x:r.minX,y:root.bounds.height-r.maxY,width:r.width,height:r.height)
        }
        func expectedRect(_ name:String,matching predicate:([String:Any])->Bool)->NSRect {
            let node=(palettes[name]!["controls"] as! [[String:Any]]).last(where:predicate)!,r=node["rect"] as! [Double]
            return NSRect(x:r[0],y:r[1],width:r[2],height:r[3])
        }
        func compare(_ actual:NSRect,_ expected:NSRect,_ label:String) {
            precondition(zip([actual.minX,actual.minY,actual.width,actual.height],[expected.minX,expected.minY,expected.width,expected.height]).allSatisfy{close($0,$1)},"\(label): native \(actual), DOM \(expected)")
        }
        func checkSize(_ palette:MarkupPalette,_ name:String) {
            _ = palette.view
            palette.view.frame=NSRect(origin:.zero,size:palette.preferredContentSize); palette.view.layoutSubtreeIfNeeded()
            let expected=palettes[name]!["size"] as! [Double]
            precondition(close(palette.preferredContentSize.width,expected[0]) && close(palette.preferredContentSize.height,expected[1]),"\(name): native \(palette.preferredContentSize), DOM \(expected)")
            let views=descendants(palette.view)
            for (label,unit) in [("Opacity percent","%"),("Line width points","pt")] {
                guard let input=views.compactMap({$0 as? NSTextField}).first(where:{$0.accessibilityLabel()==label && !$0.isHiddenOrHasHiddenAncestor}) else { continue }
                let source=expectedRect(name) { n in n["tag"] as? String=="INPUT" && n["value"] is String && n["min"] is NSNull && close(CGFloat((n["rect"] as! [Double])[3]),30) && (unit=="%" ? (n["rect"] as! [Double])[2]<28.5:(n["rect"] as! [Double])[2]>28.5) }
                compare(topRect(input,in:palette.view),source,label)
            }
            let picker=views.compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Custom color"}!
            let sourcePicker=expectedRect(name) { $0["tag"] as? String=="BUTTON" && close(CGFloat(($0["rect"] as! [Double])[0]),expected[0]-48) }
            compare(topRect(picker,in:palette.view),sourcePicker,"picker")
            let swatches=views.compactMap{$0 as? SwatchButton}.filter{!$0.isHiddenOrHasHiddenAncestor}
            let sourceSwatches=(palettes[name]!["controls"] as! [[String:Any]]).filter{$0["role"] as? String=="button"}
            precondition(swatches.count==sourceSwatches.count)
            for (native,source) in zip(swatches,sourceSwatches) {
                let r=source["rect"] as! [Double]
                compare(topRect(native,in:palette.view).insetBy(dx:3,dy:3),NSRect(x:r[0],y:r[1],width:r[2],height:r[3]),"22px color cell")
            }
        }
        let draw=MarkupPalette(kinds:[.ink],current:.ink,style:.initial(for:.ink))
        checkSize(draw,"draw")
        let opacity=descendants(draw.view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Opacity percent"}!
        precondition(opacity.font?.pointSize==14,"Numeric inputs inherit the source14px body type")
        let custom=descendants(draw.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Custom color"}!
        precondition(custom.frame.size==NSSize(width:32,height:32),"Source picker target32px, icon24px")
        let shape=MarkupPalette(kinds:Array(MarkupKind.allCases.prefix(10)),current:.rectangle,style:.initial(for:.rectangle))
        checkSize(shape,"shape-fill")
        let border=descendants(shape.view).compactMap{$0 as? NSButton}.first{$0.title=="Border line"}!
        border.performClick(nil); checkSize(shape,"shape-border")
        let width=descendants(shape.view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Line width points"}!
        func send(_ field:NSTextField,_ text:String) { field.stringValue=text; _ = field.sendAction(field.action,to:field.target) }
        var changes=0; shape.onStyle={_ in changes+=1}
        send(width,"4.7"); precondition(shape.style.width==5 && changes==1)
        send(width,"21"); precondition(shape.style.width==5 && changes==1)
        send(width,"bad"); precondition(shape.style.width==5 && changes==1)
        let opacityInput=descendants(shape.view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Opacity percent"}!
        send(opacityInput,"63.7"); precondition(shape.style.opacity==0.64)
        send(opacityInput,"bad"); precondition(shape.style.opacity==0.64)
        var localStyle=shape.style; localStyle.stroke=PodTheme.color(0x123456); localStyle.fill=PodTheme.color(0xABCDEF); shape.setStyle(localStyle)
        let selected=descendants(shape.view).compactMap{$0 as? LuminLegacyIconButton}.first{$0.isSelected}!
        precondition(selected.selectedGlyphColor==localStyle.stroke,"Selected shape uses its current stroke, not selected label text")
        descendants(shape.view).compactMap{$0 as? NSButton}.first{$0.title=="Fill"}!.performClick(nil)
        precondition(shape.style.stroke==localStyle.stroke && shape.style.fill==localStyle.fill,"Switching tabs must preserve PDF style values")
        let line=descendants(shape.view).compactMap{$0 as? NSButton}.first{$0.accessibilityLabel()=="Line"}!
        line.performClick(nil)
        precondition(descendants(shape.view).compactMap{$0 as? NSButton}.first{$0.title=="Fill"}?.isEnabled==false)
        let text=MarkupPalette(kinds:[.underline,.squiggly,.strikeout],current:.underline,style:.initial(for:.underline))
        checkSize(text,"text-tools")
        checkSize(MarkupPalette(kinds:[.highlight],current:.highlight,style:.initial(for:.highlight)),"highlight-text")
        checkSize(MarkupPalette(kinds:[.freehandHighlight],current:.freehandHighlight,style:.initial(for:.freehandHighlight)),"highlight-freehand")
        let highlight=LuminHighlightMenu(); _ = highlight.view
        let expected=palettes["highlight-menu"]!["size"] as! [Double]
        precondition(close(highlight.preferredContentSize.width,expected[0]) && close(highlight.preferredContentSize.height,expected[1]))
        let eraser=LuminEraserPalette(); _ = eraser.view; eraser.view.frame=NSRect(origin:.zero,size:eraser.preferredContentSize); eraser.view.layoutSubtreeIfNeeded()
        precondition(eraser.preferredContentSize==NSSize(width:312,height:100) && eraser.slider.numberOfTickMarks==4)
        precondition(eraser.slider.minValue==8 && eraser.slider.maxValue==32 && eraser.slider.allowsTickMarkValuesOnly)
        compare(topRect(eraser.slider,in:eraser.view),NSRect(x:56,y:16,width:232,height:32),"Eraser slider parent")
        eraser.slider.doubleValue=24; _ = eraser.slider.sendAction(eraser.slider.action,to:eraser.slider.target); precondition(eraser.size==24)
        let eraserCell=eraser.slider.cell as! LuminSliderCell
        precondition(eraserCell.sourceMarkColor(at:0)==NSColor.white.withAlphaComponent(0.8) && eraserCell.sourceMarkColor(at:3)==PodTheme.color(0x20375A))
        let widthSlider=descendants(draw.view).compactMap{$0 as? LuminSlider}.first{$0.accessibilityLabel()=="Line width"}!,widthCell=widthSlider.cell as! LuminSliderCell
        widthSlider.doubleValue=1
        compare(widthCell.sourceFilledTrackRect(in:NSRect(x:0,y:0,width:152,height:32)),NSRect(x:-2,y:11,width:6.8671875,height:4),"Stroke filled track margins")
        let slider=descendants(draw.view).compactMap{$0 as? LuminSlider}.first{$0.accessibilityLabel()=="Opacity"}!,cell=slider.cell as! LuminSliderCell
        compare(cell.sourceTrackRect(in:slider.bounds),NSRect(x:0,y:8.3984375,width:196,height:12),"Opacity custom rail")
        slider.doubleValue=0; compare(cell.knobRect(flipped:true),NSRect(x:-8,y:5,width:16,height:16),"Thumb min")
        slider.doubleValue=100; compare(cell.knobRect(flipped:true),NSRect(x:188,y:5,width:16,height:16),"Thumb max")
        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:1000,height:700),styleMask:[.titled],backing:.buffered,defer:false); owner.isReleasedWhenClosed=false
        let anchor=NSButton(frame:NSRect(x:400,y:600,width:32,height:32)); owner.contentView?.addSubview(anchor)
        for content in [draw,shape,text] {
            let pop=LuminPopper(); pop.contentViewController=content; pop.show(relativeTo:anchor.bounds,of:anchor)
            precondition(content.view.fittingSize==content.preferredContentSize,"Content retains exact DOM line boxes")
            precondition(abs(pop.frame!.height-content.preferredContentSize.height)<0.51 && pop.frame!.width==content.preferredContentSize.width,"AppKit rounds the outer panel to its pixel grid; source control geometry stays fractional")
            pop.close()
        }
        owner.close()
        print("Lumin core palettes: source panel dimensions, style states and numeric/picker controls passed")
    }
}
