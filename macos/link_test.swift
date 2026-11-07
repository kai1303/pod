import AppKit
import PDFKit

@main struct LinkChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let out = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine = try Engine()
        for name in ["web-links", "relative-links"] {
            let bytes = try Data(contentsOf:out.appendingPathComponent(name+".pdf"))
            let eager = try engine.load(bytes,page:0,width:612)
            let indexed = try engine.openPage(bytes,page:0,width:612)
            precondition(eager.pixels.data == indexed.pixels.data)
            let links = indexed.pages[0].links
            precondition(links.count == 6 && indexed.pages[0].annotations.isEmpty)
            precondition(links[0].url?.absoluteString == "https://example.com/lesson")
            precondition(links[2].contains(CGPoint(x:100,y:630)))
            precondition(!links[2].contains(CGPoint(x:100,y:605)))
            precondition(links[2].contains(CGPoint(x:100,y:580)))
            precondition(links[3].url == nil && !links[3].contains(CGPoint(x:100,y:510)))
            precondition(links[4].url == nil)
            precondition(links[5].url?.absoluteString == (name == "relative-links" ? "https://example.com/course/chapter.html" : nil))
            // Reopening page views must not retain pointers into a closed view arena.
            for _ in 0..<3 {
                let next = try engine.turnPage(indexed,page:0,width:612)
                precondition(next.pages[0].links.map(\.uri) == links.map(\.uri))
                precondition(next.pages[0].links.map(\.base) == links.map(\.base))
            }
            let mark = Markup(kind:.rectangle,points:[CGPoint(x:280,y:640),CGPoint(x:360,y:680)],rect:.zero,style:.initial(for:.rectangle))
            let annotated = try engine.annotate(bytes,page:0,marks:[mark])
            let edited = try engine.replace(annotated,page:0,run:0,text:"Hi")
            let reopened = try engine.openPage(edited,page:0,width:612)
            precondition(reopened.pages[0].links.map(\.uri) == links.map(\.uri))
            precondition(reopened.pages[0].annotations.count == 1)
            try edited.write(to:out.appendingPathComponent(name+"-edited.pdf"))
            let nativeImage = NSBitmapImageRep(cgImage:reopened.pixels.cgImage!)
            try nativeImage.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+"-native.png"))
            let foreign = PDFDocument(data:edited)!
            let annotations = foreign.page(at:0)!.annotations.filter { $0.type == "Link" }
            precondition(annotations.count == 6)
            let lesson = annotations.first { ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.com/lesson" }!
            precondition(lesson.contents == "Keep this note")
            let image = foreign.page(at:0)!.thumbnail(of:CGSize(width:612,height:792),for:.mediaBox)
            let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+"-independent.png"))
            if name == "web-links" {
                let extracted = try engine.selectPages(edited,indices:[0])
                let extractedPage = try engine.load(extracted,page:0,width:612)
                precondition(extractedPage.pages[0].links.count == 6)
                try extracted.write(to:out.appendingPathComponent("extracted.pdf"))
                try checkClicks(indexed)
                // A separate reader/writer supplies a real foreign link annotation.
                let imported = PDFDocument(data:bytes)!
                let added = PDFAnnotation(bounds:CGRect(x:300,y:300,width:120,height:30),forType:.link,withProperties:nil)
                added.action = PDFActionURL(url:URL(string:"https://example.com/pdfkit")!)
                let border = PDFBorder(); border.lineWidth = 0; added.border = border
                imported.page(at:0)!.addAnnotation(added)
                let generated = imported.dataRepresentation()!
                try generated.write(to:out.appendingPathComponent("pdfkit-links.pdf"))
                let read = try engine.openPage(generated,page:0,width:612)
                precondition(read.pages[0].links.count == 7)
                precondition(read.pages[0].links.last!.uri == "https://example.com/pdfkit")
            }
        }
        try checkInternal(engine,out)
        for value in ["file:///tmp/secret", "javascript:alert(1)", "data:text/html,test", "https://example.com/\n"] {
            precondition(PageLink(id:1,rect:.zero,uri:value,base:"",quads:[],hidden:false).url == nil)
        }
        print("PASS: URI links, indexed pages, borders, quads, relative targets, inactive schemes, markup/text edits, extraction, independent PDFKit round trips and native clicks")
    }
    static func checkInternal(_ engine: Engine, _ out: URL) throws {
        let bytes = try Data(contentsOf:out.appendingPathComponent("destinations.pdf"))
        let document = try engine.openPage(bytes,page:0,width:612)
        let links = document.pages[0].links
        precondition(links.count == 11 && links.allSatisfy { $0.destination?.page == 1 && $0.isActive })
        precondition(links.prefix(8).enumerated().allSatisfy { $0.element.destination?.mode.rawValue == UInt32($0.offset) })
        precondition(links[8].destination?.mode == .fitH && links[9].destination?.mode == .xyz && links[10].destination?.mode == .fitB)
        let viewport=CGSize(width:800,height:600), point=CGPoint(x:80,y:680)
        for link in links {
            let result = try engine.followDestination(document,destination:link.destination!,viewport:viewport,
                                                     currentZoom:0.7,currentPoint:point,backingScale:1,viewRotation:0)
            precondition(result.0.pageIndex == 1 && result.0.pages[1].rotation == 90)
            precondition(result.0.pages[1].links[0].destination?.page == 0, "Indexed views must expose full-document page numbers")
            precondition(result.1.zoom.isFinite && result.1.anchor.x.isFinite && result.1.anchor.y.isFinite)
            if link.destination!.mode == .xyz {
                precondition(result.1.zoom == 1.5 && result.1.anchor == CGPoint(x:680,y:62))
            }
            if link.destination!.mode == .fitR {
                precondition(abs(result.1.zoom-2.48) < 0.00001 && result.1.anchor == CGPoint(x:230,y:162))
            }
        }
        let blank = PageInfo(box:CGRect(x:0,y:0,width:600,height:800),mediaBox:CGRect(x:0,y:0,width:600,height:800),rotation:0,runs:[],annotations:[])
        let unchanged = PageDestination(page:0,mode:.xyz,parameters:[nil,nil,nil,nil]).view(on:blank,viewport:viewport,currentZoom:0.7,currentPoint:point)
        precondition(unchanged.zoom == 0.7 && unchanged.anchor == CGPoint(x:80,y:120))
        let bbox = CGRect(x:50,y:70,width:100,height:30)
        let fitted = PageDestination(page:0,mode:.fitB,parameters:[nil,nil,nil,nil]).view(on:blank,viewport:CGSize(width:256,height:256),currentZoom:1,currentPoint:point,contentBounds:bbox)
        precondition(fitted.zoom == 2 && fitted.anchor == CGPoint(x:100,y:715))
        let changed = try engine.replace(bytes,page:0,run:0,text:"Index")
        let saved = try engine.openPage(changed,page:0,width:612)
        precondition(saved.pages[0].links[9].destination?.page == 1)
        try changed.write(to:out.appendingPathComponent("destinations-edited.pdf"))
        let foreign = PDFDocument(data:changed)!
        precondition(foreign.pageCount == 2 && foreign.page(at:0)!.annotations.count == 11)
        let originalReader = PDFDocument(data:bytes)!
        for (i, annotation) in foreign.page(at:0)!.annotations.enumerated() {
            let target = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
            if i == 8 {
                // PDFKit cannot resolve this legacy dictionary destination even
                // in the original fixture. The qpdf check verifies its target.
                let original = originalReader.page(at:0)!.annotations[i]
                let before = original.destination ?? (original.action as? PDFActionGoTo)?.destination
                if before?.page == nil { precondition(target?.page == nil) }
                else { precondition(target?.page.map { foreign.index(for:$0) } == 1) }
            } else {
                precondition(target?.page.map { foreign.index(for:$0) } == 1, "Independent reader must resolve the same target page")
            }
        }
        for name in ["destinations-objstm.pdf", "destinations-linearized.pdf"] {
            let url = out.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:url.path) {
                let encoded = try Data(contentsOf:url)
                let read = try engine.openPage(encoded,page:0,width:612)
                precondition(read.pages[0].links.map { $0.destination?.page } == links.map { $0.destination?.page })
                precondition(read.pages[0].links.map { $0.destination?.mode } == links.map { $0.destination?.mode })
                let edit = try engine.replace(encoded,page:0,run:0,text:"Index")
                let reopened = try engine.openPage(edit,page:0,width:612)
                precondition(reopened.pages[0].links[9].destination?.page == 1)
                print("PASS: destination lookup and save/reopen in \(name)")
            }
        }
        let directBytes = try Data(contentsOf:out.appendingPathComponent("direct-destinations.pdf"))
        let reordered = try engine.selectPages(directBytes,indices:[1,0])
        let reorderedFirst = try engine.openPage(reordered,page:0,width:612)
        let reorderedSecond = try engine.turnPage(reorderedFirst,page:1,width:612)
        precondition(reorderedFirst.pages[0].links[0].destination?.page == 1)
        precondition(reorderedSecond.pages[1].links.allSatisfy { $0.destination?.page == 0 })
        try reordered.write(to:out.appendingPathComponent("destinations-reordered.pdf"))
        let merged = try engine.merge(directBytes,with:directBytes)
        let mergedPage = try engine.openPage(merged,page:2,width:612)
        precondition(mergedPage.pages[2].links.allSatisfy { $0.destination?.page == 3 })
        do {
            _ = try engine.selectPages(directBytes,indices:[0])
            preconditionFailure("Extracting away an internal target must not leave a dangling link")
        } catch is EngineError {}
        // Exercise the actual canvas event route, target load, zoom and scroll.
        let canvas=PageCanvas(), scroll=NSScrollView(frame:NSRect(x:0,y:0,width:800,height:600))
        scroll.documentView=canvas
        let window=NSWindow(contentRect:scroll.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=scroll; window.orderBack(nil)
        canvas.configure(document.pixels,page:document.pages[0],zoom:1)
        var followed=false
        canvas.onDestination = { destination in
            do {
                let result = try engine.followDestination(document,destination:destination,viewport:viewport,currentZoom:1,currentPoint:point,backingScale:1,viewRotation:0)
                canvas.configure(result.0.pixels,page:result.0.pages[1],zoom:result.1.zoom)
                canvas.applyDestination(result.1)
                precondition(canvas.page?.rotation == 90 && canvas.zoom == 1.5)
                precondition(scroll.contentView.bounds.origin.x > 0, "XYZ navigation must position the target")
                followed=true
            } catch { preconditionFailure("Destination click failed: \(error)") }
        }
        let hit=canvas.viewRect(CGRect(x:100,y:710,width:1,height:1)).origin
        let location=canvas.convert(hit,to:nil)
        func mouse(_ type:NSEvent.EventType)->NSEvent { NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)! }
        canvas.mouseDown(with:mouse(.leftMouseDown)); canvas.mouseUp(with:mouse(.leftMouseUp))
        precondition(followed)
        window.orderOut(nil)
        print("PASS: explicit/named destinations, eight view modes, cropped/rotated targets, indexed page identities, reorder/merge, native navigation and independent PDFKit checks")
    }
    static func checkClicks(_ document: LoadedPDF) throws {
        let canvas = PageCanvas()
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:800,height:850))
        scroll.documentView = canvas
        let window = NSWindow(contentRect:scroll.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView = scroll; window.orderBack(nil)
        canvas.configure(document.pixels,page:document.pages[0],zoom:1)
        var opened = [URL]()
        canvas.onOpenLink = { opened.append($0) }
        func event(_ type:NSEvent.EventType, _ p:CGPoint) -> NSEvent {
            let rect = canvas.viewRect(CGRect(x:p.x,y:p.y,width:1,height:1))
            let location = canvas.convert(rect.origin,to:nil)
            return NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        let p = CGPoint(x:100,y:725)
        canvas.mouseDown(with:event(.leftMouseDown,p)); canvas.mouseUp(with:event(.leftMouseUp,p))
        precondition(opened.count == 1 && opened[0].absoluteString == "https://example.com/lesson")
        canvas.mouseDown(with:event(.leftMouseDown,p))
        canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:150,y:725)))
        canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:150,y:725)))
        precondition(opened.count == 1, "Dragging a link must not open it")
        let unsafe = CGPoint(x:100,y:450)
        canvas.mouseDown(with:event(.leftMouseDown,unsafe)); canvas.mouseUp(with:event(.leftMouseUp,unsafe))
        precondition(opened.count == 1)
        canvas.tool = .rectangle
        canvas.mouseDown(with:event(.leftMouseDown,p)); canvas.mouseUp(with:event(.leftMouseUp,p))
        precondition(opened.count == 1, "Annotation tools must not activate links")
        window.orderOut(nil)
    }
}
