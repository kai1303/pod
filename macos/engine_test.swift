import Foundation
import PDFKit
@main struct EngineChecks {
    static func checkStrokeHistory(_ engine: Engine, _ original: Data) throws {
        var history = PDFEditHistory()
        var revisions = [original]
        let style = MarkupStyle.initial(for: .ink)
        for i in 0..<13 {
            let before = revisions.last!
            let page = i % 2
            if i == 10 {
                revisions.append(try engine.rotate(before, page: page, degrees: 90))
                history.record(before: before)
            } else {
                let mark = Markup(kind: .ink, points: [.init(x: 30+i, y: 100),.init(x: 120, y: 140)], rect: .zero, style: style)
                revisions.append(try engine.annotate(before, page: page, marks: [mark]))
                history.record(before: before, stroke: mark, page: page)
            }
        }
        var bytes = revisions.last!
        for expected in revisions.dropLast().reversed() {
            let restored = try history.undo.last!.bytes(using: engine)
            precondition(restored == expected, "Undo must restore exact PDF bytes, including object IDs")
            history.didRestore(undoing: true, leaving: bytes)
            bytes = restored
        }
        for expected in revisions.dropFirst() {
            let restored = try history.redo.last!.bytes(using: engine)
            precondition(restored == expected)
            history.didRestore(undoing: false, leaving: bytes)
            bytes = restored
        }
        let branched = try history.undo.last!.bytes(using: engine)
        history.didRestore(undoing: true, leaving: bytes)
        history.record(before: branched)
        precondition(history.redo.isEmpty)
    }
    static func checkIndexedReading(_ engine: Engine, _ original: Data) throws {
        let first = try engine.openPage(original, page: 0, width: 612)
        let second = try engine.turnPage(first, page: 1, width: 612)
        let eager = try engine.load(original, page: 1, width: 612)
        precondition(first.source === second.source && first.pages[1].runs.isEmpty)
        precondition(second.pixels.data == eager.pixels.data)
        precondition(second.pages[1].runs.map(\.text) == eager.pages[1].runs.map(\.text))
        let thumbnail = try engine.previewInfo(first.source!, page: 1)
        precondition(thumbnail.runs.map(\.text) == eager.pages[1].runs.map(\.text))

        // Preserve xref offsets and break only the second page's text operator.
        var damaged = original
        let title = Data("(Notes for tomorrow) Tj".utf8)
        let end = damaged.range(of: title)!.upperBound
        damaged.replaceSubrange((end-2)..<end, with: Data("ZZ".utf8))
        let readable = try engine.openPage(damaged, page: 0, width: 612)
        do {
            _ = try engine.turnPage(readable, page: 1, width: 612)
            preconditionFailure("Expected a page-local rendering error")
        } catch is EngineError {}
        let retry = try engine.turnPage(readable, page: 0, width: 612)
        precondition(retry.pixels.data == first.pixels.data)

        var missingStream = original
        let ref = missingStream.range(of: Data("/Contents 7 0 R".utf8))!
        missingStream.replaceSubrange(ref, with: Data("/Contents 0 0 R".utf8))
        let intactPage = try engine.openPage(missingStream, page: 0, width: 612)
        do {
            _ = try engine.turnPage(intactPage, page: 1, width: 612)
            preconditionFailure("Expected missing page contents to fail on navigation")
        } catch is EngineError {}

        let mark = Markup(kind: .ink, points: [.init(x: 35, y: 60), .init(x: 65, y: 90)], rect: .zero, style: .initial(for: .ink))
        let edited = try engine.annotate(original, page: 1, marks: [mark])
        let revision = try engine.openPage(edited, page: 0, width: 612)
        let annotated = try engine.turnPage(revision, page: 1, width: 612)
        let reference = try engine.load(edited, page: 1, width: 612)
        precondition(revision.source !== first.source && annotated.pixels.data == reference.pixels.data)
        precondition(annotated.pages[1].annotations.first?.points == mark.points)
    }

    static func checkFileSnapshot(_ engine: Engine, _ original: Data) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var large = original
        large.append(Data(repeating: 32, count: 256 * 1024))
        try large.write(to: url)
        let first = try engine.openPage(Engine.read(url), page: 0, width: 160)
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: 0)
        try writer.close()
        let second = try engine.turnPage(first, page: 1, width: 160)
        precondition(second.bytes == large)
        let expected = try engine.openPage(original, page: 1, width: 160)
        precondition(second.pixels.data == expected.pixels.data)
    }

    static func main() throws {
        precondition(Markup.hasDrawnExtent([.zero,CGPoint(x:20,y:30),.zero],threshold:1),"Closed strokes must commit")
        precondition(!Markup.hasDrawnExtent([.zero,.zero],threshold:1))
        let hitMark=Markup(kind:.highlight,points:[CGPoint(x:10,y:10),CGPoint(x:110,y:25)],rect:CGRect(x:-60,y:-60,width:240,height:155),style:.initial(for:.highlight))
        precondition(hitMark.hitTest(CGPoint(x:50,y:15),tolerance:2))
        precondition(!hitMark.hitTest(CGPoint(x:50,y:50),tolerance:2),"Appearance padding must not select an adjacent line")
        var colorStyle=MarkupStyle.initial(for:.rectangle)
        let originalColor=colorStyle.cValue.stroke
        for _ in 0..<20 { colorStyle=MarkupStyle(colorStyle.cValue) }
        precondition(abs(colorStyle.cValue.stroke.0-originalColor.0)<0.000001,"Annotation colors must not drift across edits")
        let engine=try Engine()
        let original=try Engine.read(URL(fileURLWithPath:CommandLine.arguments[1]))
        try checkIndexedReading(engine, original)
        try checkFileSnapshot(engine, original)
        try checkStandardInk(engine,original)
        try checkStrokeHistory(engine,original)
        let loaded=try engine.load(original,page:0,width:612)
        precondition(loaded.pages.count==2 && loaded.pixels.height==792)
        let text=loaded.pages[0].runs[0].text
        let edited=try engine.replace(original,page:0,run:0,text:"Hello Pod")
        let again=try engine.load(edited,page:0,width:612)
        precondition(again.pages[0].runs[0].text=="Hello Pod")
        let unchanged=try engine.load(original,page:0,width:612)
        precondition(unchanged.pages[0].runs[0].text==text)
        do { _=try engine.replace(original,page:0,run:0,text:String(repeating:"x",count:200)); preconditionFailure("expected overflow") } catch is EngineError {}
        let blank=try engine.replace(original,page:0,run:0,text:"")
        let empty=try engine.load(blank,page:0,width:612)
        precondition(empty.pages[0].runs[0].text.isEmpty)
        let second=try engine.load(original,page:1,width:612)
        precondition(second.pages[1].runs[0].text=="Notes for tomorrow")
        let selection=try PageSelection.parse("2, 1",count:2); precondition(selection == [1,0])
        let range=try PageSelection.parse("1-2",count:2); precondition(range == [0,1])
        for invalid in ["", "0", "3", "1,1", "2-1", "1,", "1-999999999"] {
            do { _ = try PageSelection.parse(invalid,count:2); preconditionFailure("invalid selection accepted") } catch is EngineError {}
        }
        let reordered=try engine.selectPages(original,indices:[1,0])
        let reversed=try engine.load(reordered,page:0,width:612)
        precondition(reversed.pages[0].runs[0].text=="Notes for tomorrow")
        let extracted=try engine.selectPages(original,indices:[1])
        let single=try engine.load(extracted,page:0,width:612)
        precondition(single.pages.count==1 && single.pages[0].runs[0].text=="Notes for tomorrow")
        let merged=try engine.merge(original,with:extracted)
        let three=try engine.load(merged,page:2,width:612)
        precondition(three.pages.count==3 && three.pages[2].runs[0].text=="Notes for tomorrow")
        let cropped=try engine.crop(original,page:0,box:CGRect(x:20,y:30,width:480,height:670))
        let rotated=try engine.rotate(cropped,page:0,degrees:90)
        let geometry=try engine.load(rotated,page:0,width:670)
        precondition(geometry.pixels.height==480 && geometry.pages[0].rotation==90)
        let originalAgain=try engine.load(original,page:0,width:612)
        precondition(originalAgain.pages[0].rotation==0 && originalAgain.pages[0].box.width==612)
        for rotation in [0,90,180,270] {
            let page=PageInfo(box:CGRect(x:20,y:30,width:480,height:670),mediaBox:CGRect(x:0,y:0,width:612,height:792),rotation:rotation,runs:[],annotations:[])
            let point=CGPoint(x:137,y:491)
            let back=page.pdfPoint(page.displayPoint(point))
            precondition(abs(back.x-point.x)<0.000001 && abs(back.y-point.y)<0.000001)
            let rect=page.displayRect(page.box)
            precondition(rect.origin == .zero && rect.size == page.displaySize)
        }
        let outDirectory=URL(fileURLWithPath:CommandLine.arguments[2]).deletingLastPathComponent()
        try rotated.write(to:outDirectory.appendingPathComponent("page-geometry.pdf"))
        try merged.write(to:outDirectory.appendingPathComponent("page-merged.pdf"))
        try extracted.write(to:outDirectory.appendingPathComponent("page-extracted.pdf"))
        try reordered.write(to:outDirectory.appendingPathComponent("page-reordered.pdf"))
        let clamped=try engine.load(extracted,page:2,width:612,clampPage:true)
        precondition(clamped.pageIndex==0)
        let splitRoot=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:splitRoot,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:splitRoot) }
        let splitFolder=try engine.splitPages(original,to:splitRoot)
        let splitFiles=try FileManager.default.contentsOfDirectory(at:splitFolder,includingPropertiesForKeys:nil).sorted{$0.lastPathComponent<$1.lastPathComponent}
        precondition(splitFiles.count==2)
        let splitSecond=try engine.load(Engine.read(splitFiles[1]),page:0,width:612)
        precondition(splitSecond.pages.count==1 && splitSecond.pages[0].runs[0].text=="Notes for tomorrow")
        var ink = Markup(kind:.ink, points:[CGPoint(x:100,y:200),CGPoint(x:140,y:280),CGPoint(x:180,y:200),
                                           CGPoint(x:300,y:200)], rect:.zero, text:"Đã xem", style:.initial(for:.ink))
        ink.inkPathStarts = [0,3]
        ink.link = "https://example.com/ink"
        ink.style.width = 10
        ink.style.opacity = 0.5
        let inkBytes = try engine.annotate(original,page:0,marks:[ink])
        try inkBytes.write(to:outDirectory.appendingPathComponent("grouped-ink.pdf"))
        let drawn = try engine.load(inkBytes,page:0,width:612)
        let group = drawn.pages[0].annotations[0]
        precondition(drawn.pages[0].annotations.count == 1 && group.points == ink.points && group.inkPathStarts == [0,3])
        precondition(group.link == ink.link && group.text == ink.text && !group.legacyInk)
        func red(_ x:Int,_ y:Int) -> UInt8 { drawn.pixels.data[((791-y)*612+x)*4] }
        precondition(red(140,240)<250 && red(140,275)==255, "Paint the quadratic rather than its control polygon")
        precondition(red(97,199)<250 && red(296,200)<250 && red(304,200)<250, "Round cap and both sides of centered dot")
        precondition(red(235,200)==255 && red(305,200)==255 && red(304,204)==255, "Separate contours and disk radius")
        func exported(_ bytes:Data) -> [PDFAnnotation] { PDFDocument(data:bytes)!.page(at:0)!.annotations }
        let companions = exported(inkBytes)
        precondition(companions.count == 2 && companions[0].paths?.count == 2 && companions[0].contents == ink.text)
        precondition(companions[1].type == "Link" && companions[1].url?.absoluteString == ink.link && companions[1].bounds == companions[0].bounds)
        // Use PDFKit's appearance interpreter as an independent check on the disk and quadratic.
        let independentDocument = PDFDocument(data:inkBytes)!
        let thumbnail = withExtendedLifetime(independentDocument) {
            independentDocument.page(at:0)!.thumbnail(of:NSSize(width:612,height:792),for:.mediaBox)
        }
        let independent = NSBitmapImageRep(data:thumbnail.tiffRepresentation!)!
        func previewRed(_ x:Int,_ y:Int) -> CGFloat {
            independent.colorAt(x:x*independent.pixelsWide/612,y:(791-y)*independent.pixelsHigh/792)!.usingColorSpace(.sRGB)!.redComponent
        }
        precondition(previewRed(140,240)<0.85 && previewRed(140,275)>0.97 && previewRed(300,200)<0.85 && previewRed(305,200)>0.97)
        var crossed = ink
        crossed.link = ""
        crossed.points = [CGPoint(x:80,y:300),CGPoint(x:180,y:300),CGPoint(x:130,y:250),CGPoint(x:130,y:350)]
        crossed.inkPathStarts = [0,2]
        let crossedBytes = try engine.annotate(original,page:0,marks:[crossed])
        let crossedPage = try engine.load(crossedBytes,page:0,width:612)
        let row = (791-300)*612
        precondition(crossedPage.pixels.data[(row+95)*4] == crossedPage.pixels.data[(row+130)*4], "Crossings in one ink annotation share opacity")
        let movedInk = group.translated(x:8,y:5)
        let inkEdited = try engine.annotate(inkBytes,page:0,marks:[movedInk])
        let afterInk = try engine.load(inkEdited,page:0,width:612).pages[0].annotations[0]
        precondition(afterInk.points == movedInk.points && afterInk.inkPathStarts == [0,3] && afterInk.id == group.id && afterInk.link == ink.link)
        let movedPair = exported(inkEdited)
        precondition(movedPair[0].bounds == movedPair[1].bounds && movedPair[0].bounds.origin != companions[0].bounds.origin)
        var unlinked = afterInk
        unlinked.link = ""
        let unlinkedBytes = try engine.annotate(inkEdited,page:0,marks:[unlinked])
        precondition(exported(unlinkedBytes).count == 1)
        let linkedAgain = try engine.annotate(unlinkedBytes,page:0,marks:[afterInk])
        precondition(exported(linkedAgain).last?.url?.absoluteString == ink.link)
        let extractedInk = try engine.selectPages(linkedAgain,indices:[0])
        let copiedInkPage = try engine.load(extractedInk,page:0,width:612).pages[0]
        precondition(copiedInkPage.annotations.count == 1 && copiedInkPage.annotations[0].link == ink.link)
        let removedInk = try engine.annotate(inkEdited,page:0,marks:[],deleting:[group.id])
        let removedPage = try engine.load(removedInk,page:0,width:612).pages[0]
        precondition(removedPage.annotations.isEmpty && exported(removedInk).isEmpty)
        var marked=original
        for kind in MarkupKind.allCases {
            let column=Int(kind.rawValue)%3, row=Int(kind.rawValue)/3
            let x=Double(50+column*180), y=Double(60+row*100)
            let points = kind == .polygon ? [CGPoint(x:x,y:y),CGPoint(x:x+130,y:y),CGPoint(x:x+65,y:y+60)] : [CGPoint(x:x,y:y),CGPoint(x:x+130,y:y+60)]
            let mark=Markup(kind:kind,points:points,rect:.zero,text:kind.isText ? "A note":"",style:MarkupStyle.initial(for:kind))
            marked=try engine.annotate(marked,page:0,marks:[mark])
        }
        let all=try engine.load(marked,page:0,width:612)
        precondition(all.pages[0].annotations.count==18)
        var moved=all.pages[0].annotations[0].translated(x:10,y:10)
        let oldColor=moved.style.cValue.stroke
        moved=moved.scaled(to:CGRect(x:70,y:80,width:140,height:90))
        let updated=try engine.annotate(marked,page:0,marks:[moved])
        let verify=try engine.load(updated,page:0,width:612)
        let savedMark=verify.pages[0].annotations[0]
        precondition(abs(savedMark.geometryBounds.width-140)<0.0001 && abs(savedMark.geometryBounds.height-90)<0.0001)
        precondition(abs(savedMark.style.cValue.stroke.0-oldColor.0)<0.000001)
        let deleted=try engine.annotate(updated,page:0,marks:[],deleting:[moved.id])
        let fewer=try engine.load(deleted,page:0,width:612)
        precondition(fewer.pages[0].annotations.count==17)
        try marked.write(to:URL(fileURLWithPath:CommandLine.arguments[2]).deletingLastPathComponent().appendingPathComponent("annotations.pdf"))
        try edited.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("Swift engine: text/markup, merge, extract, split, reorder, crop/rotation, coordinate round trips, invalid selections and restore clamping passed")
    }
    static func checkStandardInk(_ engine:Engine,_ original:Data) throws {
        let source = PDFDocument(data:original)!
        let page = source.page(at:0)!
        let box = CGRect(x:100,y:150,width:200,height:100)
        let ink = PDFAnnotation(bounds:box,forType:.ink,withProperties:nil)
        ink.userName="Reviewer"
        ink.contents="Imported"
        ink.color=NSColor(srgbRed:1,green:0,blue:0,alpha:0.7)
        let border=PDFBorder()
        border.lineWidth=5
        ink.border=border
        let path=NSBezierPath()
        path.move(to:CGPoint(x:5,y:5))
        path.line(to:CGPoint(x:40,y:70))
        path.line(to:CGPoint(x:80,y:10))
        ink.add(path)
        let dot=NSBezierPath()
        dot.move(to:CGPoint(x:130,y:80))
        dot.line(to:CGPoint(x:130,y:80))
        ink.add(dot)
        page.addAnnotation(ink)
        let other=PDFAnnotation(bounds:CGRect(x:30,y:60,width:60,height:15),forType:.highlight,withProperties:nil)
        other.quadrilateralPoints=[CGPoint(x:0,y:15),CGPoint(x:60,y:15),CGPoint(x:0,y:0),CGPoint(x:60,y:0)].map(NSValue.init(point:))
        other.contents="Keep me"
        page.addAnnotation(other)
        let bytes=source.dataRepresentation()!
        let first=try engine.load(bytes,page:0,width:612)
        let mark=first.pages[0].annotations.first{$0.kind == .ink}!
        precondition(mark.importedInk && !mark.inkLocked && mark.inkPathStarts == [0,3] && abs(mark.style.opacity-0.7)<0.0001)
        precondition(mark.points.first == CGPoint(x:105,y:155))
        let center=mark.points.last!
        let eraser=CGPath(ellipseIn:CGRect(x:center.x-4,y:center.y-4,width:8,height:8),transform:nil)
        guard mark.hitTest(center,tolerance:0), case .edited(let withoutDot)=mark.subtractingInk(eraser) else {
            preconditionFailure("A repeated point from PDFKit must remain selectable and erasable as a dot.")
        }
        precondition(withoutDot.points == Array(mark.points.prefix(3)) && withoutDot.inkPathStarts.isEmpty)

        let crossing = CGPath(ellipseIn: CGRect(x: mark.points[1].x-2, y: mark.points[1].y-2, width: 4, height: 4), transform: nil)
        guard case .edited(let onlyDot) = mark.subtractingInk(crossing, mode: .stroke),
              onlyDot.points == Array(mark.points.dropFirst(3)), onlyDot.id == mark.id else {
            preconditionFailure("Touching one path must preserve its untouched sibling in the imported ink annotation")
        }
        for kind in [MarkupKind.rectangle, .comment] {
            var nonInk = mark; nonInk.kind = kind
            guard case .unchanged = nonInk.subtractingInk(crossing, mode: .stroke) else { preconditionFailure("Eraser removed a non-ink annotation") }
        }
        let marker = Markup(kind: .freehandHighlight, points: [CGPoint(x: 30, y: 120), CGPoint(x: 190, y: 120)],
                            rect: .zero, style: .initial(for: .freehandHighlight))
        let marked = try engine.annotate(bytes, page: 0, marks: [marker])
        let savedMarker = try engine.load(marked, page: 0, width: 612).pages[0].annotations.first { $0.kind == .freehandHighlight }!
        let cut = CGPath(rect: CGRect(x: 98, y: 100, width: 16, height: 40), transform: nil)
        guard case .removed = savedMarker.subtractingInk(cut, mode: .stroke),
              case .edited(let split) = savedMarker.subtractingInk(cut) else { preconditionFailure("Expected a cut across the highlighter") }
        let cutPDF = try engine.annotate(marked, page: 0, marks: split.erasedFragments)
        let pieces = try engine.load(cutPDF, page: 0, width: 612).pages[0].annotations.filter { $0.kind == .freehandHighlight }
        precondition(pieces.count == 2 && pieces[0].id == savedMarker.id)
        precondition(pieces.allSatisfy { !$0.hitTest(CGPoint(x: 106, y: 120), tolerance: 0) && $0.style.opacity == marker.style.opacity })
        let unchanged=try engine.annotate(bytes,page:0,marks:[mark])
        let noOp=try engine.load(unchanged,page:0,width:612)
        precondition(first.pixels.data == noOp.pixels.data)
        var comment=mark
        comment.text="Reviewed ✓"
        let noted=try engine.annotate(unchanged,page:0,marks:[comment])
        let commentOnly=try engine.load(noted,page:0,width:612)
        precondition(first.pixels.data == commentOnly.pixels.data)
        var edited=comment.translated(x:8,y:12)
        edited.style.width=8
        edited.style.opacity=0.5
        edited.style.stroke=NSColor(srgbRed:0,green:1,blue:0,alpha:1)
        edited.link="https://example.com/drawing"
        let changed=try engine.annotate(noted,page:0,marks:[edited])
        let reopened=try engine.load(changed,page:0,width:612)
        let after=reopened.pages[0].annotations.first{$0.kind == .ink}!
        precondition(reopened.pages[0].annotations.count == 2 && after.id == mark.id && after.importedInk && after.points == edited.points && after.inkPathStarts == [0,3])
        let independent=PDFDocument(data:changed)!
        let external=independent.page(at:0)!.annotations
        let externalInk=external.first{$0.type == "Ink"}!
        precondition(externalInk.userName == "Reviewer" && externalInk.contents == comment.text && externalInk.paths?.count == 2 && externalInk.border?.lineWidth == 8)
        precondition(externalInk.color.usingColorSpace(.sRGB)!.greenComponent > 0.99)
        precondition(external.first{$0.type == "Link"}?.url?.absoluteString == edited.link)
        precondition(external.first{$0.type == "Highlight"}?.contents == "Keep me")
        let removed=try engine.annotate(changed,page:0,marks:[],deleting:[mark.id])
        let left=try engine.load(removed,page:0,width:612)
        precondition(left.pages[0].annotations.count == 1 && left.pages[0].annotations[0].text == "Keep me")
        precondition(PDFDocument(data:removed)!.page(at:0)!.annotations.count == 1)
    }

}
