import Foundation

enum DaemonError: Error, LocalizedError {
    case notFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .notFound: "bozod not found"
        case .timeout: "bozod did not start in time"
        }
    }
}

enum DaemonManager {
    static let socketPath = "/tmp/bozod.sock"

    /// Find bozod: look in our app bundle first, then PATH.
    static func findBinary() -> URL? {
        if let exe = Bundle.main.executableURL {
            let sibling = exe.deletingLastPathComponent().appendingPathComponent("bozod")
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling
            }
        }
        // Fall back to PATH
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["bozod"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Check if the socket is alive by attempting a connection.
    private static func socketIsAlive() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    /// Ensure the daemon is running, spawning it if needed.
    static func ensureDaemon() async throws {
        if socketIsAlive() {
            return
        }
        // Remove stale socket
        try? FileManager.default.removeItem(atPath: socketPath)
        guard let bin = findBinary() else {
            throw DaemonError.notFound
        }
        let proc = Process()
        proc.executableURL = bin
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        try proc.run()

        // Poll for socket
        for _ in 0..<75 { // 15 seconds at 200ms intervals
            try await Task.sleep(for: .milliseconds(200))
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }
        }
        throw DaemonError.timeout
    }
}
