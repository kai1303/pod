import AppKit
import Metal
import PDFKit

@main struct ImageChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let metal=MetalPageRenderer()!
        let cpu=try Engine(), gpu=try Engine(metal:metal)
        let names=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String]
        for name in names {
            let original=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            precondition(PDFDocument(data:original)?.pageCount == 1)
            if name == "rgb" {
                original.withUnsafeBytes { bytes in
                    let doc=pod_open(bytes.bindMemory(to:UInt8.self).baseAddress,original.count)!
                    defer { pod_close(doc) }
                    var height:UInt32=123, hairlines=false
                    var context:UInt8=0
                    let paint:PodCompositePaintCallback={_,_,_,_,_,_,_,_ in true}
                    precondition(pod_collect_compositing_paints(doc,0,nil,0,200,&context,paint,&height,&hairlines)==0 && height==0)
                    precondition(String(cString:pod_error())=="UnsupportedImageCollection")
                }
            }
            if name == "appearance" {
                let source=try PDFPageIndex(original)
                let expected=try cpu.annotationAppearance(source,page:0,annotation:7,width:120)
                original.withUnsafeBytes { bytes in
                    let index=pod_index_open(bytes.bindMemory(to:UInt8.self).baseAddress,original.count)!
                    defer { pod_index_close(index) }
                    let doc=pod_index_open_page(index,0)!
                    defer { pod_close(doc) }
                    guard let scene=metal.annotationAppearance(document:doc,page:0,annotation:7,fonts:[],width:120),let pixels=scene.bitmap(width:120) else { fatalError("Image appearance fell back to CPU") }
                    precondition(expected.data==pixels.data)
                    var height:UInt32=123, hairlines=false, context:UInt8=0
                    let paint:PodCompositePaintCallback={_,_,_,_,_,_,_,_ in true}
                    let image:PodImagePaintCallback={_,_,_,_,_,_,_ in true}
                    precondition(pod_collect_image_scene(doc,0,7,nil,0,120,2,0,&context,paint,image,&height,&hairlines)==0 && height==0)
                    precondition(String(cString:pod_error())=="InvalidTransform")
                }
            }
            let saved=try cpu.annotate(original,page:0,marks:[])
            let rotated=try cpu.rotate(original,page:0,degrees:90)
            let organized=try cpu.selectPages(cpu.merge(original,with:original),indices:[1])
            var variants=[("",original),("-saved",saved),("-rotated",rotated),("-organized",organized)]
            if name == "inline-text" {
                let edited=try cpu.replace(cpu.replace(original,page:0,run:0,text:"Ink"),page:0,run:1,text:"Tail")
                let before=try cpu.load(original,page:0,width:200)
                let after=try cpu.load(edited,page:0,width:200)
                precondition(before.pages[0].runs.map(\.text)==["Before","After"])
                precondition(after.pages[0].runs.map(\.text)==["Ink","Tail"])
                precondition(before.pages[0].runs[1].bounds.origin==after.pages[0].runs[1].bounds.origin)
                variants.append(("-edited",edited))
            }
            for (suffix,bytes) in variants {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                for width in [200,400] {
                    let reference=try cpu.load(bytes,page:0,width:width)
                    let loaded=try gpu.openPage(bytes,page:0,width:width)
                    guard let page=loaded.metalPage, let pixels=page.bitmap(width:width) else { fatalError("Image used CPU fallback: \(name)") }
                    precondition(reference.pixels.data.count==pixels.data.count)
                    var different=0,worst=0
                    for (a,b) in zip(reference.pixels.data,pixels.data) {
                        let delta=abs(Int(a)-Int(b));worst=max(worst,delta)
                        if delta>1 { different += 1 }
                    }
                    // Float GPU transforms can choose the neighboring texel when a
                    // sample lies exactly on a sharp image boundary. Allow only sparse,
                    // one-pixel boundary differences, never a different interior color.
                    func hasNeighbor(_ source:Data, _ target:Data, at:Int) -> Bool {
                        let x=at/4%width, y=at/4/width, height=target.count/4/width
                        for dy in -1...1 { for dx in -1...1 {
                            let nx=x+dx, ny=y+dy
                            if nx<0 || nx>=width || ny<0 || ny>=height { continue }
                            let other=(ny*width+nx)*4
                            if (0..<3).allSatisfy({ abs(Int(source[at+$0])-Int(target[other+$0]))<=1 }) { return true }
                        } }
                        return false
                    }
                    if worst>32 {
                        for at in stride(from:0,to:pixels.data.count,by:4) {
                            if (0..<3).contains(where:{abs(Int(reference.pixels.data[at+$0])-Int(pixels.data[at+$0]))>32}) {
                                precondition(hasNeighbor(reference.pixels.data,pixels.data,at:at) && hasNeighbor(pixels.data,reference.pixels.data,at:at),"Image interior differs: \(name)\(suffix)")
                            }
                        }
                    }
                    precondition(different<=max(8,pixels.data.count/2000),"\(name)\(suffix) CPU/Metal: \(different), worst \(worst)")
                    let png=NSBitmapImageRep(cgImage:reference.pixels.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width).png"))
                }
            }
            print("PASS: \(name) CPU/Metal, indexed reads, save/reopen, rotation and page assembly")
        }
        for file in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("invalid"),includingPropertiesForKeys:nil) {
            let bytes=try Data(contentsOf:file)
            do { _=try cpu.load(bytes,page:0,width:200);fatalError("Accepted \(file.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(bytes,page:0,width:200);fatalError("Indexed accepted \(file.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: malformed and unsupported images rejected on full/indexed paths")
        let mutations=root.appendingPathComponent("mutations",isDirectory:true)
        if FileManager.default.fileExists(atPath:mutations.path) {
            let files=try FileManager.default.contentsOfDirectory(at:mutations,includingPropertiesForKeys:nil).filter { $0.pathExtension=="pdf" }
            for file in files {
                let bytes=try Data(contentsOf:file)
                do { _=try cpu.load(bytes,page:0,width:100) } catch is EngineError {}
                do { _=try gpu.openPage(bytes,page:0,width:100) } catch is EngineError {}
            }
            print("PASS: \(files.count) image mutations reached full/indexed native rendering without crashes")
        }
    }
}
