import AppKit
import PDFKit

@main struct UnicodeChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine = try Engine()
        let gpu = try Engine(metal:MetalPageRenderer()!)
        let plain = try Data(contentsOf:root.appendingPathComponent("plain.pdf"))
        let reference = try engine.load(plain,page:0,width:612)
        let cases = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as! [[String:String]]
        for item in cases {
            let name = item["name"]!, expected = item["text"]!, replacement = item["replacement"]!
            let bytes = try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let loaded = try engine.openPage(bytes,page:0,width:612)
            precondition(loaded.pages[0].runs[0].text == expected)
            precondition(loaded.pixels.data == reference.pixels.data,"Unicode metadata changed glyph rendering")
            let accelerated = try gpu.load(bytes,page:0,width:612)
            precondition(accelerated.metalPage != nil)
            precondition(accelerated.pages[0].runs[0].text == expected)
            let baselineGPU = try gpu.load(plain,page:0,width:612)
            precondition(accelerated.pixels.data == baselineGPU.pixels.data)
            let originalPage = PDFDocument(data:bytes)!.page(at:0)!
            let pdfkitMapsUnicode = originalPage.string!.contains("😀")
            if !pdfkitMapsUnicode {
                // CoreGraphics explicitly reports that embedded UseCMap is unsupported.
                // MuPDF checks this fixture's Unicode text separately in unicode_check.py.
                precondition(name == "inherited" && originalPage.string == "fiéCDEFGH tail")
                print("PDFKit does not resolve inherited UseCMap; MuPDF is the Unicode oracle for this case")
            }
            let edited = try engine.replace(bytes,page:0,run:0,text:replacement)
            let reopened = try engine.openPage(edited,page:0,width:612)
            precondition(reopened.pages[0].runs[0].text == replacement)
            precondition(abs(reopened.pages[0].runs[1].bounds.minX-loaded.pages[0].runs[1].bounds.minX)<1e-7)
            let foreign = PDFDocument(data:edited)!.page(at:0)!
            if pdfkitMapsUnicode { precondition(foreign.string!.hasPrefix(replacement),"Independent saved-text mismatch: \(foreign.string!)") }
            let sourceTail = (originalPage.string! as NSString).range(of:"tail")
            let savedTail = (foreign.string! as NSString).range(of:"tail")
            precondition(sourceTail.location != NSNotFound && savedTail.location != NSNotFound)
            precondition(abs(originalPage.selection(for:sourceTail)!.bounds(for:originalPage).minX - foreign.selection(for:savedTail)!.bounds(for:foreign).minX)<0.01)
            let mark = Markup(kind:.highlight,points:[CGPoint(x:72,y:695),CGPoint(x:175,y:717)],rect:.zero,style:.initial(for:.highlight))
            let annotated = try engine.annotate(edited,page:0,marks:[mark])
            let marked = try engine.load(annotated,page:0,width:612)
            precondition(marked.pages[0].annotations.count == 1 && marked.pages[0].runs[0].text == replacement)
            let independent = PDFDocument(data:annotated)!.page(at:0)!
            if pdfkitMapsUnicode { precondition(independent.string!.hasPrefix(replacement)) }
            precondition(independent.annotations.contains { $0.type == "Highlight" })
            try annotated.write(to:root.appendingPathComponent(name+"-annotated.pdf"))
            // Repeated indexed reads borrow map data only from the live page arena.
            for _ in 0..<3 {
                let again = try engine.turnPage(loaded,page:0,width:612)
                precondition(again.pages[0].runs[0].text == expected && again.pixels.data == reference.pixels.data)
            }
            print("PASS: \(name), unchanged CPU/Metal glyphs, Unicode extraction/edit, annotation save, indexed reads and PDFKit positions (Unicode mapping: \(pdfkitMapsUnicode))")
        }
    }
}
