import AppKit

@main enum LuminFormBuilderTests {
 static func main() {
  _ = NSApplication.shared
  let fixture=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"research/lumin/form-builder-layout-fixture.json"))) as! [String:Any]
  let sources=fixture["sources"] as! [[String:Any]]
  func source(_ s:Int,_ i:Int)->NSRect { let n=(sources[s]["nodes"] as! [[String:Any]]).first{$0["index"] as? Int==i}!,a=n["rect"] as! [Double]; return NSRect(x:a[0],y:a[1],width:a[2],height:a[3]) }
  func same(_ a:NSRect,_ b:NSRect) { precondition(zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<0.02},"Source form rectangle: \(a) versus \(b)") }
  let menu=LuminFormBuilderMenu(); _=menu.view
  precondition(menu.preferredContentSize==NSSize(width:266,height:80))
  for (i,n) in [3,8].enumerated() { same(menu.rows[i].frame,source(0,n)); precondition(menu.rows[i].isEnabled && menu.rows[i].sourceImage != nil && menu.rows[i].premiumRect==nil) }
  let panel=LuminFormBuilderPanel(frame:NSRect(x:0,y:0,width:360,height:730)); panel.layoutSubtreeIfNeeded()
  for (key,n) in [("header",1),("headerTitle",2),("close",4),("insertTitle",11),("tabTrack",12),("properties",27),("propertiesTitle",30),("empty",31),("footer",32),("cancel",33),("apply",36)] { same(panel.controls[key]!.convert(panel.controls[key]!.bounds,to:panel),source(1,n)) }
  for (i,n) in [15,18,21,24].enumerated() { same(panel.tabs[i].convert(panel.tabs[i].bounds,to:panel),source(1,n)); precondition(panel.tabs[i].image != nil) }
  precondition(panel.selectedKind==nil && panel.tabs.allSatisfy{!$0.selected} && !panel.apply.isEnabled)
  for i in 0..<4 { panel.tabs[i].performClick(nil); precondition(panel.selectedKind?.rawValue==i && panel.tabs.filter{$0.selected}.count==1 && !panel.apply.isEnabled && !panel.controls["empty"]!.isHidden,"Selecting a creation-tool preview does not invent fields or properties") }
  panel.reset(); precondition(panel.selectedKind==nil && panel.tabs.allSatisfy{!$0.selected})
  panel.frame.size.height=600; panel.layoutSubtreeIfNeeded(); precondition(panel.cancel.frame.minY==533 && panel.controls["properties"]!.frame.height==402,"Source calc heights retain the11px lower gap at another viewport height")
  var closed=0; panel.onCancel={closed+=1}; panel.cancel.performClick(nil); (panel.controls["close"] as! NSButton).performClick(nil); precondition(closed==2)
  print("Lumin Form builder: source266x80 menu,360px panel frames, original glyphs, empty/tab state and Cancel/Apply geometry passed")
 }
}
