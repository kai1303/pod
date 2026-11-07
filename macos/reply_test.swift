import AppKit
import PDFKit

@main struct ReplyChecks {
    static func main() throws {
        setbuf(stdout,nil)
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let engine = try Engine(), gpu = try Engine(metal:MetalPageRenderer()!)
        for name in ["note","highlight","review","no-view"] {
            let bytes = try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            let loaded = try engine.load(bytes,page:0,width:400)
            let marks = loaded.pages[0].annotations
            precondition(marks[0].hasReplies && marks[1].hasReplies && !marks[0].canDelete && marks[2].canDelete)
            let reading = ReadingIndex()
            var hits: [ReadingIndex.Hit]?
            reading.scan(bytes:bytes,query:nil) { found,_ in hits=found }
            let deadline = Date().addingTimeInterval(5)
            while hits == nil && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            precondition(hits?.count == 1 && hits?.first?.note == "Question ✓","Notes navigator exposed replies independently")
            precondition(hits?.first?.snippet.isEmpty == true,"Blank page produced a passage snippet")
            precondition(marks.count == 3 && marks[0].comment.replyTo == 0)
            precondition(marks[1].comment.replyTo == marks[0].id && marks[2].comment.replyTo == marks[1].id)
            precondition(marks[1].comment.threadRoot == marks[0].id && marks[2].comment.threadRoot == marks[0].id)
            precondition(marks[0].comment.author == "Teacher" && marks[1].comment.author == "Student")
            if name == "review" { precondition(marks[2].comment.reviewState == "Accepted" && marks[2].comment.stateModel == "Review") }
            let indexed = try engine.previewInfo(PDFPageIndex(bytes),page:0)
            precondition(indexed.annotations[2].comment.threadRoot == marks[0].id)
            var reply = Markup(kind:.comment,points:[],rect:.zero,text:"New reply — 已阅",style:.initial(for:.comment))
            reply.comment.replyTo = marks[1].id; reply.comment.author = "Học sinh 😀"
            let revised = try engine.annotate(bytes,page:0,marks:[reply])
            let updated = try engine.load(revised,page:0,width:400)
            let child = updated.pages[0].annotations.last!
            precondition(child.comment.replyTo == marks[1].id && child.comment.threadRoot == marks[0].id)
            precondition(child.text == reply.text && child.comment.author == reply.comment.author)
            precondition(updated.pixels.data == loaded.pixels.data,"Reply added an independent page icon")
            let gpuView = try gpu.load(revised,page:0,width:400)
            precondition(gpuView.metalPage != nil)
            precondition(zip(gpuView.pixels.data,updated.pixels.data).allSatisfy { abs(Int($0)-Int($1)) <= 1 })
            let external = PDFDocument(data:revised)!.page(at:0)!
            precondition(external.annotations.contains { $0.contents == reply.text && $0.userName == reply.comment.author })
            do { _ = try engine.annotate(revised,page:0,marks:[],deleting:[marks[1].id]); preconditionFailure("Parent with replies was removed") } catch { }
            var edited = child; edited.text = "Edited reply ✓"
            let editedBytes = try engine.annotate(revised,page:0,marks:[edited])
            let editedInfo = try engine.previewInfo(PDFPageIndex(editedBytes),page:0).annotations.last!
            precondition(editedInfo.text == edited.text && editedInfo.comment.replyTo == marks[1].id)
            let removed = try engine.annotate(editedBytes,page:0,marks:[],deleting:[child.id])
            let extracted = try engine.selectPages(revised,indices:[0])
            let extractedMarks = try engine.load(extracted,page:0,width:400).pages[0].annotations
            precondition(extractedMarks.last?.comment.threadRoot == extractedMarks[0].id)
            try revised.write(to:root.appendingPathComponent(name+"-replied.pdf"))
            try removed.write(to:root.appendingPathComponent(name+"-removed.pdf"))
            try extracted.write(to:root.appendingPathComponent(name+"-extracted.pdf"))
            bytes.withUnsafeBytes { raw in
                let doc = pod_open(raw.bindMemory(to:UInt8.self).baseAddress,bytes.count)!
                defer { pod_close(doc) }
                var count = 0
                precondition(pod_annotation_count(doc,0,&count) != 0 && count == 3)
                var output: UInt32 = 123
                precondition(pod_comment_reply(doc,0,marks[0].id,nil,1,nil,0,&output) == 0 && output == 0)
                let index = pod_index_open(raw.bindMemory(to:UInt8.self).baseAddress,bytes.count)!
                defer { pod_index_close(index) }
                let page = pod_index_open_page(index,0)!
                defer { pod_close(page) }
                let text: [UInt8] = [65]
                text.withUnsafeBufferPointer { text in
                    precondition(pod_comment_reply(page,0,marks[0].id,text.baseAddress,1,nil,0,&output) == 0 && String(cString:pod_error()) == "ReadOnlyPage")
                    precondition(pod_comment_reply(doc,0,UInt32.max,text.baseAddress,1,nil,0,&output) == 0 && output == 0)
                }
                let answer = Array("Bridge reply ✓".utf8)
                answer.withUnsafeBufferPointer { text in
                    precondition(pod_comment_reply(doc,0,marks[0].id,text.baseAddress,text.count,nil,0,&output) != 0 && output != 0)
                }
                precondition(pod_annotation_count(doc,0,&count) != 0 && count == 4)
                var metadata = PodCommentInfo()
                precondition(pod_comment_info(doc,0,3,&metadata) != 0 && metadata.reply_to == marks[0].id)
                precondition(pod_annotation_remove(doc,0,output) != 0)
                precondition(pod_annotation_count(doc,0,&count) != 0 && count == 3)
            }
            print("PASS: \(name) full/indexed threads, Unicode create/edit/remove, parent protection, CPU/Metal pixels, PDFKit reopen, extraction and C errors")
        }
        for name in ["cycle","orphan","cross-page","group","wrong-generation"] {
            let bytes = try Data(contentsOf:root.appendingPathComponent(name+".pdf"))
            do { _ = try engine.load(bytes,page:0,width:400); preconditionFailure("Malformed thread opened: \(name)") } catch { }
            print("PASS: rejected \(name) relationship")
        }
    }
}
