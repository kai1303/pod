import AppKit
import PDFKit

@main struct CommentIconChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine(), metal=MetalPageRenderer()!, gpu=try Engine(metal:metal)
        var previews:[String:Data]=[:]
        for name in ["Note","Comment","Key","Help","NewParagraph","Paragraph","Insert","Unknown","Default"] {
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let loaded=try cpu.openPage(bytes,page:0,width:160)
            let mark=loaded.pages[0].annotations[0]
            precondition(mark.importedComment && !mark.canChangeAppearance && !mark.inkLocked)
            let source=loaded.source!
            var firstCount:Int?
            for zoom in [0.5,1,2] {
                let width=Int(160*zoom)
                let expected=try cpu.pageViewPixels(source,page:0,width:width,zoom:zoom)
                let actual=try gpu.pageViewPixels(source,page:0,width:width,zoom:zoom)
                precondition(zip(expected.data,actual.data).allSatisfy { abs(Int($0)-Int($1)) <= 1 })
                let values=[UInt8](expected.data)
                let count=stride(from:0,to:values.count,by:4).filter { Array(values[$0..<$0+3]) != [51,102,204] }.count
                precondition(count > 50)
                if let firstCount { precondition(count==firstCount,"Icon scaled with zoom") } else { firstCount=count }
                bytes.withUnsafeBytes { raw in
                    let handle=pod_open(raw.bindMemory(to:UInt8.self).baseAddress!,bytes.count)!
                    defer { pod_close(handle) }
                    precondition(metal.pageView(document:handle,page:0,fonts:[],width:width,zoom:zoom,rotation:0) != nil)
                }
            }
            let preview=try cpu.annotationAppearance(source,page:0,annotation:mark.id,width:144)
            previews[name]=preview.data
            try NSBitmapImageRep(cgImage:preview.cgImage!).representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
            var edited=mark;edited.text="Fallback note ✓"
            let saved=try cpu.annotate(bytes,page:0,marks:[edited])
            try saved.write(to:root.appendingPathComponent(name+"-edited.pdf"))
            let reopened=try cpu.openPage(saved,page:0,width:160)
            precondition(reopened.pixels.data==loaded.pixels.data && reopened.pages[0].annotations[0].text==edited.text)
            precondition(PDFDocument(data:saved)!.page(at:0)!.annotations.contains { $0.contents==edited.text })
            print("PASS: \(name) fallback icon, CPU/Metal, fixed size, note edit and independent PDFKit reopen")
        }
        precondition(previews["Note"]==previews["Unknown"] && previews["Note"]==previews["Default"])
        precondition(Set(previews.filter { !["Unknown","Default"].contains($0.key) }.map(\.value)).count==7)
    }
}
