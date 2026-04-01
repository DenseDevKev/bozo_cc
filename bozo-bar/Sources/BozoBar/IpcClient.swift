import Foundation

/// Connects to bozod over a Unix domain socket and provides JSON-lines IPC.
final class IpcClient: @unchecked Sendable {
    private let fd: Int32
    private let readHandle: FileHandle
    private let writeHandle: FileHandle
    private let responseStream: AsyncStream<IpcResponse>
    private let responseContinuation: AsyncStream<IpcResponse>.Continuation

    var responses: AsyncStream<IpcResponse> { responseStream }

    init?() {
        let sockFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockFd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = DaemonManager.socketPath
        let pathLen = path.utf8.count
        guard pathLen < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(sockFd)
            return nil
        }
        path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(sockFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(sockFd)
            return nil
        }

        self.fd = sockFd
        self.readHandle = FileHandle(fileDescriptor: sockFd, closeOnDealloc: false)
        self.writeHandle = FileHandle(fileDescriptor: sockFd, closeOnDealloc: false)

        let (stream, continuation) = AsyncStream<IpcResponse>.makeStream()
        self.responseStream = stream
        self.responseContinuation = continuation

        startReading()
    }

    deinit {
        responseContinuation.finish()
        close(fd)
    }

    func send(_ request: IpcRequest) {
        guard var data = try? JSONEncoder().encode(request) else { return }
        data.append(0x0A) // newline
        writeHandle.write(data)
    }

    // MARK: - Private

    private func startReading() {
        let handle = self.readHandle
        let continuation = self.responseContinuation
        let decoder = JSONDecoder()

        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break } // EOF
                buffer.append(chunk)
                // Process complete lines
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<newline]
                    buffer = Data(buffer[buffer.index(after: newline)...])
                    if let response = try? decoder.decode(IpcResponse.self, from: lineData) {
                        continuation.yield(response)
                    }
                }
            }
            continuation.finish()
        }
    }
}
