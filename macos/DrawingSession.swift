import AppKit
import CryptoKit

private enum DrawingMessage:Codable {
    case document(version:Int,session:UUID,digest:String,name:String,bytes:Data)
    case accepted
    case records([DrawingStroke])
    case ready
    case preview(DrawingStroke?)
    case cursor(DrawingCursor?)
}

final class DrawingSession {
    static let maxPDF=32*1024*1024
    let invite:DrawingInvite
    let owner:DrawingOwner
    private let peer:DirectPeer
    private(set) var base:Data?
    private(set) var name="Shared PDF.pdf"
    private(set) var boxes:[CGRect]=[]
    private(set) var board=DrawingBoard()
    private(set) var remotePreview:DrawingStroke?
    private(set) var remoteCursor:DrawingCursor?
    private var pendingCursor:DrawingCursor?
    private var cursorSend:DispatchWorkItem?
    private var cursorExpiry:DispatchWorkItem?
    private var lastCursorSend=0.0
    var onPresenceChange:(()->Void)?
    private(set) var connected=false
    private(set) var status="Connecting…"
    private var phase=0
    private var generation=0
    private var lastPreviewTime=0.0
    private var handshakeTimeout:DispatchWorkItem?
    var onChange:(()->Void)?
    var onStatus:((String)->Void)?
    var onDocument:((Data,String,@escaping (Result<[CGRect],Error>)->Void)->Void)?

    init(invite:DrawingInvite,owner:DrawingOwner) {
        self.invite=invite; self.owner=owner; peer=DirectPeer(invite:invite)
        peer.onListening={ [weak self] in self?.report("Sharing · waiting for the other Mac") }
        peer.onReady={ [weak self] in self?.established() }
        peer.onData={ [weak self] data in self?.receive(data) }
        peer.onDisconnect={ [weak self] message in
            guard let self else { return }
            self.generation += 1; self.phase=0; self.connected=false; self.remotePreview=nil; self.clearCursor(); self.handshakeTimeout?.cancel(); self.onChange?(); self.report(message)
        }
    }
    func host(document:LoadedPDF,name:String) throws {
        guard document.bytes.count<=Self.maxPDF else { throw DrawingError(message:"Direct drawing currently supports PDFs up to 32 MB.") }
        base=document.bytes; boxes=document.pages.map(\.box); self.name=String(name.prefix(255)); try peer.listen()
    }
    func join() { clearCursor(); generation += 1; phase=0; remotePreview=nil; handshakeTimeout?.cancel(); connected=false; report("Connecting directly…"); peer.connect() }
    func reconnect() {
        guard !connected else { return }
        if owner == .guest { join() }
        else { clearCursor(); generation += 1; phase=0; remotePreview=nil; handshakeTimeout?.cancel(); do { try peer.listen() } catch { report(error.localizedDescription) } }
    }
    func stop() { clearCursor(); generation += 1; phase=0; connected=false; remotePreview=nil; handshakeTimeout?.cancel(); peer.stop() }
    private func report(_ message:String) { status=message; onStatus?(message) }
    private func send(_ message:DrawingMessage) throws { try peer.send(JSONEncoder().encode(message)) }
    private func digest(_ bytes:Data) -> String { SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined() }
    private func established() {
        clearCursor()
        generation += 1; phase=1; connected=false; remotePreview=nil
        report("Synchronizing PDF and drawings…")
        let current=generation
        let timeout=DispatchWorkItem { [weak self] in
            guard let self,self.generation==current,!self.connected else { return }
            self.peer.disconnect("Synchronization timed out. Reconnect to try again.")
        }
        handshakeTimeout?.cancel(); handshakeTimeout=timeout; DispatchQueue.main.asyncAfter(deadline:.now()+60,execute:timeout)
        if owner == .host,let base {
            do { try send(.document(version:DrawingInvite.protocolVersion,session:invite.session,digest:digest(base),name:name,bytes:base)) }
            catch { peer.disconnect(error.localizedDescription) }
        }
    }
    private func receive(_ data:Data) {
        do {
            let message=try JSONDecoder().decode(DrawingMessage.self,from:data)
            switch message {
            case .document(let version,let session,let hash,let name,let bytes):
                guard owner == .guest,phase==1,version==DrawingInvite.protocolVersion,session==invite.session,!bytes.isEmpty,bytes.count<=Self.maxPDF,name.utf8.count<=1024,hash==digest(bytes) else { throw DrawingError(message:"Invalid shared PDF or session.") }
                phase=2
                if let base {
                    guard base==bytes else { throw DrawingError(message:"This invitation now refers to a different PDF.") }
                    try send(.accepted)
                } else {
                    let current=generation
                    guard let onDocument else { throw DrawingError(message:"PDF receiver is not ready.") }
                    onDocument(bytes,name) { [weak self] result in
                        guard let self,self.generation==current else { return }
                        do {
                            self.boxes=try result.get()
                            guard !self.boxes.isEmpty else { throw DrawingError(message:"Shared PDF has no pages.") }
                            self.base=bytes; self.name=name; try self.send(.accepted); self.onChange?()
                        } catch { self.peer.disconnect(error.localizedDescription) }
                    }
                }
            case .accepted:
                guard owner == .host,phase==1 else { throw DrawingError(message:"Unexpected session acknowledgement.") }
                phase=2; try send(.records(board.records)); try send(.ready)
            case .records(let records):
                guard phase>=2,base != nil else { throw DrawingError(message:"Drawing arrived before its PDF.") }
                if owner == .host { try board.merge(records,from:.guest,boxes:boxes) }
                else { try board.mergeFromHost(records,boxes:boxes) }
                if let preview=remotePreview,records.contains(where:{$0.id==preview.id}) { remotePreview=nil }
                onChange?()
            case .ready:
                guard phase==2,base != nil else { throw DrawingError(message:"Unexpected ready message.") }
                if owner == .guest { try send(.records(board.records.filter{$0.owner == .guest})); try send(.ready) }
                else { try send(.records(board.records)) }
                phase=3; connected=true; handshakeTimeout?.cancel(); handshakeTimeout=nil
                report("Connected · drawing together"); onChange?()
            case .cursor(let cursor):
                guard phase==3 else { throw DrawingError(message:"Cursor arrived before synchronization.") }
                if let cursor { try cursor.validate(boxes:boxes,receiver:owner) }
                cursorExpiry?.cancel(); cursorExpiry=nil
                remoteCursor=cursor; onPresenceChange?()
                if cursor != nil {
                    let expiry=DispatchWorkItem { [weak self] in self?.remoteCursor=nil; self?.cursorExpiry=nil; self?.onPresenceChange?() }
                    cursorExpiry=expiry; DispatchQueue.main.asyncAfter(deadline:.now()+10,execute:expiry)
                }
            case .preview(let stroke):
                guard phase==3 else { throw DrawingError(message:"Drawing preview arrived before synchronization.") }
                if let stroke {
                    guard stroke.owner != owner,!stroke.removed else { throw DrawingError(message:"Invalid drawing owner.") }
                    try stroke.validate(boxes:boxes)
                }
                remotePreview=stroke; onChange?()
            }
        } catch { peer.disconnect(error.localizedDescription) }
    }
    private func clearCursor() {
        cursorSend?.cancel(); cursorSend=nil; pendingCursor=nil; lastCursorSend=0
        cursorExpiry?.cancel(); cursorExpiry=nil; remoteCursor=nil; onPresenceChange?()
    }
    func updateCursor(_ point:CGPoint?,page:Int,drawing:Bool) {
        guard connected else { return }
        if let point {
            let cursor=DrawingCursor(owner:owner,page:page,point:DrawingPoint(x:point.x,y:point.y),drawing:drawing)
            do { try cursor.validate(boxes:boxes,receiver:owner == .host ? .guest:.host) }
            catch { return }
            pendingCursor=cursor
            guard cursorSend==nil else { return }
            let delay=max(0,lastCursorSend+1.0/30-ProcessInfo.processInfo.systemUptime)
            let work=DispatchWorkItem { [weak self] in
                guard let self else { return }; self.cursorSend=nil
                guard self.connected,let cursor=self.pendingCursor else { return }
                self.pendingCursor=nil; self.lastCursorSend=ProcessInfo.processInfo.systemUptime
                do { try self.send(.cursor(cursor)) } catch { self.peer.disconnect(error.localizedDescription) }
            }
            cursorSend=work; DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
        } else {
            cursorSend?.cancel(); cursorSend=nil; pendingCursor=nil
            do { try send(.cursor(nil)) } catch { peer.disconnect(error.localizedDescription) }
        }
    }
    func preview(_ mark:Markup?,page:Int) {
        guard connected else { return }
        let now=ProcessInfo.processInfo.systemUptime
        if mark != nil && now-lastPreviewTime<1.0/30 { return }
        lastPreviewTime=now
        let stroke=mark.map{DrawingStroke(mark:$0,page:page,owner:owner,order:board.nextOrder)}
        do { if let stroke { try stroke.validate(boxes:boxes) }; try send(.preview(stroke)) }
        catch { peer.disconnect(error.localizedDescription) }
    }
    func add(_ mark:Markup,page:Int) throws {
        let record=try board.add(mark,page:page,owner:owner,boxes:boxes)
        publish([record])
    }
    func update(_ id:UUID,mark:Markup) throws {
        publish(try board.change(updates:[(id,mark)],deleting:[],owner:owner,boxes:boxes))
    }
    func erase(updates:[(UUID,Markup)],deleting:[UUID]) throws {
        publish(try board.change(updates:updates,deleting:deleting,owner:owner,boxes:boxes))
    }
    func undo() throws { publish(try board.undo(owner:owner,boxes:boxes)) }
    func redo() throws { publish(try board.redo(owner:owner,boxes:boxes)) }
    func remove(_ id:UUID) throws {
        if let record=try board.remove(id,owner:owner,boxes:boxes) { publish([record]) }
    }
    private func publish(_ records:[DrawingStroke]) {
        guard !records.isEmpty else { return }
        onChange?()
        guard connected else { return }
        do { try send(.records(records)); try send(.preview(nil)) }
        catch { peer.disconnect(error.localizedDescription) }
    }
    deinit { cursorSend?.cancel(); cursorExpiry?.cancel(); handshakeTimeout?.cancel(); peer.stop() }
}
