import Foundation
import CoreGraphics
import AppKit

struct TextRun {
    let id: Int
    let text: String
    let size: Double
    let bounds: CGRect
}
struct PageInfo {
    let box: CGRect
    let mediaBox: CGRect
    let rotation: Int
    let runs: [TextRun]
    let annotations: [Markup]
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
private func makePageInfo(_ page: PodPage, runs: [TextRun] = [], annotations: [Markup] = []) -> PageInfo {
    let m = page.media
    return PageInfo(box: CGRect(x: page.x, y: page.y, width: page.width, height: page.height),
                    mediaBox: CGRect(x: m.0, y: m.1, width: m.2-m.0, height: m.3-m.1),
                    rotation: Int(page.rotation), runs: runs, annotations: annotations)
}

final class PDFPageIndex {
    // NSData guarantees a stable byte pointer while the native index borrows it.
    private let storage: NSData
    private let handle: OpaquePointer
    let geometry: [PageInfo]

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
}
struct LoadedPDF {
    let pageIndex: Int
    let bytes: Data
    let pages: [PageInfo]
    let pixels: PagePixels
    let metalPage: MetalPage?
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
        case "AnnotationLocked": message = "This drawing is locked in the PDF."
        case "UnsupportedAnnotationAppearance": message = "This PDF contains an ink appearance Pod cannot preserve during editing."
        case "InvalidAnnotationLink": message = "Enter a complete HTTP or HTTPS address for this drawing."
        case "InvalidCropBox": message = "The crop must have a positive width and height and stay inside the original page."
        case "PageNotFound", "DuplicatePage", "EmptyPageSelection": message = "Choose valid page numbers without repeats. Keep at least one page."
        case "TextOverflow": message = "The replacement is wider than the selected text. Use a shorter line so the rest of the page stays in place."
        case "UnsupportedEncoding": message = "This version supports printable English characters (ASCII) only."
        case "InvalidHeader": message = "This file is not a readable PDF."
        default:
            if code.hasPrefix("Unsupported") {
                message = "This PDF uses a feature Pod cannot display yet (\(code)). Try the included sample. Your file has not been changed."
            } else { message = "Pod could not process this document (\(code)). Your file has not been changed." }
        }
        return EngineError(message: message)
    }
}

// Engine calls run on the controller's serial worker queue. No PDF API is used by Swift.
final class Engine {
    private let font: Data
    private let metal: MetalPageRenderer?
    init(metal: MetalPageRenderer? = nil) throws {
        self.metal = metal
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Courier New.ttf")
        guard let data = try? Data(contentsOf: url) else {
            throw EngineError(message: "Courier New is missing from this Mac. Install it in Font Book to use Pod's initial Courier renderer.")
        }
        font = data
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
            let b=run.bounds
            runs.append(TextRun(id:id,text:text,size:run.size,bounds:CGRect(x:b.0,y:b.1,width:max(0,b.2-b.0),height:max(0,b.3-b.1))))
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
            mark.inkLocked = value.ink_locked != 0
            marks.append(mark)
        }
        return makePageInfo(info, runs: runs, annotations: marks)
    }

    func previewPNG(_ source: PDFPageIndex, page: Int, width: Int) throws -> Data? {
        let pixels = try source.withPage(page) { try cpuPixels($0, page: 0, width: width) }
        guard let provider = CGDataProvider(data: pixels.data as CFData),
              let image = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func previewInfo(_ source: PDFPageIndex, page: Int) throws -> PageInfo {
        try source.withPage(page) { try pageInfo($0, index: 0) }
    }

    // Full-document inspection is also used for exports and shared-document validation.
    func load(_ bytes: Data, page: Int, width: Int, clampPage: Bool = false) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        return try withDocument(bytes) { doc in
            let pages = try (0..<pod_page_count(doc)).map { try pageInfo(doc, index: $0) }
            let page = try targetPage(page, count: pages.count, clamp: clampPage)
            return try rendered(doc, nativePage: page, page: page, width: width, bytes: bytes,
                                pages: pages, source: nil, start: start)
        }
    }

    func openPage(_ bytes: Data, page: Int, width: Int, clampPage: Bool = false) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        return try displayPage(PDFPageIndex(bytes), bytes: bytes, page: page, width: width, clamp: clampPage, start: start)
    }

    func turnPage(_ document: LoadedPDF, page: Int, width: Int) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        let source = try document.source ?? PDFPageIndex(document.bytes)
        return try displayPage(source, bytes: document.bytes, page: page, width: width, clamp: false, start: start)
    }

    private func targetPage(_ page: Int, count: Int, clamp: Bool) throws -> Int {
        guard count > 0 else { throw EngineError(message: "This PDF has no pages.") }
        if clamp { return min(max(page, 0), count-1) }
        guard (0..<count).contains(page) else { throw EngineError(message: "That page does not exist.") }
        return page
    }

    private func displayPage(_ source: PDFPageIndex, bytes: Data, page: Int, width: Int, clamp: Bool, start: Double) throws -> LoadedPDF {
        let page = try targetPage(page, count: source.geometry.count, clamp: clamp)
        return try source.withPage(page) { doc in
            var pages = source.geometry
            pages[page] = try pageInfo(doc, index: 0)
            return try rendered(doc, nativePage: 0, page: page, width: width, bytes: bytes,
                                pages: pages, source: source, start: start)
        }
    }

    private func rendered(_ doc: OpaquePointer, nativePage: Int, page: Int, width: Int, bytes: Data,
                          pages: [PageInfo], source: PDFPageIndex?, start: Double) throws -> LoadedPDF {
        guard (1...4096).contains(width) else { throw EngineError(message: "Invalid page raster width.") }
        let metadataMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let scene = metal?.scene(document: doc, page: nativePage, font: font, width: width)
        let preview = scene?.bitmap(width: min(width, 512))
        let pixels = try preview ?? cpuPixels(doc, page: nativePage, width: width)
        return LoadedPDF(pageIndex: page, bytes: bytes, pages: pages, pixels: pixels,
                         metalPage: preview == nil ? nil : scene, source: source, metadataMS: metadataMS,
                         elapsedMS: (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    private func cpuPixels(_ doc: OpaquePointer, page: Int, width: Int) throws -> PagePixels {
        var bitmap = PodBitmap()
        let ok = font.withUnsafeBytes { raw in
            pod_render(doc, page, raw.bindMemory(to: UInt8.self).baseAddress!, font.count, UInt32(width), &bitmap)
        }
        guard ok != 0, let pixels = bitmap.data else { throw EngineError.current() }
        let data = Data(bytesNoCopy: pixels, count: bitmap.length, deallocator: .custom { pointer, length in
            pod_buffer_free(pointer.assumingMemoryBound(to: UInt8.self), length)
        })
        return PagePixels(data: data, width: Int(bitmap.width), height: Int(bitmap.height))
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
    func annotate(_ bytes:Data,page:Int,marks:[Markup],deleting:[UInt32]=[]) throws -> Data {
        try withDocument(bytes) { doc in
            for id in deleting { guard pod_annotation_remove(doc,page,id) != 0 else { throw EngineError.current() } }
            for mark in marks {
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
            var output=PodBuffer()
            guard pod_save(doc,&output) != 0,let data=output.data else { throw EngineError.current() }
            defer { pod_buffer_free(data,output.length) }
            return Data(bytes:data,count:output.length)
        }
    }
    static func read(_ url: URL) throws -> Data {
        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw EngineError(message:"This PDF exceeds Pod's current 256 MB input limit.") }
        let bytes=try Data(contentsOf:url)
        guard !bytes.isEmpty else { throw EngineError(message:"This file is empty.") }
        return bytes
    }
}
