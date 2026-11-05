import AppKit
import PDFKit

@main struct ImportedTextMarkupChecks {
    static func main() throws {
        for (type, kind) in [(PDFAnnotationSubtype.highlight, MarkupKind.highlight), (.underline, .underline), (.strikeOut, .strikeout), (PDFAnnotationSubtype(rawValue: "Squiggly"), .squiggly)] {
            try check(type, kind)
        }
        print("PDFKit multiline text markup: editing, rendering and independent reopen passed")
    }
    static func check(_ type: PDFAnnotationSubtype, _ kind: MarkupKind) throws {
        let original = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        let box = CGRect(x: 70, y: 548, width: 330, height: 38)
        let source = PDFAnnotation(bounds: box, forType: type, withProperties: nil)
        let quads = [CGPoint(x: 0,y: 38), CGPoint(x: 320,y: 38), CGPoint(x: 0,y: 24), CGPoint(x: 320,y: 24),
                     CGPoint(x: 0,y: 14), CGPoint(x: 190,y: 14), CGPoint(x: 0,y: 0), CGPoint(x: 190,y: 0)]
        source.quadrilateralPoints = quads.map(NSValue.init(point:))
        source.color = .yellow
        source.userName = "Reviewer"
        source.contents = "Review both lines ✓"
        original.page(at: 0)!.addAnnotation(source)
        let input = original.dataRepresentation()!
        let engine = try Engine()
        let before = try engine.load(input, page: 0, width: 612)
        var mark = before.pages[0].annotations[0]
        precondition(mark.kind == kind && mark.points.count == 8)
        precondition(mark.hitTest(CGPoint(x: 150, y: 550), tolerance: 1))
        precondition(!mark.hitTest(CGPoint(x: 150, y: 568), tolerance: 1))
        precondition(!mark.hitTest(CGPoint(x: 350, y: 550), tolerance: 1))
        precondition(mark.text == source.contents && mark.hasEditableText)
        let originalPoints = mark.points
        mark.style.stroke = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        mark.style.opacity = 0.5
        if kind != .highlight { mark.style.width = 3 }
        let changed = try engine.annotate(input, page: 0, marks: [mark])
        let reopened = try engine.load(changed, page: 0, width: 612)
        let item = reopened.pages[0].annotations[0]
        precondition(item.id == mark.id && item.points == originalPoints && item.rect == box && item.style.width == mark.style.width)
        let externalDocument = PDFDocument(data: changed)!
        let externalPage = externalDocument.page(at: 0)!
        let external = externalPage.annotations[0]
        precondition(external.type == source.type && external.userName == source.userName && external.contents == source.contents)
        precondition(external.bounds == box && external.quadrilateralPoints!.map(\.pointValue) == quads)
        let color = external.color.usingColorSpace(.sRGB)!
        precondition(color.greenComponent > 0.99 && color.redComponent < 0.01 && color.blueComponent < 0.01)
        func pixel(_ x: Int, _ y: Int, _ data: Data) -> [UInt8] {
            let offset = ((791-y)*612+x)*4
            return Array(data[offset..<(offset+4)])
        }
        precondition(pixel(71,568,reopened.pixels.data) == [255,255,255,255]) // gap between the lines
        let ys: [Int] = (572..<586).filter { y in let c = pixel(71,y,reopened.pixels.data); return Int(c[1]) - Int(c[0]) > 10 }
        precondition(!ys.isEmpty)
        switch kind {
        case .highlight: precondition(ys.count == 14)
        case .underline, .squiggly: precondition(ys.max()! < 578, "\(type) colored rows \(ys), points \(originalPoints), width \(mark.style.width)")
        case .strikeout: precondition(ys.min()! >= 576 && ys.max()! <= 581)
        default: fatalError()
        }
        let sampleY = kind == .highlight ? 585 : ys.min { pixel(71,$0,reopened.pixels.data)[0] < pixel(71,$1,reopened.pixels.data)[0] }!
        let context = CGContext(data: nil, width: 612, height: 792, bitsPerComponent: 8, bytesPerRow: 612*4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
        withExtendedLifetime(externalDocument) { externalPage.draw(with: .mediaBox, to: context) }
        let independentlyRendered = Data(bytes: context.data!, count: 612*792*4)
        let tint = pixel(71, sampleY, independentlyRendered)
        precondition((125...230).contains(tint[0]) && tint[1] == 255 && tint[2] == tint[0], "\(type) sample \(sampleY), PDFKit \(tint), CPU \(pixel(71,sampleY,reopened.pixels.data))")
        precondition(pixel(71,568,independentlyRendered) == [255,255,255,255])
        if let renderer = MetalPageRenderer() {
            let gpu = try Engine(metal: renderer).load(changed, page: 0, width: 612)
            guard let pixels = gpu.metalPage?.bitmap(width: 612) else { fatalError("Metal fallback") }
            precondition(pixel(71,sampleY,pixels.data) == pixel(71,sampleY,reopened.pixels.data))
        } else if ProcessInfo.processInfo.environment["POD_REQUIRE_METAL"] == "1" { fatalError("Metal unavailable") }
        var note = item
        note.text = "Đã duyệt ✓"
        let noted = try engine.annotate(changed, page: 0, marks: [note])
        precondition(PDFDocument(data: noted)!.page(at: 0)!.annotations[0].contents == note.text)
        let moved = note.translated(x: 5, y: 8).scaled(to: CGRect(x: 80, y: 510, width: 400, height: 90))
        let updated = try engine.annotate(noted, page: 0, marks: [moved])
        let restored = try engine.load(updated, page: 0, width: 612)
        precondition(restored.pages[0].annotations[0].points == moved.points)
        let deleted = try engine.annotate(updated, page: 0, marks: [], deleting: [mark.id])
        precondition(PDFDocument(data: deleted)!.page(at: 0)!.annotations.isEmpty)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let destination = kind == .highlight ? output : output.deletingLastPathComponent().appendingPathComponent("imported-\(external.type!).pdf")
        try changed.write(to: destination)
    }
}
