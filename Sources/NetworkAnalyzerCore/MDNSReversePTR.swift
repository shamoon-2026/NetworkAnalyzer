import Foundation
import Darwin
import CDNSSD

/// Performs a genuine multicast DNS (RFC 6762) reverse PTR query via `dns_sd`'s
/// `kDNSServiceFlagsForceMulticast` flag.
///
/// Plain `getnameinfo()` reverse DNS does **not** reach mDNSResponder for an ordinary LAN subnet
/// (192.168.x.x, 10.x.x.x, ...) — `scutil --dns` shows macOS only auto-routes reverse lookups
/// through mDNS for `169.254.0.0/16` (APIPA) and IPv6 link-local. Since almost no home router
/// publishes real PTR records for its DHCP leases either, a plain unicast reverse lookup fails
/// for nearly every host on a typical home network — this is the actual, correct mDNS query that
/// most LAN devices (Apple, Android, printers, IoT) do answer.
enum MDNSReversePTR {
    static func resolve(ip: String, timeoutSeconds: Double) async -> String? {
        guard let reverseName = ip.contains(":") ? reverseARPAName(forIPv6: ip) : reverseARPAName(forIPv4: ip) else {
            return nil
        }
        return await Query.run(name: reverseName, timeoutSeconds: timeoutSeconds)
    }

    /// "192.168.1.10" -> "10.1.168.192.in-addr.arpa."
    static func reverseARPAName(forIPv4 ip: String) -> String? {
        let octets = ip.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return octets.reversed().joined(separator: ".") + ".in-addr.arpa."
    }

    /// "2001:db8::1" -> every hex nibble of the fully-expanded 128-bit address, reversed and
    /// dot-separated, e.g. "1.0.0.0...b.8.d.0.1.0.0.2.ip6.arpa." per RFC 3596. Any zone id
    /// ("%en0") is irrelevant to the query name and is dropped by `IPv6AddressExpansion`.
    static func reverseARPAName(forIPv6 ip: String) -> String? {
        guard let groups = IPv6AddressExpansion.groups(for: ip) else { return nil }
        let nibbles = groups.joined().reversed()
        return nibbles.map { String($0) }.joined(separator: ".") + ".ip6.arpa."
    }

    /// Decodes a DNS wire-format domain name (length-prefixed labels). dns_sd delivers only the
    /// record's raw RDATA, not the surrounding message, so a compression pointer (top two bits of
    /// a length byte set) can't be resolved from this buffer alone — such names are reported as
    /// undecodable (nil) rather than guessed at.
    static func decodeDomainName(rdata: UnsafeRawPointer, length: Int) -> String? {
        guard length > 0 else { return nil }
        let bytes = rdata.assumingMemoryBound(to: UInt8.self)
        var labels: [String] = []
        var offset = 0
        while offset < length {
            let lengthByte = bytes[offset]
            if lengthByte == 0 { break }
            if lengthByte & 0xC0 != 0 { return nil }
            offset += 1
            guard offset + Int(lengthByte) <= length else { return nil }
            let labelBytes = UnsafeBufferPointer(start: bytes + offset, count: Int(lengthByte))
            labels.append(String(decoding: labelBytes, as: UTF8.self))
            offset += Int(lengthByte)
        }
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: ".")
    }

    /// One `DNSServiceQueryRecord` call: fires the query, then polls its socket on a background
    /// thread for a bounded time and processes at most one result. `self` is only referenced from
    /// the C callback while this instance method (or the dispatched block it starts) is still on
    /// the stack, so a plain unretained context pointer is safe — no manual retain/release needed.
    private final class Query: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?

        static func run(name: String, timeoutSeconds: Double) async -> String? {
            await withCheckedContinuation { continuation in
                Query().start(name: name, timeoutSeconds: timeoutSeconds, continuation: continuation)
            }
        }

        private func start(name: String, timeoutSeconds: Double, continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation

            var sdRef: DNSServiceRef?
            let context = Unmanaged.passUnretained(self).toOpaque()

            let err = name.withCString { namePtr in
                DNSServiceQueryRecord(
                    &sdRef,
                    DNSServiceFlags(kDNSServiceFlagsForceMulticast),
                    0,
                    namePtr,
                    UInt16(kDNSServiceType_PTR),
                    UInt16(kDNSServiceClass_IN),
                    { _, _, _, errorCode, _, _, _, rdlen, rdata, _, context in
                        guard let context else { return }
                        let query = Unmanaged<Query>.fromOpaque(context).takeUnretainedValue()
                        if errorCode == kDNSServiceErr_NoError, let rdata {
                            query.finish(decodeDomainName(rdata: rdata, length: Int(rdlen)))
                        } else {
                            query.finish(nil)
                        }
                    },
                    context
                )
            }

            guard err == kDNSServiceErr_NoError, let sdRef else {
                finish(nil)
                return
            }
            // DNSServiceRef (OpaquePointer) isn't Sendable, but it's only ever touched from this
            // one background queue between here and DNSServiceRefDeallocate below.
            let sdRefBox = UncheckedSendableBox(sdRef)

            DispatchQueue.global(qos: .utility).async { [self] in
                let sdRef = sdRefBox.value
                let fd = DNSServiceRefSockFD(sdRef)
                guard fd >= 0 else {
                    DNSServiceRefDeallocate(sdRef)
                    finish(nil)
                    return
                }
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let remainingMs = Int32(max(0, timeoutSeconds) * 1000)
                let pollResult = poll(&pfd, 1, remainingMs)
                if pollResult > 0, (Int32(pfd.revents) & POLLIN) != 0 {
                    DNSServiceProcessResult(sdRef)
                }
                DNSServiceRefDeallocate(sdRef)
                // No-op if the callback inside DNSServiceProcessResult already resolved this.
                finish(nil)
            }
        }

        private func finish(_ value: String?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
