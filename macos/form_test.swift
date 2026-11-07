import AppKit
import Metal

@main struct FormChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine()
        guard let renderer=MetalPageRenderer() else { fatalError("Metal required for Form checks") }
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
            var variants = [("",original),("-saved",saved),("-annotated",annotated),("-rotated",rotated)]
            let merged = try cpu.merge(original,with:original)
            let reordered = try cpu.selectPages(merged,indices:[1,0])
            let organized = try cpu.selectPages(reordered,indices:[0])
            variants.append(("-organized",organized))
            if name == "text" || name == "nested-text" {
                let before = try cpu.load(original,page:0,width:100).pages[0].runs
                let edited = try cpu.replace(original,page:0,run:0,text:"A")
                let after = try cpu.load(edited,page:0,width:100).pages[0].runs
                precondition(after.map(\.text) == ["A","BA"])
                precondition(before[1].bounds == after[1].bounds)
                variants.append(("-edited",edited))
            }
            if name == "reused-text" {
                do { _ = try cpu.replace(original,page:0,run:0,text:"A");fatalError("Shared Form edited") } catch is EngineError {}
            }
            // Page views cannot prove whether another page shares the edited stream.
            original.withUnsafeBytes { raw in
                let index = pod_index_open(raw.bindMemory(to:UInt8.self).baseAddress,original.count)!
                defer { pod_index_close(index) }
                let page = pod_index_open_page(index,0)!
                defer { pod_close(page) }
                var byte: UInt8 = 72
                precondition(pod_replace(page,0,0,&byte,1) == 0)
                precondition(String(cString:pod_error()) == "ReadOnlyPageView")
            }
            for (suffix,bytes) in variants {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                for width in [612,1224] {
                    let reference=try cpu.load(bytes,page:0,width:width)
                    let loaded=try gpu.openPage(bytes,page:0,width:width)
                    guard let page=loaded.metalPage,let pixels=page.bitmap(width:width) else { fatalError("Expected Metal Form path: \(name)\(suffix) width \(width)") }
                    if name == "dash-grid" && suffix.isEmpty && width == 612 {
                        let small=try cpu.load(bytes,page:0,width:61)
                        guard let preview=page.bitmap(width:61) else { fatalError("Tiled downsample failed") }
                        precondition(preview.data.count==small.pixels.data.count)
                        let delta=zip(preview.data,small.pixels.data).map { abs(Int($0)-Int($1)) }.max() ?? 0
                        guard delta<=1 else { fatalError("Tile halo changed a downsampled preview: \(delta)") }
                    }
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
        print("PASS: unsupported/malformed Forms rejected by full and indexed native opening")
    }
}
