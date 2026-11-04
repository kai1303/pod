// Independent reader acceptance only; this program is not linked into Pod.
import AppKit
import PDFKit
let path=CommandLine.arguments[1]
guard let doc=PDFDocument(url:URL(fileURLWithPath:path)), let page=doc.page(at:0) else { fatalError("Cannot read exported annotations") }
precondition(doc.pageCount==2)
let marks=page.annotations
precondition(marks.count==18,"Expected all18 markup tools")
let types=Set(marks.compactMap{$0.type})
precondition(Set(["Square","Circle","Line","PolyLine","Polygon","Highlight","Underline","Squiggly","StrikeOut","Ink","FreeText","Text"]).isSubset(of:types))
precondition(marks.contains{$0.type=="FreeText" && $0.contents=="A note"})
precondition(marks.contains{$0.type=="Text" && $0.contents=="A note"})
let image=page.thumbnail(of:NSSize(width:918,height:1188),for:.mediaBox)
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("Independent PDFKit: 18 annotations, 12 standard subtypes, text/comment contents and rendered export passed")
