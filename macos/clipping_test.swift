import AppKit
import Metal

@main struct ClippingChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine()
        guard let renderer=MetalPageRenderer() else { fatalError("Metal required for clipping checks") }
        let gpu=try Engine(metal:renderer)
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            .filter { $0.pathExtension=="pdf" && !$0.lastPathComponent.contains("-saved") && !$0.lastPathComponent.contains("-annotated") && !$0.lastPathComponent.contains("-rotated") }.sorted { $0.path < $1.path }
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
                    guard let page=loaded.metalPage,let pixels=page.bitmap(width:width) else { fatalError("Expected Metal clipping path") }
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
    }
}
