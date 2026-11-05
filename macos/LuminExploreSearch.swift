import Foundation
import JavaScriptCore

struct LuminExploreCommand:Decodable {
    let key:String
    var title:String
    var searchTitle:String
    let renders:Bool
    let mode:String?
    let icon:String?
    let bitmap:String?
    let colored:Bool?
    let shortcut:String?
    let trailingIcon:String?
    let premium:Bool?
    let disabled:Bool?
    let isSwitch:Bool?

    init(key:String,title:String,bitmap:String) {
        self.key=key; self.title=title; searchTitle=title; renders=true
        self.bitmap=bitmap; mode=nil; icon=nil; colored=nil; shortcut=nil; trailingIcon=nil; premium=nil; disabled=nil; isSwitch=nil
    }
    init(key:String,title:String,icon:String,premium:Bool=false) {
        self.key=key; self.title=title; searchTitle=title; renders=true
        self.icon=icon; self.premium=premium; mode=nil; bitmap=nil; colored=nil; shortcut=nil; trailingIcon=nil; disabled=nil; isSwitch=nil
    }
}
struct LuminExploreGroup:Decodable {
    let key:String,title:String,searchOnly:Bool
    var commands:[LuminExploreCommand]
    var toolbarMode:String? { ["annotate":"Mark up","security":"Security","fillAndSign":"Fill & Sign","pageTools":"Organize"][key] }
}

// Only the pinned official Fuse library runs in this VM, with data passed as values.
final class LuminExploreSearch {
    private struct Catalog:Decodable { let groups:[LuminExploreGroup] }
    let groups:[LuminExploreGroup]
    let libraryVersion:String
    private let active:[LuminExploreCommand]
    private let byKey:[String:LuminExploreCommand]
    private let aliases:[String:[String]]
    private let aliasOrder:[String]
    private let normalization:[String:String]
    private let context:JSContext
    private let fuse:JSValue

    init(mode:String,isLight:Bool=false) {
        let directory=LuminAssets.directory.appendingPathComponent("Explore")
        func read<T:Decodable>(_ type:T.Type,_ file:String)->T { try! JSONDecoder().decode(type,from:Data(contentsOf:directory.appendingPathComponent(file))) }
        var source=read(Catalog.self,"catalog.json").groups
        if isLight {
            for i in source.indices { for j in source[i].commands.indices where source[i].commands[j].key=="darkMode" { source[i].commands[j].title="Dark mode"; source[i].commands[j].searchTitle="Dark mode" } }
        }
        groups=source
        active=source.flatMap{$0.commands}.filter{$0.mode==nil || $0.mode==(mode=="Organize" ? "organize":"viewer")}
        byKey=Dictionary(uniqueKeysWithValues:active.map{($0.key,$0)})
        aliases=read([String:[String]].self,"aliases.json"); aliasOrder=read([String].self,"alias-order.json"); normalization=read([String:String].self,"normalization.json")
        context=JSContext()!
        let script=try! String(contentsOf:directory.appendingPathComponent("fuse-6.6.2.min.js"),encoding:.utf8)
        context.evaluateScript(script)
        let constructor=context.objectForKeyedSubscript("Fuse")!
        libraryVersion=constructor.objectForKeyedSubscript("version")!.toString()
        let map=normalization
        func normalized(_ text:String)->String { text.unicodeScalars.map{map[String($0)] ?? String($0)}.joined() }
        let items:[[String:Any]]=active.map{["key":$0.key,"fuseTitle":normalized($0.searchTitle),"fuseTokens":normalized($0.searchTitle).components(separatedBy:" ")]}
        fuse=constructor.construct(withArguments:[items,["keys":["fuseTitle","fuseTokens"],"includeScore":true,"includeMatches":true,"threshold":0.3]])
        precondition(context.exception==nil,"The bundled Explore search engine must initialize")
    }
    func normalize(_ text:String)->String { text.unicodeScalars.map{normalization[String($0)] ?? String($0)}.joined() }
    func isActive(_ command:LuminExploreCommand)->Bool { byKey[command.key] != nil && command.renders }
    func group(for command:LuminExploreCommand)->LuminExploreGroup? { groups.first{$0.commands.contains{$0.key==command.key}} }
    func results(_ query:String)->[LuminExploreCommand] {
        let matches=fuse.invokeMethod("search",withArguments:[normalize(query)])!.toArray() as! [[String:Any]]
        var keys=matches.compactMap{($0["item"] as? [String:Any])?["key"] as? String}
        var terms=query.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().components(separatedBy:.whitespacesAndNewlines).filter{!$0.isEmpty}
        if terms.isEmpty { terms=[""] }
        terms=terms.map(normalize)
        var ranks:[(key:String,rank:Int,order:Int)]=[]
        for (order,key) in aliasOrder.enumerated() {
            let words=(aliases[key] ?? []).map{normalize($0.lowercased())}
            let indexes=terms.compactMap{term in words.firstIndex{term.isEmpty || $0.contains(term)}}
            if indexes.count==terms.count,let rank=indexes.min() { ranks.append((key,rank,order)) }
        }
        for match in ranks.sorted(by:{$0.rank==$1.rank ? $0.order<$1.order:$0.rank<$1.rank}) where !keys.contains(match.key) { keys.append(match.key) }
        return keys.compactMap{byKey[$0]}.filter{$0.renders}
    }
}
