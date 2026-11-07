import AppKit
import PDFKit
import Metal

@main struct ShapeChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine(), gpu=try Engine(metal:MetalPageRenderer()!)
        var names=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String]
        // A second independent producer; it may use private metadata/AP resources.
        for (name,type) in [("pdfkit-square",PDFAnnotationSubtype.square),("pdfkit-circle",PDFAnnotationSubtype.circle)] {
            let source=PDFDocument(data:try Data(contentsOf:root.appendingPathComponent("mupdf-square.pdf")))!
            let page=source.page(at:0)!
            for mark in page.annotations { page.removeAnnotation(mark) }
            let mark=PDFAnnotation(bounds:CGRect(x:60,y:90,width:160,height:140),forType:type,withProperties:nil)
            mark.color=NSColor(srgbRed:0.1,green:0.3,blue:0.7,alpha:1)
            mark.interiorColor=NSColor(srgbRed:0.8,green:0.7,blue:0.2,alpha:1)
            mark.border=PDFBorder();mark.border?.lineWidth=3
            mark.contents="Original";mark.userName="Teacher"
            page.addAnnotation(mark)
            precondition(source.write(to:root.appendingPathComponent(name+".pdf")))
            if !names.contains(name) { names.append(name) }
        }
        try JSONSerialization.data(withJSONObject:names).write(to:root.appendingPathComponent("cases.json"))
        for name in names {
            let original=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let opened=try cpu.load(original,page:0,width:300)
            let mark=opened.pages[0].annotations[0]
            let editable=name.hasPrefix("fallback-")
            precondition(mark.importedShape && mark.canChangeAppearance == editable && mark.hasEditableText)
            precondition(mark.canMove == (name != "locked"))
            precondition(mark.canEditContents == (name != "locked" && name != "rich" && name != "line-caption"))
            precondition(mark.hasCaption == (name == "line-caption"))
            var restyled=mark;restyled.style.width += 1
            if !editable { do { _=try cpu.annotate(original,page:0,marks:[restyled]);fatalError("Foreign appearance restyled") } catch is EngineError {} }
            var resized=mark;resized.points[0].x += 5
            if !editable { do { _=try cpu.annotate(original,page:0,marks:[resized]);fatalError("Foreign appearance resized") } catch is EngineError {} }
            let saved=try cpu.annotate(original,page:0,marks:[])
            let cropped=try cpu.crop(original,page:0,box:CGRect(x:10,y:10,width:280,height:340))
            let rotated=try cpu.rotate(cropped,page:0,degrees:90)
            let merged=try cpu.merge(original,with:original)
            let organized=try cpu.selectPages(try cpu.selectPages(merged,indices:[1,0]),indices:[0])
            var variants=[("",original),("-saved",saved),("-rotated",rotated),("-organized",organized)]
            if editable {
                resized=mark.scaled(to:CGRect(x:53.25,y:70.5,width:190.75,height:180.25))
                let enlarged=try cpu.annotate(original,page:0,marks:[resized])
                let enlargedMark=try cpu.load(enlarged,page:0,width:300).pages[0].annotations[0]
                precondition(enlargedMark.canChangeAppearance)
                if mark.kind == .rectangle || mark.kind == .ellipse { precondition(enlargedMark.rect == resized.rect) }
                else {
                    precondition(zip(enlargedMark.points,resized.points).allSatisfy{abs($0.x-$1.x)<1e-8 && abs($0.y-$1.y)<1e-8})
                    precondition(enlargedMark.rect.width>0 && enlargedMark.rect.height>0)
                }
                variants.append(("-resized",enlarged))
                restyled=mark
                restyled.style.stroke=NSColor(srgbRed:0.65,green:0.15,blue:0.35,alpha:1)
                restyled.style.fill=NSColor(srgbRed:0.2,green:0.7,blue:0.4,alpha:1)
                restyled.style.width=4;restyled.style.opacity=0.6
                let colored=try cpu.annotate(original,page:0,marks:[restyled])
                let coloredMark=try cpu.load(colored,page:0,width:300).pages[0].annotations[0]
                precondition(coloredMark.canChangeAppearance && coloredMark.style.width == 4 && coloredMark.style.opacity == 0.6)
                variants.append(("-restyled",colored))
                var again=coloredMark.translated(x:13.17,y:-7.31)
                let movedColor=try cpu.annotate(colored,page:0,marks:[again])
                again=try cpu.load(movedColor,page:0,width:300).pages[0].annotations[0]
                precondition(again.canChangeAppearance)
                again.style.width=1.25;again.text="Edited again ✓"
                let repeated=try cpu.annotate(movedColor,page:0,marks:[again])
                let reopened=try cpu.load(repeated,page:0,width:300).pages[0].annotations[0]
                precondition(reopened.canChangeAppearance && reopened.style.width == 1.25 && reopened.text==again.text)
                variants.append(("-edited-again",repeated))
                precondition(PDFDocument(data:repeated)!.page(at:0)!.annotations.first{$0.type != "Popup"}!.contents == again.text)
            }
            let moved=mark.translated(x:13,y:-7)
            if name == "locked" {
                do { _=try cpu.annotate(original,page:0,marks:[moved]);fatalError("Locked shape moved") } catch is EngineError {}
                do { _=try cpu.annotate(original,page:0,marks:[],deleting:[mark.id]);fatalError("Locked shape deleted") } catch is EngineError {}
            } else {
                let shifted=try cpu.annotate(original,page:0,marks:[moved])
                let shiftedMark=try cpu.load(shifted,page:0,width:100).pages[0].annotations[0]
                precondition(shiftedMark.rect == moved.rect && shiftedMark.points == moved.points)
                variants.append(("-moved",shifted))
                let removed=try cpu.annotate(original,page:0,marks:[],deleting:[mark.id])
                let remaining=try cpu.load(removed,page:0,width:100).pages[0].annotations.count
                precondition(remaining == opened.pages[0].annotations.count-1)
                variants.append(("-removed",removed))
            }
            var noted=mark;noted.text="Đã xem — 已阅 ✓"
            if name == "locked" || name == "rich" || name == "line-caption" {
                do { _=try cpu.annotate(original,page:0,marks:[noted]);fatalError("Protected shape note edited") } catch is EngineError {}
            } else {
                let revised=try cpu.annotate(original,page:0,marks:[noted])
                let reopened=try cpu.load(revised,page:0,width:300)
                precondition(reopened.pixels.data==opened.pixels.data && reopened.pages[0].annotations[0].text==noted.text)
                precondition(PDFDocument(data:revised)!.page(at:0)!.annotations.first{$0.type != "Popup"}!.contents==noted.text)
                variants.append(("-noted",revised))
            }
            for (suffix,bytes) in variants {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                for width in [300,600] {
                    let expected=try cpu.load(bytes,page:0,width:width)
                    let actual=try gpu.openPage(bytes,page:0,width:width)
                    guard let scene=actual.metalPage,let pixels=scene.bitmap(width:width) else { fatalError("Missing Metal shape path: \(name)\(suffix)") }
                    precondition(pixels.data.count==expected.pixels.data.count)
                    let differences=zip(pixels.data,expected.pixels.data).map{abs(Int($0)-Int($1))}
                    precondition((differences.max() ?? 0)<=32 && differences.filter{$0>1}.count<=pixels.data.count/2000,"CPU/Metal shape mismatch \(name)\(suffix)")
                    let png=NSBitmapImageRep(cgImage:expected.pixels.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width).png"))
                }
            }
            print("PASS: \(name) native/indexed rendering, translation, Unicode notes, \(editable ? "resize/restyle and repeated editing":"protected edits") and round trips")
        }
        for url in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("invalid"),includingPropertiesForKeys:nil) {
            let bytes=try Data(contentsOf:url)
            do { _=try cpu.load(bytes,page:0,width:100);fatalError("Accepted malformed shape \(url.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(bytes,page:0,width:100);fatalError("Indexed open accepted malformed shape \(url.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: malformed/unsupported foreign shape inputs fail explicitly")
    }
}
