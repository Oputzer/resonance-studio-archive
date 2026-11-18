import Foundation

/// `ResonanceStudio --selftest <url> <format>` runs a real download without the window and prints the result.
/// Set RESONANCE_LIBRARY to keep test downloads out of the real library.
@MainActor
enum SelfTest {
    private static var library: Library!
    private static var center: DownloadCenter!
    private static var account: Account!

    static func run(url: String, format: String) {
        library = Library()
        center = DownloadCenter()
        account = Account()
        center.attach(library: library)
        center.start(url: url, format: AudioFormat(rawValue: format) ?? .original)
        guard let job = center.jobs.first else { exit(2) }

        var lastLine = ""
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            MainActor.assumeIsolated {
                let line = "[\(job.state)] \(job.title) — \(job.subtitle) — \(Int(job.fraction * 100))%"
                if line != lastLine { print(line); lastLine = line }
                guard !job.isActive else { return }
                if let folder = job.folder, library.enriching.contains(folder) { return }
                timer.invalidate()
                report(job)
                exit(job.state == .done ? 0 : 1)
            }
        }
    }

    private static func report(_ job: DownloadJob) {
        print("failures:", job.failures)
        guard let folder = job.folder, let p = library.playlist(at: folder) else { print("no playlist in library"); return }
        print("folder:", folder.path)
        print("cover:", p.coverURL?.lastPathComponent ?? "none")
        for t in p.manifest.tracks {
            let art = p.artworkURL(for: t).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            print(" #\(t.index) \(t.title) | \(t.displayArtist) | genre=\(t.displayGenre ?? "-") | uploaded=\(t.uploadDate.map { "\($0)" } ?? "-") | plays=\(t.playCount ?? -1) | art=\(art) | catalog=\(t.catalog.map { "\($0.trackName) / \($0.albumName ?? "-") / \($0.releaseDate.map { "\($0)" } ?? "-")" } ?? "none") | file=\(t.fileName)")
        }
    }

    /// `ResonanceStudio --selftest-tools` runs the first-launch tool download and reports the result.
    static func installTools() {
        let installer = ToolInstaller()
        Task { @MainActor in
            let watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { print("phase:", installer.phase) }
            }
            await installer.install(force: true)
            watcher.invalidate()
            print("final:", installer.phase)
            if let t = Tools.locate() { print("yt-dlp:", t.ytdlp.path); print("ffmpeg:", t.ffmpeg.path) }
            exit(installer.phase == .ready ? 0 : 1)
        }
    }
}
