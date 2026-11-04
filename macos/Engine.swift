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
    let runs: [TextRun]
    let annotations: [Markup]
}
struct PagePixels {
    let data: Data
    let width: Int
    let height: Int
}
struct LoadedPDF {
    let bytes: Data
    let pages: [PageInfo]
    let pixels: PagePixels
    let elapsedMS: Double
}
struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func current() -> EngineError {
        let code = String(cString: pod_error())
        let message: String
        switch code {
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
    init() throws {
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
    func load(_ bytes: Data, page: Int, width: Int) throws -> LoadedPDF {
        let start = ProcessInfo.processInfo.systemUptime
        return try withDocument(bytes) { doc in
            var pages: [PageInfo] = []
            for index in 0..<pod_page_count(doc) {
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
                    marks.append(Markup(id:value.id,kind:kind,points:points,rect:CGRect(x:r.0,y:r.1,width:r.2-r.0,height:r.3-r.1),text:text,style:MarkupStyle(value.style)))
                }
                pages.append(PageInfo(box:CGRect(x:info.x,y:info.y,width:info.width,height:info.height),runs:runs,annotations:marks))
            }
            guard !pages.isEmpty else { throw EngineError(message:"This PDF has no pages.") }
            guard pages.indices.contains(page) else { throw EngineError(message:"That page does not exist.") }
            var bitmap = PodBitmap()
            let ok = font.withUnsafeBytes { raw in pod_render(doc,page,raw.bindMemory(to:UInt8.self).baseAddress!,font.count,UInt32(width),&bitmap) }
            guard ok != 0, let pixels=bitmap.data else { throw EngineError.current() }
            defer { pod_buffer_free(pixels,bitmap.length) }
            return LoadedPDF(bytes:bytes,pages:pages,pixels:PagePixels(data:Data(bytes:pixels,count:bitmap.length),width:Int(bitmap.width),height:Int(bitmap.height)),elapsedMS:(ProcessInfo.processInfo.systemUptime-start)*1000)
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
    func annotate(_ bytes:Data,page:Int,marks:[Markup],deleting:[UInt32]=[]) throws -> Data {
        try withDocument(bytes) { doc in
            for id in deleting { guard pod_annotation_remove(doc,page,id) != 0 else { throw EngineError.current() } }
            for mark in marks {
                let points=mark.points.map{PodPoint(x:$0.x,y:$0.y)}
                let text=Array(mark.text.utf8)+[0]
                let ok=points.withUnsafeBufferPointer { p in text.withUnsafeBufferPointer { t in
                    pod_annotation_put(doc,page,mark.id,mark.kind.rawValue,p.baseAddress!,p.count,t.baseAddress!,t.count-1,mark.style.cValue)
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
