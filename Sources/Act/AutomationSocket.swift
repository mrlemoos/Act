import ActCore
import Darwin
import Foundation

/// One bounded JSONL exchange per connection. Native document work stays on MainActor.
final class AutomationSocket: @unchecked Sendable {
    private var listener: Int32 = -1
    private var lockFile: Int32 = -1
    private let directory: URL
    private let socketPath: String
    private let handler: @Sendable (Data) async -> Data
    private let queue = DispatchQueue(label: "dev.act.automation.accept", qos: .utility)

    init(directory: URL, handler: @escaping @Sendable (Data) async -> Data) {
        self.directory = directory
        socketPath = "/tmp/act-\(getuid())-\(SceneAnchor.digest(directory.path).prefix(16)).sock"
        self.handler = handler
    }

    func start() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let attributes = try fm.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw AutomationFailure("invalid_endpoint", "Automation directory must be a real directory owned by this account.")
            }
        } else { try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        lockFile = Darwin.open(directory.appendingPathComponent("server.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
            throw AutomationFailure("already_running", "Another Act automation server owns this endpoint.")
        }
        var existing = stat()
        if lstat(socketPath, &existing) == 0 {
            guard existing.st_uid == getuid(), (existing.st_mode & S_IFMT) == S_IFSOCK else {
                throw AutomationFailure("invalid_endpoint", "Socket path is occupied by another owner or file type.")
            }
            Darwin.unlink(socketPath)
        }
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(socketPath, 0o600) == 0, Darwin.listen(listener, 16) == 0 else { throw POSIXError(.EIO) }
        let endpoint: AutomationValue = .object(["version": .number(1), "socketPath": .string(socketPath), "pid": .number(Double(getpid()))])
        try endpoint.data().write(to: directory.appendingPathComponent("endpoint.json"), options: .atomic)
        queue.async { [self] in
            while listener >= 0 {
                let client = Darwin.accept(listener, nil, nil)
                if client < 0 { break }
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { Darwin.close(client); continue }
                var timeout = timeval(tv_sec: 5, tv_usec: 0), yes: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
                // Serial reads bound resource use; async execution never blocks the main actor.
                var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
                while data.count <= 4_194_304 {
                    let count = Darwin.read(client, &buffer, buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                    if data.contains(10) { break }
                }
                guard let end = data.firstIndex(of: 10), end <= 4_194_304 else { Darwin.close(client); continue }
                let request = Data(data.prefix(upTo: end))
                Task {
                    var response = await handler(request); response.append(10)
                    response.withUnsafeBytes { raw in
                        var sent = 0
                        while sent < raw.count {
                            let count = Darwin.write(client, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                            if count <= 0 { break }; sent += count
                        }
                    }
                    Darwin.close(client)
                }
            }
        }
    }

    func stop() {
        guard listener >= 0 else { return }
        let descriptor = listener; listener = -1
        Darwin.shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor)
        Darwin.unlink(socketPath)
        if lockFile >= 0 { flock(lockFile, LOCK_UN); Darwin.close(lockFile); lockFile = -1 }
    }
}
