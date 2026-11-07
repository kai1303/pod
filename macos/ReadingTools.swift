import AppKit
import PDFKit

// PDFKit supplies the system's text selection and reading order. Pod's engine owns all edits.
struct ReadingPassage {
    let text: String
    let lines: [CGRect]

    init?(_ selection: PDFSelection?, page: PDFPage) {
        guard let selection, let text = selection.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.text = text
        lines = selection.selectionsByLine().map { $0.bounds(for: page) }
            .filter { !$0.isEmpty && !$0.isInfinite }
        if lines.isEmpty { return nil }
    }

    func markup(_ kind: MarkupKind, style: MarkupStyle, note: String = "") -> Markup {
        let points = lines.flatMap { r in
            [CGPoint(x:r.minX,y:r.maxY), CGPoint(x:r.maxX,y:r.maxY),
             CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.maxX,y:r.minY)]
        }
        return Markup(kind:kind, points:points, rect:lines.reduce(.null) { $0.union($1) }, text:note, style:style)
    }
}

final class ReadingIndex {
    struct Hit {
        let page: Int
        let range: NSRange?
        let annotation: UInt32?
        let kind: String
        let snippet: String
        let note: String
    }
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    static let limit = 1000
    func cancel() { queue.cancelAllOperations() }

    func scan(bytes: Data, query: String?, failed: @escaping (Error) -> Void = { _ in }, done: @escaping ([Hit], Bool) -> Void) {
        cancel()
        let work = BlockOperation()
        work.addExecutionBlock { [weak work] in
            guard let work, !work.isCancelled, let document = PDFDocument(data:bytes) else { return }
            do {
                let source = query == nil ? try PDFPageIndex(bytes):nil
                let engine = query == nil ? try Engine():nil
                var hits = [Hit]()
                for index in 0..<document.pageCount {
                    guard !work.isCancelled else { return }
                    try autoreleasepool {
                        guard let page = document.page(at:index) else { return }
                        if let query {
                            let text = (page.string ?? "") as NSString
                            var start = 0
                            while start < text.length && !work.isCancelled && hits.count <= Self.limit {
                                let range = text.range(of:query, options:.caseInsensitive, range:NSRange(location:start,length:text.length-start))
                                guard range.location != NSNotFound, range.length > 0 else { break }
                                let left = max(0, range.location-32)
                                let right = min(text.length, NSMaxRange(range)+48)
                                let snippet = text.substring(with:NSRange(location:left,length:right-left))
                                hits.append(Hit(page:index, range:range, annotation:nil, kind:"Match", snippet:snippet, note:""))
                                start = NSMaxRange(range)
                            }
                        } else {
                            // PDFKit does not expose IRT reliably. Pod owns annotation identity
                            // and thread relationships; PDFKit only supplies passage snippets.
                            let info = try engine!.previewInfo(source!,page:index)
                            let marks = info.annotations
                            let types: [MarkupKind:String] = [.highlight:"Highlight",.underline:"Underline",.squiggly:"Squiggly",.strikeout:"StrikeOut",.comment:"Text"]
                            for mark in marks {
                                guard !work.isCancelled, hits.count <= Self.limit else { break }
                                guard let type = types[mark.kind] ?? (mark.importedShape ? mark.kind.title:nil), mark.comment.replyTo == 0 else { continue }
                                let rect = mark.points.prefix(4).reduce(CGRect.null) { $0.union(CGRect(origin:$1,size:.zero)) }
                                let snippet = type == "Text" || info.runs.isEmpty ? "" : page.selection(for:rect.isNull ? mark.rect:rect)?.string ?? ""
                                hits.append(Hit(page:index, range:nil, annotation:mark.id, kind:type, snippet:String(snippet.prefix(160)), note:mark.text))
                            }
                        }
                    }
                    if hits.count > Self.limit { break }
                }
                let truncated = hits.count > Self.limit
                if truncated { hits.removeLast() }
                DispatchQueue.main.async { if !work.isCancelled { done(hits,truncated) } }
            } catch { DispatchQueue.main.async { if !work.isCancelled { failed(error) } } }
        }
        queue.addOperation(work)
    }
}
