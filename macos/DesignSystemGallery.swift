import AppKit

// A living catalog: these are the same controls used by the editor, not mockups.
final class DesignSystemGallery:NSViewController {
    override func loadView() {
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:900,height:760)); scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true
        preferredContentSize=NSSize(width:900,height:760)
        let page=PodSurfaceStack(); page.orientation = .vertical; page.alignment = .leading
        page.spacing=24; page.edgeInsets=NSEdgeInsets(top:28,left:32,bottom:28,right:32)
        scroll.documentView=page; page.translatesAutoresizingMaskIntoConstraints=false
        page.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
        page.topAnchor.constraint(equalTo:scroll.contentView.topAnchor).isActive=true
        page.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor).isActive=true
        view=scroll

        let header=row()
        let icon=NSImageView(); if let url=Bundle.main.url(forResource:"Pod",withExtension:"icns") { icon.image=NSImage(contentsOf:url) }
        icon.imageScaling = .scaleProportionallyUpOrDown; icon.widthAnchor.constraint(equalToConstant:56).isActive=true; icon.heightAnchor.constraint(equalToConstant:56).isActive=true
        header.addArrangedSubview(icon)
        header.addArrangedSubview(label("Pod / Design system",.systemFont(ofSize:26,weight:.semibold)))
        let flexible=NSView(); flexible.setContentHuggingPriority(.defaultLow,for:.horizontal); header.addArrangedSubview(flexible)
        let appearance=NSPopUpButton(); appearance.addItems(withTitles:["System","Light","Dark"])
        appearance.target=self; appearance.action=#selector(changeAppearance); appearance.setAccessibilityLabel("Gallery appearance")
        header.addArrangedSubview(appearance); page.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo:page.widthAnchor,constant:-64).isActive=true
        page.addArrangedSubview(label("Layered paper. Warm color. Precise native controls.",PodTypography.body,PodTheme.secondaryText))

        page.addArrangedSubview(section("01   Color",subtitle:"Semantic roles adapt to the window appearance."))
        let palette=row()
        for (name,color) in [("Coral",PodTheme.accent),("Chrome",PodTheme.chrome),("Surface",PodTheme.surface),("Canvas",PodTheme.canvas),("Selected",PodTheme.selectedSurface),("Text",PodTheme.text)] {
            let item=NSStackView(); item.orientation = .vertical; item.alignment = .leading; item.spacing=8
            let swatch=PodSurfaceView(); swatch.surface=color; swatch.widthAnchor.constraint(equalToConstant:112).isActive=true; swatch.heightAnchor.constraint(equalToConstant:48).isActive=true
            item.addArrangedSubview(swatch); item.addArrangedSubview(label(name,PodTypography.caption)); palette.addArrangedSubview(item)
        }
        page.addArrangedSubview(palette)

        page.addArrangedSubview(section("02   Controls",subtitle:"32 pt controls · 8 pt corners · native keyboard focus and activation"))
        let controls=row()
        for (title,emphasis,selected,enabled) in [("Save a Copy",PodButton.Emphasis.primary,false,true),("Open",.plain,false,true),("Selected",.plain,true,true),("Disabled",.plain,false,false),("Delete",.destructive,false,true)] {
            let b=PodButton(title:title,target:self,action:#selector(demonstrate)); b.emphasis=emphasis; b.isSelected=selected; b.isEnabled=enabled; controls.addArrangedSubview(b)
        }
        page.addArrangedSubview(controls)
        let tools=row()
        for symbol in ["cursorarrow","rectangle","highlighter","pencil.tip","text.bubble"] {
            let b=PodButton(title:"",target:self,action:#selector(toggle)); b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:symbol); b.setAccessibilityLabel(symbol)
            b.widthAnchor.constraint(equalToConstant:32).isActive=true; b.isSelected=symbol=="rectangle"; tools.addArrangedSubview(b)
        }
        let choices=PodChoiceGroup(labels:["Fill","Border line"],selectedIndex:1); choices.widthAnchor.constraint(equalToConstant:PodMetrics.paletteContent).isActive=true
        tools.addArrangedSubview(choices); page.addArrangedSubview(tools)

        page.addArrangedSubview(section("03   Typography",subtitle:"Native system font; hierarchy adapted from Lumin's Inter controls."))
        let type=row(); type.spacing=32
        for (sample,font) in [("Heading / 18",PodTypography.heading),("Body / 14",PodTypography.body),("Control / 12",PodTypography.control),("Caption / 11",PodTypography.caption)] { type.addArrangedSubview(label(sample,font)) }
        page.addArrangedSubview(type)

        page.addArrangedSubview(section("04   Layout & surfaces",subtitle:"56 pt header · 48 pt toolbar · 300 pt palette · 16 pt inset · 8 pt gaps"))
        let surfaces=row(); surfaces.alignment = .top
        for (title,color) in [("Toolbar / surface",PodTheme.surface),("Palette / raised",PodTheme.raised),("Document / canvas",PodTheme.canvas)] {
            let panel=PodSurfaceStack(); panel.surface=color; panel.orientation = .vertical; panel.alignment = .leading; panel.spacing=12
            panel.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
            panel.widthAnchor.constraint(equalToConstant:240).isActive=true
            panel.addArrangedSubview(label(title,PodTypography.section))
            panel.addArrangedSubview(label("Space establishes hierarchy.",PodTypography.caption,PodTheme.secondaryText))
            let example=PodButton(title:"Example action",target:self,action:#selector(demonstrate)); panel.addArrangedSubview(example)
            surfaces.addArrangedSubview(panel)
        }
        page.addArrangedSubview(surfaces)
        page.addArrangedSubview(label("Source: observed Lumin viewer structure. Pod adaptation: coral palette, native typography and symbols.",PodTypography.caption,PodTheme.secondaryText))
    }
    private func label(_ text:String,_ font:NSFont,_ color:NSColor=PodTheme.text)->NSTextField {
        let label=NSTextField(labelWithString:text); label.font=font; label.textColor=color; return label
    }
    private func row()->NSStackView { let stack=NSStackView(); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing=16; return stack }
    private func section(_ title:String,subtitle:String)->NSStackView {
        let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=6
        stack.addArrangedSubview(label(title,PodTypography.heading)); stack.addArrangedSubview(label(subtitle,PodTypography.caption,PodTheme.secondaryText)); return stack
    }
    @objc private func changeAppearance(_ sender:NSPopUpButton) {
        view.window?.appearance=sender.indexOfSelectedItem==0 ? nil:NSAppearance(named:sender.indexOfSelectedItem==1 ? .aqua:.darkAqua)
    }
    @objc private func demonstrate(_ sender:PodButton) { sender.toolTip="Native action received" }
    @objc private func toggle(_ sender:PodButton) { sender.isSelected.toggle() }
}
