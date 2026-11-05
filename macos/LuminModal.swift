import AppKit

private final class LuminModalBackdrop:NSView {
    var onClose:(()->Void)?
    var contentFrame=NSRect.zero
    var opacity:CGFloat=0.6
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override var acceptsFirstResponder:Bool { true }
    override func draw(_ rect:NSRect) { NSColor.black.withAlphaComponent(opacity).setFill(); bounds.fill() }
    override func mouseDown(with event:NSEvent) { if !contentFrame.contains(convert(event.locationInWindow,from:nil)) { onClose?() } }
}

final class LuminDialogPaper:PodSurfaceView {
    var radius:CGFloat=16
    var shadowLayers:[(CGFloat,CGFloat,CGFloat)]=[(43,17,0.01),(24,14,0.04),(11,11,0.06),(0,2,0.16)]
    override var isFlipped:Bool { true }
    override var isOpaque:Bool { false }
    override var wantsDefaultClipping:Bool { false }
    override func draw(_ rect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds,xRadius:radius,yRadius:radius)
        if radius==16 {
            for (offset,blur,alpha) in shadowLayers {
                NSGraphicsContext.saveGraphicsState(); let shadow=NSShadow(); shadow.shadowOffset=NSSize(width:0,height:offset); shadow.shadowBlurRadius=blur; shadow.shadowColor=NSColor.black.withAlphaComponent(alpha); shadow.set(); surface.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
            }
        }
        surface.setFill(); path.fill()
        if radius==16 { NSGraphicsContext.saveGraphicsState(); path.addClip(); NSColor.white.withAlphaComponent(0.64).setStroke(); path.lineWidth=0.5; path.stroke(); NSGraphicsContext.restoreGraphicsState() }
    }
}

// In-window viewport modal: CSS centers the complete card group, including its gap.
final class LuminModal:NSObject {
    var backdropOpacity:CGFloat=0.6
    private var overlay:LuminModalBackdrop?
    private weak var root:NSView?
    private weak var accessibilityOwner:NSWindow?
    private var ownsAccessibilityOverride=false
    private weak var previousResponder:NSResponder?
    private var content:NSViewController?
    private var hiddenViews:[(NSView,Bool)]=[]
    private var monitor:Any?
    private var resizeObserver:NSObjectProtocol?
    var onClose:(()->Void)?
    var onKeyDown:((NSEvent)->Bool)?
    var isShown:Bool { overlay?.superview != nil }
    static func placement(size:NSSize,viewport:NSRect)->NSRect {
        NSRect(x:viewport.midX-size.width/2,y:viewport.midY-size.height/2,width:size.width,height:size.height)
    }
    func show(_ controller:NSViewController,in root:NSView,initialResponder:NSResponder?) {
        close(); self.root=root; content=controller; previousResponder=root.window?.firstResponder
        let overlay=LuminModalBackdrop(frame:root.bounds); overlay.autoresizingMask=[.width,.height]
        overlay.opacity=backdropOpacity
        overlay.setAccessibilityElement(true); overlay.setAccessibilityRole(.group); overlay.setAccessibilityLabel("Dialog")
        func backgroundViews(_ views:[NSView])->[NSView] { views.flatMap{[$0]+backgroundViews($0.subviews)} }
        hiddenViews=backgroundViews(root.subviews).map{($0,$0.isAccessibilityHidden())}; hiddenViews.forEach{$0.0.setAccessibilityHidden(true)}
        overlay.onClose={ [weak self] in self?.close() }; self.overlay=overlay
        overlay.addSubview(controller.view); root.addSubview(overlay); layout()
        accessibilityOwner=root.window
        // The override API can be removed to resume AppKit's dynamic hierarchy.
        // setAccessibilityChildren(nil) instead leaves the window with no children.
        ownsAccessibilityOverride=accessibilityOwner?.accessibilitySetOverrideValue([overlay],forAttribute:.children) ?? false
        root.window?.makeFirstResponder(initialResponder ?? overlay)
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self,let owner=self.root?.window,event.window===owner else { return event }
            if event.keyCode==53 { close(); return nil }
            return onKeyDown?(event)==true ? nil:event
        }
        resizeObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResizeNotification,object:root.window,queue:.main) { [weak self] _ in self?.layout() }
    }
    func layout() { guard let overlay,let content else { return }; content.view.frame=Self.placement(size:content.preferredContentSize,viewport:overlay.bounds); overlay.contentFrame=content.view.frame; content.view.needsLayout=true; content.view.layoutSubtreeIfNeeded() }
    func close() {
        let shown=overlay != nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor=nil }
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver); self.resizeObserver=nil }
        content?.view.removeFromSuperview(); overlay?.removeFromSuperview(); overlay=nil; content=nil
        hiddenViews.forEach{$0.0.setAccessibilityHidden($0.1)}; hiddenViews=[]
        if ownsAccessibilityOverride { _ = accessibilityOwner?.accessibilitySetOverrideValue(nil,forAttribute:.children) }
        ownsAccessibilityOverride=false; accessibilityOwner=nil
        if let previousResponder { root?.window?.makeFirstResponder(previousResponder) }; root=nil
        if shown { onClose?() }
    }
    deinit { close() }
}
