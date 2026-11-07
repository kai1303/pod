import AppKit
import Metal
import PDFKit

@main struct CodecImageChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine(),gpu=try Engine(metal:MetalPageRenderer()!)
        let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String:[String:Int]]
        for name in cases.keys.sorted() {
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf")),width=cases[name]!["width"]!
            let expected=try cpu.load(bytes,page:0,width:width)
            precondition(expected.pixels.height==cases[name]!["height"]!)
            let indexed=try gpu.openPage(bytes,page:0,width:width)
            guard let scene=indexed.metalPage,let pixels=scene.bitmap(width:width) else {fatalError("Encoded image fell back to CPU")}
            precondition(expected.pixels.data==pixels.data)
            let png=NSBitmapImageRep(cgImage:expected.pixels.cgImage!).representation(using:.png,properties:[:])!
            try png.write(to:root.appendingPathComponent(name+"-samples.png"))
            let saved=try cpu.annotate(bytes,page:0,marks:[])
            let copy=try cpu.load(saved,page:0,width:width)
            precondition(copy.pixels.data==expected.pixels.data)
            precondition(PDFDocument(data:saved)?.pageCount==1)
            try saved.write(to:root.appendingPathComponent(name+"-saved.pdf"))
            let assembled=try cpu.selectPages(cpu.merge(bytes,with:bytes),indices:[1])
            let page=try cpu.load(assembled,page:0,width:width)
            precondition(page.pixels.data==expected.pixels.data)
            print("PASS: \(name) CPU/Metal, indexed reads, save/reopen and page assembly")
        }
        let invalid=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("invalid.json"))) as! [String]
        for name in invalid {
            let file=root.appendingPathComponent("invalid/"+name+".pdf")
            let bytes=try Data(contentsOf:file)
            do {_=try cpu.load(bytes,page:0,width:100);fatalError("Accepted \(file.lastPathComponent)")} catch is EngineError {}
            do {_=try gpu.openPage(bytes,page:0,width:100);fatalError("Indexed accepted \(file.lastPathComponent)")} catch is EngineError {}
        }
        print("PASS: malformed and unsupported encoded images rejected through full/indexed handles")
    }
}
