import AppKit

// Shipped source has distinct Stamp popover, Security modal and Edit text modal layouts.
final class LuminPremiumGate:NSViewController {
    enum Kind { case popover,modal,editText }
    let kind:Kind
    let upgrade=LuminShareButton("Upgrade now",style:.filled)
    private(set) var controls:[String:NSView]=[:]
    var onUpgrade:(()->Void)?
    init(kind:Kind = .popover) { self.kind=kind; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let modal=kind != .popover,editText=kind == .editText
        let title=editText ? "Edit text directly — no retyping needed":"Upgrade to access"
        let body=editText ? "Level up your work and edit any PDF text in seconds.":"Level up your work by unlocking this feature"
        let root=LuminDialogPaper(); root.surface=PodTheme.raised
        if !modal { root.shadowLayers=[(11,4,0.01),(6,4,0.04),(3,3,0.07),(0,2,0.16)] }
        view=root
        let frames:[String:NSRect]
        switch kind {
        case .popover:
            preferredContentSize=NSSize(width:304,height:230)
            frames=["artwork":NSRect(x:128,y:24,width:48,height:48),"heading":NSRect(x:82.078125,y:96,width:139.8359375,height:24),"message":NSRect(x:16,y:124,width:272,height:42),"upgrade":NSRect(x:16,y:182,width:272,height:32)]
        case .modal:
            preferredContentSize=NSSize(width:480,height:213)
            frames=["artwork":NSRect(x:216,y:32,width:48,height:48),"heading":NSRect(x:151.109375,y:88,width:177.78125,height:28),"message":NSRect(x:95.4296875,y:120,width:289.1328125,height:21),"upgrade":NSRect(x:24,y:157,width:432,height:32)]
        case .editText:
            preferredContentSize=NSSize(width:480,height:229)
            frames=["artwork":NSRect(x:199.234375,y:32,width:81.5234375,height:64),"heading":NSRect(x:56.484375,y:104,width:367.0234375,height:28),"message":NSRect(x:66.890625,y:136,width:346.21875,height:21),"upgrade":NSRect(x:24,y:173,width:432,height:32)]
        }
        let image=NSImageView(); image.image=LuminAssets.bitmap(editText ? "Premium/magic":"Premium/three-stars"); image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel(title); image.setAccessibilityElement(false)
        let heading=LuminTextLabel(title,font:modal ? LuminAssets.headline(20):LuminAssets.font(16,520),lineHeight:modal ? 28:24,color:LuminLegacyStyle.text)
        let message:NSView=modal ? LuminTextLabel(body,font:LuminAssets.font(14,420),lineHeight:21,color:LuminLegacyStyle.text):LuminPremiumMessage()
        upgrade.size=14; upgrade.horizontalPadding=12; upgrade.onPress={ [weak self] in self?.onUpgrade?() }
        for (name,child) in [("artwork",image as NSView),("heading",heading),("message",message),("upgrade",upgrade)] {
            child.frame=frames[name]!; root.addSubview(child); controls[name]=child
        }
        root.setAccessibilityLabel(title)
    }
}

private final class LuminPremiumMessage:NSView {
    private let text="Level up your work by unlocking this feature"
    override var isFlipped:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityValue(text) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ rect:NSRect) {
        let p=NSMutableParagraphStyle(); p.alignment = .center; p.minimumLineHeight=21; p.maximumLineHeight=21; p.lineBreakMode = .byWordWrapping
        (text as NSString).draw(with:bounds,options:.usesLineFragmentOrigin,attributes:[.font:LuminAssets.font(14,420),.foregroundColor:LuminLegacyStyle.text,.paragraphStyle:p])
    }
}
