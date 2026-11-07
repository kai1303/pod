// Main-thread request bookkeeping. The worker owns its index and renderer.
import AppKit

final class NavigationPreviews {
    private struct Key: Hashable {
        let revision: String
        let page: Int       // One-based, like the navigation UI.
        let width: Int
    }
    private struct Entry {
        let png: Data
        let cost: Int
    }
    private struct Request {
        let operation: BlockOperation
        var callbacks: [UUID: (Data?) -> Void]
    }
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private let budget = 4 * 1024 * 1024
    private var cache: [Key: Entry] = [:]
    private var order: [Key] = []
    private(set) var cachedBytes = 0
    private var pending: [Key: Request] = [:]
    private var prepare: Operation?
    private final class Snapshot {
        let bytes: Data
        // Initialized only on the serial render queue and only if a preview is needed.
        lazy var source = try? PDFPageIndex(bytes)
        init(_ bytes: Data) { self.bytes = bytes }
    }
    private var snapshot: Snapshot?
    private weak var displayIndex: PDFPageIndex?
    private var count = 0
    private(set) var revision = ""
    private var thumbnailRevision = ""
    private var versions: [Int: String] = [:]
    private var renderer: Engine?

    func update(_ document: LoadedPDF, changedPage: Int? = nil, publish: @escaping ([String: Any]) -> Void) {
        // Turning a page reuses its index. Comparing two different file
        // mappings byte by byte here could fault their contents into RAM.
        if let source = document.source {
            guard displayIndex !== source else { return }
        } else if snapshot?.bytes == document.bytes {
            return
        }
        displayIndex = document.source
        snapshot = Snapshot(document.bytes)
        revision = UUID().uuidString
        let localEdit = changedPage != nil && count == document.pages.count && !thumbnailRevision.isEmpty
        count = document.pages.count
        if localEdit, let changedPage {
            versions[changedPage + 1] = revision
        } else {
            thumbnailRevision = revision
            versions.removeAll()
        }
        for key in order where !isCurrent(key) { evict(key) }
        let obsolete = pending.keys.filter { !isCurrent($0) }
        for key in obsolete {
            guard let request = pending.removeValue(forKey: key) else { continue }
            request.operation.cancel()
            for callback in request.callbacks.values { callback(nil) }
        }

        let token = revision, data = document.bytes, pageCount = count
        var state: [String: Any] = ["previewRevision": token, "thumbnailRevision": thumbnailRevision,
                                   "thumbnailVersions": Dictionary(uniqueKeysWithValues: versions.map { (String($0.key), $0.value) })]
        if !localEdit {
            state["pageSizes"] = document.pages.map { [$0.displaySize.width, $0.displaySize.height] }
            state["outlines"] = []
        }
        if localEdit {
            publish(state)
            return
        }
        prepare?.cancel()
        prepare = nil
        if document.source?.hasOutlines == false {
            publish(state)
            return
        }
        let preparation = BlockOperation { [weak self] in
            let outlines = Self.outlines(in: data, count: pageCount)
            DispatchQueue.main.async { if self?.thumbnailRevision == token { publish(["outlines": outlines]) } }
        }
        prepare = preparation
        queue.addOperation(preparation)
        publish(state)
    }

    func deferRendering(_ busy: Bool) {
        queue.isSuspended = busy
    }

    private func isCurrent(_ key: Key) -> Bool {
        key.page > 0 && key.page <= count &&
        key.revision == (key.width == 160 ? versions[key.page] ?? thumbnailRevision : revision)
    }

    private func evict(_ key: Key) {
        if let entry = cache.removeValue(forKey: key) { cachedBytes -= entry.cost }
        order.removeAll { $0 == key }
    }

    func thumbnail(page: Int, completion: @escaping (Data?) -> Void) -> () -> Void {
        request(Key(revision: versions[page] ?? thumbnailRevision, page: page, width: 160), completion)
    }

    func request(_ url: URL, completion: @escaping (Data?) -> Void) -> () -> Void {
        let parts = url.pathComponents
        guard parts.count == 5, let page = Int(parts[3]), let width = Int(parts[4]),
              [96, 160, 896].contains(width) else { completion(nil); return {} }
        return request(Key(revision: parts[2], page: page, width: width), completion)
    }

    private func request(_ key: Key, _ completion: @escaping (Data?) -> Void) -> () -> Void {
        guard isCurrent(key), let snapshot else { completion(nil); return {} }
        if let entry = cache[key] {
            order.removeAll { $0 == key }
            order.append(key)
            completion(entry.png)
            return {}
        }
        let id = UUID()
        if pending[key] != nil {
            pending[key]?.callbacks[id] = completion
        } else {
            let op = BlockOperation()
            op.addExecutionBlock { [weak self, weak op] in
                guard let self, let op, !op.isCancelled else { return }
                var png: Data?
                var cost = 0
                if let source = snapshot.source, source.geometry.indices.contains(key.page - 1) {
                    let size = source.geometry[key.page - 1].displaySize
                    let limit: CGFloat = key.width == 160 ? 224 : 2048
                    let width = max(1, Int(min(CGFloat(key.width), limit * size.width / size.height)))
                    if self.renderer == nil { self.renderer = try? Engine() }
                    png = try? self.renderer?.previewPNG(source, page: key.page - 1, width: width)
                    if png != nil { cost = width * Int(ceil(CGFloat(width) * size.height / size.width)) * 4 }
                }
                DispatchQueue.main.async {
                    guard self.pending[key]?.operation === op, let request = self.pending.removeValue(forKey: key) else { return }
                    if let png, key.width == 160 {
                        let cost = max(png.count, cost)
                        if cost <= self.budget {
                            while self.cachedBytes + cost > self.budget, let oldest = self.order.first { self.evict(oldest) }
                            self.cache[key] = Entry(png: png, cost: cost)
                            self.order.append(key)
                            self.cachedBytes += cost
                        }
                    }
                    for callback in request.callbacks.values { callback(png) }
                }
            }
            pending[key] = Request(operation: op, callbacks: [id: completion])
            queue.addOperation(op)
        }
        return { [weak self] in
            guard let self else { return }
            self.pending[key]?.callbacks.removeValue(forKey: id)
            if self.pending[key]?.callbacks.isEmpty == true {
                self.pending.removeValue(forKey: key)?.operation.cancel()
            }
        }
    }
    private static func outlines(in bytes: Data, count: Int) -> [[String: Any]] {
        guard let provider = CGDataProvider(data: bytes as CFData), let pdf = CGPDFDocument(provider),
              let root = pdf.outline as NSDictionary? else { return [] }
        var result = [[String: Any]]()
        func visit(_ node: NSDictionary, depth: Int) {
            guard depth < 64, let children = node[kCGPDFOutlineChildren] as? [NSDictionary] else { return }
            for child in children {
                if let title = child[kCGPDFOutlineTitle] as? String,
                   let page = child[kCGPDFOutlineDestination] as? Int, (1...count).contains(page) {
                    result.append(["title": title, "page": page, "depth": depth])
                }
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return result
    }
}
