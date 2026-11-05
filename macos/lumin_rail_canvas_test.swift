import AppKit

private func rect(_ v:[Double])->NSRect { NSRect(x:v[0],y:v[1],width:v[2],height:v[3]) }
private func close(_ a:NSRect,_ b:NSRect)->Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.025} }
private func colorMatches(_ color:NSColor,_ css:String)->Bool {
    let v=css.replacingOccurrences(of:"rgba(",with:"").replacingOccurrences(of:"rgb(",with:"").replacingOccurrences(of:")",with:"").split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))}
    guard v.count>=3,let c=color.usingColorSpace(.sRGB) else { return false }; let a=v.count==4 ? v[3]:1
    return abs(c.alphaComponent-a)<0.001 && (a==0 || zip([c.redComponent*255,c.greenComponent*255,c.blueComponent*255],v.prefix(3)).allSatisfy{abs($0-$1)<0.1})
}
@main enum LuminRailCanvasTests {
    static func main() {
        _ = NSApplication.shared
        let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/mode-rail-canvas-layout-fixture.json"))) as! [String:Any]
        for variant in fixture["variants"] as! [[String:Any]] {
            let rail=LuminModeRail(); let size=rect(variant["rect"] as! [Double]).size; rail.frame=NSRect(origin:.zero,size:size); rail.layoutSubtreeIfNeeded()
            let source=variant["buttons"] as! [[String:Any]]
            for (button,row) in zip(rail.buttons,source) {
                button.appearance=NSAppearance(named:.darkAqua); button.selected=row["active"] as! Bool
                precondition(close(button.frame,rect(row["rect"] as! [Double])))
                precondition(close(button.iconWrapperRect.offsetBy(dx:button.frame.minX,dy:button.frame.minY),rect(row["iconWrapper"] as! [Double])))
                precondition(close(button.iconRect.offsetBy(dx:button.frame.minX,dy:button.frame.minY),rect(row["icon"] as! [Double])))
                precondition(close(button.labelRect.offsetBy(dx:button.frame.minX,dy:button.frame.minY),rect(row["label"] as! [Double])))
                precondition(button.assetKey==row["assetKey"] as! String && button.sourceImage != nil)
                NSAppearance(named:.darkAqua)!.performAsCurrentDrawingAppearance {
                    precondition(colorMatches(button.labelColor,(row["labelStyle"] as! [String:String])["color"]!))
                    precondition(colorMatches(button.iconColor,(row["pathFills"] as! [String]).first!))
                    precondition(colorMatches(button.iconBackground,row["iconBackground"] as! String))
                }
            }
            precondition(rail.focusButton.frame==NSRect(x:20,y:size.height-56,width:40,height:40))
        }
        precondition(LuminModeAssets.records.count==28)
        for key in LuminModeAssets.records.keys { precondition(LuminModeAssets.image(key) != nil) }
        let pattern=LuminCanvasPattern.centers(in:NSRect(x:0,y:0,width:52,height:52),origin:.zero)
        precondition(pattern==[CGPoint(x:13,y:13),CGPoint(x:39,y:13),CGPoint(x:13,y:39),CGPoint(x:39,y:39)])
        let shifted=LuminCanvasPattern.centers(in:NSRect(x:17,y:101,width:52,height:52),origin:CGPoint(x:17,y:101)).map{CGPoint(x:$0.x-17,y:$0.y-101)}
        precondition(pattern==shifted,"CSS background remains attached to the viewport during scrolling")
        let page=fixture["settledPage"] as! [String:Any],canvas=page["canvas"] as! [String:Double],sourcePage=page["page"] as! [String:Double]
        let layout=LuminCanvasLayout(pageSize:NSSize(width:504,height:661),zoom:2.67,viewport:NSSize(width:canvas["width"]!,height:canvas["height"]!))
        precondition(layout.margin==11)
        precondition(close(layout.borderFrame,NSRect(x:sourcePage["x"]!-canvas["x"]!,y:sourcePage["y"]!-canvas["y"]!,width:sourcePage["width"]!,height:sourcePage["height"]!)))
        precondition(LuminCanvasLayout(pageSize:NSSize(width:612,height:792),zoom:0.95,viewport:NSSize(width:1100,height:796)).margin==4)
        let normal=LuminViewerLayout(viewport:NSSize(width:1512,height:834),focus:false),focused=LuminViewerLayout(viewport:NSSize(width:1512,height:834),focus:true)
        precondition(normal.canvas==NSRect(x:82,y:104,width:1372,height:730))
        precondition(focused.canvas==NSRect(x:2,y:48,width:1508,height:786))
        precondition(focused.restore==NSRect(x:0,y:774,width:36,height:48))
        print("Lumin rail/canvas: source mode frames/colors/28 SVG variants, dot anchoring, engine page rounding and focus geometry passed")
    }
}
