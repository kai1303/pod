import AppKit

private final class LuminPopperPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}

// Source poppers are bottom-end aligned, arrowless, radius 8, with viewport inset 8.
final class LuminPopper:NSObject {
    enum Alignment { case start,center,end }
    var cornerRadius:CGFloat=8
    var alignment:Alignment = .end
    var sideAlignment:Alignment = .center
    var gap:CGFloat=0
    var crossAxisOffset:CGFloat=0
    var viewportInset:CGFloat=8
    var roundsPlacementToBackingPixels=false
    weak var initialResponder:NSResponder?
    var focusDelay:TimeInterval=0
    var takesKeyFocus=true
    var keepsAnchorInteractive=false
    var onClose:(()->Void)?
    var onEscape:(()->Void)?
    var onKeyDown:((NSEvent)->Bool)?
    var contentViewController:NSViewController?
    private var panel:LuminPopperPanel?
    private weak var anchor:NSView?
    private var anchorRect=NSRect.zero
    private var edge:NSRectEdge = .maxY
    private var localMonitor:Any?
    private var globalMonitor:Any?
    private var observations:[NSObjectProtocol]=[]
    var isShown:Bool { panel?.isVisible == true }
    var frame:NSRect? { panel?.frame }

    static func placement(anchor:NSRect,size:NSSize,viewport:NSRect,alignment:Alignment = .end,gap:CGFloat=0,edge:NSRectEdge = .maxY,inset:CGFloat=8,crossAxisOffset:CGFloat=0,sideAlignment:Alignment = .center)->NSRect {
        let available=viewport.insetBy(dx:inset,dy:inset)
        let width=min(size.width,available.width),height=min(size.height,available.height)
        if edge == .maxX {
            var x=anchor.maxX+gap
            if x+width>available.maxX && anchor.minX-gap-width>=available.minX { x=anchor.minX-gap-width }
            let y:CGFloat
            switch sideAlignment { case .start:y=anchor.maxY-height; case .center:y=anchor.midY-height/2; case .end:y=anchor.minY }
            return NSRect(x:min(max(x,available.minX),available.maxX-width),y:min(max(y-crossAxisOffset,available.minY),available.maxY-height),width:width,height:height)
        }
        let preferredX:CGFloat
        switch alignment { case .start:preferredX=anchor.minX; case .center:preferredX=anchor.midX-width/2; case .end:preferredX=anchor.maxX-width }
        let x=min(max(preferredX+crossAxisOffset,available.minX),available.maxX-width)
        var y=edge == .minY ? anchor.maxY+gap:anchor.minY-height-gap
        if edge == .minY {
            if y+height>available.maxY && anchor.minY-gap-height>=available.minY { y=anchor.minY-gap-height }
        } else if y<available.minY && anchor.maxY+gap+height<=available.maxY { y=anchor.maxY+gap }
        y=min(max(y,available.minY),available.maxY-height)
        return NSRect(x:x,y:y,width:width,height:height)
    }
    static func pixelAligned(_ frame:NSRect,scale:CGFloat)->NSRect {
        guard scale>0 else { return frame }
        var aligned=frame; aligned.origin.x=(frame.minX*scale).rounded()/scale; aligned.origin.y=(frame.minY*scale).rounded()/scale; return aligned
    }
    func show(relativeTo rect:NSRect,of view:NSView,preferredEdge:NSRectEdge = .maxY) {
        close()
        guard let owner=view.window,let content=contentViewController else { return }
        anchor=view; anchorRect=rect; edge=preferredEdge
        let panel=LuminPopperPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false; panel.isOpaque=false; panel.backgroundColor = .clear
        panel.hasShadow=true; panel.level = .popUpMenu; panel.hidesOnDeactivate=true
        panel.title=content.title ?? view.accessibilityLabel() ?? "Tool options"
        panel.becomesKeyOnlyIfNeeded=true; panel.contentViewController=content
        self.panel=panel
        fitContent()
        owner.addChildWindow(panel,ordered:.above)
        if takesKeyFocus { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(panel) }
        else { panel.orderFront(nil) }
        if takesKeyFocus,let initialResponder {
            if focusDelay==0 { panel.makeFirstResponder(initialResponder) }
            else { DispatchQueue.main.asyncAfter(deadline:.now()+focusDelay) { [weak self,weak panel] in guard let self,let panel,self.panel===panel else { return }; panel.makeFirstResponder(self.initialResponder) } }
        }
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown,.keyDown]) { [weak self] event in
            guard let self,let panel=self.panel else { return event }
            if event.type == .keyDown && event.keyCode==53 { self.close(); self.onEscape?(); return nil }
            if event.type == .keyDown && self.onKeyDown?(event)==true { return nil }
            if event.type != .keyDown && !self.contains(event.window,within:panel) {
                if self.keepsAnchorInteractive,let anchor=self.anchor,event.window === anchor.window,anchor.bounds.contains(anchor.convert(event.locationInWindow,from:nil)) { return event }
                self.close(); return event
            }
            DispatchQueue.main.async { [weak self] in self?.fitContent() }
            return event
        }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.otherMouseDown]) { [weak self] _ in self?.close() }
        let center=NotificationCenter.default
        let viewer=viewerWindow(owner)
        for observed in viewer === owner ? [owner]:[owner,viewer] {
            for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] {
                observations.append(center.addObserver(forName:name,object:observed,queue:.main) { [weak self] _ in self?.fitContent() })
            }
        }
        observations.append(center.addObserver(forName:NSWindow.willCloseNotification,object:owner,queue:.main) { [weak self] _ in self?.close() })
        observations.append(center.addObserver(forName:NSWindow.willCloseNotification,object:panel,queue:.main) { [weak self] _ in self?.close() })
        observations.append(center.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.close() })
    }
    private func contains(_ window:NSWindow?,within root:NSWindow)->Bool {
        guard let window else { return false }
        if window===root { return true }
        return (root.childWindows ?? []).contains { contains(window,within:$0) }
    }
    private func viewerWindow(_ window:NSWindow)->NSWindow {
        var root=window
        while let parent=root.parent { root=parent }
        return root
    }
    func fitContent() {
        guard let panel,let anchor,let owner=anchor.window,let content=contentViewController else { return }
        let view=content.view
        if panel.contentView !== view { panel.contentViewController=nil; panel.contentViewController=content }
        view.layoutSubtreeIfNeeded()
        let preferred=content.preferredContentSize,fitting=view.fittingSize
        let size=NSSize(width:preferred.width>0 ? preferred.width:max(300,fitting.width),height:fitting.height>0 ? fitting.height:preferred.height)
        view.wantsLayer=true; view.layer?.cornerRadius=cornerRadius; view.layer?.masksToBounds=true
        let screenAnchor=owner.convertToScreen(anchor.convert(anchorRect,to:nil))
        let viewer=viewerWindow(owner)
        let viewport=viewer.convertToScreen(viewer.contentView?.bounds ?? viewer.contentLayoutRect)
        var frame=Self.placement(anchor:screenAnchor,size:size,viewport:viewport,alignment:alignment,gap:gap,edge:edge,inset:viewportInset,crossAxisOffset:crossAxisOffset,sideAlignment:sideAlignment)
        if roundsPlacementToBackingPixels { frame=Self.pixelAligned(frame,scale:owner.backingScaleFactor) }
        panel.setFrame(frame,display:true)
    }
    func close() {
        let wasOpen=panel != nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor=nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor=nil }
        observations.forEach { NotificationCenter.default.removeObserver($0) }; observations=[]
        if let panel {
            (panel.childWindows ?? []).forEach{$0.close()}
            panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        }
        panel=nil; anchor=nil
        if wasOpen { onClose?() }
    }
    deinit { close() }
}
