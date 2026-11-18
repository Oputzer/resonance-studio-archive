import CryptoKit
import Foundation

/// Downloads yt-dlp and FFmpeg into Application Support on first launch, so nobody has
/// to install anything by hand. Every file is checked against its published SHA-256.
@MainActor
final class ToolInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(step: String, progress: Double)
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = Tools.locate() == nil ? .idle : .ready

    nonisolated static var binDir: URL {
        if let dir = ProcessInfo.processInfo.environment["RESONANCE_TOOLS_DIR"]?.nilIfBlank {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return Paths.support.appendingPathComponent("bin", isDirectory: true)
    }

    private struct Item {
        let name: String          // executable name on disk
        let label: String         // shown in the UI
        let url: URL
        let isZip: Bool
    }

    private static var items: [Item] {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif
        let ffmpegBase = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/release/"
        return [
            Item(name: "yt-dlp", label: "yt-dlp",
                 url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!, isZip: false),
            Item(name: "ffmpeg", label: "FFmpeg", url: URL(string: ffmpegBase + "ffmpeg.zip")!, isZip: true),
            Item(name: "ffprobe", label: "FFprobe", url: URL(string: ffmpegBase + "ffprobe.zip")!, isZip: true),
        ]
    }

    var isWorking: Bool { if case .working = phase { return true } else { return false } }

    /// Installs whatever is missing. Safe to call repeatedly.
    func installIfNeeded() async {
        guard !isWorking else { return }
        if Tools.locate() != nil { phase = .ready; return }
        await install(force: false)
    }

    func install(force: Bool) async {
        guard !isWorking else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.binDir, withIntermediateDirectories: true)
            let items = Self.items.filter { force || !fm.isExecutableFile(atPath: Self.binDir.appendingPathComponent($0.name).path) }
            for (i, item) in items.enumerated() {
                let step = "Downloading \(item.label) (\(i + 1) of \(items.count))…"
                phase = .working(step: step, progress: 0)
                try await installItem(item) { [weak self] p in self?.phase = .working(step: step, progress: p) }
            }
            UserDefaults.standard.set(Date(), forKey: "toolsUpdatedAt")
            phase = Tools.locate() != nil ? .ready : .failed("The tools were downloaded but couldn't be started.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// yt-dlp needs frequent updates to keep working with SoundCloud. Update our own copy
    /// in the background at most every few days.
    func updateYtdlpIfStale() {
        let last = UserDefaults.standard.object(forKey: "toolsUpdatedAt") as? Date ?? .distantPast
        let ytdlp = Self.binDir.appendingPathComponent("yt-dlp")
        guard Date().timeIntervalSince(last) > 3 * 86_400,
              FileManager.default.isExecutableFile(atPath: ytdlp.path) else { return }
        Task.detached(priority: .background) {
            let result = try? await Shell.run(ytdlp, ["--update"], env: ProcessInfo.processInfo.environment)
            if result?.status == 0 {
                await MainActor.run { UserDefaults.standard.set(Date(), forKey: "toolsUpdatedAt") }
            }
        }
    }

    // MARK: Steps

    private func installItem(_ item: Item, progress: @escaping (Double) -> Void) async throws {
        let (file, finalURL) = try await Self.download(item.url, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }

        // Verify against the checksum published next to the file.
        let expected = try await Self.publishedChecksum(for: item, finalURL: finalURL)
        let actual = try Self.sha256(of: file)
        guard actual == expected else {
            throw AppError("\(item.label) didn't pass its security check, so it wasn't installed. Please try again.")
        }

        let dest = Self.binDir.appendingPathComponent(item.name)
        let fm = FileManager.default
        if item.isZip {
            let unpack = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: unpack) }
            let r = try await Shell.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", file.path, unpack.path],
                                        env: ProcessInfo.processInfo.environment)
            guard r.status == 0 else { throw AppError("Couldn't unpack \(item.label).") }
            guard let found = fm.enumerator(at: unpack, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == item.name }) else {
                throw AppError("\(item.label) download was missing the program.")
            }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: found, to: dest)
        } else {
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: file, to: dest)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        try await Self.makeRunnable(dest)
    }

    /// Apple silicon refuses to run unsigned code, so ad-hoc sign anything that isn't signed.
    private static func makeRunnable(_ url: URL) async throws {
        let env = ProcessInfo.processInfo.environment
        _ = try? await Shell.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-d", "com.apple.quarantine", url.path], env: env)
        let check = try await Shell.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", url.path], env: env)
        if check.status != 0 {
            _ = try await Shell.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "--sign", "-", url.path], env: env)
        }
    }

    private static func publishedChecksum(for item: Item, finalURL: URL) async throws -> String {
        let sumsURL: URL
        if item.isZip {
            sumsURL = URL(string: finalURL.absoluteString + ".sha256")!
        } else {
            sumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS")!
        }
        guard let (data, response) = try? await URLSession.shared.data(from: sumsURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError("Couldn't verify \(item.label). Check your internet connection and try again.")
        }
        let wanted = item.isZip ? finalURL.lastPathComponent : "yt-dlp_macos"
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts.last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "*")) == wanted {
                return parts[0].lowercased()
            }
        }
        throw AppError("Couldn't find the security checksum for \(item.label).")
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads to a temporary file, reporting progress, and returns the file plus the final URL after redirects.
    private static func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> (URL, URL) {
        try await withCheckedThrowingContinuation { cont in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                observation?.invalidate()
                if let error { cont.resume(throwing: AppError("Download failed: \(error.localizedDescription)")); return }
                guard let tmp, let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url else {
                    cont.resume(throwing: AppError("Download failed. Please try again."))
                    return
                }
                // The system deletes `tmp` when this handler returns, so move it first.
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: tmp, to: keep)
                    cont.resume(returning: (keep, final))
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in
                let value = p.fractionCompleted
                DispatchQueue.main.async { progress(value) }
            }
            task.resume()
        }
    }
}
