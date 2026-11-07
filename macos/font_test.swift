import AppKit
import PDFKit

@main struct FontChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let out = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine = try Engine()
        let metal = MetalPageRenderer()!
        let fonts = SystemPDFFonts.shared.sources
        precondition(fonts.count == 14)
        let names = ["Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
                     "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique",
                     "Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic", "Symbol", "ZapfDingbats"]
        for name in names {
            let data = try Data(contentsOf:out.appendingPathComponent(name+".pdf"))
            let eager = try engine.load(data,page:0,width:612)
            let indexed = try engine.openPage(data,page:0,width:612)
            precondition(eager.pixels.data == indexed.pixels.data)
            precondition(indexed.pages[0].runs.count >= 149)
            precondition(indexed.pages[0].runs.allSatisfy { $0.fontName == name })
            precondition(indexed.pixels.data.filter { $0 < 128 }.count > 1000)
            try NSBitmapImageRep(cgImage:indexed.pixels.cgImage!).representation(using:.png,properties:[:])!
                .write(to:out.appendingPathComponent(name+"-native.png"))
            let handle = data.withUnsafeBytes { pod_open($0.bindMemory(to:UInt8.self).baseAddress!,data.count) }!
            defer { pod_close(handle) }
            guard let scene = metal.scene(document:handle,page:0,fonts:fonts,width:612), let image = scene.bitmap(width:612) else {
                fatalError("Metal paint collection failed for \(name): \(String(cString:pod_error()))")
            }
            precondition(image.data.filter { $0 < 128 }.count > 1000)
            var different = 0, worst = 0
            for (a,b) in zip(image.data,indexed.pixels.data) {
                let delta = abs(Int(a)-Int(b))
                if delta > 1 { different += 1 }
                worst = max(worst,delta)
            }
            precondition(image.data.count == indexed.pixels.data.count && worst <= 32 && different <= image.data.count/2000,
                         "CPU/Metal mismatch in \(name): \(different) channels, worst \(worst)")
            var bounds = PodBounds()
            precondition(pod_page_content_bounds_with_fonts(handle,0,fonts,fonts.count,&bounds) != 0 && bounds.present == 1)
            precondition(bounds.rect.0 >= 20 && bounds.rect.2 < 610 && bounds.rect.1 >= 20 && bounds.rect.3 < 790)
            var bitmap = PodBitmap()
            precondition(pod_render_with_fonts(handle,0,nil,15,612,&bitmap) == 0)
            precondition(String(cString:pod_error()) == "InvalidFontSource" && bitmap.data == nil)
            precondition(pod_render_with_fonts(handle,0,[fonts[0],fonts[0]],2,612,&bitmap) == 0)
            precondition(String(cString:pod_error()) == "InvalidFontSource")
            precondition(pod_render_with_fonts(handle,0,nil,0,612,&bitmap) == 0)
            precondition(String(cString:pod_error()) == "MissingRenderFont")
            if name == "Courier" {
                for invalid in [PodFontSource(face:14,data:fonts[0].data,length:fonts[0].length),
                                PodFontSource(face:0,data:nil,length:1),
                                PodFontSource(face:0,data:fonts[0].data,length:0),
                                PodFontSource(face:0,data:fonts[0].data,length:64*1024*1024+1)] {
                    precondition(pod_render_with_fonts(handle,0,[invalid],1,612,&bitmap) == 0)
                    precondition(String(cString:pod_error()) == "InvalidFontSource")
                }
                precondition(pod_render_with_fonts(handle,0,nil,1,612,&bitmap) == 0)
                precondition(String(cString:pod_error()) == "InvalidFontSource")
            }
            print("PASS: \(name) glyph grid, CPU/indexed rendering, Metal paints and content bounds")
        }
        for name in ["win-ansi","mac-roman","standard","differences","widths"] {
            let bytes = try Data(contentsOf:out.appendingPathComponent(name+".pdf"))
            let expected = try String(contentsOf:out.appendingPathComponent(name+".txt"),encoding:.utf8)
            let loaded = try engine.load(bytes,page:0,width:612)
            precondition(loaded.pages[0].runs[0].text == expected, name)
            let replacement = name == "differences" ? "é" : name == "widths" ? "B" : name == "standard" ? "ﬁ" : "é"
            let saved = try engine.replace(bytes,page:0,run:0,text:replacement)
            let reopened = try engine.openPage(saved,page:0,width:612)
            precondition(reopened.pages[0].runs[0].text == replacement)
            precondition(abs(reopened.pages[0].runs[1].bounds.minX-loaded.pages[0].runs[1].bounds.minX) < 0.00001)
            let source = PDFDocument(data:bytes)!.page(at:0)!
            let foreign = PDFDocument(data:saved)!.page(at:0)!
            precondition(foreign.string!.hasPrefix(replacement.replacingOccurrences(of:"ﬁ",with:"fi")) || foreign.string!.hasPrefix(replacement), name)
            let a = (source.string! as NSString).range(of:"tail")
            let b = (foreign.string! as NSString).range(of:"tail")
            precondition(a.location != NSNotFound && b.location != NSNotFound)
            let originalTail = source.selection(for:a)!.bounds(for:source)
            let savedTail = foreign.selection(for:b)!.bounds(for:foreign)
            precondition(abs(originalTail.minX-savedTail.minX) < 0.01, name)
            try saved.write(to:out.appendingPathComponent(name+"-edited.pdf"))
            do {
                _ = try engine.replace(bytes,page:0,run:0,text:"😀")
                fatalError("Unrepresentable edit accepted")
            } catch is EngineError { }
            let unchanged = try engine.load(bytes,page:0,width:612)
            precondition(unchanged.pages[0].runs[0].text == expected)
            print("PASS: \(name) extraction, UTF-8 edit, position preservation and independent PDFKit reopen")
        }
        for name in ["invalid-differences","invalid-widths","negative-width"] {
            let data = try Data(contentsOf:out.appendingPathComponent(name+".pdf"))
            let handle = data.withUnsafeBytes { pod_open($0.bindMemory(to:UInt8.self).baseAddress!,data.count) }
            precondition(handle == nil, name)
        }
        print("PASS: malformed encodings and widths fail explicitly")
    }
}
