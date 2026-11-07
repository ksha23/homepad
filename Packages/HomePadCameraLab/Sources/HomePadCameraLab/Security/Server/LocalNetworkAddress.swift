import Darwin
import Foundation

/// Finds this iPad's IPv4 address on the local network, for the setup URLs.
enum LocalNetworkAddress {
    /// The Wi-Fi (en0) address, else the first other active non-loopback IPv4 address.
    static func current() -> String? {
        var addresses: [(name: String, address: String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: interface.ifa_name)
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            addresses.append((name, address))
        }
        return addresses.first { $0.name == "en0" }?.address
            ?? addresses.first { $0.name.hasPrefix("en") }?.address
            ?? addresses.first?.address
    }
}
