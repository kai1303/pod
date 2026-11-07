import AppKit
import PDFKit
import Metal

@main struct FreeTextChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let cpu=try Engine(), gpu=try Engine(metal:MetalPageRenderer()!)
        var names=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("cases.json"))) as! [String]
        if CommandLine.arguments.contains("--fixtures") {
        for name in ["pdfkit-left","pdfkit-center"] {
            let source=PDFDocument(data:try Data(contentsOf:root.appendingPathComponent("mupdf-left.pdf")))!
            let page=source.page(at:0)!
            for mark in page.annotations { page.removeAnnotation(mark) }
            let mark=PDFAnnotation(bounds:CGRect(x:60,y:90,width:180,height:140),forType:.freeText,withProperties:nil)
            mark.font=NSFont(name:"Arial",size:14)!
            mark.fontColor=NSColor(srgbRed:0.1,green:0.2,blue:0.4,alpha:1)
            mark.color=NSColor(srgbRed:0.9,green:0.8,blue:0.6,alpha:1)
            mark.alignment=name.hasSuffix("center") ? .center : .left
            mark.contents="Teacher note\nA second line";mark.userName="Teacher"
            page.addAnnotation(mark)
            precondition(source.write(to:root.appendingPathComponent(name+".pdf")))
            if !names.contains(name) { names.append(name) }
        }
        let source=try Data(contentsOf:root.appendingPathComponent("mupdf-left.pdf"))
        let marks=try cpu.load(source,page:0,width:100).pages[0].annotations
        let blank=try cpu.annotate(source,page:0,marks:[],deleting:marks.map(\.id))
        for (name,text,box) in [
            ("pod-created-auto","Reading notes for class, with explanations and examples.",CGRect(x:60,y:90,width:180,height:140)),
            ("pod-created-unicode","Café costs €5.\nRésumé — notes",CGRect(x:60,y:90,width:180,height:140)),
            ("pod-created-wrap","Students read, highlight, and explain their thinking.",CGRect(x:60,y:90,width:110,height:140)),
            ("pod-created-overflow","One\nTwo\nThree\nFour",CGRect(x:60,y:90,width:140,height:22)),
            ("pod-created-long-word","ALongWordWithoutAnySpacesToBreak.",CGRect(x:60,y:90,width:110,height:140)),
            ("pod-created-empty","",CGRect(x:60,y:90,width:180,height:140)),
            ("pod-created-escaped","Café (notes) \\ résumé",CGRect(x:60,y:90,width:180,height:140)),
            ("pod-created-lines","First\r\nSecond\rThird\tline",CGRect(x:60,y:90,width:180,height:140)),
        ] {
            var style=MarkupStyle();style.width=1;style.opacity=0.6
            if name == "pod-created-auto" { style.fontSize=0 }
            style.stroke=NSColor(srgbRed:0.1,green:0.2,blue:0.4,alpha:1)
            style.fill=NSColor(srgbRed:0.9,green:0.8,blue:0.6,alpha:1)
            let mark=Markup(kind:.freeText,points:[CGPoint(x:box.minX,y:box.minY),CGPoint(x:box.maxX,y:box.maxY)],rect:box,text:text,style:style)
            let bytes=try cpu.annotate(blank,page:0,marks:[mark])
            try bytes.write(to:root.appendingPathComponent(name+".pdf"))
            if !names.contains(name) { names.append(name) }
        }
        try JSONSerialization.data(withJSONObject:names).write(to:root.appendingPathComponent("cases.json"))
            return
        }
        for name in names where CommandLine.arguments.count < 3 || CommandLine.arguments[2] == name {
            let original=try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let opened=try cpu.load(original,page:0,width:300)
            let mark=opened.pages[0].annotations[0]
            precondition(mark.kind == .freeText && mark.importedFreeText && !mark.importedShape)
            let resourceFont=name.hasPrefix("resource-")
            let intervalFit=name == "fallback-spacing-auto-interval"
            let editable=name.hasPrefix("fallback-") || name.hasPrefix("pod-created-") || resourceFont
            precondition(mark.freeTextEditable == editable && mark.canEditContents == editable && mark.canChangeAppearance == editable && mark.canMove == (name != "locked"))
            precondition((mark.contentsLockReason == nil) == editable)
            var noted=mark;noted.text=resourceFont ? "AB é\nAB" : "Café — revised\nA second line"
            if intervalFit {
                do { _=try cpu.annotate(original,page:0,marks:[noted]);fatalError("Spacing with no fitting size accepted") } catch is EngineError {}
                let unchanged=try cpu.load(original,page:0,width:300)
                precondition(unchanged.pixels.data == opened.pixels.data)
                noted.text="AB\nAB"
            }
            var styled=mark;styled.style.fontSize += 2;styled.style.width += 1;styled.style.opacity=0.5
            styled.style.stroke=NSColor(srgbRed:0.2,green:0.4,blue:0.1,alpha:1)
            styled.style.fill=NSColor(srgbRed:1,green:0.9,blue:0.5,alpha:1)
            let resized=mark.scaled(to:mark.rect.insetBy(dx:-5,dy:-5))
            if !editable {
                for changed in [noted,styled,resized] {
                    do { _=try cpu.annotate(original,page:0,marks:[changed]);fatalError("Protected text box changed") } catch is EngineError {}
                }
            }
            let saved=try cpu.annotate(original,page:0,marks:[])
            let savedPage=try cpu.load(saved,page:0,width:300)
            precondition(savedPage.pixels.data == opened.pixels.data)
            let rotated=try cpu.rotate(try cpu.crop(original,page:0,box:CGRect(x:10,y:10,width:280,height:340)),page:0,degrees:90)
            var variants=[("",original),("-saved",saved),("-rotated",rotated)]
            let organized=try cpu.selectPages(try cpu.merge(original,with:original),indices:[1])
            variants.append(("-organized",organized))
            if editable {
                for (suffix,changed) in [("-edited",noted),("-restyled",styled),("-resized",resized)] {
                    let bytes=try cpu.annotate(original,page:0,marks:[changed])
                    let reopened=try cpu.load(bytes,page:0,width:300).pages[0].annotations[0]
                    precondition(reopened.freeTextEditable && reopened.canEditContents && reopened.canChangeAppearance)
                    precondition(reopened.text == changed.text && reopened.rect == changed.rect)
                    precondition(abs(reopened.style.fontSize-changed.style.fontSize)<0.00001 && abs(reopened.style.width-changed.style.width)<0.00001 && abs(reopened.style.opacity-changed.style.opacity)<0.00001)
                    precondition((PDFDocument(data:bytes)!.page(at:0)!.annotations.first{$0.type == "FreeText"}!.contents ?? "") == changed.text)
                    variants.append((suffix,bytes))
                    if suffix == "-edited" {
                        var again=reopened;again.text=resourceFont ? "é AB" : "Edited again — €5"
                        if intervalFit { again.text="ABC" }
                        let editedAgain=try cpu.annotate(bytes,page:0,marks:[again])
                        let final=try cpu.load(editedAgain,page:0,width:300).pages[0].annotations[0]
                        precondition(final.text == again.text && final.canEditContents)
                        variants.append(("-edited-again",editedAgain))
                    }
                }
                var unsupported=mark;unsupported.text="中文"
                do { _=try cpu.annotate(original,page:0,marks:[unsupported]);fatalError("Unsupported script accepted") } catch is EngineError {}
            }
            let moved=mark.translated(x:13,y:-7)
            if name == "locked" {
                do { _=try cpu.annotate(original,page:0,marks:[moved]);fatalError("Locked text box moved") } catch is EngineError {}
                do { _=try cpu.annotate(original,page:0,marks:[],deleting:[mark.id]);fatalError("Locked text box deleted") } catch is EngineError {}
            } else {
                let shifted=try cpu.annotate(original,page:0,marks:[moved])
                let shiftedMark=try cpu.load(shifted,page:0,width:300).pages[0].annotations[0]
                precondition(shiftedMark.rect == moved.rect && shiftedMark.points == moved.points && shiftedMark.text == mark.text && shiftedMark.importedFreeText)
                precondition((PDFDocument(data:shifted)!.page(at:0)!.annotations.first{$0.type == "FreeText"}!.contents ?? "") == mark.text)
                variants.append(("-moved",shifted))
                let removed=try cpu.annotate(original,page:0,marks:[],deleting:[mark.id])
                let remaining=try cpu.load(removed,page:0,width:100).pages[0].annotations.count
                precondition(remaining == opened.pages[0].annotations.count-1)
                variants.append(("-removed",removed))
            }
            for (suffix,bytes) in variants {
                try bytes.write(to:root.appendingPathComponent(name+suffix+".pdf"))
                let before=try cpu.load(bytes,page:0,width:300)
                if var auto=before.pages[0].annotations.first,auto.style.fontSize == 0 || resourceFont || name.contains("-hscale-") || name.contains("-spacing-") {
                    // Materialize no-AP layouts for independent font-resource rendering.
                    let text=auto.text;auto.text += " "
                    let interim=try cpu.annotate(bytes,page:0,marks:[auto])
                    auto=try cpu.load(interim,page:0,width:300).pages[0].annotations[0];auto.text=text
                    let materialized=try cpu.annotate(interim,page:0,marks:[auto])
                    let after=try cpu.load(materialized,page:0,width:300)
                    precondition(zip(before.pixels.data,after.pixels.data).allSatisfy{abs(Int($0)-Int($1))<=1},"Autosized appearance changed layout")
                    try materialized.write(to:root.appendingPathComponent(name+suffix+"-materialized.pdf"))
                }
                for width in [300,600] {
                    let expected=try cpu.load(bytes,page:0,width:width)
                    let actual=try gpu.openPage(bytes,page:0,width:width)
                    guard let pixels=actual.metalPage?.bitmap(width:width) else { fatalError("Missing Metal text box: \(name)\(suffix)") }
                    precondition(pixels.data.count == expected.pixels.data.count)
                    let delta=zip(pixels.data,expected.pixels.data).map{abs(Int($0)-Int($1))}
                    let maxError=delta.max() ?? 0, changed=delta.filter{$0>1}.count
                    if maxError>32 || changed>pixels.data.count/2000 {
                        print("CPU/Metal mismatch \(name)\(suffix) width=\(width) maximum=\(maxError) changed=\(changed)/\(pixels.data.count)")
                        for (label,image) in [("cpu",expected.pixels),("gpu",pixels)] {
                            let diagnostic=NSBitmapImageRep(cgImage:image.cgImage!).representation(using:.png,properties:[:])!
                            try diagnostic.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width)-\(label).png"))
                        }
                    }
                    precondition(maxError<=32 && changed<=pixels.data.count/2000,"CPU/Metal FreeText mismatch: \(name)\(suffix)")
                    let png=NSBitmapImageRep(cgImage:expected.pixels.cgImage!).representation(using:.png,properties:[:])!
                    try png.write(to:root.appendingPathComponent("\(name)\(suffix)-\(width).png"))
                }
            }
            print("PASS: \(name) FreeText full/indexed rendering, editing capabilities, movement, removal and round trips")
        }
        if CommandLine.arguments.count < 3 {
            func checkMerge(_ name:String,_ bytes:Data,_ sources:[Data]) throws {
                try bytes.write(to:root.appendingPathComponent(name+".pdf"))
                let pageCount=try cpu.load(bytes,page:0,width:100).pages.count
                precondition(pageCount == sources.count)
                for (page,source) in sources.enumerated() {
                    try source.write(to:root.appendingPathComponent("\(name)-source-\(page).pdf"))
                    for width in [300,600] {
                        let original=try cpu.load(source,page:0,width:width)
                        let result=try cpu.load(bytes,page:page,width:width)
                        precondition(result.pages[page].annotations[0].freeTextEditable)
                        precondition(result.pixels.data == original.pixels.data,"Merge changed the selected font")
                        let metal=try gpu.openPage(bytes,page:page,width:width).metalPage!.bitmap(width:width)!
                        let delta=zip(metal.data,result.pixels.data).map{abs(Int($0)-Int($1))}
                        precondition(delta.max()!<=32 && delta.filter{$0>1}.count<=metal.data.count/2000)
                        let png=NSBitmapImageRep(cgImage:result.pixels.cgImage!).representation(using:.png,properties:[:])!
                        try png.write(to:root.appendingPathComponent("\(name)-page-\(page)-\(width).png"))
                    }
                }
            }
            for (variant,suffix) in [("original",""),("appearances","-edited")] {
                let sources=try ["resource-standard","resource-cid"].map{try Data(contentsOf:root.appendingPathComponent($0+suffix+".pdf"))}
                let merged=try cpu.merge(sources[0],with:sources[1])
                try checkMerge("font-merge-"+variant,merged,sources)
                if variant == "appearances" {
                    var edited=merged, expected:[Data]=[]
                    for (page,source) in sources.enumerated() {
                        var target=try cpu.load(edited,page:page,width:100).pages[page].annotations[0]
                        target.text="AB é";target.style.fontSize += 3
                        edited=try cpu.annotate(edited,page:page,marks:[target])
                        var original=try cpu.load(source,page:0,width:100).pages[0].annotations[0]
                        original.text=target.text;original.style=target.style
                        expected.append(try cpu.annotate(source,page:0,marks:[original]))
                    }
                    try checkMerge("font-merge-edited",edited,expected)
                }
            }
            print("PASS: colliding document fonts, retained appearances and edits after merge on CPU/Metal")
        }
        for url in try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("invalid"),includingPropertiesForKeys:nil) {
            let bytes=try Data(contentsOf:url)
            do { _=try cpu.load(bytes,page:0,width:100);fatalError("Accepted invalid text box: \(url.lastPathComponent)") } catch is EngineError {}
            do { _=try gpu.openPage(bytes,page:0,width:100);fatalError("Indexed open accepted invalid text box: \(url.lastPathComponent)") } catch is EngineError {}
        }
        print("PASS: invalid/unsupported FreeText inputs reject explicitly")
    }
}
