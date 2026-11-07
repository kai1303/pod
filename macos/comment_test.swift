import AppKit
import PDFKit

@main struct CommentChecks {
    static func checkAppearance(_ bytes: Data, name: String, root: URL) throws {
        let cpu = try Engine(), metal = MetalPageRenderer()!, gpu = try Engine(metal:metal)
        let source = try PDFPageIndex(bytes)
        let info = try cpu.previewInfo(source,page:0)
        let id = info.annotations[0].id
        for width in [24,48,96] {
            let expected = try cpu.annotationAppearance(source,page:0,annotation:id,width:width)
            let actual = try gpu.annotationAppearance(source,page:0,annotation:id,width:width)
            precondition(expected.width == actual.width && expected.height == actual.height)
            precondition(zip(expected.data,actual.data).allSatisfy{abs(Int($0)-Int($1)) <= 1})
            let png = NSBitmapImageRep(cgImage:expected.cgImage!).representation(using:.png,properties:[:])!
            try png.write(to:root.appendingPathComponent("\(name)-appearance-\(width).png"))
            // Require the Metal collection path itself, rather than a CPU fallback.
            bytes.withUnsafeBytes { raw in
                let index = pod_index_open(raw.bindMemory(to:UInt8.self).baseAddress,bytes.count)!
                defer { pod_index_close(index) }
                let page = pod_index_open_page(index,0)!
                defer { pod_close(page) }
                precondition(metal.annotationAppearance(document:page,page:0,annotation:id,fonts:[],width:width) != nil)
                var output = PodBitmap()
                precondition(pod_render_annotation_appearance_with_fonts(page,0,UInt32.max,nil,0,UInt32(width),&output) == 0 && output.data == nil && output.length == 0)
            }
        }
        print("PASS: \(name) normal appearance CPU/Metal previews at 24/48/96 pixels")
    }
    static func checkPageView(_ root: URL) throws {
        let bytes = try Data(contentsOf:root.appendingPathComponent("page-view.pdf"))
        let source = try PDFPageIndex(bytes)
        let cpu = try Engine(), metal = MetalPageRenderer()!, gpu = try Engine(metal:metal)
        for rotation in [0,90,180,270] {
            for zoom in [0.5,1.0,2.0] {
                for density in [1,2] {
                    let width = Int(Double(rotation % 180 == 0 ? 140 : 160)*zoom*Double(density))
                    let expected = try cpu.pageViewPixels(source,page:0,width:width,zoom:zoom,rotation:rotation)
                    let actual = try gpu.pageViewPixels(source,page:0,width:width,zoom:zoom,rotation:rotation)
                    precondition(expected.width == actual.width && expected.height == actual.height)
                    let error = zip(expected.data,actual.data).map { abs(Int($0)-Int($1)) }.max()!
                    precondition(error <= 1,"CPU/Metal page-view difference \(error)")
                    let name = "page-view-r\(rotation)-z\(String(format:"%g",zoom))-d\(density)"
                    let png = NSBitmapImageRep(cgImage:expected.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent(name+".png"))
                    bytes.withUnsafeBytes { raw in
                        let index = pod_index_open(raw.bindMemory(to:UInt8.self).baseAddress,bytes.count)!
                        defer { pod_index_close(index) }
                        let page = pod_index_open_page(index,0)!
                        defer { pod_close(page) }
                        precondition(metal.pageView(document:page,page:0,fonts:[],width:width,zoom:zoom,rotation:rotation) != nil)
                        var output = PodBitmap(); output.length = 123
                        precondition(pod_render_page_view(page,0,nil,0,UInt32(width),0,0,&output) == 0 && output.data == nil && output.length == 0)
                        precondition(pod_render_page_view(page,0,nil,0,UInt32(width),zoom,45,&output) == 0 && output.data == nil)
                    }
                }
            }
        }
        let geometry = try cpu.previewInfo(source,page:0)
        precondition(geometry.rotation == 90,"View rotation changed PDF geometry")
        print("PASS: fixed comment icons, crop/rotation/zoom/density, transparency and overlapping appearances on CPU/Metal page views")
    }
    static func main() throws {
        setbuf(stdout,nil)
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        if CommandLine.arguments.contains("--page-view") { try checkPageView(root); return }
        if CommandLine.arguments.contains("--verify-imports") {
            for name in ["pdfkit","mupdf"] {
                let modified=try Data(contentsOf:root.appendingPathComponent(name+"-edited.pdf"))
                let page=PDFDocument(data:modified)!.page(at:0)!
                let note=page.annotations.first{$0.type=="Text"}!
                precondition(note.contents=="Cần dẫn chứng — 已阅" && note.userName=="Teacher")
                try checkAppearance(modified,name:name+"-edited",root:root)
                for width in [24,48,96] {
                    let before = try Data(contentsOf:root.appendingPathComponent("\(name)-appearance-\(width).png"))
                    let after = try Data(contentsOf:root.appendingPathComponent("\(name)-edited-appearance-\(width).png"))
                    precondition(before == after,"Note-only edit changed the normal appearance preview")
                }
                let removed=try Data(contentsOf:root.appendingPathComponent(name+"-removed.pdf"))
                precondition(PDFDocument(data:removed)!.page(at:0)!.annotations.isEmpty)
                print("PASS: independent PDFKit imported-comment edit, author and popup removal for \(name)")
            }
            return
        }
        let sample=try Data(contentsOf:root.appendingPathComponent("sample.pdf"))
        let engine=try Engine(), gpu=try Engine(metal:MetalPageRenderer()!)
        let original="Bài học ✓ 😀",replacement="Cần dẫn chứng — 已阅"
        let mark=Markup(kind:.comment,points:[CGPoint(x:100,y:500),CGPoint(x:124,y:524)],rect:.zero,text:original,style:.initial(for:.comment))
        let created=try engine.annotate(sample,page:0,marks:[mark])
        let loaded=try engine.load(created,page:0,width:612)
        precondition(loaded.pages[0].annotations[0].text==original)
        let pageView = try engine.pageViewPixels(PDFPageIndex(created),page:0,width:612,zoom:1)
        precondition(pageView.data == loaded.pixels.data,"Pod comment AP differs from canonical rendering at 100%")
        let accelerated=try gpu.load(created,page:0,width:612)
        precondition(accelerated.metalPage != nil)
        var edited=loaded.pages[0].annotations[0];edited.text=replacement
        let revised=try engine.annotate(created,page:0,marks:[edited])
        let reopened=try engine.load(revised,page:0,width:612)
        precondition(reopened.pages[0].annotations[0].text==replacement)
        precondition(loaded.pixels.data==reopened.pixels.data)
        precondition(PDFDocument(data:revised)!.page(at:0)!.annotations[0].contents==replacement)
        try created.write(to:root.appendingPathComponent("pod.pdf"))
        try revised.write(to:root.appendingPathComponent("pod-edited.pdf"))
        print("PASS: native Unicode comment creation/edit/save, unchanged icon pixels, Metal and independent PDFKit reopening")

        let foreign=PDFDocument(data:sample)!
        let note=PDFAnnotation(bounds:CGRect(x:100,y:500,width:24,height:24),forType:.text,withProperties:nil)
        note.contents=original;note.userName="Teacher";note.iconType = .note;note.color = .systemYellow
        foreign.page(at:0)!.addAnnotation(note)
        precondition(foreign.write(to:root.appendingPathComponent("pdfkit.pdf")))
        let appearances=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("appearance-cases.json"))) as! [String]
        for name in appearances {
            let bytes=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            try checkAppearance(bytes,name:name,root:root)
            let opened = try engine.load(bytes,page:0,width:612)
            let expected = try engine.pageViewPixels(PDFPageIndex(bytes),page:0,width:612,zoom:1)
            precondition(opened.pixels.data == expected.data,"Native opening differs from explicit comment view")
            var mark = opened.pages[0].annotations[0]
            mark.text = "Native comment edit ✓"
            let edited = try engine.annotate(bytes,page:0,marks:[mark])
            let reopened = try engine.load(edited,page:0,width:612)
            precondition(reopened.pages[0].annotations[0].text == mark.text)
            precondition(reopened.pixels.data == opened.pixels.data,"Note edit changed appearance")
            print("PASS: \(name) native open, note editing and unchanged appearance")
        }
    }
}
