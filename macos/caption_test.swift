import AppKit
import PDFKit
import Metal

@main struct CaptionChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine(), gpu=try Engine(metal:MetalPageRenderer()!)
        let names=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String]
        for name in names {
            let original=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let opened=try cpu.load(original,page:0,width:300)
            let mark=opened.pages[0].annotations[0]
            precondition(mark.importedShape && mark.hasCaption && mark.canChangeAppearance && mark.canEditContents)
            let saved=try cpu.annotate(original,page:0,marks:[])
            let moved=try cpu.annotate(original,page:0,marks:[mark.translated(x:5,y:-4)])
            var changed=mark;changed.style.width=3
            let generated=try cpu.annotate(original,page:0,marks:[changed])
            changed=try cpu.load(generated,page:0,width:300).pages[0].annotations[0]
            changed.style.width=mark.style.width
            let regenerated=try cpu.annotate(generated,page:0,marks:[changed])
            // Rendering metadata directly and interpreting its saved AP must agree.
            let regeneratedPage=try cpu.load(regenerated,page:0,width:300)
            precondition(regeneratedPage.pixels.data == opened.pixels.data,"Fallback/AP mismatch: \(name)")
            let resized=try cpu.annotate(original,page:0,marks:[mark.scaled(to:CGRect(x:15,y:25,width:260,height:300))])
            changed=mark;changed.style.opacity=0.4;changed.style.width=4
            changed.style.stroke=NSColor(srgbRed:0.7,green:0.1,blue:0.2,alpha:1)
            let restyled=try cpu.annotate(original,page:0,marks:[changed])
            changed=mark;changed.text="Updated café — €30"
            let noted=try cpu.annotate(original,page:0,marks:[changed])
            let reopened=try cpu.load(noted,page:0,width:300)
            precondition(reopened.pixels.data != opened.pixels.data && reopened.pages[0].annotations[0].text == changed.text)
            precondition(PDFDocument(data:noted)!.page(at:0)!.annotations[0].contents == changed.text)
            changed=reopened.pages[0].annotations[0].translated(x:5,y:-4)
            changed.text="Final label"
            let again=try cpu.annotate(noted,page:0,marks:[changed])
            let second=try cpu.load(again,page:0,width:300).pages[0].annotations[0]
            precondition(second.canEditContents && second.canChangeAppearance && second.text == "Final label")
            changed=second;changed.text="中文 😀"
            do { _=try cpu.annotate(again,page:0,marks:[changed]);fatalError("Accepted unavailable caption glyphs") } catch is EngineError {}
            let unchanged=try cpu.load(again,page:0,width:300)
            precondition(unchanged.pages[0].annotations[0].text == second.text)
            changed=second;changed.text=""
            let empty=try cpu.annotate(again,page:0,marks:[changed])
            let rotated=try cpu.rotate(try cpu.crop(noted,page:0,box:CGRect(x:5,y:5,width:290,height:350)),page:0,degrees:90)
            let removed=try cpu.annotate(again,page:0,marks:[],deleting:[second.id])
            let deleted=try cpu.load(removed,page:0,width:100)
            precondition(deleted.pages[0].annotations.isEmpty)
            for (suffix,bytes) in [("",original),("-saved",saved),("-moved",moved),("-regenerated",regenerated),("-resized",resized),("-restyled",restyled),("-noted",noted),("-again",again),("-empty",empty),("-rotated",rotated)] {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                for width in [300,600] {
                    let expected=try cpu.load(bytes,page:0,width:width)
                    let actual=try gpu.openPage(bytes,page:0,width:width)
                    guard let pixels=actual.metalPage?.bitmap(width:width) else { fatalError("Missing Metal caption: \(name)\(suffix)") }
                    precondition(pixels.data.count == expected.pixels.data.count)
                    let differences=zip(pixels.data,expected.pixels.data).map{abs(Int($0)-Int($1))}
                    precondition((differences.max() ?? 0)<=32 && differences.filter{$0>1}.count<=pixels.data.count/2000,"CPU/Metal caption mismatch: \(name)\(suffix)")
                    let png=NSBitmapImageRep(cgImage:expected.pixels.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width).png"))
                }
            }
            print("PASS: \(name) caption editing, fallback/AP identity, CPU/Metal, PDFKit text and round trips")
        }
        for url in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("invalid"),includingPropertiesForKeys:nil) {
            let bytes=try Data(contentsOf:url)
            do { _=try cpu.load(bytes,page:0,width:100);fatalError("Accepted invalid caption: \(url.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(bytes,page:0,width:100);fatalError("Indexed open accepted invalid caption: \(url.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: invalid caption metadata rejects in full and indexed native opening")
    }
}
