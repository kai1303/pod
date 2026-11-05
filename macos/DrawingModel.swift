import AppKit
import CryptoKit
import Security

struct DrawingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DrawingOwner: String, Codable { case host, guest }

struct DrawingInvite: Equatable {
    static let protocolVersion=4
    let host: String
    let port: UInt16
    let session: UUID
    let key: Data

    init(host: String, port: UInt16) throws {
        guard Self.validHost(host), port>0 else { throw DrawingError(message:"Enter an IP address or hostname and a port from 1 to 65535.") }
        var secret=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,secret.count,&secret)==errSecSuccess else { throw DrawingError(message:"Could not create a secure invitation.") }
        self.host=host; self.port=port; session=UUID(); key=Data(secret)
    }
    init(url: URL) throws {
        guard url.absoluteString.count<2048,let c=URLComponents(url:url,resolvingAgainstBaseURL:false),c.scheme=="pod",c.host=="draw",c.path.isEmpty,c.user==nil,c.password==nil,c.port==nil,
              let items=c.queryItems,items.count==4,Set(items.map(\.name))==Set(["v","host","port","session"]),
              items.first(where:{$0.name=="v"})?.value==String(Self.protocolVersion),
              let host=items.first(where:{$0.name=="host"})?.value,Self.validHost(host),
              let rawPort=items.first(where:{$0.name=="port"})?.value,let port=UInt16(rawPort),port>0,
              let rawID=items.first(where:{$0.name=="session"})?.value,let session=UUID(uuidString:rawID),
              let secret=c.fragment,secret.count==64 else { throw DrawingError(message:"This is not a valid Pod drawing invitation.") }
        var key=Data()
        for index in stride(from:0,to:64,by:2) {
            let start=secret.index(secret.startIndex,offsetBy:index),end=secret.index(start,offsetBy:2)
            guard let byte=UInt8(secret[start..<end],radix:16) else { throw DrawingError(message:"Invalid invitation key.") }
            key.append(byte)
        }
        self.host=host; self.port=port; self.session=session; self.key=key
    }
    private static func validHost(_ host:String) -> Bool {
        !host.isEmpty && host.count<=253 && host.unicodeScalars.allSatisfy { CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:%_").contains($0) }
    }
    var url: URL {
        var c=URLComponents(); c.scheme="pod"; c.host="draw"
        c.queryItems=[URLQueryItem(name:"v",value:String(Self.protocolVersion)),URLQueryItem(name:"host",value:host),URLQueryItem(name:"port",value:String(port)),URLQueryItem(name:"session",value:session.uuidString)]
        c.fragment=key.map{String(format:"%02x",$0)}.joined()
        return c.url!
    }
}

struct DrawingPoint: Codable, Equatable { var x:Double; var y:Double }

// Presence is ephemeral and deliberately has no entry in DrawingBoard or PDF export.
struct DrawingCursor: Codable, Equatable {
    var owner:DrawingOwner
    var page:Int
    var point:DrawingPoint
    var drawing:Bool
    func validate(boxes:[CGRect],receiver:DrawingOwner) throws {
        guard owner != receiver,boxes.indices.contains(page),point.x.isFinite,point.y.isFinite,
              boxes[page].insetBy(dx:-0.01,dy:-0.01).contains(CGPoint(x:point.x,y:point.y)) else { throw DrawingError(message:"Invalid peer cursor.") }
    }
}

struct DrawingStroke: Codable, Equatable {
    var id:UUID
    var owner:DrawingOwner
    var order:UInt64
    var page:Int
    var points:[DrawingPoint]
    var inkPathStarts:[Int]
    var color:[Double]
    var width:Double
    var opacity:Double
    var text:String
    var link:String
    var version:UInt64=0
    var removed=false

    init(mark:Markup,page:Int,owner:DrawingOwner,order:UInt64) {
        id=UUID(); self.owner=owner; self.order=order; self.page=page
        points=mark.points.map{DrawingPoint(x:$0.x,y:$0.y)}
        inkPathStarts=mark.inkPathStarts
        text=mark.text; link=mark.link
        let rgb=mark.style.stroke.usingColorSpace(.sRGB) ?? .black
        color=[rgb.redComponent,rgb.greenComponent,rgb.blueComponent]
        width=mark.style.width; opacity=mark.style.opacity
    }
    func validate(boxes:[CGRect]) throws {
        guard boxes.indices.contains(page),!points.isEmpty,points.count<=4096,order>0,order<UInt64.max,
              version<UInt64.max, text.utf8.count<=16384,
              color.count==3,color.allSatisfy({$0.isFinite && (0...1).contains($0)}),
              width.isFinite,(0.1...100).contains(width),opacity.isFinite,(0...1).contains(opacity) else { throw DrawingError(message:"Invalid shared drawing.") }
        if !link.isEmpty {
            guard link.utf8.count <= 2048, link.utf8.allSatisfy({ $0 > 32 && $0 != 127 }),
                  let url=URLComponents(string:link), ["http","https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false else { throw DrawingError(message:"Invalid shared drawing link.") }
        }
        if let lastStart = inkPathStarts.last {
            guard inkPathStarts.first == 0, inkPathStarts.count <= points.count,
                  lastStart < points.count,
                  zip(inkPathStarts, inkPathStarts.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw DrawingError(message:"Invalid shared ink paths.")
            }
        }
        let box=boxes[page].insetBy(dx:-0.01,dy:-0.01)
        guard points.allSatisfy({$0.x.isFinite && $0.y.isFinite && box.contains(CGPoint(x:$0.x,y:$0.y))}) else { throw DrawingError(message:"Drawing points are outside the PDF page.") }
    }
    var markup:Markup {
        var style=MarkupStyle(); style.stroke=NSColor(srgbRed:color[0],green:color[1],blue:color[2],alpha:1); style.width=width; style.opacity=opacity
        var mark=Markup(kind:.ink,points:points.map{CGPoint(x:$0.x,y:$0.y)},rect:.zero,style:style)
        mark.inkPathStarts=inkPathStarts
        mark.text=text; mark.link=link
        return mark
    }
}

// Each stroke has one writer. Owner revisions order edits, and erased identities stay retired.
struct DrawingBoard {
    private var values:[UUID:DrawingStroke]=[:]
    // Each history entry contains the prior state for all strokes affected by one gesture.
    private var backward:[DrawingOwner:[[DrawingStroke]]]=[:]
    private var forward:[DrawingOwner:[[DrawingStroke]]]=[:]
    private(set) var revision=0
    var records:[DrawingStroke] { values.values.sorted { $0.order == $1.order ? $0.id.uuidString<$1.id.uuidString : $0.order<$1.order } }
    var visible:[DrawingStroke] { records.filter{!$0.removed} }
    func canUndo(_ owner:DrawingOwner) -> Bool { !(backward[owner] ?? []).isEmpty }
    func canRedo(_ owner:DrawingOwner) -> Bool { !(forward[owner] ?? []).isEmpty }
    var nextOrder:UInt64 { (values.values.map(\.order).max() ?? 0)+1 }

    mutating func merge(_ records:[DrawingStroke],from owner:DrawingOwner?=nil,boxes:[CGRect]) throws {
        guard records.count<=10_000 else { throw DrawingError(message:"Too many shared strokes.") }
        var updated=values
        for record in records {
            try record.validate(boxes:boxes)
            guard owner==nil || record.owner==owner else { throw DrawingError(message:"A peer cannot change another person's drawings.") }
            if let old=updated[record.id] {
                guard old.owner == record.owner, old.order == record.order, old.page == record.page else {
                    throw DrawingError(message:"Conflicting stroke identity.")
                }
                if record.version == old.version {
                    guard record == old else { throw DrawingError(message:"Conflicting stroke revision.") }
                } else if record.version > old.version {
                    guard !old.removed else { throw DrawingError(message:"An erased stroke cannot be changed.") }
                    updated[record.id]=record
                } else if record.removed {
                    throw DrawingError(message:"An erased stroke cannot be changed.")
                }
            } else { updated[record.id]=record }
        }
        guard updated.count<=10_000,updated.values.reduce(0,{$0+$1.points.count})<=250_000,
              updated.values.reduce(0,{$0+$1.text.utf8.count+$1.link.utf8.count})<=2*1024*1024 else { throw DrawingError(message:"This drawing session is full. End it and start another session.") }
        if updated != values { values=updated; revision += 1 }
    }
    mutating func mergeFromHost(_ records:[DrawingStroke],boxes:[CGRect]) throws {
        guard records.count<=10_000 else { throw DrawingError(message:"Too many shared strokes.") }
        for record in records where record.owner == .guest {
            // A host may echo guest state, but cannot invent a guest operation or its deletion.
            guard let local=values[record.id] else { throw DrawingError(message:"This session contains another guest’s drawings. Ask the host to start a new session.") }
            guard local.owner == .guest, local.order == record.order, local.page == record.page,
                  record == local || (record.version < local.version && !record.removed) else { throw DrawingError(message:"The host cannot change your drawings.") }
        }
        try merge(records.filter{$0.owner == .host},from:.host,boxes:boxes)
    }
    mutating func add(_ mark:Markup,page:Int,owner:DrawingOwner,boxes:[CGRect]) throws -> DrawingStroke {
        guard mark.kind == .ink else { throw DrawingError(message:"Shared sessions support drawing only.") }
        let stroke=DrawingStroke(mark:mark,page:page,owner:owner,order:nextOrder)
        try merge([stroke],from:owner,boxes:boxes)
        var undone=stroke; undone.removed=true
        backward[owner,default:[]].append([undone]); forward[owner]=[]
        return stroke
    }
    mutating func change(updates:[(UUID,Markup)],deleting:[UUID],owner:DrawingOwner,boxes:[CGRect]) throws -> [DrawingStroke] {
        let ids=updates.map { $0.0 } + deleting
        guard ids.count<=10_000, Set(ids).count == ids.count else { throw DrawingError(message:"Invalid drawing edit.") }
        var previous:[DrawingStroke]=[], changes:[DrawingStroke]=[]
        func editable(_ id:UUID) throws -> DrawingStroke {
            guard let stroke=values[id], stroke.owner == owner, !stroke.removed else {
                throw DrawingError(message:"Only the owner can edit an active shared drawing.")
            }
            return stroke
        }
        for (id,mark) in updates {
            let old=try editable(id)
            guard mark.kind == .ink else { throw DrawingError(message:"Shared sessions support drawing only.") }
            var stroke=DrawingStroke(mark:mark,page:old.page,owner:owner,order:old.order)
            stroke.id=id; stroke.version=old.version
            if stroke == old { continue }
            stroke.version += 1
            changes.append(stroke); previous.append(old)
        }
        for id in deleting {
            let old=try editable(id)
            var stroke=old; stroke.removed=true; stroke.version += 1
            changes.append(stroke); previous.append(old)
        }
        guard !changes.isEmpty else { return [] }
        try merge(changes,from:owner,boxes:boxes)
        backward[owner,default:[]].append(previous); forward[owner]=[]
        return changes
    }
    mutating func remove(_ id:UUID,owner:DrawingOwner,boxes:[CGRect]) throws -> DrawingStroke? {
        guard let stroke=values[id],stroke.owner==owner,!stroke.removed else { return nil }
        return try change(updates:[],deleting:[id],owner:owner,boxes:boxes).first
    }
    mutating func undo(owner:DrawingOwner,boxes:[CGRect]) throws -> [DrawingStroke] { try history(owner:owner,boxes:boxes,undo:true) }
    mutating func redo(owner:DrawingOwner,boxes:[CGRect]) throws -> [DrawingStroke] { try history(owner:owner,boxes:boxes,undo:false) }
    private mutating func history(owner:DrawingOwner,boxes:[CGRect],undo:Bool) throws -> [DrawingStroke] {
        guard let entry=(undo ? backward[owner]:forward[owner])?.last else { return [] }
        var changes:[DrawingStroke]=[], inverse:[DrawingStroke]=[]
        var replacements:[UUID:UUID]=[:]
        for var desired in entry {
            guard var current=values[desired.id], current.owner == owner else { throw DrawingError(message:"Missing drawing history.") }
            if current.removed {
                // Restore as a fresh identity at the same stacking order. Old tombstones stay final.
                desired.id=UUID(); desired.version=0; desired.removed=false
                replacements[current.id]=desired.id; current.id=desired.id
            } else { desired.version=current.version+1 }
            changes.append(desired); inverse.append(current)
        }
        try merge(changes,from:owner,boxes:boxes)
        if undo { backward[owner]?.removeLast() } else { forward[owner]?.removeLast() }
        if !replacements.isEmpty {
            func rebind(_ group:[DrawingStroke]) -> [DrawingStroke] {
                group.map { saved in
                    guard let id=replacements[saved.id] else { return saved }
                    var copy=saved; copy.id=id; return copy
                }
            }
            backward[owner]=backward[owner]?.map(rebind)
            forward[owner]=forward[owner]?.map(rebind)
        }
        if undo { forward[owner,default:[]].append(inverse) } else { backward[owner,default:[]].append(inverse) }
        return changes
    }
    func export(_ base:Data,using engine:Engine) throws -> Data {
        var bytes=base
        let groups=Dictionary(grouping:visible,by:\.page)
        for page in groups.keys.sorted() { bytes=try engine.annotate(bytes,page:page,marks:groups[page]!.map(\.markup)) }
        return bytes
    }
}
