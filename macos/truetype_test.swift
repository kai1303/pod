import AppKit
import PDFKit

struct FontFixture: Decodable { let name: String; let text: String; let replacement: String; let tail: String; var pdfkit: Bool? = nil; var pdfkitGeometry: Bool? = nil; var vertical: Bool? = nil }

@main struct TrueTypeChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine=try Engine(), gpu=try Engine(metal:MetalPageRenderer()!)
        let names=["unicode","mac-symbolic","mac-nonsymbolic","windows-symbolic","unicode-full","mac-format-zero","attached","scaled","without-unicode","reportlab"]
        let manifest=root.appendingPathComponent("cases.json")
        let cases = FileManager.default.fileExists(atPath:manifest.path)
            ? try JSONDecoder().decode([FontFixture].self,from:Data(contentsOf:manifest))
            : names.map { FontFixture(name:$0,text:$0 == "reportlab" ? "Students café — résumé" : "ABé",replacement:$0 == "reportlab" ? "café" : "é",tail:$0 == "reportlab" ? "tail" : "AB") }
        for fixture in cases {
            let name=fixture.name
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let expected=fixture.text
            let loaded=try engine.load(bytes,page:0,width:612)
            let indexed=try engine.openPage(bytes,page:0,width:612)
            precondition(indexed.pages[0].runs[0].text == expected)
            precondition(indexed.pixels.data == loaded.pixels.data)
            let accelerated=try gpu.load(bytes,page:0,width:612)
            precondition(accelerated.metalPage != nil)
            let actual=accelerated.metalPage!.bitmap(width:612)!.data
            var different=0,worst=0
            for (a,b) in zip(actual,loaded.pixels.data) {
                let delta=abs(Int(a)-Int(b));if delta>1 { different+=1 };worst=max(worst,delta)
            }
            precondition(worst<=32 && different<=actual.count/2000,"CPU/Metal mismatch")
            try NSBitmapImageRep(cgImage:loaded.pixels.cgImage!).representation(using:.png,properties:[:])!
                .write(to:root.appendingPathComponent(name+"-native.png"))
            if fixture.vertical == true {
                let large=try engine.load(bytes,page:0,width:2448)
                try NSBitmapImageRep(cgImage:large.pixels.cgImage!).representation(using:.png,properties:[:])!
                    .write(to:root.appendingPathComponent(name+"-native-4x.png"))
            }
            let handle=bytes.withUnsafeBytes {pod_open($0.bindMemory(to:UInt8.self).baseAddress!,bytes.count)}!
            defer {pod_close(handle)}
            var bitmap=PodBitmap()
            precondition(pod_render_with_fonts(handle,0,nil,0,612,&bitmap) != 0,"Embedded fonts unexpectedly require host font data")
            precondition(Data(bytes:bitmap.data!,count:bitmap.length)==loaded.pixels.data)
            pod_buffer_free(bitmap.data,bitmap.length)
            var bounds=PodBounds()
            precondition(pod_page_content_bounds_with_fonts(handle,0,nil,0,&bounds) != 0 && bounds.present==1)
            let replacement=fixture.replacement
            let saved=try engine.replace(bytes,page:0,run:0,text:replacement)
            let reopened=try engine.openPage(saved,page:0,width:612)
            precondition(reopened.pages[0].runs[0].text==replacement)
            precondition(reopened.pages[0].runs[1].bounds == loaded.pages[0].runs[1].bounds)
            if fixture.vertical == true {
                let large=try engine.load(saved,page:0,width:2448)
                try NSBitmapImageRep(cgImage:large.pixels.cgImage!).representation(using:.png,properties:[:])!
                    .write(to:root.appendingPathComponent(name+"-edited-native-4x.png"))
                let empty=try engine.replace(bytes,page:0,run:0,text:"")
                let emptyPage=try engine.openPage(empty,page:0,width:612)
                precondition(emptyPage.pages[0].runs[0].text.isEmpty)
                precondition(emptyPage.pages[0].runs[1].bounds==loaded.pages[0].runs[1].bounds)
                do { _=try engine.replace(bytes,page:0,run:0,text:expected+expected);fatalError("Vertical text overflow accepted") } catch is EngineError {}
            }
            let foreign=PDFDocument(data:saved)!.page(at:0)!
            if fixture.pdfkit != false {
            if fixture.vertical == true {
                let expectedText=(replacement+loaded.pages[0].runs.dropFirst().map{ $0.text }.joined()).filter{!$0.isWhitespace}
                precondition(foreign.string!.filter{!$0.isWhitespace}.sorted()==expectedText.sorted(),"PDFKit cannot read saved \(name)")
            } else {
                precondition(foreign.string!.hasPrefix(replacement),"PDFKit cannot read saved \(name)")
            }
            let originalPage=PDFDocument(data:bytes)!.page(at:0)!
            let tail=fixture.tail
            let oldRange=(originalPage.string! as NSString).range(of:tail,options:.backwards)
            let newRange=(foreign.string! as NSString).range(of:tail,options:.backwards)
            precondition(oldRange.location != NSNotFound && newRange.location != NSNotFound)
            let oldBox=originalPage.selection(for:oldRange)!.bounds(for:originalPage)
            let newBox=foreign.selection(for:newRange)!.bounds(for:foreign)
            if fixture.pdfkitGeometry != false {
                precondition(abs(oldBox.minX-newBox.minX)<1e-7 && abs(oldBox.width-newBox.width)<1e-7 && abs(oldBox.minY-newBox.minY)<1e-7 && abs(oldBox.height-newBox.height)<1e-7,"PDFKit following-text position changed")
            } else {
                print("PDFKit selection geometry is unreliable for this fixture; independent checks verify \(name) geometry")
            }
            } else {
                let original=PDFDocument(data:bytes)!.page(at:0)!.string
                let fullText=loaded.pages[0].runs.map{ $0.text }.joined().filter{!$0.isWhitespace}
                precondition(original?.filter{!$0.isWhitespace} != fullText,"PDFKit behavior changed; restore Unicode assertions")
                print("PDFKit cannot fully extract this Encoding CMap; independent checks verify \(name)")
            }
            let mark=Markup(kind:.rectangle,points:[CGPoint(x:60,y:690),CGPoint(x:320,y:735)],rect:.zero,style:.initial(for:.rectangle))
            let annotated=try engine.annotate(saved,page:0,marks:[mark])
            let checked=try engine.load(annotated,page:0,width:612)
            precondition(checked.pages[0].annotations.count==1 && checked.pages[0].runs[0].text==replacement)
            try saved.write(to:root.appendingPathComponent(name+"-edited.pdf"))
            try annotated.write(to:root.appendingPathComponent(name+"-annotated.pdf"))
            do { _=try engine.replace(bytes,page:0,run:0,text:"🦊");fatalError("Subset accepted missing glyph") } catch is EngineError {}
            print("PASS: \(name) embedded outlines, CPU/Metal, indexed reads, zero host fonts, text/annotation edits and independent-reader fixtures")
        }
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        let mutations=files.filter{$0.lastPathComponent.hasPrefix("mutation-") && $0.pathExtension == "pdf"}
        for path in mutations {
            let bytes=try Data(contentsOf:path)
            do { _=try engine.load(bytes,page:0,width:612) } catch is EngineError {}
        }
        print("PASS: \(mutations.count) malformed-font mutations reach extraction and native rasterization without crashes")
        let invalid=files.filter{($0.lastPathComponent.hasPrefix("invalid-") || $0.lastPathComponent.hasPrefix("unsupported-")) && $0.pathExtension == "pdf"}
        for path in invalid {
            let bytes=try Data(contentsOf:path)
            do { _=try engine.load(bytes,page:0,width:612);fatalError("Accepted malformed or unsupported font: \(path.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: \(invalid.count) malformed/unsupported font fixtures fail explicitly")
    }
}
