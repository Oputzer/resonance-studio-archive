import Foundation
import SwiftUI

@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case preparing, downloading, finishing, done, failed(String), cancelled
    }

    let id = UUID()
    let url: String
    let format: AudioFormat

    @Published var state: State = .preparing
    @Published var title = "Reading link…"
    @Published var total = 0
    @Published var completed = 0
    @Published var currentTitle = ""
    @Published var currentProgress = 0.0
    @Published var failures: [String] = []
    @Published var folder: URL?
    @Published var coverURL: URL?

    var process: Process?
    var titlesByID: [String: String] = [:]
    var saved: [String: String] = [:]   // track id -> file path
    var savedOrder: [String] = []

    init(url: String, format: AudioFormat) {
        self.url = url
        self.format = format
    }

    var isActive: Bool {
        switch state {
        case .preparing, .downloading, .finishing: return true
        default: return false
        }
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completed) + currentProgress) / Double(total))
    }

    var subtitle: String {
        switch state {
        case .preparing: return "Reading link…"
        case .downloading:
            if total == 0 { return "Starting…" }
            let current = currentTitle.isEmpty ? "" : " · \(currentTitle)"
            return "\(min(completed + 1, total)) of \(total)\(current)"
        case .finishing: return "Saving song details…"
        case .done:
            return "\(completed) \(completed == 1 ? "song" : "songs") · \(format.title) · Saved to \(Paths.displayLibraryPath)"
        case .failed(let message): return message
        case .cancelled: return completed > 0 ? "Stopped after \(completed) \(completed == 1 ? "song" : "songs")" : "Cancelled"
        }
    }

    func handle(_ line: String) {
        let parts = line.components(separatedBy: "\t")
        switch parts.first {
        case "ITEM" where parts.count >= 5:
            if let n = Int(parts[3]), n > 0 { total = n }
            currentTitle = parts[4...].joined(separator: " ")
            currentProgress = 0
        case "PROG" where parts.count >= 4:
            let done = Double(parts[2]) ?? 0
            let size = Double(parts[3]) ?? 0
            if size > 0 { currentProgress = min(0.95, done / size * 0.95) }
        case "SAVED" where parts.count >= 3:
            let id = parts[1]
            if saved[id] == nil { savedOrder.append(id) }
            saved[id] = parts[2...].joined(separator: "\t")
            completed = saved.count
            currentProgress = 0
            if coverURL == nil, let folder {
                let art = folder.appendingPathComponent(".resonance/art/\(id).jpg")
                if FileManager.default.fileExists(atPath: art.path) { coverURL = art }
            }
        default:
            guard line.hasPrefix("ERROR:") else { return }
            let message = Self.clean(error: line)
            if let r = line.range(of: #"^ERROR: \[[^\]]+\] [^:]+:"#, options: .regularExpression),
               let id = line[r].split(separator: "]").last?.dropLast().trimmingCharacters(in: .whitespaces),
               let name = titlesByID[id] {
                failures.append("\(name): \(message)")
            } else {
                failures.append(message)
            }
        }
    }

    nonisolated static func clean(error line: String) -> String {
        var s = line.replacingOccurrences(of: "ERROR: ", with: "")
        if let r = s.range(of: #"^\[[^\]]+\] [^:]+: "#, options: .regularExpression) { s.removeSubrange(r) }
        if s.contains("Requested format is not available") {
            return "SoundCloud only allows a 30-second preview of this song (SoundCloud Go+), so it was skipped."
        }
        return String(s.prefix(240))
    }
}

@MainActor
final class DownloadCenter: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published var openRequest: URL?

    private weak var library: Library?

    var activeCount: Int { jobs.filter(\.isActive).count }

    func attach(library: Library) {
        self.library = library
    }

    static func isSoundCloudLink(_ raw: String) -> Bool {
        guard let u = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.scheme == "https" || u.scheme == "http",
              let host = u.host?.lowercased() else { return false }
        return host == "soundcloud.com" || host.hasSuffix(".soundcloud.com")
    }

    func start(url raw: String, format: AudioFormat) {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = DownloadJob(url: url, format: format)
        jobs.insert(job, at: 0)
        Task { await run(job) }
    }

    func cancel(_ job: DownloadJob) {
        guard job.isActive else { return }
        job.state = .cancelled
        job.process?.terminate()
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive }
    }

    private func run(_ job: DownloadJob) async {
        guard let tools = Tools.locate() else {
            job.state = .failed("Resonance Studio's helper tools are missing. Open Settings to fix this.")
            return
        }
        do {
            let probe = try await Downloader.probe(url: job.url, tools: tools)
            if job.state == .cancelled { return }
            job.title = probe.title
            job.total = probe.count
            job.titlesByID = probe.titlesByID

            let folder = try Downloader.makeFolder(for: probe.title)
            job.folder = folder

            job.state = .downloading
            _ = try await Downloader.download(job: job, folder: folder, tools: tools, isPlaylist: probe.isPlaylist)

            if job.state == .cancelled && job.saved.isEmpty {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            let wasCancelled = job.state == .cancelled
            job.state = .finishing
            let manifest = Downloader.buildManifest(job: job, probe: probe, folder: folder)
            guard !manifest.tracks.isEmpty else {
                try? FileManager.default.removeItem(at: folder)
                let reason = job.failures.first.map { $0.components(separatedBy: ": ").dropFirst().joined(separator: ": ") }
                job.state = .failed(reason?.nilIfBlank ?? job.failures.first ?? "No songs could be downloaded. The uploader may have blocked them.")
                return
            }
            try manifest.save(to: folder)
            if job.format == .wav {
                await Downloader.tagWAVFiles(folder: folder, manifest: manifest)
            }
            job.coverURL = LibraryPlaylist(folder: folder, manifest: manifest).coverURL
            library?.reload()
            job.state = wasCancelled ? .cancelled : .done
            library?.enrich(folder: folder)
        } catch {
            if job.state != .cancelled { job.state = .failed(error.localizedDescription) }
        }
    }
}

struct Probe {
    var title: String
    var uploader: String?
    var description: String?
    var count: Int
    var isPlaylist: Bool
    var titlesByID: [String: String]
}

enum Downloader {
    static func probe(url: String, tools: Tools) async throws -> Probe {
        let result = try await Shell.run(tools.ytdlp, ["--flat-playlist", "-J", "--no-warnings", url], env: tools.environment)
        guard result.status == 0,
              let obj = try? JSONSerialization.jsonObject(with: result.out) as? [String: Any] else {
            let reason = result.err.split(separator: "\n").last { $0.hasPrefix("ERROR") }.map { DownloadJob.clean(error: String($0)) }
            throw AppError(reason ?? "Couldn't open that link. Make sure it's public.")
        }
        let isPlaylist = (obj["_type"] as? String) == "playlist"
        let entries = isPlaylist ? (obj["entries"] as? [[String: Any]] ?? []) : [obj]
        let count = entries.count
        var titles: [String: String] = [:]
        for e in entries {
            if let id = (e["id"] as? String) ?? (e["id"] as? NSNumber)?.stringValue, let t = e["title"] as? String { titles[id] = t }
        }
        if count == 0 {
            throw AppError("This playlist has no downloadable songs. The uploader may have blocked them.")
        }
        return Probe(
            title: (obj["title"] as? String)?.nilIfBlank ?? "SoundCloud",
            uploader: obj["uploader"] as? String,
            description: (obj["description"] as? String)?.nilIfBlank,
            count: count,
            isPlaylist: isPlaylist,
            titlesByID: titles
        )
    }

    /// Desktop › Resonance Studio › "<Playlist name> — <yyyy-MM-dd>"
    static func makeFolder(for title: String) throws -> URL {
        let fm = FileManager.default
        let root = Paths.libraryRoot
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        let day = dayFormat.string(from: Date())
        let base = "\(Paths.safeName(title)) — \(day)"
        var name = base
        var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(name).path) {
            name = "\(base) (\(n))"
            n += 1
        }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder.appendingPathComponent(".resonance/info"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent(".resonance/art"), withIntermediateDirectories: true)
        return folder
    }

    @MainActor
    static func download(job: DownloadJob, folder: URL, tools: Tools, isPlaylist: Bool) async throws -> Int32 {
        var args = [
            "--yes-playlist", "--ignore-errors", "--no-overwrites", "--newline", "--progress",
            "--no-simulate", "--color", "no_color",
            "--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path,
        ]
        args += job.format.ytdlpArguments
        args += [
            "--embed-metadata",
            "--write-thumbnail", "--convert-thumbnails", "jpg",
            "--write-info-json",
        ]
        if isPlaylist {
            args += ["--parse-metadata", "playlist_index:(?P<track_number>.+)",
                     "--parse-metadata", "playlist_title:(?P<album>.+)"]
        }
        if job.format.embedsArtwork { args.append("--embed-thumbnail") }
        args += [
            "--print", "before_dl:ITEM\t%(id)s\t%(playlist_index|1)s\t%(n_entries|1)s\t%(title)s",
            "--print", "after_move:SAVED\t%(id)s\t%(filepath)s",
            "--progress-template", "download:PROG\t%(info.id)s\t%(progress.downloaded_bytes|0)s\t%(progress.total_bytes,progress.total_bytes_estimate|0)s",
            "-P", folder.path,
            "-o", isPlaylist ? "%(playlist_index)02d - %(title)s.%(ext)s" : "%(title)s.%(ext)s",
            "-o", "thumbnail:.resonance/art/%(id)s.%(ext)s",
            "-o", "infojson:.resonance/info/%(id)s",
            "-o", "pl_thumbnail:.resonance/art/playlist.%(ext)s",
            "-o", "pl_infojson:.resonance/info/playlist",
            job.url,
        ]
        return try await Shell.stream(tools.ytdlp, args, env: tools.environment,
                                      started: { p in job.process = p },
                                      onLine: { line in MainActor.assumeIsolated { job.handle(line) } })
    }

    @MainActor
    static func buildManifest(job: DownloadJob, probe: Probe, folder: URL) -> PlaylistManifest {
        let infoDir = folder.appendingPathComponent(".resonance/info")
        let artDir = folder.appendingPathComponent(".resonance/art")
        var tracks: [TrackMeta] = []
        for (position, id) in job.savedOrder.enumerated() {
            guard let path = job.saved[id], FileManager.default.fileExists(atPath: path) else { continue }
            let info = readJSON(infoDir.appendingPathComponent("\(id).info.json")) ?? [:]
            let art = FileManager.default.fileExists(atPath: artDir.appendingPathComponent("\(id).jpg").path) ? "\(id).jpg" : nil
            tracks.append(track(from: info, id: id, fallbackIndex: position + 1,
                                fileName: URL(fileURLWithPath: path).lastPathComponent, artworkFile: art))
        }
        tracks.sort { $0.index < $1.index }
        let playlistInfo = readJSON(infoDir.appendingPathComponent("playlist.info.json"))
        return PlaylistManifest(
            title: probe.title,
            uploader: (playlistInfo?["uploader"] as? String) ?? probe.uploader ?? tracks.first?.artist,
            sourceURL: (playlistInfo?["webpage_url"] as? String) ?? job.url,
            description: (playlistInfo?["description"] as? String)?.nilIfBlank ?? probe.description,
            downloadedAt: Date(),
            format: job.format,
            isSingleTrack: !probe.isPlaylist,
            tracks: tracks
        )
    }

    /// WAV can't carry artwork through FFmpeg, so write the ID3 tag ourselves.
    static func tagWAVFiles(folder: URL, manifest: PlaylistManifest) async {
        let jobs = manifest.tracks.map { t -> (URL, WAVTagger.Tags) in
            let art = t.artworkFile.flatMap { try? Data(contentsOf: folder.appendingPathComponent(".resonance/art/\($0)")) }
            let tags = WAVTagger.Tags(title: t.title, artist: t.artist,
                                      album: manifest.isSingleTrack ? nil : manifest.title,
                                      track: manifest.isSingleTrack ? nil : t.index, artwork: art)
            return (folder.appendingPathComponent(t.fileName), tags)
        }
        await Task.detached(priority: .userInitiated) {
            for (url, tags) in jobs { try? WAVTagger.embed(tags, into: url) }
        }.value
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func track(from info: [String: Any], id: String, fallbackIndex: Int, fileName: String, artworkFile: String?) -> TrackMeta {
        func str(_ k: String) -> String? { (info[k] as? String)?.nilIfBlank }
        func int(_ k: String) -> Int? { (info[k] as? NSNumber)?.intValue }
        func dbl(_ k: String) -> Double? { (info[k] as? NSNumber)?.doubleValue }
        var uploaded = str("upload_date").flatMap { dayFormatter.date(from: $0) }
        if uploaded == nil, let ts = dbl("timestamp") { uploaded = Date(timeIntervalSince1970: ts) }
        return TrackMeta(
            id: id,
            index: int("playlist_index") ?? fallbackIndex,
            title: str("track") ?? str("title") ?? fileName,
            artist: str("artist") ?? str("uploader") ?? "Unknown Artist",
            album: str("album"),
            genre: str("genre"),
            uploadDate: uploaded,
            duration: dbl("duration"),
            description: str("description"),
            sourceURL: str("webpage_url"),
            uploaderURL: str("uploader_url"),
            license: str("license"),
            playCount: int("view_count"),
            likeCount: int("like_count"),
            repostCount: int("repost_count"),
            commentCount: int("comment_count"),
            sourceCodec: str("acodec"),
            sourceBitrate: dbl("abr"),
            fileName: fileName,
            artworkFile: artworkFile,
            catalog: nil,
            catalogChecked: nil
        )
    }
}
