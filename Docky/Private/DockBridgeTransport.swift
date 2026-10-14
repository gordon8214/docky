import Foundation
import Darwin

struct DockBridgeRequest: Codable, Sendable {
    let session: String
    let revision: UInt64
    let display: UInt32
    let rect: [Double]
    let reason: Int32
    let orientation: Int32
}

struct DockBridgeResponse: Codable, Sendable {
    let revision: UInt64?
    let dockPID: Int32?
    let error: String?
    let backendDetails: String?
}

/// The socket is user-only. Validate its kernel-reported peer PID as well as
/// the session/revision response; a forged endpoint must not be trusted.
actor DockBridgeTransport {
    static let shared = DockBridgeTransport()

    func send(_ request: DockBridgeRequest, dockPID: pid_t) throws -> DockBridgeResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("Could not create bridge socket") }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = "/tmp/DockyDockBridge-\(getuid()).sock"
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                    _ = strlcpy(destination, source, 104)
                }
            }
        }
        var budget = timeval(tv_sec: 1, tv_usec: 0)
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &budget, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &budget, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        try Self.connectWithinBudget(descriptor, address: &address)
        var peerPID: pid_t = 0
        var peerSize = socklen_t(MemoryLayout<pid_t>.size)
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(descriptor, &peerUID, &peerGID) == 0, peerUID == getuid(),
              getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &peerSize) == 0,
              peerPID == dockPID else { throw failure("Unexpected Dock-side bridge identity") }
        let body = try JSONEncoder().encode(request)
        guard body.count < 4096 else { throw failure("Bridge request exceeded its size limit") }
        var length = UInt32(body.count).bigEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }
        packet.append(body)
        try write(packet, to: descriptor)
        let header = try read(count: 4, from: descriptor)
        let count = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard count > 0, count < 4096 else { throw failure("Invalid bridge response size") }
        let response = try JSONDecoder().decode(
            DockBridgeResponse.self, from: read(count: Int(count), from: descriptor))
        guard response.error == nil, response.revision == request.revision, response.dockPID == dockPID else {
            throw failure(response.error ?? "Stale bridge response")
        }
        return response
    }

    static func connectWithinBudget(_ descriptor: Int32, address: inout sockaddr_un) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw connectionFailure()
        }
        defer { _ = fcntl(descriptor, F_SETFL, flags) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected == 0 { return }
        guard errno == EINPROGRESS || errno == EAGAIN else { throw connectionFailure() }
        let deadline = ContinuousClock.now + .seconds(1)
        var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        while ContinuousClock.now < deadline {
            let remaining = ContinuousClock.now.duration(to: deadline).components
            let milliseconds = max(1, Int32(remaining.seconds * 1_000
                + remaining.attoseconds / 1_000_000_000_000_000))
            let result = poll(&event, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard result > 0, event.revents & Int16(POLLOUT) != 0,
                  getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw connectionFailure()
            }
            return
        }
        throw connectionFailure()
    }

    private static func connectionFailure() -> NSError {
        NSError(domain: "DockyDockBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey:
            "Dock-side bridge is not connected within its one-second budget"])
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure("Bridge write failed") }
                offset += count
            }
        }
    }

    private func read(count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { buffer in
            recv(descriptor, buffer.baseAddress, count, MSG_WAITALL)
        }
        guard received == count else { throw failure("Bridge read timed out or returned incomplete data") }
        return data
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DockyDockBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
