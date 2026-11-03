import Darwin
import Foundation

/// `CmdTab --island-hook`: what Claude Code's PermissionRequest hook runs. Passes the request to the
/// running CmdTab and prints its answer. If CmdTab isn't running it prints nothing, so Claude Code
/// asks in the terminal as usual. The connection stays open while waiting: when Claude Code gives up
/// and ends this process, CmdTab sees it close and takes the question off the island.
enum ClaudeHookClient {
    static let argument = "--island-hook"

    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, connect(fd, path: IslandFiles.hookSocket.path) else { exit(0) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var sent = 0
        input.withUnsafeBytes { buffer in
            while sent < buffer.count {
                let count = write(fd, buffer.baseAddress! + sent, buffer.count - sent)
                if count <= 0 { break }
                sent += count
            }
        }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            reply.append(contentsOf: chunk[0..<count])
        }
        FileHandle.standardOutput.write(reply)
        exit(0)
    }

    private static func connect(_ fd: Int32, path: String) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }
}
