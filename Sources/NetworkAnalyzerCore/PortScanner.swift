import Foundation
import Network

/// Probes a curated list of well-known ports using `Network.framework`, which needs no raw
/// sockets and no elevated privileges.
public enum PortScanner {
    /// Default well-known ports to probe, editable in Settings.
    public static let defaultPorts: [(port: Int, proto: PortProtocolKind)] = [
        (21, .tcp), (22, .tcp), (23, .tcp), (25, .tcp), (53, .tcp), (80, .tcp), (110, .tcp),
        (139, .tcp), (143, .tcp), (443, .tcp), (445, .tcp), (3389, .tcp),
        (53, .udp), (123, .udp), (137, .udp), (161, .udp)
    ]

    public static func scan(
        ip: String,
        ports: [(port: Int, proto: PortProtocolKind)] = defaultPorts,
        timeoutSeconds: Double = 1.5
    ) async -> [PortResult] {
        await withTaskGroup(of: PortResult.self) { group in
            for entry in ports {
                group.addTask {
                    switch entry.proto {
                    case .tcp:
                        return await scanTCP(ip: ip, port: entry.port, timeoutSeconds: timeoutSeconds)
                    case .udp:
                        return await scanUDP(ip: ip, port: entry.port, timeoutSeconds: timeoutSeconds)
                    }
                }
            }
            var results: [PortResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                lhs.port == rhs.port ? lhs.proto.rawValue < rhs.proto.rawValue : lhs.port < rhs.port
            }
        }
    }

    /// Attempts a TCP handshake. `.ready` -> open, `.failed` (connection refused, etc.) -> closed,
    /// no resolution within `timeoutSeconds` -> timeout (commonly a firewall silently dropping
    /// the SYN).
    static func scanTCP(ip: String, port: Int, timeoutSeconds: Double) async -> PortResult {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return PortResult(port: port, proto: .tcp, tcpStatus: .closed)
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<TCPStatus, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
            let box = OneShotContinuation<TCPStatus>(continuation)
            let finish: @Sendable (TCPStatus) -> Void = { status in
                connection.cancel()
                box.resume(with: status)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.open)
                case .failed: finish(.closed)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { finish(.timeout) }
        }
        return PortResult(port: port, proto: .tcp, tcpStatus: status)
    }

    /// UDP is connectionless: a probe datagram is sent and the socket is watched for any reply.
    /// Per the spec, no attempt is made to infer open/closed from silence — only whether a reply
    /// arrived at all (an ICMP Port Unreachable notification would require a raw socket to read,
    /// which needs root, so this stays a binary responded/no-response signal).
    static func scanUDP(ip: String, port: Int, timeoutSeconds: Double) async -> PortResult {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return PortResult(port: port, proto: .udp, udpStatus: .noResponse)
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<UDPStatus, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .udp)
            let box = OneShotContinuation<UDPStatus>(continuation)
            let finish: @Sendable (UDPStatus) -> Void = { status in
                connection.cancel()
                box.resume(with: status)
            }
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: Data(), completion: .contentProcessed { _ in
                        connection.receiveMessage { data, _, _, _ in
                            if let data, !data.isEmpty {
                                finish(.responded)
                            }
                        }
                    })
                } else if case .failed = state {
                    finish(.noResponse)
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { finish(.noResponse) }
        }
        return PortResult(port: port, proto: .udp, udpStatus: status)
    }
}
