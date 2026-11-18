import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AudioFormat: String, CaseIterable, Codable, Identifiable {
    case original, mp3, aac, wav, flac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .mp3: return "MP3"
        case .aac: return "AAC"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        }
    }

    var detail: String {
        switch self {
        case .original: return "Untouched source file. Best quality, smallest size."
        case .mp3: return "320 kbps. Plays on everything."
        case .aac: return "Apple's format. Great for the Music app."
        case .wav: return "Uncompressed. For DJ and editing software."
        case .flac: return "Lossless, and smaller than WAV."
        }
    }

    var ytdlpArguments: [String] {
        // Never accept SoundCloud's 30-second previews of Go+ songs.
        let source = ["-f", "bestaudio[format_id!*=preview]/best[format_id!*=preview]"]
        switch self {
        case .original: return source
        case .mp3: return source + ["-x", "--audio-format", "mp3", "--audio-quality", "320K"]
        case .aac: return source + ["-x", "--audio-format", "m4a", "--audio-quality", "0"]
        case .wav: return source + ["-x", "--audio-format", "wav"]
        case .flac: return source + ["-x", "--audio-format", "flac"]
        }
    }

    /// WAV has no reliable place to store cover art.
    var embedsArtwork: Bool { self != .wav }
}

/// Song details from Apple's public music catalog, when a confident match exists.
struct CatalogMatch: Codable, Hashable {
    var trackName: String
    var artistName: String
    var albumName: String?
    var releaseDate: Date?
    var genre: String?
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var explicit: Bool?
    var artworkURL: String?
    var storeURL: String?
    var artworkFile: String?
}

struct TrackMeta: Codable, Identifiable, Hashable {
    var id: String
    var index: Int
    var title: String
    var artist: String
    var album: String?
    var genre: String?
    var uploadDate: Date?
    var duration: Double?
    var description: String?
    var sourceURL: String?
    var uploaderURL: String?
    var license: String?
    var playCount: Int?
    var likeCount: Int?
    var repostCount: Int?
    var commentCount: Int?
    var sourceCodec: String?
    var sourceBitrate: Double?
    var fileName: String
    var artworkFile: String?
    var catalog: CatalogMatch?
    var catalogChecked: Bool?

    var displayArtist: String { catalog?.artistName ?? artist }
    var displayAlbum: String? { catalog?.albumName ?? album }
    var displayGenre: String? { genre?.nilIfBlank ?? catalog?.genre }
    var displayDate: Date? { catalog?.releaseDate ?? uploadDate }
}

struct PlaylistManifest: Codable, Hashable {
    var version = 1
    var title: String
    var uploader: String?
    var sourceURL: String
    var description: String?
    var downloadedAt: Date
    var format: AudioFormat
    var isSingleTrack: Bool
    var tracks: [TrackMeta]

    var totalDuration: Double { tracks.compactMap(\.duration).reduce(0, +) }

    static let fileName = "playlist.json"

    static func load(from folder: URL) -> PlaylistManifest? {
        let url = folder.appendingPathComponent(".resonance/\(fileName)")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSON.decoder.decode(PlaylistManifest.self, from: data)
    }

    func save(to folder: URL) throws {
        let dir = folder.appendingPathComponent(".resonance", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSON.encoder.encode(self).write(to: dir.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// A downloaded playlist living on disk.
struct LibraryPlaylist: Identifiable, Hashable {
    var folder: URL
    var manifest: PlaylistManifest
    var id: URL { folder }

    var coverURL: URL? {
        let cover = folder.appendingPathComponent(".resonance/art/playlist.jpg")
        if FileManager.default.fileExists(atPath: cover.path) { return cover }
        return manifest.tracks.first.flatMap(artworkURL(for:))
    }

    func fileURL(for track: TrackMeta) -> URL { folder.appendingPathComponent(track.fileName) }

    func artworkURL(for track: TrackMeta) -> URL? {
        track.artworkFile.map { folder.appendingPathComponent(".resonance/art/\($0)") }
    }

    /// Prefers the high-resolution catalog cover when one was found.
    func bestArtworkURL(for track: TrackMeta) -> URL? {
        if let file = track.catalog?.artworkFile {
            let url = folder.appendingPathComponent(".resonance/art/\(file)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return artworkURL(for: track)
    }
}

enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

enum Fmt {
    static func duration(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s > 0 else { return "—" }
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func longDuration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func count(_ n: Int?) -> String? {
        guard let n else { return nil }
        return n.formatted(.number.notation(.compactName))
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
