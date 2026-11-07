import AppKit
import Metal

private final class PaintModes { var modes: Set<UInt32> = [] }

@main struct BlendChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine()
        guard let renderer=MetalPageRenderer() else { fatalError("Metal required for graphics-state checks") }
        let gpu=try Engine(metal:renderer)
        let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [[String:Any]]
        let files=cases.map { root.appendingPathComponent(($0["name"] as! String)+".pdf") }
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
        let ids: [PodBlendMode] = [POD_BLEND_NORMAL,POD_BLEND_MULTIPLY,POD_BLEND_SCREEN,POD_BLEND_OVERLAY,POD_BLEND_DARKEN,POD_BLEND_LIGHTEN,POD_BLEND_COLOR_DODGE,POD_BLEND_COLOR_BURN,POD_BLEND_HARD_LIGHT,POD_BLEND_SOFT_LIGHT,POD_BLEND_DIFFERENCE,POD_BLEND_EXCLUSION,POD_BLEND_HUE,POD_BLEND_SATURATION,POD_BLEND_COLOR,POD_BLEND_LUMINOSITY]
        for (index,mode) in ["Normal","Multiply","Screen","Overlay","Darken","Lighten","ColorDodge","ColorBurn","HardLight","SoftLight","Difference","Exclusion","Hue","Saturation","Color","Luminosity"].enumerated() {
            let bytes=try Data(contentsOf:root.appendingPathComponent(mode+"-1.pdf"))
            let doc=bytes.withUnsafeBytes { pod_open($0.bindMemory(to:UInt8.self).baseAddress,bytes.count) }!
            defer { pod_close(doc) }
            let modes=PaintModes()
            let retained=Unmanaged.passRetained(modes)
            defer { retained.release() }
            var height:UInt32=0,hairlines=false
            let ok=pod_collect_compositing_paints(doc,0,nil,0,612,retained.toOpaque(),{ context,_,_,_,_,_,mode,_ in
                Unmanaged<PaintModes>.fromOpaque(context!).takeUnretainedValue().modes.insert(mode);return true
            },&height,&hairlines)
            precondition(ok==1 && height==792 && modes.modes==Set([0,ids[index].rawValue]))
            let legacy=pod_collect_paints_with_state(doc,0,nil,0,612,retained.toOpaque(),{ _,_,_,_,_,_,_,_ in true },&height,&hairlines)
            precondition(legacy == (index<=1 ? 1:0))
        }
        print("PASS: all blend-mode ids cross the C bridge; older callbacks reject unrepresentable modes")
    }
}
