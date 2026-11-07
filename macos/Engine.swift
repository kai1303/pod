import Foundation
import CoreGraphics
import AppKit

struct TextRun {
    let id: Int
    let text: String
    let size: Double
    let bounds: CGRect
    var fontName: String = "Courier"
}
enum DestinationMode: UInt32 { case xyz, fit, fitH, fitV, fitR, fitB, fitBH, fitBV }
struct DestinationView {
    let zoom: CGFloat
    let anchor: CGPoint
    let alignment: CGPoint
}
struct PageDestination {
    let page: Int
    let mode: DestinationMode
    let parameters: [Double?]
    var needsContentBounds: Bool { [.fitB, .fitBH, .fitBV].contains(mode) }
    func view(on page: PageInfo, viewport: CGSize, currentZoom: CGFloat, currentPoint: CGPoint,
              contentBounds: CGRect? = nil) -> DestinationView {
        let available = CGSize(width:max(1,viewport.width-56),height:max(1,viewport.height-56))
        let bounds = needsContentBounds ? (contentBounds ?? page.box) : page.box
        let area = page.displayRect(bounds)
        var zoom = currentZoom
        var anchor = area.origin
        var alignment = CGPoint.zero
        switch mode {
        case .xyz:
            zoom = parameters[2].map { CGFloat($0) } ?? currentZoom
            anchor = page.displayPoint(CGPoint(x:parameters[0].map { CGFloat($0) } ?? currentPoint.x,
                                              y:parameters[1].map { CGFloat($0) } ?? currentPoint.y))
        case .fit, .fitB:
            zoom = min(available.width/area.width, available.height/area.height)
            anchor = CGPoint(x:area.midX,y:area.midY); alignment = CGPoint(x:0.5,y:0.5)
        case .fitH, .fitBH:
            zoom = available.width/area.width
            let point = page.displayPoint(CGPoint(x:bounds.minX,y:parameters[0].map { CGFloat($0) } ?? currentPoint.y))
            anchor = CGPoint(x:area.midX,y:point.y); alignment.x = 0.5
        case .fitV, .fitBV:
            zoom = available.height/area.height
            let point = page.displayPoint(CGPoint(x:parameters[0].map { CGFloat($0) } ?? currentPoint.x,y:bounds.maxY))
            anchor = CGPoint(x:point.x,y:area.midY); alignment.y = 0.5
        case .fitR:
            let rect = CGRect(x:parameters[0]!,y:parameters[1]!,width:parameters[2]!-parameters[0]!,height:parameters[3]!-parameters[1]!)
            let region = page.displayRect(rect)
            zoom = min(available.width/region.width,available.height/region.height)
            anchor = CGPoint(x:region.midX,y:region.midY); alignment = CGPoint(x:0.5,y:0.5)
        }
        return DestinationView(zoom:min(3,max(0.1,zoom)),anchor:anchor,alignment:alignment)
    }
}
struct PageLink {
    let id: UInt32
    let rect: CGRect
    let uri: String
    let base: String
    let quads: [CGPoint]
    let hidden: Bool
    var destination: PageDestination? = nil
    var isActive: Bool { !hidden && (destination != nil || url != nil) }
    // PDF actions are data, never automatic execution. Only explicit web-link
    // clicks reach the OS; other URI schemes remain preserved but inactive.
    var url: URL? {
        guard !hidden, !uri.isEmpty, !uri.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 }),
              let url = URL(string: uri, relativeTo: base.isEmpty ? nil : URL(string: base))?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        return url
    }
    func contains(_ point: CGPoint) -> Bool {
        guard !hidden, rect.contains(point) else { return false }
        // PDF ignores QuadPoints outside Rect. Accept both perimeter and text
        // quad ordering by sorting the four vertices around their centroid.
        guard !quads.isEmpty, quads.count % 4 == 0,
              quads.allSatisfy({ $0.x >= rect.minX && $0.x <= rect.maxX && $0.y >= rect.minY && $0.y <= rect.maxY }) else { return true }
        for i in stride(from: 0, to: quads.count, by: 4) {
            let group = Array(quads[i..<(i+4)])
            let center = CGPoint(x: group.reduce(0) { $0+$1.x }/4, y: group.reduce(0) { $0+$1.y }/4)
            let polygon = group.sorted { atan2($0.y-center.y,$0.x-center.x) < atan2($1.y-center.y,$1.x-center.x) }
            var positive = false, negative = false
            for j in 0..<4 {
                let a = polygon[j], b = polygon[(j+1)%4]
                let cross = (b.x-a.x)*(point.y-a.y)-(b.y-a.y)*(point.x-a.x)
                positive = positive || cross > 0.000001
                negative = negative || cross < -0.000001
            }
            if positive != negative { return true }
        }
        return false
    }
}
struct PageInfo {
    let box: CGRect
    let mediaBox: CGRect
    let rotation: Int
    let runs: [TextRun]
    let annotations: [Markup]
    var links: [PageLink] = []
    var displaySize: CGSize { rotation % 180 == 0 ? box.size : CGSize(width:box.height,height:box.width) }
    // Display coordinates start at the top left; engine coordinates stay in PDF space.
    func displayPoint(_ point: CGPoint) -> CGPoint {
        let x=point.x-box.minX, y=point.y-box.minY
        switch rotation {
        case 90: return CGPoint(x:y,y:x)
        case 180: return CGPoint(x:box.width-x,y:y)
        case 270: return CGPoint(x:box.height-y,y:box.width-x)
        default: return CGPoint(x:x,y:box.height-y)
        }
    }
    func pdfPoint(_ point: CGPoint) -> CGPoint {
        let p: CGPoint
        switch rotation {
        case 90: p=CGPoint(x:point.y,y:point.x)
        case 180: p=CGPoint(x:box.width-point.x,y:point.y)
        case 270: p=CGPoint(x:box.width-point.y,y:box.height-point.x)
        default: p=CGPoint(x:point.x,y:box.height-point.y)
        }
        return CGPoint(x:p.x+box.minX,y:p.y+box.minY)
    }
    func displayRect(_ rect: CGRect) -> CGRect {
        let first=displayPoint(rect.origin), last=displayPoint(CGPoint(x:rect.maxX,y:rect.maxY))
        return CGRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(last.x-first.x),height:abs(last.y-first.y))
    }
}
extension PageInfo {
    // A single-column reading view. Use displayed coordinates so PDF crop and rotation
    // are accounted for before joining text-show operations into lines and paragraphs.
    var readingParagraphs: [String] {
        struct Piece {
            var text: String
            let rect: CGRect
            let size: CGFloat
        }
        let pieces = runs.compactMap { run -> Piece? in
            let rect = displayRect(run.bounds)
            guard !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  rect.intersects(CGRect(origin: .zero, size: displaySize)) else { return nil }
            return Piece(text: run.text, rect: rect, size: max(1, abs(run.size)))
        }.sorted {
            if $0.rect.midY == $1.rect.midY { return $0.rect.minX < $1.rect.minX }
            return $0.rect.midY < $1.rect.midY
        }
        var lines = [[Piece]]()
        for piece in pieces {
            if let first = lines.last?.first, abs(piece.rect.midY-first.rect.midY) <= min(first.size, piece.size)*0.4 {
                lines[lines.count-1].append(piece)
            } else { lines.append([piece]) }
        }
        var paragraphs = [String]()
        var previous: Piece?
        for line in lines {
            let row = line.sorted { $0.rect.minX < $1.rect.minX }
            guard var last = row.first else { continue }
            var text = last.text
            var rect = last.rect
            for piece in row.dropFirst() {
                if piece.rect.minX-last.rect.maxX > min(last.size,piece.size)*0.13,
                   text.last?.isWhitespace == false, piece.text.first?.isWhitespace == false { text += " " }
                text += piece.text
                rect = rect.union(piece.rect)
                last = piece
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let size = row.map(\.size).max() ?? last.size
            if let prev = previous, rect.midY-prev.rect.midY <= 1.65*max(size,prev.size),
               abs(prev.size-size) <= size*0.12, abs(rect.minX-prev.rect.minX) < size*0.8,
               prev.rect.width > displaySize.width*0.48,
               text.range(of: #"^(?:[•▪‣]|\d+[.)]\s)"#, options: .regularExpression) == nil {
                paragraphs[paragraphs.count-1] += (paragraphs.last?.hasSuffix("-") == true ? "" : " ") + text
            } else { paragraphs.append(text) }
            previous = Piece(text: text, rect: rect, size: size)
        }
        return paragraphs
    }
}

private func makePageInfo(_ page: PodPage, runs: [TextRun] = [], annotations: [Markup] = [], links: [PageLink] = []) -> PageInfo {
    let m = page.media
    return PageInfo(box: CGRect(x: page.x, y: page.y, width: page.width, height: page.height),
                    mediaBox: CGRect(x: m.0, y: m.1, width: m.2-m.0, height: m.3-m.1),
                    rotation: Int(page.rotation), runs: runs, annotations: annotations, links: links)
}

final class PDFPageIndex {
    // NSData guarantees a stable byte pointer while the native index borrows it.
    private let storage: NSData
    private let handle: OpaquePointer
    let geometry: [PageInfo]
    let hasOutlines: Bool

    init(_ bytes: Data) throws {
        let storage = bytes as NSData
        guard let handle = pod_index_open(storage.bytes.assumingMemoryBound(to: UInt8.self), storage.length) else {
            throw EngineError.current()
        }
        do {
            let count = pod_index_count(handle)
            guard count > 0 else { throw EngineError(message: "This PDF has no pages.") }
            geometry = try (0..<count).map { index in
                var page = PodPage()
                guard pod_index_geometry(handle, index, &page) != 0 else { throw EngineError.current() }
                return makePageInfo(page)
            }
        } catch {
            pod_index_close(handle)
            throw error
        }
        self.storage = storage
        self.handle = handle
        hasOutlines = pod_index_has_outlines(handle)
    }

    deinit { pod_index_close(handle) }

    fileprivate func withPage<T>(_ index: Int, _ read: (OpaquePointer) throws -> T) throws -> T {
        guard geometry.indices.contains(index) else { throw EngineError(message: "That page does not exist.") }
        guard let page = pod_index_open_page(handle, index) else {
            throw EngineError.current()
        }
        defer { pod_close(page) }
        return try read(page)
    }
}
enum PageSelection {
    static func parse(_ text: String, count: Int) throws -> [Int] {
        let invalid=EngineError(message:"Enter page numbers from 1 to \(count), separated by commas or ranges, without repeats. For example: 1, 3-5.")
        guard count>0, text.utf8.count<=1_000_000 else { throw invalid }
        var result:[Int]=[], seen=Set<Int>()
        for token in text.split(separator:",",omittingEmptySubsequences:false) {
            let bounds=token.split(separator:"-",omittingEmptySubsequences:false).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
            guard (1...2).contains(bounds.count),let start=Int(bounds[0]),start>=1,start<=count else { throw invalid }
            let end: Int
            if bounds.count==2 { guard let value=Int(bounds[1]),value>=start,value<=count else { throw invalid }; end=value } else { end=start }
            for number in start...end {
                guard seen.insert(number).inserted else { throw invalid }
                result.append(number-1)
            }
        }
        return result
    }
}
struct PagePixels {
    let data: Data
    let width: Int
    let height: Int
    var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

}
struct PageViewState {
    var zoom: Double = 1
    var rotation: Int = 0
}
struct LoadedPDF {
    let pageIndex: Int
    let bytes: Data
    let pages: [PageInfo]
    let pixels: PagePixels
    let metalPage: MetalPage?
    var view: PageViewState? = nil
    var source: PDFPageIndex? = nil
    let metadataMS: Double
    let elapsedMS: Double
}
// Each freehand revision shares its predecessor. Periodic checkpoints bound the
// number of PDF writes needed to reconstruct the exact bytes on undo or redo.
final class PDFRevision {
    enum Contents {
        case snapshot(Data)
        case stroke(previous: PDFRevision, page: Int, mark: Markup)
    }
    let contents: Contents
    let depth: Int
    init(snapshot: Data) {
        contents = .snapshot(snapshot)
        depth = 0
    }
    init(previous: PDFRevision, page: Int, stroke: Markup) {
        contents = .stroke(previous: previous, page: page, mark: stroke)
        depth = previous.depth + 1
    }
    func bytes(using engine: Engine) throws -> Data {
        switch contents {
        case .snapshot(let data): return data
        case let .stroke(previous, page, mark):
            return try engine.annotate(previous.bytes(using: engine), page: page, marks: [mark])
        }
    }
    fileprivate func storageBytes(seen: inout Set<ObjectIdentifier>) -> Int {
        guard seen.insert(ObjectIdentifier(self)).inserted else { return 0 }
        switch contents {
        case .snapshot(let data): return data.count
        case let .stroke(previous, _, mark):
            let payload = mark.points.count * MemoryLayout<CGPoint>.stride
                + mark.inkPathStarts.count * MemoryLayout<Int>.stride + mark.text.utf8.count + mark.link.utf8.count
            return payload + previous.storageBytes(seen: &seen)
        }
    }
}

struct PDFEditHistory {
    private(set) var undo: [PDFRevision] = []
    private(set) var redo: [PDFRevision] = []
    private var current: PDFRevision?
    static func storageBytes(_ revisions: [PDFRevision]) -> Int {
        var seen = Set<ObjectIdentifier>()
        return revisions.reduce(0) { $0 + $1.storageBytes(seen: &seen) }
    }
    private static func append(_ revision: PDFRevision, to stack: inout [PDFRevision]) {
        stack.append(revision)
        while stack.count > 20 || (stack.count > 1 && storageBytes(stack) > 64 * 1024 * 1024) {
            stack.removeFirst()
        }
    }
    mutating func record(before bytes: Data, stroke: Markup? = nil, page: Int = 0) {
        var before = current ?? PDFRevision(snapshot: bytes)
        if let stroke {
            if before.depth >= 4 { before = PDFRevision(snapshot: bytes) }
            current = PDFRevision(previous: before, page: page, stroke: stroke)
        } else {
            current = nil
        }
        Self.append(before, to: &undo)
        redo.removeAll()
    }
    mutating func didRestore(undoing: Bool, leaving bytes: Data) {
        let leaving = current ?? PDFRevision(snapshot: bytes)
        if undoing {
            current = undo.removeLast()
            Self.append(leaving, to: &redo)
        } else {
            current = redo.removeLast()
            Self.append(leaving, to: &undo)
        }
    }
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func current() -> EngineError {
        let code = String(cString: pod_error())
        let message: String
        switch code {
        case "UnsupportedPageOrganization": message = "This PDF contains document links or metadata that Pod cannot preserve while rearranging pages yet. Your document has not been changed."
        case "AnnotationHasReplies": message = "Delete the replies before deleting this annotation."
        case "InvalidAnnotationReply": message = "This PDF contains a malformed comment thread."
        case "UnsupportedAnnotationReply": message = "This PDF uses an annotation grouping relationship Pod does not support yet."
        case "AnnotationLocked": message = "This annotation is locked in the PDF."
        case "UnsupportedLinkAction": message = "This PDF contains a link action Pod does not support yet."
        case "DestinationNotFound": message = "A PDF link points to a destination that is missing from this document."
        case "InvalidDestination", "InvalidDestinationTree": message = "This PDF contains a malformed page destination."
        case "DestinationLimit": message = "This PDF's destination tree exceeds Pod's processing limits."
        case "UnsupportedDestinationMode", "UnsupportedStructureDestination": message = "This PDF contains a destination type Pod does not support yet."
        case "UnsupportedLinkAppearance": message = "This PDF contains a link appearance Pod cannot render yet."
        case "InvalidLink": message = "This PDF contains a malformed link."
        case "UnsupportedAnnotationAppearance", "MissingAnnotationAppearance": message = "Pod cannot display this annotation's appearance yet. Your file has not been changed."
        case "InvalidAnnotationLink": message = "Enter a complete HTTP or HTTPS address for this drawing."
        case "InvalidCropBox": message = "The crop must have a positive width and height and stay inside the original page."
        case "PageNotFound", "DuplicatePage", "EmptyPageSelection": message = "Choose valid page numbers without repeats. Keep at least one page."
        case "TextOverflow": message = "The replacement is wider than the selected text. Use a shorter line so the rest of the page stays in place."
        case "UnsupportedEncoding": message = "This text contains characters that the selected PDF font or annotation cannot represent."
        case "MissingRenderFont": message = "A system font needed to render this PDF is missing. Check the standard Arial, Times New Roman, Courier New, Symbol and Zapf Dingbats fonts in Font Book."
        case "UnsupportedEmbeddedFont": message = "This PDF uses a font program or embedding format that Pod does not support yet."
        case "InvalidCMap", "InvalidCMapUnicode", "CMapCycle", "AmbiguousCMap": message = "This PDF contains an invalid Unicode character map."
        case "CMapLimit": message = "This PDF exceeds Pod’s character-map processing limits."
        case "UnsupportedPredefinedCMap", "UnsupportedCMapOperator": message = "This PDF uses a character-map feature Pod does not support yet."
        case "MissingGlyph": message = "This PDF font is missing a glyph needed for the text."
        case "UnsupportedFontCmap", "UnsupportedCMapEncoding": message = "This PDF font uses a character map Pod does not support yet."
        case "InvalidCIDFont", "InvalidCharacterCode": message = "This PDF contains malformed composite-font or character-code data."
        case "InvalidFontWidth": message = "This PDF contains invalid font spacing data."
        case "InvalidHeader": message = "This file is not a readable PDF."
        case "InvalidCompressedStream", "InvalidStreamChecksum", "InvalidASCIIHex", "InvalidASCII85", "InvalidRunLength", "InvalidLZW", "InvalidPredictorData":
            message = "This PDF contains damaged or incomplete encoded data."
        case "DecodedStreamLimit", "FilterLimit":
            message = "This PDF exceeds Pod's stream decoding limits."
        default:
            if code.hasPrefix("Unsupported") {
                message = "This PDF uses a feature Pod cannot display yet (\(code)). Try the included sample. Your file has not been changed."
            } else { message = "Pod could not process this document (\(code)). Your file has not been changed." }
        }
        return EngineError(message: message)
    }
}

// Immutable OS font bytes are retained for the lifetime of their C pointers.
// Pod parses the TrueType outlines itself; the system supplies only font files.
final class SystemPDFFonts {
    static let shared = SystemPDFFonts()
    private let storage: [NSData]
    let sources: [PodFontSource]
    private init() {
        let names = ["Supplemental/Courier New", "Supplemental/Courier New Bold",
                     "Supplemental/Courier New Italic", "Supplemental/Courier New Bold Italic",
                     "Supplemental/Arial", "Supplemental/Arial Bold",
                     "Supplemental/Arial Italic", "Supplemental/Arial Bold Italic",
                     "Supplemental/Times New Roman", "Supplemental/Times New Roman Bold",
                     "Supplemental/Times New Roman Italic", "Supplemental/Times New Roman Bold Italic",
                     "Symbol", "ZapfDingbats"]
        var retained: [NSData] = []
        var fonts: [PodFontSource] = []
        for (face, name) in names.enumerated() {
            guard let data = NSData(contentsOfFile: "/System/Library/Fonts/" + name + ".ttf") else { continue }
            retained.append(data)
            fonts.append(PodFontSource(face:UInt32(face),data:data.bytes.assumingMemoryBound(to:UInt8.self),length:data.length))
        }
        storage = retained
        sources = fonts
    }
}

// Engine calls run on the controller's serial worker queue. No PDF API is used by Swift.
final class Engine {
    private let fonts = SystemPDFFonts.shared
    private let metal: MetalPageRenderer?
    init(metal: MetalPageRenderer? = nil) throws {
        self.metal = metal
    }
    private func withDocument<T>(_ bytes: Data, _ action: (OpaquePointer) throws -> T) throws -> T {
        guard !bytes.isEmpty else { throw EngineError(message:"This file is empty.") }
        let handle = bytes.withUnsafeBytes { raw in pod_open(raw.bindMemory(to: UInt8.self).baseAddress!, bytes.count) }
        guard let handle else { throw EngineError.current() }
        defer { pod_close(handle) }
        return try action(handle)
    }
    private func pageInfo(_ doc: OpaquePointer, index: Int) throws -> PageInfo {
        var info = PodPage()
        guard pod_page(doc,index,&info) != 0 else { throw EngineError.current() }
        var runs: [TextRun] = []
        for id in 0..<info.runs {
            var run = PodRun()
            guard pod_run(doc,index,id,&run) != 0 else { throw EngineError.current() }
            let text = String(decoding: UnsafeBufferPointer(start: run.text,count:run.length),as:UTF8.self)
            var font = PodString()
            guard pod_run_font(doc,index,id,&font) != 0 else { throw EngineError.current() }
            let fontName = String(decoding:UnsafeBufferPointer(start:font.data,count:font.length),as:UTF8.self)
            let b=run.bounds
            runs.append(TextRun(id:id,text:text,size:run.size,bounds:CGRect(x:b.0,y:b.1,width:max(0,b.2-b.0),height:max(0,b.3-b.1)),fontName:fontName))
        }
        var annotationCount=0
        guard pod_annotation_count(doc,index,&annotationCount) != 0 else { throw EngineError.current() }
        var marks:[Markup]=[]
        for i in 0..<annotationCount {
            var value=PodAnnotation()
            guard pod_annotation(doc,index,i,&value) != 0,let kind=MarkupKind(rawValue:value.kind) else { throw EngineError.current() }
            let points=UnsafeBufferPointer(start:value.points,count:value.point_count).map{CGPoint(x:$0.x,y:$0.y)}
            let text=String(decoding:UnsafeBufferPointer(start:value.text,count:value.text_length),as:UTF8.self)
            let r=value.rect
            var mark=Markup(id:value.id,kind:kind,points:points,rect:CGRect(x:r.0,y:r.1,width:r.2-r.0,height:r.3-r.1),text:text,style:MarkupStyle(value.style))
            mark.inkPathStarts = Array(UnsafeBufferPointer(start:value.ink_starts,count:value.ink_start_count))
            mark.link = String(decoding:UnsafeBufferPointer(start:value.link,count:value.link_length),as:UTF8.self)
            mark.legacyInk = value.legacy_ink != 0
            mark.importedInk = value.imported_ink != 0
            mark.importedComment = value.imported_comment != 0
            var importedShape: Int32 = 0
            guard pod_annotation_imported_shape(doc,index,i,&importedShape) != 0 else { throw EngineError.current() }
            mark.importedShape = importedShape != 0
            var importedFreeText: Int32 = 0
            guard pod_annotation_imported_free_text(doc,index,i,&importedFreeText) != 0 else { throw EngineError.current() }
            mark.importedFreeText = importedFreeText != 0
            var freeTextEditable: Int32 = 0
            guard pod_annotation_free_text_editable(doc,index,i,&freeTextEditable) != 0 else { throw EngineError.current() }
            mark.freeTextEditable = freeTextEditable != 0
            var shapeEditable: Int32 = 0
            guard pod_annotation_shape_editable(doc,index,i,&shapeEditable) != 0 else { throw EngineError.current() }
            mark.shapeEditable = shapeEditable != 0
            var hasCaption: Int32 = 0
            guard pod_annotation_has_caption(doc,index,i,&hasCaption) != 0 else { throw EngineError.current() }
            mark.hasCaption = hasCaption != 0
            mark.inkLocked = value.ink_locked != 0
            do {
                var info = PodCommentInfo()
                guard pod_comment_info(doc,index,i,&info) != 0 else { throw EngineError.current() }
                let r = info.popup_rect
                mark.comment = CommentInfo(
                    author:String(decoding:UnsafeBufferPointer(start:info.author.data,count:info.author.length),as:UTF8.self),
                    subject:String(decoding:UnsafeBufferPointer(start:info.subject.data,count:info.subject.length),as:UTF8.self),
                    initiallyOpen:info.initially_open != 0,
                    popupRect:info.has_popup != 0 ? CGRect(x:r.0,y:r.1,width:r.2-r.0,height:r.3-r.1):nil,
                    richText:info.rich_text != 0,replyTo:info.reply_to,threadRoot:info.thread_root,
                    reviewState:String(decoding:UnsafeBufferPointer(start:info.review_state.data,count:info.review_state.length),as:UTF8.self),
                    stateModel:String(decoding:UnsafeBufferPointer(start:info.state_model.data,count:info.state_model.length),as:UTF8.self))
            }
            marks.append(mark)
        }
        let replyParents = Set(marks.filter { $0.comment.replyTo != 0 }.map { $0.comment.replyTo })
        for i in marks.indices { marks[i].hasReplies = replyParents.contains(marks[i].id) }
        var linkCount = 0
        guard pod_link_count(doc,index,&linkCount) != 0 else { throw EngineError.current() }
        let links: [PageLink] = try (0..<linkCount).map { i in
            var value = PodLink()
            guard pod_link(doc,index,i,&value) != 0 else { throw EngineError.current() }
            let r = value.rect
            var target = PodDestination()
            guard pod_link_destination(doc,index,i,&target) != 0 else { throw EngineError.current() }
            let destination: PageDestination?
            if target.present != 0 {
                guard let mode = DestinationMode(rawValue:target.mode) else { throw EngineError(message:"Invalid PDF destination mode.") }
                let values = [target.parameters.0,target.parameters.1,target.parameters.2,target.parameters.3]
                destination = PageDestination(page:target.page,mode:mode,parameters:values.enumerated().map { target.fields & (1 << $0.offset) != 0 ? $0.element : nil })
            } else { destination = nil }
            return PageLink(id:value.id,rect:CGRect(x:r.0,y:r.1,width:r.2-r.0,height:r.3-r.1),
                            uri:String(decoding:UnsafeBufferPointer(start:value.uri,count:value.uri_length),as:UTF8.self),
                            base:String(decoding:UnsafeBufferPointer(start:value.base,count:value.base_length),as:UTF8.self),
                            quads:UnsafeBufferPointer(start:value.quads,count:value.point_count).map { CGPoint(x:$0.x,y:$0.y) },
                            hidden:value.hidden != 0,destination:destination)
        }
        return makePageInfo(info, runs: runs, annotations: marks, links: links)
    }

    func previewPNG(_ source: PDFPageIndex, page: Int, width: Int) throws -> Data? {
        let pixels = try source.withPage(page) { try cpuPixels($0, page: 0, width: width) }
        guard let image = pixels.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func previewInfo(_ source: PDFPageIndex, page: Int) throws -> PageInfo {
        try source.withPage(page) { try pageInfo($0, index: 0) }
    }

    // Full-document inspection is also used for exports and shared-document validation.
    func load(_ bytes: Data, page: Int, width: Int, clampPage: Bool = false, view: PageViewState? = nil) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        return try withDocument(bytes) { doc in
            let pages = try (0..<pod_page_count(doc)).map { try pageInfo(doc, index: $0) }
            let page = try targetPage(page, count: pages.count, clamp: clampPage)
            return try rendered(doc, nativePage: page, page: page, width: width, bytes: bytes,
                                pages: pages, source: nil, start: start, view: view)
        }
    }

    func openPage(_ bytes: Data, page: Int, width: Int, clampPage: Bool = false, view: PageViewState? = nil) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        return try displayPage(PDFPageIndex(bytes), bytes: bytes, page: page, width: width, clamp: clampPage, start: start, view: view)
    }

    func turnPage(_ document: LoadedPDF, page: Int, width: Int, view: PageViewState? = nil) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        let source = try document.source ?? PDFPageIndex(document.bytes)
        return try displayPage(source, bytes: document.bytes, page: page, width: width, clamp: false, start: start, view: view ?? document.view)
    }

    func followDestination(_ document: LoadedPDF, destination: PageDestination, viewport: CGSize,
                           currentZoom: CGFloat, currentPoint: CGPoint, backingScale: CGFloat, viewRotation: Int) throws -> (LoadedPDF, DestinationView) {
        let start = ProcessInfo.processInfo.systemUptime
        let source = try document.source ?? PDFPageIndex(document.bytes)
        let page = try targetPage(destination.page,count:source.geometry.count,clamp:false)
        return try source.withPage(page) { doc in
            var pages = source.geometry
            pages[page] = try pageInfo(doc,index:0)
            let original = pages[page]
            let geometry = PageInfo(box:original.box,mediaBox:original.mediaBox,rotation:(original.rotation+viewRotation)%360,
                                    runs:original.runs,annotations:original.annotations,links:original.links)
            var bounds: CGRect?
            if destination.needsContentBounds {
                var value = PodBounds()
                let ok = pod_page_content_bounds_with_fonts(doc,0,fonts.sources,fonts.sources.count,&value)
                guard ok != 0 else { throw EngineError.current() }
                if value.present != 0 { let r=value.rect; bounds=CGRect(x:r.0,y:r.1,width:r.2-r.0,height:r.3-r.1) }
            }
            let view = destination.view(on:geometry,viewport:viewport,currentZoom:currentZoom,currentPoint:currentPoint,contentBounds:bounds)
            let width = min(2400,max(240,Int(original.displaySize.width*view.zoom*backingScale)))
            let loaded = try rendered(doc,nativePage:0,page:page,width:width,bytes:document.bytes,pages:pages,source:source,start:start,view:PageViewState(zoom:Double(view.zoom),rotation:viewRotation))
            return (loaded,view)
        }
    }
    private func targetPage(_ page: Int, count: Int, clamp: Bool) throws -> Int {
        guard count > 0 else { throw EngineError(message: "This PDF has no pages.") }
        if clamp { return min(max(page, 0), count-1) }
        guard (0..<count).contains(page) else { throw EngineError(message: "That page does not exist.") }
        return page
    }

    private func displayPage(_ source: PDFPageIndex, bytes: Data, page: Int, width: Int, clamp: Bool, start: Double, view: PageViewState?) throws -> LoadedPDF {
        let page = try targetPage(page, count: source.geometry.count, clamp: clamp)
        return try source.withPage(page) { doc in
            var pages = source.geometry
            pages[page] = try pageInfo(doc, index: 0)
            return try rendered(doc, nativePage: 0, page: page, width: width, bytes: bytes,
                                pages: pages, source: source, start: start, view: view)
        }
    }

    private func rendered(_ doc: OpaquePointer, nativePage: Int, page: Int, width: Int, bytes: Data,
                          pages: [PageInfo], source: PDFPageIndex?, start: Double, view: PageViewState?) throws -> LoadedPDF {
        guard (1...4096).contains(width) else { throw EngineError(message: "Invalid page raster width.") }
        let metadataMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let fixedView = pages[page].annotations.contains { $0.kind == .comment } ? (view ?? PageViewState()) : nil
        let scene: MetalPage?
        if let fixedView {
            scene = metal?.pageView(document:doc,page:nativePage,fonts:fonts.sources,width:width,zoom:fixedView.zoom,rotation:fixedView.rotation)
        } else { scene = metal?.scene(document:doc,page:nativePage,fonts:fonts.sources,width:width) }
        let preview = scene?.bitmap(width: min(width, 512))
        let pixels = try preview ?? cpuPixels(doc, page: nativePage, width: width, view: fixedView)
        return LoadedPDF(pageIndex: page, bytes: bytes, pages: pages, pixels: pixels,
                         metalPage: preview == nil ? nil : scene, view: fixedView, source: source, metadataMS: metadataMS,
                         elapsedMS: (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    private func cpuPixels(_ doc: OpaquePointer, page: Int, width: Int, view: PageViewState? = nil) throws -> PagePixels {
        var bitmap = PodBitmap()
        let ok: Int32
        if let view {
            guard [0,90,180,270].contains(view.rotation) else { throw EngineError(message:"Invalid page view.") }
            ok = pod_render_page_view(doc,page,fonts.sources,fonts.sources.count,UInt32(width),view.zoom,Int32(view.rotation),&bitmap)
        } else { ok = pod_render_with_fonts(doc, page, fonts.sources, fonts.sources.count, UInt32(width), &bitmap) }
        guard ok != 0, let pixels = bitmap.data else { throw EngineError.current() }
        let data = Data(bytesNoCopy: pixels, count: bitmap.length, deallocator: .custom { pointer, length in
            pod_buffer_free(pointer.assumingMemoryBound(to: UInt8.self), length)
        })
        return PagePixels(data: data, width: Int(bitmap.width), height: Int(bitmap.height))
    }
    // Re-render after magnification/rotation changes; icons are fixed in this view's pixels.
    func pageViewPixels(_ source: PDFPageIndex, page: Int, width: Int, zoom: Double, rotation: Int = 0) throws -> PagePixels {
        guard (1...4096).contains(width), zoom.isFinite, zoom > 0, zoom <= 1e6,
              [0,90,180,270].contains(rotation) else { throw EngineError(message:"Invalid page view.") }
        return try source.withPage(page) { doc in
            if let image = metal?.pageView(document:doc,page:0,fonts:fonts.sources,width:width,zoom:zoom,rotation:rotation)?.bitmap(width:width) { return image }
            var bitmap = PodBitmap()
            guard pod_render_page_view(doc,0,fonts.sources,fonts.sources.count,UInt32(width),zoom,Int32(rotation),&bitmap) != 0,
                  let pixels = bitmap.data else { throw EngineError.current() }
            let data = Data(bytesNoCopy:pixels,count:bitmap.length,deallocator:.custom { pointer,length in
                pod_buffer_free(pointer.assumingMemoryBound(to:UInt8.self),length)
            })
            return PagePixels(data:data,width:Int(bitmap.width),height:Int(bitmap.height))
        }
    }
    // An isolated normal-appearance preview, separate from whole-page composition.
    func annotationAppearance(_ source: PDFPageIndex, page: Int, annotation: UInt32, width: Int) throws -> PagePixels {
        guard (1...4096).contains(width) else { throw EngineError(message:"Invalid appearance preview width.") }
        return try source.withPage(page) { doc in
            if let image = metal?.annotationAppearance(document:doc,page:0,annotation:annotation,fonts:fonts.sources,width:width)?.bitmap(width:width) {
                return image
            }
            var bitmap = PodBitmap()
            guard pod_render_annotation_appearance_with_fonts(doc,0,annotation,fonts.sources,fonts.sources.count,UInt32(width),&bitmap) != 0,
                  let pixels = bitmap.data else { throw EngineError.current() }
            let data = Data(bytesNoCopy:pixels,count:bitmap.length,deallocator:.custom { pointer,length in
                pod_buffer_free(pointer.assumingMemoryBound(to:UInt8.self),length)
            })
            return PagePixels(data:data,width:Int(bitmap.width),height:Int(bitmap.height))
        }
    }

    func replace(_ bytes: Data, page: Int, run: Int, text: String) throws -> Data {
        try withDocument(bytes) { doc in
            let input=Array(text.utf8)
            let ok = input.withUnsafeBufferPointer { buffer in
                // A non-null pointer is required by the ABI even for an empty replacement.
                var empty: UInt8=0
                if buffer.isEmpty { return pod_replace(doc,page,run,&empty,0) }
                return pod_replace(doc,page,run,buffer.baseAddress!,buffer.count)
            }
            guard ok != 0 else { throw EngineError.current() }
            var output=PodBuffer()
            guard pod_save(doc,&output) != 0, let data=output.data else { throw EngineError.current() }
            defer { pod_buffer_free(data,output.length) }
            return Data(bytes:data,count:output.length)
        }
    }
    private func output(_ action: (UnsafeMutablePointer<PodBuffer>) -> Int32) throws -> Data {
        var buffer=PodBuffer()
        guard action(&buffer) != 0, let data=buffer.data else { throw EngineError.current() }
        defer { pod_buffer_free(data,buffer.length) }
        return Data(bytes:data,count:buffer.length)
    }
    func selectPages(_ bytes: Data, indices: [Int]) throws -> Data {
        guard !indices.isEmpty,indices.count<=100_000,indices.allSatisfy({$0>=0}) else { throw EngineError(message:"Choose at least one valid page.") }
        return try withDocument(bytes) { doc in
            try indices.withUnsafeBufferPointer { pages in try output { pod_select_pages(doc,pages.baseAddress,pages.count,$0) } }
        }
    }
    func merge(_ bytes: Data, with other: Data) throws -> Data {
        try withDocument(bytes) { doc in try withDocument(other) { source in try output { pod_merge(doc,source,$0) } } }
    }
    func rotate(_ bytes: Data, page: Int, degrees: Int32) throws -> Data {
        guard page>=0 else { throw EngineError(message:"Choose a valid page.") }
        return try withDocument(bytes) { doc in try output { pod_rotate_page(doc,page,degrees,$0) } }
    }
    func crop(_ bytes: Data, page: Int, box: CGRect) throws -> Data {
        guard page>=0 else { throw EngineError(message:"Choose a valid page.") }
        return try withDocument(bytes) { doc in try output { pod_crop_page(doc,page,box.minX,box.minY,box.maxX,box.maxY,$0) } }
    }
    func splitPages(_ bytes: Data, to parent: URL) throws -> URL {
        try withDocument(bytes) { doc in
            let count=pod_page_count(doc)
            guard count>0 else { throw EngineError(message:"This PDF has no pages to split.") }
            let directory=parent.appendingPathComponent("Pod pages - \(UUID().uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
            do {
                for page in 0..<count {
                    var index=page
                    let data=try output { pod_select_pages(doc,&index,1,$0) }
                    let file=directory.appendingPathComponent(String(format:"Page %05d.pdf",page+1))
                    try data.write(to:file,options:.withoutOverwriting)
                }
                return directory
            } catch {
                // Only this call's newly created directory is removed on failure.
                try? FileManager.default.removeItem(at:directory)
                throw error
            }
        }
    }
    func erasePreview(_ source: PDFPageIndex, page: Int, width: Int, marks: [Markup], deleting: [UInt32], view: PageViewState? = nil) throws -> CGImage? {
        try source.withPage(page) { doc in
            try applyAnnotations(doc, page: 0, marks: marks, deleting: deleting)
            return try cpuPixels(doc, page: 0, width: width, view: view).cgImage
        }
    }

    private func applyAnnotations(_ doc: OpaquePointer, page: Int, marks: [Markup], deleting: [UInt32]) throws {
        for id in deleting { guard pod_annotation_remove(doc,page,id) != 0 else { throw EngineError.current() } }
        for mark in marks {
            if mark.id == 0, mark.comment.replyTo != 0 {
                let text = Array(mark.text.utf8), author = Array(mark.comment.author.utf8)
                var id: UInt32 = 0
                let ok = text.withUnsafeBufferPointer { text in author.withUnsafeBufferPointer { author in
                    pod_comment_reply(doc,page,mark.comment.replyTo,text.baseAddress,text.count,author.baseAddress,author.count,&id)
                } }
                guard ok != 0 else { throw EngineError.current() }
                continue
            }
            let points=mark.points.map{PodPoint(x:$0.x,y:$0.y)}
            let text=Array(mark.text.utf8)+[0]
            guard !points.isEmpty else { throw EngineError(message:"An annotation must contain at least one point.") }
            let link=Array(mark.link.utf8)
            let ok=mark.inkPathStarts.withUnsafeBufferPointer { starts in link.withUnsafeBufferPointer { url in
                points.withUnsafeBufferPointer { p in text.withUnsafeBufferPointer { t in
                    pod_annotation_put_with_ink(doc,page,mark.id,mark.kind.rawValue,p.baseAddress!,p.count,t.baseAddress!,t.count-1,mark.style.cValue,starts.baseAddress,starts.count,url.baseAddress,url.count)
                }}
            }}
            guard ok != 0 else { throw EngineError.current() }
        }
    }

    func annotate(_ bytes:Data,page:Int,marks:[Markup],deleting:[UInt32]=[]) throws -> Data {
        try withDocument(bytes) { doc in
            try applyAnnotations(doc, page: page, marks: marks, deleting: deleting)
            var output=PodBuffer()
            guard pod_save(doc,&output) != 0,let data=output.data else { throw EngineError.current() }
            defer { pod_buffer_free(data,output.length) }
            return Data(bytes:data,count:output.length)
        }
    }
    static func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let limit = 256 * 1024 * 1024
        let tooLarge = EngineError(message: "This PDF exceeds Pod's current 256 MB input limit.")
        guard size <= limit else { throw tooLarge }
        let bytes: Data
        if size >= 64 * 1024, let mapped = mappedSnapshot(of: url) {
            bytes = mapped
        } else {
            bytes = try Data(contentsOf: url)
        }
        guard bytes.count <= limit else { throw tooLarge }
        guard !bytes.isEmpty else { throw EngineError(message:"This file is empty.") }
        return bytes
    }

    // Map a private copy-on-write clone so edits or truncation of the original
    // cannot invalidate the parser's borrowed pointers. Unlink after mapping.
    private static func mappedSnapshot(of url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else { return nil }
        let clone = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard fclonefileat(fd, AT_FDCWD, clone.path, UInt32(CLONE_NOOWNERCOPY)) == 0 else { return nil }
        defer { unlink(clone.path) }
        return try? Data(contentsOf: clone, options: .alwaysMapped)
    }
}
