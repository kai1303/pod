import AppKit

@main
enum LuminPopperTests {
    static func main() {
        _ = NSApplication.shared
        let viewport=NSRect(x:100,y:100,width:800,height:600)
        let size=NSSize(width:300,height:200)
        let normal=LuminPopper.placement(anchor:NSRect(x:450,y:600,width:32,height:32),size:size,viewport:viewport)
        precondition(normal==NSRect(x:182,y:400,width:300,height:200),"Source poppers align bottom-end without arrow space")
        let start=LuminPopper.placement(anchor:NSRect(x:450,y:600,width:32,height:32),size:size,viewport:viewport,alignment:.start,gap:8)
        precondition(start==NSRect(x:450,y:392,width:300,height:200),"Type lists use bottom-start with gap8")
        let centered=LuminPopper.placement(anchor:NSRect(x:450,y:600,width:32,height:32),size:size,viewport:viewport,alignment:.center,gap:8)
        precondition(centered==NSRect(x:316,y:392,width:300,height:200),"The nested color picker is centered under its trigger")
        let flipped=LuminPopper.placement(anchor:NSRect(x:450,y:110,width:32,height:32),size:size,viewport:viewport)
        precondition(flipped.minY==142,"Use available space above when the bottom placement overflows")
        let left=LuminPopper.placement(anchor:NSRect(x:105,y:600,width:32,height:32),size:size,viewport:viewport)
        precondition(left.minX==108,"Keep the source 8 px viewport inset")
        let constrained=LuminPopper.placement(anchor:.zero,size:NSSize(width:1200,height:900),viewport:viewport)
        precondition(constrained==viewport.insetBy(dx:8,dy:8))
        let owner=NSWindow(contentRect:NSRect(x:100,y:100,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
        owner.isReleasedWhenClosed=false
        let anchor=NSButton(frame:NSRect(x:400,y:500,width:32,height:32)); owner.contentView?.addSubview(anchor)
        let content=NSViewController(); content.view=NSView(frame:NSRect(x:0,y:0,width:300,height:200)); content.preferredContentSize=size
        let popper=LuminPopper(); popper.contentViewController=content
        popper.show(relativeTo:anchor.bounds,of:anchor)
        precondition(popper.isShown && owner.childWindows?.count==1)
        precondition(popper.frame?.size==size)
        precondition(content.view.layer?.cornerRadius==8 && content.view.layer?.masksToBounds==true)
        precondition(content.view.window?.styleMask.contains(.titled)==false,"Native title/popover chrome must not be introduced")
        let childAnchor=NSButton(frame:NSRect(x:100,y:100,width:24,height:24)); content.view.addSubview(childAnchor)
        let child=LuminPopper(); let childContent=NSViewController(); childContent.view=NSView(frame:NSRect(x:0,y:0,width:300,height:300)); childContent.preferredContentSize=NSSize(width:300,height:300); child.contentViewController=childContent
        child.show(relativeTo:childAnchor.bounds,of:childAnchor); precondition(child.isShown)
        precondition(child.frame?.size==NSSize(width:300,height:300),"Source preventOverflow uses the viewer viewport, not a nested menu's bounds")
        let childAnchorScreen=content.view.window!.convertToScreen(childAnchor.convert(childAnchor.bounds,to:nil))
        let viewerViewport=owner.convertToScreen(owner.contentView!.bounds)
        precondition(child.frame==LuminPopper.placement(anchor:childAnchorScreen,size:NSSize(width:300,height:300),viewport:viewerViewport),"Nested options use the top-level viewer's positioning boundary")
        popper.close(); precondition(!child.isShown,"Closing a parent palette must also dismiss nested pickers")
        precondition(!popper.isShown && (owner.childWindows ?? []).isEmpty)
        owner.close()
        print("Lumin popper: bottom-end/flip/clamp placement, exact content size, arrowless chrome, 8 px clipping and cleanup passed")
    }
}
