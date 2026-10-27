import Darwin
import Foundation

// セッションのディレクトリの名前付きパイプで、serve と send がやり取りする。
// send は応答用のパイプを作り、`<応答パイプのパス>\t<コマンド>\n` をコマンド用のパイプに書いて、応答の 1 行を待つ。

enum Session {
    static func commandPipe(_ directory: URL) -> String { directory.appendingPathComponent("command.fifo").path }

    /// 名前付きパイプの読み書きに使う。RDWR で開くと、相手がいなくても open が止まらず、EOF にもならない。
    static func openPipe(_ path: String, flags: Int32) throws -> Int32 {
        let fd = open(path, flags)
        guard fd >= 0 else { throw DriverError.message("\(path) を開けなかった: \(String(cString: strerror(errno)))") }
        return fd
    }

    static func writeAll(_ fd: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written <= 0 { return }
            offset += written
        }
    }

    /// 改行までの 1 行を読む。EOF なら nil。
    static func readLine(_ fd: Int32) -> String? {
        var line = [UInt8]()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            // シグナルで中断されたときは EOF と区別して読み直す。
            if count < 0, errno == EINTR { continue }
            if count <= 0 { return line.isEmpty ? nil : String(decoding: line, as: UTF8.self) }
            if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
            line.append(byte)
        }
    }

    // MARK: send

    static func send(directory: URL, command: String) throws -> String {
        let commandPath = commandPipe(directory)
        // serve が準備できるまでの間は、パイプがない（ENOENT）か、読み手がいない（ENXIO）。60 秒まで待つ。
        var commandFD = open(commandPath, O_WRONLY | O_NONBLOCK)
        for _ in 0..<600 where commandFD < 0 {
            usleep(100_000)
            commandFD = open(commandPath, O_WRONLY | O_NONBLOCK)
        }
        guard commandFD >= 0 else {
            throw DriverError.message("60 秒待っても serve が起動しなかった: \(commandPath)")
        }
        defer { close(commandFD) }
        let replyPath = directory.appendingPathComponent("reply-\(getpid()).fifo").path
        unlink(replyPath)
        guard mkfifo(replyPath, 0o600) == 0 else {
            throw DriverError.message("応答用のパイプを作れなかった: \(String(cString: strerror(errno)))")
        }
        defer { unlink(replyPath) }
        let replyFD = try openPipe(replyPath, flags: O_RDWR)
        defer { close(replyFD) }
        writeAll(commandFD, "\(replyPath)\t\(command.replacingOccurrences(of: "\n", with: " "))\n")
        // serve が途中で落ちても待ち続けないよう、応答を待つ時間に上限を置く。
        var descriptor = pollfd(fd: replyFD, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 90_000) > 0 else { throw DriverError.message("90 秒たっても応答がなかった。serve が止まっている") }
        guard let reply = readLine(replyFD) else { throw DriverError.message("応答がなかった") }
        return reply
    }

    // MARK: serve

    /// コマンドを 1 行ずつ受け取るストリーム。読み取りはブロックするので、専用のスレッドで行う。
    static func requests(directory: URL) throws -> AsyncStream<(reply: String, command: String)> {
        let path = commandPipe(directory)
        unlink(path)
        guard mkfifo(path, 0o600) == 0 else {
            throw DriverError.message("コマンド用のパイプを作れなかった: \(String(cString: strerror(errno)))")
        }
        let fd = try openPipe(path, flags: O_RDWR)
        let (stream, continuation) = AsyncStream<(reply: String, command: String)>.makeStream()
        Thread.detachNewThread {
            while let line = readLine(fd) {
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                continuation.yield((String(parts[0]), String(parts[1])))
            }
            continuation.finish()
        }
        return stream
    }

    static func reply(to path: String, _ text: String) {
        let fd = open(path, O_WRONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        defer { close(fd) }
        writeAll(fd, text + "\n")
    }
}
