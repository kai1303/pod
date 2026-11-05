import AppKit

private final class LuminShareMenuSurface:PodSurfaceView { override var isFlipped:Bool { true } }
final class LuminShareMenu:NSViewController {
    enum Kind:String { case scope="access-menu",publicRole="permission-menu",bulk="bulk-permission-menu",export="export-menu" }
    let kind:Kind,selection:Int
    private(set) var rows:[LuminHeaderMenuRow]=[]
    private var focused:Int?
    var onChoose:((Int)->Void)?
    var alignment:LuminPopper.Alignment { kind == .publicRole ? .end:kind == .bulk ? .center:.start }
    var gap:CGFloat { kind == .scope ? 4:8 }
    var edge:NSRectEdge { kind == .publicRole ? .minY:.maxY }
    init(kind:Kind,selection:Int) { self.kind=kind; self.selection=selection; super.init(nibName:nil,bundle:nil); title=kind == .scope ? "Link access":kind == .export ? "Export permission":"Permission" }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let titles:[String],glyphs:[String?],bitmaps:[String?],width:CGFloat
        switch kind {
        case .scope:titles=["Restricted","Anyone with the link"]; glyphs=["kiwi-icon-shield-md","kiwi-icon-world-md"]; bitmaps=[nil,nil]; width=216
        case .publicRole:titles=["Viewer","Commenter","Editor"]; glyphs=["kiwi-icon-eye-md","kiwi-icon-message-circle-md","kiwi-icon-pencil-md"]; bitmaps=[nil,nil,nil]; width=180
        case .bulk:titles=["Can view","Can comment","Can edit","Can share"]; glyphs=[nil,nil,nil,nil]; bitmaps=["Share/eye","Share/comment","Share/pencil","Share/link"]; width=157.25
        case .export:titles=["Anyone with document access","Sharers and editors","Sharers, editors and commenters"]; glyphs=[nil,nil,nil]; bitmaps=["Share/world","Share/pencil","Share/comment"]; width=590
        }
        let root=LuminShareMenuSurface(frame:NSRect(x:0,y:0,width:width,height:16+CGFloat(titles.count)*40)); root.surface=PodTheme.raised
        for index in titles.indices {
            let item=LuminHeaderMenuItem(key:String(index),title:titles[index],glyph:glyphs[index],bitmap:bitmaps[index],iconSize:20,iconSectionSize:24)
            let row=LuminHeaderMenuRow(item,dense:false); row.frame=NSRect(x:8,y:8+CGFloat(index)*40,width:width-16,height:40); row.selected=kind == .export && selection==index; row.fitsLabelToText=kind == .export
            row.onChoose={ [weak self] _ in self?.onChoose?(index) }; root.addSubview(row); rows.append(row)
        }
        root.setAccessibilityElement(true); root.setAccessibilityRole(kind == .export ? .list:.menu); root.setAccessibilityLabel(title); root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows))
        view=root; preferredContentSize=root.frame.size
    }
    func handleKey(_ event:NSEvent)->Bool {
        let current=rows.firstIndex{$0.window?.firstResponder === $0} ?? focused
        let next:Int
        switch event.keyCode {
        case 125:next=current.map{($0+1)%rows.count} ?? 0
        case 126:next=current.map{($0+rows.count-1)%rows.count} ?? rows.count-1
        case 115:next=0
        case 119:next=rows.count-1
        case 36,76,49:guard let current else { return false }; rows[current].performClick(nil); return true
        default:return false
        }
        focused=next; rows.enumerated().forEach{$0.element.keyboardFocused=$0.offset==next}; view.window?.makeFirstResponder(rows[next]); return true
    }
}
