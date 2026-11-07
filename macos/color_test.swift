import AppKit
import Metal

@main struct ColorChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [[String:Any]]
        let cpu=try Engine()
        guard let renderer=MetalPageRenderer() else { fatalError("Metal required") }
        let gpu=try Engine(metal:renderer)
        for test in cases {
            let name=test["name"] as! String
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let saved=try cpu.annotate(bytes,page:0,marks:[])
            let edited=try cpu.replace(bytes,page:0,run:0,text:"Ink")
            var tail: CGRect?
            for (suffix,data) in [("",bytes),("-saved",saved),("-edited",edited)] {
                let expected=try cpu.load(data,page:0,width:612)
                guard expected.pixels.cgImage?.colorSpace?.name == CGColorSpace.sRGB else { print("FAIL: rendered pixels are not tagged sRGB"); exit(1) }
                let actual=try gpu.openPage(data,page:0,width:612)
                guard let pixels=actual.metalPage?.bitmap(width:612) else { fatalError("Metal scene missing") }
                var different=0,worst=0
                for (a,b) in zip(pixels.data,expected.pixels.data) {
                    let delta=abs(Int(a)-Int(b));worst=max(worst,delta)
                    if delta>1 { different += 1 }
                }
                precondition(pixels.data.count==expected.pixels.data.count && worst<=32 && different<=max(8,pixels.data.count/2000))
                let next=expected.pages[0].runs[1].bounds
                if let tail { precondition(next==tail) } else { tail=next }
                precondition(expected.pages[0].runs[0].text==(suffix=="-edited" ? "Ink":"Color"))
                try data.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                let png=NSBitmapImageRep(cgImage:expected.pixels.cgImage!).representation(using:.png,properties:[:])!
                try png.write(to:root.appendingPathComponent(name+suffix+".png"))
            }
            print("PASS: \(name) native full/indexed reads, CPU/Metal, save and text replacement")
        }
        for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where file.pathExtension=="pdf" && file.lastPathComponent.hasPrefix("invalid-") {
            do { _=try cpu.load(Data(contentsOf:file),page:0,width:100);fatalError("Accepted \(file.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(Data(contentsOf:file),page:0,width:100);fatalError("Indexed accepted \(file.lastPathComponent)") } catch is EngineError {}
        }
        let mutations=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension=="pdf" && $0.lastPathComponent.hasPrefix("mutation-") }
        for file in mutations {
            do { _=try cpu.load(Data(contentsOf:file),page:0,width:100) } catch is EngineError {}
        }
        print("PASS: malformed color fixtures rejected; \(mutations.count) color mutations reached native parsing/rendering without crashes")
    }
}
