import AppKit
import WebKit

// React owns editor chrome; the existing native PDF canvas remains the document view.
private final class ReactAssetHandler:NSObject,WKURLSchemeHandler {
    var preview: ((URL, @escaping (Data?) -> Void) -> () -> Void)?
    private var pending: [ObjectIdentifier: () -> Void] = [:]
    private let root:URL
    init(root:URL) { self.root=root.resolvingSymlinksInPath() }
    func webView(_ webView:WKWebView,start task:WKURLSchemeTask) {
        guard let url=task.request.url,url.host=="editor" else { task.didFailWithError(URLError(.badURL)); return }
        if url.path.hasPrefix("/page-preview/"), let preview {
            let id = ObjectIdentifier(task)
            pending[id] = {}
            let cancel = preview(url) { [weak self] bytes in
                guard self?.pending.removeValue(forKey: id) != nil else { return }
                guard let bytes else { task.didFailWithError(URLError(.resourceUnavailable)); return }
                task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: bytes.count, textEncodingName: nil))
                task.didReceive(bytes)
                task.didFinish()
            }
            if pending[id] != nil { pending[id] = cancel }
            return
        }
        let file=root.appendingPathComponent(url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path+"/"),let data=try? Data(contentsOf:file) else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
        let types=["html":"text/html","js":"text/javascript","css":"text/css","png":"image/png","svg":"image/svg+xml","ttf":"font/ttf","woff2":"font/woff2","json":"application/json"]
        let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:["Content-Type":types[file.pathExtension] ?? "application/octet-stream","Access-Control-Allow-Origin":"*","Cache-Control":"no-cache"])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView:WKWebView,stop task:WKURLSchemeTask) { pending.removeValue(forKey: ObjectIdentifier(task))?() }
}

private final class ReactMessageProxy:NSObject,WKScriptMessageHandler {
    weak var owner:ReactEditor?
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) { owner?.userContentController(controller,didReceive:message) }
}

final class ReactEditor:NSView,WKScriptMessageHandler,WKNavigationDelegate {
    private let assets: ReactAssetHandler
    var onPagePreview: ((URL, @escaping (Data?) -> Void) -> () -> Void)? {
        didSet { assets.preview = onPagePreview }
    }
    let webView:WKWebView
    let canvasScroll:NSScrollView
    var onCommand:((String,[String:Any])->Void)?
    var onDeleteEase: (([Double]) -> Void)?
    var onViewportChange:(()->Void)?
    private(set) var needsPageBackdrop = false
    private var pageTurnSamples: [Double] = []
    private var ready=false
    private var latest:[String:Any]=[:]
    private var clipObserver:NSObjectProtocol?
    private var wheelMonitor: Any?
    private var readingWheel = false
    override var isFlipped:Bool { true }
    init(resources:URL,canvas:NSScrollView) {
        canvasScroll=canvas
        let configuration=WKWebViewConfiguration()
        assets = ReactAssetHandler(root: resources)
        configuration.setURLSchemeHandler(assets,forURLScheme:"pod-ui")
        configuration.userContentController.addUserScript(WKUserScript(source:"window.__POD_NATIVE__=true;",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        webView=WKWebView(frame:.zero,configuration:configuration)
        super.init(frame:.zero)
        let proxy=ReactMessageProxy(); proxy.owner=self; configuration.userContentController.add(proxy,name:"pod")
        webView.navigationDelegate=self
        webView.autoresizingMask=[.width,.height]
        webView.setAccessibilityLabel("Pod editor controls")
        canvas.removeFromSuperview(); canvas.translatesAutoresizingMaskIntoConstraints=true
        addSubview(webView); addSubview(canvas)
        canvas.isHidden=true
        clipObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:canvas.contentView,queue:.main) { [weak self] _ in self?.onViewportChange?() }
        canvas.contentView.postsBoundsChangedNotifications=true
        webView.load(URLRequest(url:URL(string:"pod-ui://editor/index.html")!))
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
        guard window != nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.readingWheel, event.window === self.window,
                  !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  self.canvasScroll.frame.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            // WebKit normalizes wheel ticks to pixels. Preserve their line units for the reader.
            self.webView.callAsyncJavaScript("""
                document.querySelector('.reading-pages[data-continuous="true"]')?.dispatchEvent(
                  new WheelEvent('wheel', {deltaY: lines, deltaMode: 1, cancelable: true}));
                """, arguments: ["lines": -event.scrollingDeltaY], in: nil, in: .page, completionHandler: nil)
            return nil
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }; if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }; webView.configuration.userContentController.removeScriptMessageHandler(forName:"pod") }
    override func layout() { super.layout(); webView.frame=bounds }
    func animatePageTurn(forward: Bool) {
        guard !canvasScroll.isHidden, !pageTurnSamples.isEmpty,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let page = canvasScroll.documentView else { return }
        page.wantsLayer = true
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let offset = forward ? 10.0 : -10.0
        slide.values = pageTurnSamples.map { (1 - $0) * offset }
        slide.duration = 0.2
        page.layer?.add(slide, forKey: "pageTurn")
    }
    func setState(_ state:[String:Any]) {
        latest.merge(state,uniquingKeysWith:{$1})
        guard ready else { return }
        webView.callAsyncJavaScript("window.__POD_STATE__=Object.assign(window.__POD_STATE__||{},state);window.dispatchEvent(new CustomEvent('pod:state',{detail:state}));",arguments:["state":state],in:nil,in:.page,completionHandler:nil)
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame,let url=message.frameInfo.request.url,url.scheme=="pod-ui",url.host=="editor",let body=message.body as? [String:Any],let command=body["command"] as? String else { return }
        let data=body["data"] as? [String:Any] ?? [:]
        if command=="ready" {
            if let samples = data["deleteEaseSamples"] as? [Double], (2...120).contains(samples.count),
               samples.first == 0, samples.last == 1, samples.allSatisfy({ (0...1).contains($0) }) {
                onDeleteEase?(samples)
            }
            if let samples = data["pageTurnSamples"] as? [Double], (2...120).contains(samples.count),
               samples.allSatisfy({ (0...1).contains($0) }) { pageTurnSamples = samples }
            ready=true; setState(latest); onViewportChange?(); return
        }
        if command=="layout" {
            guard let x=data["x"] as? Double,let y=data["y"] as? Double,let width=data["width"] as? Double,let height=data["height"] as? Double,[x,y,width,height].allSatisfy({$0.isFinite}),width>=0,height>=0 else { return }
            let rect=NSRect(x:x,y:y,width:width,height:height).intersection(bounds)
            readingWheel = data["readingWheel"] as? Bool ?? false
            needsPageBackdrop = data["backdrop"] as? Bool ?? (data["overlay"] as? Bool ?? false)
            canvasScroll.frame=rect.isNull ? .zero:rect
            canvasScroll.isHidden=(data["overlay"] as? Bool ?? false) || rect.isNull || width<1 || height<1
            onViewportChange?(); return
        }
        onCommand?(command,data)
    }
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!) { ready=false; readingWheel=false; canvasScroll.isHidden=true }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url else { decisionHandler(.cancel); return }
        let allowed=url.scheme=="pod-ui" && url.host=="editor"
        if !allowed,navigationAction.navigationType == .linkActivated,["https","http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(allowed ? .allow:.cancel)
    }
}
