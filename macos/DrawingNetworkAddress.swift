import Foundation
import Darwin

// Only inspects local interfaces; no discovery or public-IP service is contacted.
enum DrawingNetworkAddress {
    static func localAddress() -> String {
        var interfaces:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces)==0 else { return "127.0.0.1" }
        defer { freeifaddrs(interfaces) }
        var current=interfaces
        while let item=current {
            defer { current=item.pointee.ifa_next }
            guard item.pointee.ifa_flags & UInt32(IFF_UP) != 0,item.pointee.ifa_flags & UInt32(IFF_LOOPBACK)==0,
                  let address=item.pointee.ifa_addr,address.pointee.sa_family==UInt8(AF_INET) else { continue }
            var host=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST)==0 { return String(cString:host) }
        }
        return "127.0.0.1"
    }
}
