import AppKit

// Default source rail:40px controls in a56px column, with16px dividers.
final class LuminUtilityRail:PodSurfaceView {
    private(set) var buttons:[LuminToolbarButton]=[]
    private(set) var dividers:[NSView]=[]
    var onAction:((NSButton)->Void)?
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame); surface=PodTheme.chrome
        let titles=["Lumin AI","Search","Comments","Download","Print","Copy link","Xero","Add apps"]
        let offsets:[CGFloat]=[4,48,92,157,201,245,310,358]
        for (index,title) in titles.enumerated() {
            let button=LuminToolbarButton(title:title,glyph:LuminAssets.tools[title],kind:.utility)
            if index==0 { button.image=LuminAssets.bitmap("Toolbar/utility-ai"); button.imageSize=28; button.preservesImageColors=true }
            if index==6 { button.image=LuminAssets.bitmap("Toolbar/utility-xero"); button.preservesImageColors=true }
            if index==7 { button.image=LuminAssets.bitmap("Toolbar/utility-apps"); button.imageSize=20 }
            button.usesLegacyForeground=title=="Comments"; button.frame=NSRect(x:8,y:offsets[index],width:40,height:40); button.target=self; button.action=#selector(choose)
            addSubview(button); buttons.append(button)
        }
        for y:CGFloat in [144,297] { let divider=PodSurfaceView(frame:NSRect(x:20,y:y,width:16,height:1)); divider.surface=LuminLegacyStyle.outline; addSubview(divider); dividers.append(divider) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose(_ sender:NSButton) { onAction?(sender) }
}
