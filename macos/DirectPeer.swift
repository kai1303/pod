import Foundation
import Network
import Security

// All callbacks and state run on the main queue. TLS authenticates the invitation before any PDF is sent.
final class DirectPeer {
    static let maxFrame=48*1024*1024
    private let invite:DrawingInvite
    private var listener:NWListener?
    private var connection:NWConnection?
    private var timeout:DispatchWorkItem?
    private var queuedBytes=0
    var onReady:(()->Void)?
    var onListening:(()->Void)?
    var onData:((Data)->Void)?
    var onDisconnect:((String)->Void)?

    init(invite:DrawingInvite) { self.invite=invite }
    private func parameters() -> NWParameters {
        let tls=NWProtocolTLS.Options()
        let key=invite.key.withUnsafeBytes{DispatchData(bytes:$0)}
        let identity=Data(invite.session.uuidString.utf8).withUnsafeBytes{DispatchData(bytes:$0)}
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,key as __DispatchData,identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,tls_ciphersuite_t(rawValue:TLS_PSK_WITH_AES_128_GCM_SHA256)!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        let tcp=NWProtocolTCP.Options(); tcp.noDelay=true; tcp.enableKeepalive=true; tcp.keepaliveIdle=15; tcp.keepaliveInterval=5; tcp.keepaliveCount=3
        return NWParameters(tls:tls,tcp:tcp)
    }
    func listen() throws {
        stop()
        let listener=try NWListener(using:parameters(),on:NWEndpoint.Port(rawValue:invite.port)!)
        self.listener=listener
        listener.stateUpdateHandler={ [weak self,weak listener] state in
            guard let self,let listener,self.listener === listener else { return }
            switch state {
            case .ready: self.onListening?()
            case .failed(let error): self.stop(); self.onDisconnect?("Could not listen: \(error.localizedDescription)")
            default: break
            }
        }
        listener.newConnectionHandler={ [weak self] incoming in
            guard let self,self.connection==nil else { incoming.cancel(); return }
            self.start(incoming)
        }
        listener.start(queue:.main)
    }
    func connect() {
        stop()
        start(NWConnection(host:NWEndpoint.Host(invite.host),port:NWEndpoint.Port(rawValue:invite.port)!,using:parameters()))
    }
    private func start(_ connection:NWConnection) {
        self.connection=connection; queuedBytes=0
        let timeout=DispatchWorkItem { [weak self,weak connection] in
            guard let self,let connection,self.connection === connection else { return }
            self.disconnect("Connection timed out. Check the address, port, and firewall. No relay is used.")
        }
        self.timeout=timeout; DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:timeout)
        connection.stateUpdateHandler={ [weak self,weak connection] state in
            guard let self,let connection,self.connection === connection else { return }
            switch state {
            case .ready: self.timeout?.cancel(); self.timeout=nil; self.onReady?(); self.readHeader(connection)
            case .failed(let error): self.disconnect("Direct connection failed: \(error.localizedDescription)")
            default: break
            }
        }
        connection.start(queue:.main)
    }
    func send(_ data:Data) throws {
        guard let connection else { throw DrawingError(message:"The other Mac is disconnected.") }
        guard !data.isEmpty,data.count<=Self.maxFrame,queuedBytes+data.count<=2*Self.maxFrame else { throw DrawingError(message:"Shared data exceeds the connection limit.") }
        var size=UInt32(data.count).bigEndian
        var frame=withUnsafeBytes(of:&size){Data($0)}; frame.append(data)
        queuedBytes += data.count
        connection.send(content:frame,completion:.contentProcessed { [weak self,weak connection] error in
            guard let self,let connection,self.connection === connection else { return }
            self.queuedBytes -= data.count
            if let error { self.disconnect("Sending stopped: \(error.localizedDescription)") }
        })
    }
    private func readHeader(_ connection:NWConnection) {
        connection.receive(minimumIncompleteLength:4,maximumLength:4) { [weak self,weak connection] data,_,complete,error in
            guard let self,let connection,self.connection === connection else { return }
            guard error==nil,!complete,let data,data.count==4 else { self.disconnect("Peer disconnected. Drawings are kept on this Mac."); return }
            let length=data.reduce(0){($0<<8)|Int($1)}
            guard length>0,length<=Self.maxFrame else { self.disconnect("Peer sent an invalid message size."); return }
            self.readBody(connection,length:length)
        }
    }
    private func readBody(_ connection:NWConnection,length:Int) {
        connection.receive(minimumIncompleteLength:length,maximumLength:length) { [weak self,weak connection] data,_,complete,error in
            guard let self,let connection,self.connection === connection else { return }
            guard error==nil,let data,data.count==length else { self.disconnect("The transfer was interrupted. Drawings are kept on this Mac."); return }
            self.onData?(data)
            if self.connection === connection {
                if complete { self.disconnect("Peer disconnected. Drawings are kept on this Mac.") } else { self.readHeader(connection) }
            }
        }
    }
    func disconnect(_ reason:String) {
        timeout?.cancel(); timeout=nil
        let old=connection; connection=nil; old?.stateUpdateHandler=nil; old?.cancel(); queuedBytes=0
        onDisconnect?(reason)
    }
    func stop() {
        timeout?.cancel(); timeout=nil
        let old=connection; connection=nil; old?.stateUpdateHandler=nil; old?.cancel()
        listener?.stateUpdateHandler=nil; listener?.newConnectionHandler=nil; listener?.cancel(); listener=nil; queuedBytes=0
    }
    deinit { connection?.cancel(); listener?.cancel(); timeout?.cancel() }
}
