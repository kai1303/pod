import AppKit
import CryptoKit
import Darwin

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func rejects(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected validation failure") } catch {}
}
@main struct DrawingTests {
    static func main() throws {
        let invite=try DrawingInvite(host:"127.0.0.1",port:48672)
        let parsed=try DrawingInvite(url:invite.url); expect(parsed == invite,"Invitation round trip")
        rejects { _ = try DrawingInvite(url:URL(string:invite.url.absoluteString.replacingOccurrences(of:"v=\(DrawingInvite.protocolVersion)&",with:"v=3&"))!) }
        let ipv6=try DrawingInvite(host:"2001:db8::1",port:48672)
        let parsed6=try DrawingInvite(url:ipv6.url); expect(parsed6 == ipv6,"IPv6 round trip")
        rejects { _ = try DrawingInvite(url:URL(string:"https://example.com")!) }
        rejects { _ = try DrawingInvite(url:URL(string:"pod://draw?host=127.0.0.1&port=0")!) }
        rejects { _ = try DrawingInvite(host:"https://example.com/path",port:48672) }
        let box=CGRect(x:0,y:0,width:612,height:792)
        let cursor=DrawingCursor(owner:.host,page:0,point:DrawingPoint(x:20,y:30),drawing:false)
        try cursor.validate(boxes:[box],receiver:.guest)
        rejects { try cursor.validate(boxes:[box],receiver:.host) }
        var badCursor=cursor; badCursor.page=1
        rejects { try badCursor.validate(boxes:[box],receiver:.guest) }
        badCursor=cursor; badCursor.point.x = .nan
        rejects { try badCursor.validate(boxes:[box],receiver:.guest) }
        badCursor=cursor; badCursor.point.y=1000
        rejects { try badCursor.validate(boxes:[box],receiver:.guest) }
        let mark=Markup(kind:.ink,points:[CGPoint(x:20,y:30),CGPoint(x:80,y:90)],rect:.zero,style:MarkupStyle())
        try groupedInkValidation(mark,box:box)
        try editValidation(mark,box:box)
        var a=DrawingBoard(), b=DrawingBoard()
        let first=try a.add(mark,page:0,owner:.host,boxes:[box])
        let second=try b.add(mark,page:0,owner:.guest,boxes:[box])
        try a.merge([second],from:.guest,boxes:[box]); try b.merge([first],from:.host,boxes:[box])
        expect(a.visible == b.visible,"Concurrent drawing converges")
        let deletion=try a.undo(owner:.host,boxes:[box]).first!
        try b.merge([deletion],from:.host,boxes:[box])
        try b.merge([first],from:.host,boxes:[box])
        expect(a.visible == b.visible && b.visible == [second],"Deleted strokes cannot resurrect")
        var c=DrawingBoard()
        try c.merge([deletion,first],from:.host,boxes:[box])
        expect(c.visible.isEmpty,"Delete before add converges")
        rejects { try c.merge([second],from:.host,boxes:[box]) }
        var invalid=first; invalid.points[0].x = .infinity
        rejects { try c.merge([invalid],from:.host,boxes:[box]) }
        invalid=first; invalid.page=4
        rejects { try c.merge([invalid],from:.host,boxes:[box]) }
        invalid=first; invalid.width=0
        rejects { try c.merge([invalid],from:.host,boxes:[box]) }
        invalid=first; invalid.points[0].x = -100
        rejects { try c.merge([invalid],from:.host,boxes:[box]) }
        invalid=deletion; invalid.points[0].x = 40
        rejects { try c.merge([invalid],from:.host,boxes:[box]) }
        let redone=try a.redo(owner:.host,boxes:[box]).first!
        expect(redone.id != first.id && a.visible.count==2,"Redo creates a new stroke")
        try b.merge([redone],from:.host,boxes:[box])
        expect(a.visible == b.visible,"Redo converges")
        var forgedGuest=second; forgedGuest.removed=true
        rejects { try b.mergeFromHost([forgedGuest],boxes:[box]) }
        var fabricated=second; fabricated.id=UUID()
        rejects { try b.mergeFromHost([fabricated],boxes:[box]) }
        try b.mergeFromHost(a.records,boxes:[box])
        expect(b.visible==a.visible,"Host snapshots may echo known guest records")
        let encoded=try JSONEncoder().encode(a.records)
        var decoded=DrawingBoard(); try decoded.merge(JSONDecoder().decode([DrawingStroke].self,from:encoded),boxes:[box])
        expect(decoded.visible == a.visible,"Serializable state")
        for _ in 0..<40 {
            var shuffled=DrawingBoard()
            for r in ([first,second,deletion,redone,first,deletion]).shuffled() { try shuffled.merge([r],boxes:[box]) }
            expect(shuffled.visible == a.visible,"Merge is independent of order and duplicates")
        }
        var eraseBoard=DrawingBoard()
        let erasable=try eraseBoard.add(mark,page:0,owner:.host,boxes:[box])
        _ = try eraseBoard.remove(erasable.id,owner:.host,boxes:[box])
        _ = try eraseBoard.undo(owner:.host,boxes:[box])
        expect(eraseBoard.visible.count==1,"Undo eraser restores the local stroke")
        _ = try eraseBoard.redo(owner:.host,boxes:[box])
        expect(eraseBoard.visible.isEmpty,"Redo eraser removes the restored stroke")
        print("Drawing invitation, validation, ownership, merge, undo/redo passed")
        try networkAndExport()
        try transportFrames()

    }
    static func groupedInkValidation(_ mark:Markup,box:CGRect) throws {
        var grouped=mark
        grouped.points.append(CGPoint(x:150,y:160))
        grouped.inkPathStarts=[0,2]
        var board=DrawingBoard()
        let group=try board.add(grouped,page:0,owner:.host,boxes:[box])
        expect(group.markup.inkPathStarts==[0,2],"Preserves separate line and tap")
        for starts in [[1], [0,0], [0,2,1], [0,3], [-1,1]] {
            var invalid=group
            invalid.inkPathStarts=starts
            rejects { try invalid.validate(boxes:[box]) }
        }
        var conflicting=group
        conflicting.inkPathStarts=[]
        rejects { try board.merge([conflicting],from:.host,boxes:[box]) }
        var oversized=group
        oversized.points=Array(repeating:group.points[0],count:4097)
        rejects { try oversized.validate(boxes:[box]) }
        _=try board.remove(group.id,owner:.host,boxes:[box])
        expect(board.visible.isEmpty,"Erases the entire shared ink group")
        _=try board.undo(owner:.host,boxes:[box])
        expect(board.visible.count==1 && board.visible[0].inkPathStarts==[0,2],"Restores the entire group")
        var tap=mark
        tap.points=[mark.points[0]]
        _=try board.add(tap,page:0,owner:.host,boxes:[box])
    }
    static func editValidation(_ mark:Markup,box:CGRect) throws {
        var board=DrawingBoard()
        let first=try board.add(mark,page:0,owner:.guest,boxes:[box])
        let second=try board.add(mark,page:0,owner:.guest,boxes:[box])
        var moved=mark.translated(x:15,y:20)
        moved.style.width=64; moved.style.opacity=0.5; moved.text="A note 🖊"; moved.link="https://example.com/annotation"
        let changes=try board.change(updates:[(first.id,moved)],deleting:[second.id],owner:.guest,boxes:[box])
        expect(changes.count==2 && board.visible.map(\.id)==[first.id],"Sweep edits and deletes together")
        let edited=changes[0], removed=changes[1]
        let undone=try board.undo(owner:.guest,boxes:[box])
        expect(undone.count==2 && board.visible.count==2 && board.visible.allSatisfy { $0.markup.points==mark.points && $0.text.isEmpty },"One undo restores all sweep targets")
        let redone=try board.redo(owner:.guest,boxes:[box])
        expect(board.visible.count==1 && board.visible[0].markup.points==moved.points && board.visible[0].text==moved.text,"Redo repeats the sweep")
        for _ in 0..<20 {
            var peer=DrawingBoard()
            try peer.merge(([first,second,edited,removed]+undone+redone).shuffled(),from:.guest,boxes:[box])
            expect(peer.records==board.records,"Reordered edits, erase, restore, redo converge")
        }
        try board.mergeFromHost([first,second],boxes:[box])
        var spoof=edited; spoof.version=20
        rejects { try board.mergeFromHost([spoof],boxes:[box]) }
        rejects { _=try board.change(updates:[(first.id,mark)],deleting:[],owner:.host,boxes:[box]) }
        var invalid=moved; invalid.link="file:///tmp/file"
        rejects { _=try board.change(updates:[(first.id,invalid)],deleting:[],owner:.guest,boxes:[box]) }
        let before=board.records
        rejects { _=try board.change(updates:[(first.id,mark)],deleting:[UUID()],owner:.guest,boxes:[box]) }
        expect(board.records==before,"Failed batch leaves all drawings intact")
        var illegal=removed; illegal.removed=false; illegal.version += 1
        rejects { try board.merge([illegal],from:.guest,boxes:[box]) }
    }
    static func wait(_ label:String,seconds:Double=10,diagnostic:()->String={""},until condition:()->Bool) {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() && Date()<deadline { _ = RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.01)) }
        expect(condition(),"Timed out: \(label). \(diagnostic())")
    }
    static func availablePort() throws -> UInt16 {
        let fd=socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else { throw DrawingError(message:"Test socket failed") }; defer { close(fd) }
        var address=sockaddr_in(); address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family=sa_family_t(AF_INET)
        let bound=withUnsafePointer(to:&address) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound==0 else { throw DrawingError(message:"Test port allocation failed") }
        var length=socklen_t(MemoryLayout<sockaddr_in>.size)
        let queried=withUnsafeMutablePointer(to:&address) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(fd,$0,&length) } }
        guard queried==0 else { throw DrawingError(message:"Test port lookup failed") }
        return UInt16(bigEndian:address.sin_port)
    }
    static func networkAndExport() throws {
        let engine=try Engine()
        let source=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let document=try engine.load(source,page:0,width:300)
        let invite=try DrawingInvite(host:"127.0.0.1",port:try availablePort())
        let host=DrawingSession(invite:invite,owner:.host),guest=DrawingSession(invite:invite,owner:.guest)
        defer { host.stop(); guest.stop() }
        var receivedDocuments=0
        guest.onDocument={ data,_,done in
            receivedDocuments += 1
            done(Result { try engine.load(data,page:0,width:300).pages.map(\.box) })
        }
        try host.host(document:document,name:"Test.pdf")
        wait("listener",diagnostic:{host.status}) { host.status.hasPrefix("Sharing") }
        guest.join()
        wait("TLS peers ready") { host.connected && guest.connected }
        expect(guest.base==source && receivedDocuments==1,"Verified PDF transferred")
        let revision=guest.board.revision
        host.updateCursor(CGPoint(x:30,y:50),page:0,drawing:false)
        wait("remote hover cursor") { guest.remoteCursor?.point == DrawingPoint(x:30,y:50) }
        host.updateCursor(CGPoint(x:60,y:80),page:0,drawing:true)
        host.updateCursor(CGPoint(x:90,y:100),page:0,drawing:true)
        wait("coalesced cursor retains final position") { guest.remoteCursor?.point == DrawingPoint(x:90,y:100) && guest.remoteCursor?.drawing==true }
        expect(guest.board.revision==revision && guest.board.records.isEmpty,"Presence does not change drawings or undo history")
        host.updateCursor(nil,page:0,drawing:false)
        wait("cursor leaves page") { guest.remoteCursor==nil }
        host.updateCursor(CGPoint(x:40,y:70),page:0,drawing:false)
        host.updateCursor(nil,page:0,drawing:false)
        // Flush after an immediate hide; a pending movement must not resurrect the cursor.
        let settle=Date().addingTimeInterval(0.08)
        while Date()<settle { _ = RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.01)) }
        expect(guest.remoteCursor==nil,"Hidden cursor is not revived by a queued update")
        guest.updateCursor(CGPoint(x:70,y:90),page:1,drawing:false)
        wait("reverse cursor and page") { host.remoteCursor?.page==1 }

        let mark=Markup(kind:.ink,points:[CGPoint(x:20,y:30),CGPoint(x:80,y:90)],rect:.zero,style:MarkupStyle())
        var grouped=mark
        grouped.points.append(CGPoint(x:110,y:50))
        grouped.inkPathStarts=[0,2]
        host.preview(grouped,page:0)
        wait("live stroke before commit") { guest.remotePreview?.markup.inkPathStarts == [0,2] }
        try host.add(grouped,page:0); try guest.add(mark,page:1)
        wait("bidirectional commits") { host.board.visible.count==2 && guest.board.visible.count==2 && guest.remotePreview==nil }
        expect(host.board.visible==guest.board.visible,"Both peers converge")
        let hostID=host.board.visible.first { $0.owner == .host }!.id
        rejects { try guest.update(hostID,mark:mark) }
        grouped=grouped.translated(x:5,y:10)
        grouped.text="Discuss this curve ✎"; grouped.link="https://example.com/drawing"; grouped.style.width=6
        try host.update(hostID,mark:grouped)
        wait("live shared edit") { guest.board.visible.first { $0.id==hostID }?.text == grouped.text }
        try host.undo()
        wait("undo edit keeps drawing") { guest.board.visible.first { $0.id==hostID }?.text == "" }
        try host.redo()
        wait("redo edit preserves identity") { guest.board.visible.first { $0.id==hostID }?.link == grouped.link }
        try guest.undo()
        wait("remote undo") { host.board.visible.count==1 }
        expect(host.board.visible[0].owner == .host,"Guest undo preserves host drawing")
        try guest.redo()
        wait("guest stroke restored before disconnect") { host.board.visible==guest.board.visible }
        let guestID=guest.board.visible.first { $0.owner == .guest }!.id
        guest.stop()
        wait("disconnect") { !host.connected }
        expect(host.remoteCursor==nil && guest.remoteCursor==nil,"Disconnect clears both cursors")
        try host.add(mark,page:0)
        var offline=mark; offline.text="Edited while offline"
        try guest.update(guestID,mark:offline)
        guest.reconnect()
        wait("reconnect catch-up") { host.connected && guest.connected && host.board.visible==guest.board.visible }
        expect(host.board.visible.count==3 && receivedDocuments==1,"Offline changes retained without reloading PDF")
        expect(host.remoteCursor==nil && guest.remoteCursor==nil,"Reconnect does not replay stale presence")
        expect(host.board.visible.first { $0.id==guestID }?.text==offline.text,"Stale host snapshot cannot overwrite offline guest edit")
        let other=host.board.visible.first { $0.owner == .host && $0.id != hostID }!.id
        let clipped=grouped.translated(x:2,y:2)
        try host.erase(updates:[(hostID,clipped)],deleting:[other])
        wait("sweep sync") { host.board.visible==guest.board.visible && guest.board.visible.count==2 }
        try host.undo()
        wait("one step undoes sweep") { host.board.visible==guest.board.visible && guest.board.visible.count==3 }
        let exported=try host.board.export(source,using:engine)
        let reopened=try engine.load(exported,page:0,width:300)
        expect(reopened.pages[0].annotations.count==document.pages[0].annotations.count+2,"Host strokes embedded")
        expect(reopened.pages[0].annotations.contains { $0.kind == .ink && $0.inkPathStarts == [0,2] && $0.points == grouped.points && $0.text == grouped.text && $0.link == grouped.link && $0.style.width == 6 }, "Reopened PDF retains both separate ink paths in one annotation")
        expect(reopened.pages[1].annotations.count==document.pages[1].annotations.count+1,"Guest stroke embedded")
        let guestExport=try guest.board.export(source,using:engine)
        expect(exported==guestExport,"Peers export identical PDFs")
        try exported.write(to:URL(fileURLWithPath:"test-out/shared-drawing.pdf"))
        guest.stop(); wait("second disconnect") { !host.connected }
        var badURL=URLComponents(url:invite.url,resolvingAgainstBaseURL:false)!
        badURL.fragment=String(repeating:"11",count:32)
        let wrong=DirectPeer(invite:try DrawingInvite(url:badURL.url!))
        var wrongReady=false,wrongClosed=false,wrongData=false
        wrong.onReady={ wrongReady=true }; wrong.onData={_ in wrongData=true }; wrong.onDisconnect={_ in wrongClosed=true }
        wrong.connect(); wait("wrong-key rejection",seconds:20) { wrongClosed }
        expect(!wrongReady && !wrongData,"Wrong invitation receives no PDF")
        wrong.stop()
        // The valid guest must still be able to join after an authentication failure.
        guest.reconnect(); wait("recover after rejected guest") { host.connected && guest.connected }
        print("Real TLS peers: PDF transfer, cursor presence/coalescing/cleanup, live preview, concurrent drawing, local undo, reconnect, export, wrong-key rejection passed")
    }

    static func transportFrames() throws {
        let invite=try DrawingInvite(host:"127.0.0.1",port:try availablePort())
        let server=DirectPeer(invite:invite),client=DirectPeer(invite:invite)
        defer { server.stop(); client.stop() }
        var listening=false,ready=false,received=Data(),reply=Data()
        server.onListening={ listening=true }; client.onReady={ ready=true }
        server.onData={ received=$0 }; client.onData={ reply=$0 }
        try server.listen(); wait("frame listener") { listening }
        let conflict=DirectPeer(invite:invite); var conflictReported=false
        conflict.onDisconnect={_ in conflictReported=true }
        try conflict.listen(); wait("occupied port is reported",seconds:3) { conflictReported }; conflict.stop()
        client.connect(); wait("frame client") { ready }
        let payload=Data((0..<(2*1024*1024)).map{UInt8($0 % 251)})
        try client.send(payload); wait("multi-segment frame") { received.count==payload.count }
        expect(received==payload,"TCP segmentation preserves the complete frame")
        try server.send(Data([1,2,3])); wait("small reverse frame") { reply==Data([1,2,3]) }
        rejects { try client.send(Data()) }
        rejects { try client.send(Data(repeating:0,count:DirectPeer.maxFrame+1)) }
        print("TLS framing: 2 MiB segmented payload, reverse frame and size limits passed")
    }

}
