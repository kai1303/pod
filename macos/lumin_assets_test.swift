import AppKit
import CoreText

@main
struct LuminAssetsTest {
    static func main() {
        func assertSource(_ font:NSFont?,file:String) -> NSFont {
            guard let font else { fatalError("Missing font asset: \(file)") }
            guard let url=CTFontCopyAttribute(font,kCTFontURLAttribute) as? URL else { fatalError("Font has no file identity: \(file)") }
            precondition(url.lastPathComponent==file,"Resolved \(url.path), expected \(file)")
            precondition(url.path.contains("/Lumin/"),"Resolved an installed font instead of the bundled asset")
            return font
        }
        let pdf=assertSource(LuminAssets.iconFont("pdf-icon-md_highlight"),file:"pdf-icomoon.ttf")
        let kiwi=assertSource(LuminAssets.iconFont("kiwi-icon-ph-ruler"),file:"kiwi-icomoon.ttf")
        let inter=assertSource(LuminAssets.font(14,520),file:"Inter-VariableFont.ttf")
        let medium=assertSource(LuminAssets.font(14,500),file:"Inter-Medium.ttf")
        precondition(medium.fontName=="Inter-Medium","The source's 500-weight UI uses its static Medium face")
        _ = assertSource(LuminAssets.font(14,400),file:"Inter-VariableFont.ttf")
        let variations=CTFontCopyVariation(inter) as? [NSNumber:NSNumber]
        precondition(variations?[NSNumber(value:0x77676874)]?.doubleValue==520,"Inter weight variation was lost")
        let axes=CTFontCopyVariationAxes(inter) as? [[String:Any]] ?? []
        let opticalAxis=axes.first { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value==0x6f70737a }
        let opticalDefault=(opticalAxis?[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue
        // CoreText omits default-valued axes from CTFontCopyVariation.
        let opticalSize=variations?[NSNumber(value:0x6f70737a)]?.doubleValue ?? opticalDefault
        precondition(opticalSize==14,"Inter optical size variation was lost")
        var characters:[UniChar]=[0xEABE,0xEB0D,0xEA9B]
        var pdfGlyphs:[CGGlyph]=[0,0,0],kiwiGlyphs:[CGGlyph]=[0,0,0]
        precondition(CTFontGetGlyphsForCharacters(pdf,&characters,&pdfGlyphs,3))
        precondition(CTFontGetGlyphsForCharacters(kiwi,&characters,&kiwiGlyphs,3))
        precondition(pdfGlyphs==[450,529,415],"PDF glyphs came from another icon font/version")
        precondition(kiwiGlyphs==[451,530,416],"Kiwi glyphs came from another icon font/version")
        precondition(LuminAssets.icon("pdf-icon-md_highlight") != nil)
        precondition(LuminAssets.icon("kiwi-icon-ph-ruler") != nil)
        precondition(LuminAssets.markup(.freehandHighlight) != nil,"Freehand highlight must use the source CSS icon key")
        print("Lumin assets: exact source font files, Inter variation, PDF/Kiwi glyph identities passed")
    }
}
