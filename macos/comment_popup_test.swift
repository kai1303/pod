import AppKit

@main struct CommentPopupChecks {
    static func main() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine = try Engine()
        for name in ["open","closed","parentless","unpaired","rich"] {
            let bytes = try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let loaded = try engine.load(bytes,page:0,width:400)
            precondition(loaded.pages[0].annotations.count == 1)
            let mark = loaded.pages[0].annotations[0]
            let info = mark.comment
            precondition(info.author == "Cô giáo 😀" && info.subject == "Bài học — 中文")
            precondition(info.initiallyOpen == (name != "closed"))
            precondition(info.richText == (name == "rich"))
            precondition(info.popupRect == (name == "unpaired" ? nil:CGRect(x:90,y:100,width:200,height:140)))
            let indexed = try engine.previewInfo(PDFPageIndex(bytes),page:0).annotations[0].comment
            precondition(indexed.author == info.author && indexed.subject == info.subject && indexed.initiallyOpen == info.initiallyOpen && indexed.popupRect == info.popupRect)
            try bytes.withUnsafeBytes { raw in
                let doc = pod_open(raw.bindMemory(to:UInt8.self).baseAddress,bytes.count)!
                defer { pod_close(doc) }
                var first = PodBuffer(); precondition(pod_save(doc,&first) != 0)
                defer { pod_buffer_free(first.data,first.length) }
                var meta = PodCommentInfo()
                for _ in 0..<10 { precondition(pod_comment_info(doc,0,0,&meta) != 0) }
                precondition(meta.initially_open == (info.initiallyOpen ? 1:0))
                let author = meta.author.data
                precondition(pod_comment_info(doc,0,0,&meta) != 0 && meta.author.data == author,"Metadata should reuse cached strings")
                var second = PodBuffer(); precondition(pod_save(doc,&second) != 0)
                defer { pod_buffer_free(second.data,second.length) }
                precondition(Data(bytes:first.data!,count:first.length) == Data(bytes:second.data!,count:second.length),"Reading metadata mutated saved PDF")
                precondition(pod_comment_info(doc,0,99,&meta) == 0 && meta.author.data == nil && meta.has_popup == 0 && meta.initially_open == 0)
                precondition(pod_comment_info(doc,99,0,&meta) == 0 && meta.subject.length == 0)
                if name == "rich" { try Data(bytes:second.data!,count:second.length).write(to:root.appendingPathComponent(name+"-saved.pdf")) }
            }
            var edited = mark; edited.text = "Edited note — 已阅"
            if name == "rich" {
                do { _ = try engine.annotate(bytes,page:0,marks:[edited]); preconditionFailure("Rich text was overwritten") }
                catch { precondition(String(describing:error).contains("UnsupportedAnnotation")) }
            } else {
                let saved = try engine.annotate(bytes,page:0,marks:[edited])
                let reopened = try engine.load(saved,page:0,width:400)
                let new = reopened.pages[0].annotations[0]
                precondition(new.text == edited.text && new.comment.author == info.author && new.comment.subject == info.subject)
                precondition(new.comment.initiallyOpen == info.initiallyOpen && new.comment.popupRect == info.popupRect)
                precondition(reopened.pixels.data == loaded.pixels.data)
                try saved.write(to:root.appendingPathComponent(name+"-saved.pdf"))
            }
            print("PASS: \(name) full/indexed native metadata, C lifetime/error contract, read-only queries and edit preservation")
        }
    }
}
