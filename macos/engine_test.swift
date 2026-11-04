import Foundation
@main struct EngineChecks {
    static func main() throws {
        precondition(Markup.hasDrawnExtent([.zero,CGPoint(x:20,y:30),.zero],threshold:1),"Closed strokes must commit")
        precondition(!Markup.hasDrawnExtent([.zero,.zero],threshold:1))
        let hitMark=Markup(kind:.highlight,points:[CGPoint(x:10,y:10),CGPoint(x:110,y:25)],rect:CGRect(x:-60,y:-60,width:240,height:155),style:.initial(for:.highlight))
        precondition(hitMark.hitTest(CGPoint(x:50,y:15),tolerance:2))
        precondition(!hitMark.hitTest(CGPoint(x:50,y:50),tolerance:2),"Appearance padding must not select an adjacent line")
        var colorStyle=MarkupStyle.initial(for:.rectangle)
        let originalColor=colorStyle.cValue.stroke
        for _ in 0..<20 { colorStyle=MarkupStyle(colorStyle.cValue) }
        precondition(abs(colorStyle.cValue.stroke.0-originalColor.0)<0.000001,"Annotation colors must not drift across edits")
        let engine=try Engine()
        let original=try Engine.read(URL(fileURLWithPath:CommandLine.arguments[1]))
        let loaded=try engine.load(original,page:0,width:612)
        precondition(loaded.pages.count==2 && loaded.pixels.height==792)
        let text=loaded.pages[0].runs[0].text
        let edited=try engine.replace(original,page:0,run:0,text:"Hello Pod")
        let again=try engine.load(edited,page:0,width:612)
        precondition(again.pages[0].runs[0].text=="Hello Pod")
        let unchanged=try engine.load(original,page:0,width:612)
        precondition(unchanged.pages[0].runs[0].text==text)
        do { _=try engine.replace(original,page:0,run:0,text:String(repeating:"x",count:200)); preconditionFailure("expected overflow") } catch is EngineError {}
        let blank=try engine.replace(original,page:0,run:0,text:"")
        let empty=try engine.load(blank,page:0,width:612)
        precondition(empty.pages[0].runs[0].text.isEmpty)
        let second=try engine.load(original,page:1,width:612)
        precondition(second.pages[1].runs[0].text=="Notes for tomorrow")
        var marked=original
        for kind in MarkupKind.allCases {
            let column=Int(kind.rawValue)%3, row=Int(kind.rawValue)/3
            let x=Double(50+column*180), y=Double(60+row*100)
            let points = kind == .polygon ? [CGPoint(x:x,y:y),CGPoint(x:x+130,y:y),CGPoint(x:x+65,y:y+60)] : [CGPoint(x:x,y:y),CGPoint(x:x+130,y:y+60)]
            let mark=Markup(kind:kind,points:points,rect:.zero,text:kind.isText ? "A note":"",style:MarkupStyle.initial(for:kind))
            marked=try engine.annotate(marked,page:0,marks:[mark])
        }
        let all=try engine.load(marked,page:0,width:612)
        precondition(all.pages[0].annotations.count==18)
        var moved=all.pages[0].annotations[0].translated(x:10,y:10)
        let oldColor=moved.style.cValue.stroke
        moved=moved.scaled(to:CGRect(x:70,y:80,width:140,height:90))
        let updated=try engine.annotate(marked,page:0,marks:[moved])
        let verify=try engine.load(updated,page:0,width:612)
        let savedMark=verify.pages[0].annotations[0]
        precondition(abs(savedMark.geometryBounds.width-140)<0.0001 && abs(savedMark.geometryBounds.height-90)<0.0001)
        precondition(abs(savedMark.style.cValue.stroke.0-oldColor.0)<0.000001)
        let deleted=try engine.annotate(updated,page:0,marks:[],deleting:[moved.id])
        let fewer=try engine.load(deleted,page:0,width:612)
        precondition(fewer.pages[0].annotations.count==17)
        try marked.write(to:URL(fileURLWithPath:CommandLine.arguments[2]).deletingLastPathComponent().appendingPathComponent("annotations.pdf"))
        try edited.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("Swift engine: two pages, edit, original preserved, overflow, empty replacement and reopen passed")
    }
}
