import Foundation

/// Locates the yt-dlp and FFmpeg binaries. Bundled copies win over system installs.
struct Tools {
    let ytdlp: URL
    let ffmpeg: URL

    static func locate() -> Tools? {
        guard let y = find("yt-dlp"), let f = find("ffmpeg") else { return nil }
        return Tools(ytdlp: y, ffmpeg: f)
    }

    private static func find(_ name: String) -> URL? {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("bin", isDirectory: true))
        }
        dirs.append(ToolInstaller.binDir)   // downloaded automatically on first launch
        if ProcessInfo.processInfo.environment["RESONANCE_TOOLS_ONLY"] == nil {
            dirs += ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [ffmpeg.deletingLastPathComponent().path, ytdlp.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["PYTHONIOENCODING"] = "utf-8"
        env["LC_ALL"] = "en_US.UTF-8"
        return env
    }
}

/// Splits a file handle's output into lines as it arrives.
final class LineReader {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(handle: FileHandle, onLine: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        self.onLine = onLine
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self else { return }
            if data.isEmpty {
                h.readabilityHandler = nil
                if !self.buffer.isEmpty { self.emit(self.buffer); self.buffer.removeAll() }
                onEnd()
                return
            }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                self.emit(self.buffer[self.buffer.startIndex..<newline])
                self.buffer.removeSubrange(self.buffer.startIndex...newline)
            }
        }
    }

    private func emit(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if !line.isEmpty { onLine(line) }
    }
}

enum Shell {
    /// Runs a command to completion and returns stdout, stderr and the exit code.
    static func run(_ exe: URL, _ args: [String], env: [String: String]) async throws -> (out: Data, err: String, status: Int32) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = exe
                p.arguments = args
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { cont.resume(throwing: error); return }
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                cont.resume(returning: (outData, String(decoding: errData, as: UTF8.self), p.terminationStatus))
            }
        }
    }

    /// Runs a command, delivering each output line (stdout and stderr) on the main queue.
    @MainActor
    static func stream(_ exe: URL, _ args: [String], env: [String: String],
                       started: (Process) -> Void,
                       onLine: @escaping (String) -> Void) async throws -> Int32 {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let group = DispatchGroup()
        group.enter(); group.enter(); group.enter()
        let deliver: (String) -> Void = { line in DispatchQueue.main.async { onLine(line) } }
        let r1 = LineReader(handle: out.fileHandleForReading, onLine: deliver) { group.leave() }
        let r2 = LineReader(handle: err.fileHandleForReading, onLine: deliver) { group.leave() }
        p.terminationHandler = { _ in group.leave() }

        try p.run()
        started(p)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .main) { c.resume() }
        }
        withExtendedLifetime((r1, r2)) {}
        return p.terminationStatus
    }
}
