import AppKit
import CoreText

// Original fonts and icon codepoints recovered from the viewer's published assets.
enum LuminAssets {
    static let directory:URL = {
        let bundle=Bundle.main.resourceURL?.appendingPathComponent("Lumin")
        if let bundle,FileManager.default.fileExists(atPath:bundle.path) { return bundle }
        return URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("macos/Resources/Lumin")
    }()
    // IcoMoon's PostScript name is also used by unrelated installed fonts (e.g. devicons).
    // A descriptor read from the asset URL preserves file identity across that collision.
    private static let fontDescriptors:[String:NSFontDescriptor] = {
        var result:[String:NSFontDescriptor]=[:]
        for name in ["Inter-VariableFont","Inter-Medium","pdf-icomoon","kiwi-icomoon"] {
            let url=directory.appendingPathComponent(name+".ttf")
            if let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor],let descriptor=descriptors.first { result[name]=descriptor }
        }
        return result
    }()
    static func font(_ size:CGFloat,_ weight:Double=460)->NSFont {
        if weight==500,let medium=fontDescriptors["Inter-Medium"],let font=NSFont(descriptor:medium,size:size) { return font }
        guard let source=fontDescriptors["Inter-VariableFont"] else { return .systemFont(ofSize:size) }
        let descriptor=source.addingAttributes([.variation:[NSNumber(value:0x77676874):NSNumber(value:weight),NSNumber(value:0x6f70737a):NSNumber(value:14)]])
        return NSFont(descriptor:descriptor,size:size) ?? .systemFont(ofSize:size)
    }
    private static let headlineDescriptor:NSFontDescriptor? = {
        let url=directory.appendingPathComponent("Share/PPAgrandir-Medium.otf")
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor])?.first
    }()
    static func headline(_ size:CGFloat)->NSFont { headlineDescriptor.flatMap{NSFont(descriptor:$0,size:size)} ?? font(size,500) }
    private static var signatureDescriptors:[String:NSFontDescriptor]=[:]
    static func signatureFont(_ family:String,size:CGFloat,bold:Bool=false)->NSFont {
        if signatureDescriptors[family]==nil {
            let url=directory.appendingPathComponent("Signature/"+family+".ttf")
            signatureDescriptors[family]=(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor])?.first
        }
        guard let descriptor=signatureDescriptors[family],let font=NSFont(descriptor:descriptor,size:size) else { return self.font(size) }
        return bold ? NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask):font
    }
    private static var previewDescriptors:[String:NSFontDescriptor]=[:]
    static func previewFont(_ family:String,size:CGFloat,weight:Double=420)->NSFont {
        if family=="Inter" { return font(size,weight) }
        if previewDescriptors[family]==nil {
            let url=directory.appendingPathComponent("FontPreviews").appendingPathComponent(family+".ttf")
            if let values=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor] { previewDescriptors[family]=values.first }
        }
        guard let source=previewDescriptors[family] else { return NSFont(name:family,size:size) ?? font(size,weight) }
        return NSFont(descriptor:source.addingAttributes([.variation:[NSNumber(value:0x77676874):NSNumber(value:weight)]]),size:size) ?? font(size,weight)
    }
    static func iconFont(_ name:String,size:CGFloat=24)->NSFont? {
        let asset=name.hasPrefix("kiwi-") ? "kiwi-icomoon":"pdf-icomoon"
        return fontDescriptors[asset].flatMap { NSFont(descriptor:$0,size:size) }
    }
    private static let glyphs:[String:String] = {
        guard let data=try? Data(contentsOf:directory.appendingPathComponent("icon-glyphs.json")),let values=(try? JSONSerialization.jsonObject(with:data)) as? [String:[String:String]] else { return [:] }
        return values.mapValues{$0["content"] ?? ""}
    }()
    static func icon(_ name:String,size:CGFloat=24,naturalWidth:Bool=false)->NSImage? {
        guard let glyph=glyphs[name],let font=iconFont(name,size:size) else { return nil }
        let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor.black]
        let measured=(glyph as NSString).size(withAttributes:attrs)
        let width=naturalWidth ? measured.width:size
        let image=NSImage(size:NSSize(width:width,height:size),flipped:false) { rect in
            (glyph as NSString).draw(at:NSPoint(x:(width-measured.width)/2,y:(size-measured.height)/2),withAttributes:attrs)
            return true
        }
        image.isTemplate=true; return image
    }
    static func bitmap(_ name:String)->NSImage? { NSImage(contentsOf:directory.appendingPathComponent(name+".png")) }
    static func navigation(_ name:String)->NSImage? { let image=NSImage(contentsOf:directory.appendingPathComponent(name+".png")); image?.isTemplate=true; return image }
    static let tools:[String:String]=[
        "Thumbnails":"kiwi-icon-thumbnail-lg","Read aloud":"kiwi-icon-read-aloud","View controls":"pdf-icon-md_single_page_view","Rotate view":"pdf-icon-md_rotate_counter_clockwise","Select":"pdf-icon-md_cursor","Pan":"pdf-icon-md_pan","Undo":"pdf-icon-md_undo","Redo":"pdf-icon-md_redo",
        "Eraser":"pdf-icon-md_eraser","Shape":"pdf-icon-md_rectangle","Text tools":"pdf-icon-md_text_underline","Highlight":"pdf-icon-md_highlight","Draw":"pdf-icon-md_freehand","Type":"pdf-icon-md_text_tool","Add comment":"pdf-icon-md_comment_teardrop_text","Signature":"pdf-icon-md_signature","Prepare form":"pdf-icon-md_fillable_form","Cross":"pdf-icon-tool_cross_stamp","Tick":"pdf-icon-tool_check_stamp","Dot":"pdf-icon-tool_dot_stamp","Stamp":"pdf-icon-md_stamp","Date":"pdf-icon-md_date_stamp","Perform OCR":"pdf-icon-md_OCR","Image":"pdf-icon-md_image","Measure":"kiwi-icon-ph-ruler","Redaction":"pdf-icon-md_redaction","Password protection":"pdf-icon-lg_password","Comments":"pdf-icon-md_comment_history","Search":"kiwi-icon-ph-magnifying-glass","Download":"kiwi-icon-ph-download-simple","Print":"kiwi-icon-ph-printer","Copy link":"kiwi-icon-ph-link-simple","Share":"pdf-icon-md_share","Back":"pdf-icon-md_arrow_back","Stroke":"pdf-icon-md_stroke"]
    static func tool(_ name:String)->NSImage? { tools[name].flatMap{icon($0)} }
    static func markup(_ kind:MarkupKind)->NSImage? {
        let names:[String:String]=["Text highlight":"md_highlight","Freehand highlight":"md_free_hand_highlight","Rectangle":"md_rectangle","Ellipse":"md_ellipse","Line":"md_line","Arrow":"md_arrow","Polyline":"md_polyline","Polygon":"md_polygon","Cloud":"md_cloud","Star":"md_star","Cross":"md_cross","Tick":"md_tick","Underline":"md_text_underline","Squiggly underline":"md_squiggly","Strikethrough":"md_text_strike_through"]
        return names[kind.title].flatMap{icon("pdf-icon-"+$0)} ?? tool(kind.title)
    }
    static func tinted(_ image:NSImage,_ color:NSColor)->NSImage {
        NSImage(size:image.size,flipped:false) { rect in image.draw(in:rect); color.setFill(); rect.fill(using:.sourceIn); return true }
    }
}
