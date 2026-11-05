// Independent reader checks only; PDFKit is never linked into Pod.
import Foundation
import AppKit
import PDFKit

let directory=URL(fileURLWithPath:CommandLine.arguments[1])
func open(_ name:String) -> PDFDocument {
    guard let doc=PDFDocument(url:directory.appendingPathComponent(name)) else { fatalError("Cannot open \(name)") }
    return doc
}
let merged=open("page-merged.pdf")
precondition(merged.pageCount==3)
precondition(merged.page(at:2)!.string!.contains("Notes for tomorrow"))
let extracted=open("page-extracted.pdf")
precondition(extracted.pageCount==1 && extracted.string!.contains("Notes for tomorrow"))
let reordered=open("page-reordered.pdf")
precondition(reordered.pageCount==2 && reordered.page(at:0)!.string!.contains("Notes for tomorrow"))
let geometry=open("page-geometry.pdf")
let page=geometry.page(at:0)!
precondition(page.rotation==90)
precondition(page.bounds(for:.cropBox)==CGRect(x:20,y:30,width:480,height:670))
precondition(page.bounds(for:.mediaBox)==CGRect(x:0,y:0,width:612,height:792))
precondition(geometry.page(at:1)!.rotation==0)
let thumbnail=page.thumbnail(of:NSSize(width:670,height:480),for:.cropBox)
guard let tiff=thumbnail.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) else { fatalError("Cannot render crop") }
try png.write(to:directory.appendingPathComponent("page-geometry-independent.png"))
print("Independent PDFKit: merge, extract, reorder, crop, rotation and unchanged neighboring page passed")
