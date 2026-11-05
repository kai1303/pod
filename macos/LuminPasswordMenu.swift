import AppKit

// Active legacy Security menu; licensed password forms are separate source branches.
final class LuminPasswordMenu:NSViewController {
    private(set) var rows:[LuminHeaderMenuRow]=[]
    private(set) var focusedIndex:Int?
    var onSet:(()->Void)?
    override func loadView() {
        let root=LuminDialogPaper(); root.radius=8; root.surface=PodTheme.raised
        let items:[LuminHeaderMenuItem]=[
            .init(key:"set",title:"Set password",glyph:"pdf-icon-set-password",premium:true),
            .init(key:"remove",title:"Remove password",glyph:"pdf-icon-remove-password")
        ]
        for (i,item) in items.enumerated() {
            let row=LuminHeaderMenuRow(item); row.fitsLabelToText=true; row.isEnabled=i==0
            row.frame=NSRect(x:8,y:8+CGFloat(i)*32,width:184,height:32)
            row.onChoose={ [weak self] _ in self?.onSet?() }
            root.addSubview(row); rows.append(row)
        }
        root.setAccessibilityElement(true); root.setAccessibilityRole(.menu); root.setAccessibilityLabel("Password protection")
        root.setAccessibilityChildren(NSAccessibility.unignoredChildren(from:rows))
        view=root; preferredContentSize=NSSize(width:200,height:80)
    }
    func handleKey(_ event:NSEvent)->Bool {
        switch event.keyCode {
        case 125,126,115,119: focusedIndex=0; rows[0].keyboardFocused=true; view.window?.makeFirstResponder(rows[0]); return true
        case 36,76: guard focusedIndex != nil else { return false }; onSet?(); return true
        default:return false
        }
    }
    func clearFocus() { focusedIndex=nil; rows.forEach{$0.keyboardFocused=false} }
}
