// Independent macOS validation only. PDFKit is never linked into the engine.
import Foundation
import AppKit
import PDFKit

guard CommandLine.arguments.count == 3,
      let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])),
      let page = document.page(at: 0) else {
    fputs("usage: pdfkit-check INPUT.pdf OUTPUT.png\n", stderr)
    exit(1)
}
let thumbnail = page.thumbnail(of: NSSize(width: 918, height: 1188), for: .mediaBox)
guard let tiff = thumbnail.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(2) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
let pageText = (page.string ?? "") as NSString
var characters: [[String: Any]] = []
for index in 0..<pageText.length {
    if let selection = page.selection(for: NSRange(location: index, length: 1)) {
        let rect = selection.bounds(for: page)
        characters.append(["text": pageText.substring(with: NSRange(location: index, length: 1)),
                           "x": rect.origin.x, "y": rect.origin.y])
    }
}
let info: [String: Any] = ["pages": document.pageCount, "text": document.string ?? "",
                           "characters": characters,
                           "width": page.bounds(for: .mediaBox).width,
                           "height": page.bounds(for: .mediaBox).height]
let json = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
print(String(data: json, encoding: .utf8)!)
