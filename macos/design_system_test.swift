import AppKit

@main
enum DesignSystemTests {
    static func main() {
        _ = NSApplication.shared
        func luminance(_ color:NSColor) -> Double {
            let c=color.usingColorSpace(.sRGB)!
            func channel(_ x:Double)->Double { x <= 0.04045 ? x/12.92:pow((x+0.055)/1.055,2.4) }
            return 0.2126*channel(c.redComponent)+0.7152*channel(c.greenComponent)+0.0722*channel(c.blueComponent)
        }
        for name in [NSAppearance.Name.aqua,.darkAqua] {
            NSAppearance(named:name)!.performAsCurrentDrawingAppearance {
                for (foreground,background) in [(PodTheme.text,PodTheme.surface),(PodTheme.secondaryText,PodTheme.surface),(PodTheme.selectedText,PodTheme.selectedSurface)] {
                    let a=luminance(foreground),b=luminance(background)
                    precondition((max(a,b)+0.05)/(min(a,b)+0.05)>=4.5,"Insufficient text contrast in \(name)")
                }
            }
        }
        // The source Share pair has 4.2834:1 contrast; preserve its exact colors for fidelity.
        let primaryA=luminance(PodTheme.onAccent),primaryB=luminance(PodTheme.accent)
        precondition(abs((max(primaryA,primaryB)+0.05)/(min(primaryA,primaryB)+0.05)-4.283437)<0.01)
        precondition(LuminAssets.font(12).fontName.contains("Inter"),"The original Inter font must be loaded")
        for name in ["Select","Shape","Eraser","Draw","Type","Share"] { precondition(LuminAssets.tool(name) != nil,"Missing source icon: \(name)") }
        let button=PodButton(title:"Save a Copy",target:nil,action:nil)
        precondition(button.intrinsicContentSize.height>=32)
        precondition(button.accessibilityLabel()=="Save a Copy")
        button.isSelected=true
        precondition(button.state == .on)
        let idle=PodButton(title:"",target:nil,action:nil)
        idle.frame=NSRect(x:0,y:0,width:32,height:32)
        let pixels=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:32,pixelsHigh:32,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:pixels)
        NSColor.clear.setFill(); NSRect(x:0,y:0,width:32,height:32).fill(using:.copy)
        idle.draw(idle.bounds)
        NSGraphicsContext.restoreGraphicsState()
        precondition(pixels.colorAt(x:16,y:16)!.alphaComponent==0,"Plain idle buttons must preserve the underlying surface")
        let choices=PodChoiceGroup(labels:["Fill","Border line"],selectedIndex:1)
        var picked:Int?
        choices.onChange={ picked=$0 }
        (choices.arrangedSubviews[0] as! NSButton).performClick(nil)
        precondition(choices.selectedIndex==0 && picked==0)
        precondition((choices.arrangedSubviews[0] as! PodButton).isSelected)
        precondition(!(choices.arrangedSubviews[1] as! PodButton).isSelected)
        let highlight=LuminHighlightMenu()
        var pickedHighlight:MarkupKind?,openedOptions:MarkupKind?
        highlight.onChoose={ pickedHighlight=$0 }; highlight.onOptions={ kind,_ in openedOptions=kind }
        func buttons(_ view:NSView)->[NSButton] { view.subviews.flatMap { child -> [NSButton] in (child as? NSButton).map{[$0]} ?? buttons(child) } }
        let menuButtons=buttons(highlight.view)
        precondition(menuButtons.count==4,"Both highlight rows need independent main and options buttons")
        let freehand=menuButtons.first{$0.accessibilityLabel()=="Freehand highlight"}!
        let options=menuButtons.first{$0.accessibilityLabel()=="Freehand highlight options"}!
        freehand.performClick(nil); precondition(pickedHighlight == .freehandHighlight && openedOptions == nil)
        options.performClick(nil); precondition(openedOptions == .freehandHighlight)
        let drawPalette=MarkupPalette(kinds:[.ink],current:.ink,style:.initial(for:.ink))
        _ = drawPalette.view
        precondition(drawPalette.preferredContentSize==NSSize(width:304,height:144.796875),"Draw retains the source fractional opacity line box")
        let shapePalette=MarkupPalette(kinds:Array(MarkupKind.allCases.prefix(10)),current:.rectangle,style:.initial(for:.rectangle))
        _ = shapePalette.view
        precondition(shapePalette.preferredContentSize.width==300,"Shape retains the source 300 px wrapper")
        let gallery=DesignSystemGallery()
        precondition(gallery.view.frame.width>=900 && gallery.view.frame.height>=700,"Gallery must open at a usable size")
        if CommandLine.arguments.count>1 {
            let directory=URL(fileURLWithPath:CommandLine.arguments[1])
            try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:760),styleMask:[.titled],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false; window.contentViewController=gallery
            for (name,appearance) in [("light",NSAppearance.Name.aqua),("dark",.darkAqua)] {
                window.appearance=NSAppearance(named:appearance)
                gallery.view.layoutSubtreeIfNeeded()
                let bitmap=gallery.view.bitmapImageRepForCachingDisplay(in:gallery.view.bounds)!
                gallery.view.cacheDisplay(in:gallery.view.bounds,to:bitmap)
                try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("design-system-\(name).png"))
            }
            window.close()
        }
        print("Design system: light/dark contrast, transparent idle buttons, accessible controls, exclusive choice, and gallery size passed")
    }
}
