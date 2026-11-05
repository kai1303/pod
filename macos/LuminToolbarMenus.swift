import AppKit

private final class LuminToolbarMenuSurface:PodSurfaceView { override var isFlipped:Bool { true } }

final class LuminToolbarMenu:NSViewController {
    private let names:[String]
    private let isThumbnails:Bool
    private(set) var rows:[LuminExploreRow]=[]
    private(set) var options:[LuminToolbarButton]=[]
    var onChoose:((String,NSButton)->Void)?
    var onOptions:((String,NSButton)->Void)?
    private init(names:[String],thumbnails:Bool) { self.names=names; isThumbnails=thumbnails; super.init(nibName:nil,bundle:nil); title=thumbnails ? "Thumbnails options":"More tools" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    static func thumbnails()->LuminToolbarMenu { LuminToolbarMenu(names:["Thumbnails","Outlines"],thumbnails:true) }
    static func overflow(mode:String)->LuminToolbarMenu { LuminToolbarMenu(names:LuminToolbarModel.overflow(mode),thumbnails:false) }
    override func loadView() {
        let width:CGFloat=isThumbnails ? 226:280,height:CGFloat=isThumbnails ? 32:40
        let root=LuminToolbarMenuSurface(frame:NSRect(x:0,y:0,width:width,height:CGFloat(names.count)*height+16)); root.surface=PodTheme.raised
        for (index,name) in names.enumerated() {
            let label=name=="Add comment" ? "Comment":name
            let glyph=name=="Outlines" ? "kiwi-icon-bookmark-lg":LuminAssets.tools[name] ?? "pdf-icon-md_cursor"
            let command=name=="Sign securely" ? LuminExploreCommand(key:name,title:label,bitmap:"Toolbar/sign-logo"):LuminExploreCommand(key:name,title:label,icon:glyph,premium:LuminToolbarModel.premium.contains(name))
            let row=LuminExploreRow(command:command,query:""); row.identifier=NSUserInterfaceItemIdentifier(name)
            row.frame=NSRect(x:8,y:8+CGFloat(index)*height,width:width-16,height:height)
            row.onChoose={ [weak self,weak row] _ in guard let row else { return }; self?.onChoose?(name,row) }
            root.addSubview(row); rows.append(row)
            if !isThumbnails && LuminToolbarModel.split.contains(name) {
                let divider=PodSurfaceView(frame:NSRect(x:width-53,y:row.frame.minY+8,width:1,height:24)); divider.surface=PodTheme.border; root.addSubview(divider)
                let button=LuminToolbarButton(title:name+" options",glyph:"kiwi-icon-chevron-right-md",kind:.more); button.frame=NSRect(x:width-44,y:row.frame.minY+4,width:32,height:32); button.target=self; button.action=#selector(chooseOptions); root.addSubview(button); options.append(button)
            }
        }
        view=root; preferredContentSize=root.frame.size
    }
    @objc private func chooseOptions(_ sender:NSButton) { onOptions?(sender.identifier?.rawValue.replacingOccurrences(of:" options",with:"") ?? "",sender) }
    func handleKey(_ event:NSEvent)->Bool {
        let current=rows.firstIndex{$0.window?.firstResponder === $0}
        let index:Int
        switch event.keyCode {
        case 125:index=current.map{($0+1)%rows.count} ?? 0
        case 126:index=current.map{($0+rows.count-1)%rows.count} ?? 0
        case 115:index=0
        case 119:index=rows.count-1
        case 36,76:guard let current else { return false }; rows[current].performClick(nil); return true
        default:return false
        }
        view.window?.makeFirstResponder(rows[index]); return true
    }
}
