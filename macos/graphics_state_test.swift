import AppKit
import Metal

private final class PaintGroups { var ids: [UInt32] = [] }

@main struct GraphicsStateChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine()
        guard let renderer=MetalPageRenderer() else { fatalError("Metal required for graphics-state checks") }
        let gpu=try Engine(metal:renderer)
        let names=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String]
        let files=names.map { root.appendingPathComponent($0+".pdf") }
        for file in files {
            let name=file.deletingPathExtension().lastPathComponent
            let original=try Data(contentsOf:file)
            let saved=try cpu.annotate(original,page:0,marks:[])
            var style=MarkupStyle.initial(for:.rectangle)
            style.fill = .black;style.stroke = .black
            let note=Markup(kind:.rectangle,points:[CGPoint(x:540,y:680),CGPoint(x:580,y:720)],rect:.zero,style:style)
            let annotated=try cpu.annotate(original,page:0,marks:[note])
            let cropped=try cpu.crop(original,page:0,box:CGRect(x:40,y:60,width:520,height:680))
            let rotated=try cpu.rotate(cropped,page:0,degrees:90)
            for (suffix,bytes) in [("",original),("-saved",saved),("-annotated",annotated),("-rotated",rotated)] {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                for width in [612,1224] {
                    let reference=try cpu.load(bytes,page:0,width:width)
                    let loaded=try gpu.openPage(bytes,page:0,width:width)
                    guard let page=loaded.metalPage,let pixels=page.bitmap(width:width) else { fatalError("Expected Metal graphics-state path") }
                    var different=0,worst=0
                    for (a,b) in zip(reference.pixels.data,pixels.data) {
                        let delta=abs(Int(a)-Int(b));worst=max(worst,delta)
                        if delta>1 { different += 1 }
                    }
                    precondition(reference.pixels.data.count==pixels.data.count)
                    precondition(worst<=32 && different<=max(8,pixels.data.count/2000),"\(name)\(suffix) CPU/Metal: \(different), worst \(worst)")
                    let png=NSBitmapImageRep(cgImage:reference.pixels.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width).png"))
                }
            }
            print("PASS: \(name) CPU/Metal and indexed native opening at 1x/2x")
        }
        for file in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("invalid"),includingPropertiesForKeys:nil) {
            do { _=try cpu.load(Data(contentsOf:file),page:0,width:100);fatalError("Accepted \(file.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(Data(contentsOf:file),page:0,width:100);fatalError("Indexed open accepted \(file.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: unsupported/malformed graphics states rejected by full and indexed native opening")
        for name in ["text-knockout","text-composite","text-distinct-objects","opaque-text"] {
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let doc=bytes.withUnsafeBytes { pod_open($0.bindMemory(to:UInt8.self).baseAddress,bytes.count) }!
            defer { pod_close(doc) }
            let groups=PaintGroups()
            // Retain the callback context for the full synchronous collection.
            let retained=Unmanaged.passRetained(groups)
            defer { retained.release() }
            var height:UInt32=0,hairlines=false
            let ok=pod_collect_paints_with_state(doc,0,nil,0,612,retained.toOpaque(),{ context,_,_,_,_,_,_,group in
                Unmanaged<PaintGroups>.fromOpaque(context!).takeUnretainedValue().ids.append(group);return true
            },&height,&hairlines)
            precondition(ok==1 && height==792 && groups.ids.count==3)
            if name=="text-composite" { precondition(groups.ids==[0,0,0]) }
            else { precondition(groups.ids[1]>0 && (groups.ids[1]==groups.ids[2]) == (name != "text-distinct-objects")) }
            let legacy=pod_collect_paints_with_fonts(doc,0,nil,0,612,retained.toOpaque(),{ _,_,_,_,_,_,_ in true },&height,&hairlines)
            precondition(legacy == ((name=="opaque-text" || name=="text-composite") ? 1:0))
        }
        print("PASS: knockout group boundaries cross the C bridge; legacy collectors reject unsupported compositing")
    }
}
