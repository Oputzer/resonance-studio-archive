import AppKit
import Foundation

@MainActor
final class Library: ObservableObject {
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var enriching: Set<URL> = []

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        let root = Paths.libraryRoot
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        let found = folders.compactMap { folder -> LibraryPlaylist? in
            guard let manifest = PlaylistManifest.load(from: folder) else { return nil }
            return LibraryPlaylist(folder: folder, manifest: manifest)
        }
        let sorted = found.sorted { $0.manifest.downloadedAt > $1.manifest.downloadedAt }
        if sorted != playlists { playlists = sorted }
    }

    func playlist(at folder: URL) -> LibraryPlaylist? {
        playlists.first { $0.folder == folder }
    }

    func moveToTrash(_ playlist: LibraryPlaylist) {
        try? FileManager.default.trashItem(at: playlist.folder, resultingItemURL: nil)
        reload()
    }

    /// Fills in release dates, genres, albums and high-resolution covers from Apple's public catalog.
    func enrich(folder: URL) {
        guard !enriching.contains(folder) else { return }
        enriching.insert(folder)
        Task {
            defer { enriching.remove(folder) }
            guard var manifest = PlaylistManifest.load(from: folder) else { return }
            for i in manifest.tracks.indices where manifest.tracks[i].catalogChecked != true {
                let t = manifest.tracks[i]
                if var match = await Catalog.shared.lookup(title: t.title, artist: t.artist) {
                    match.artworkFile = await Catalog.saveArtwork(match, trackID: t.id, folder: folder)
                    manifest.tracks[i].catalog = match
                }
                manifest.tracks[i].catalogChecked = true
                try? manifest.save(to: folder)
                if let idx = playlists.firstIndex(where: { $0.folder == folder }) {
                    playlists[idx].manifest = manifest
                }
            }
        }
    }

    func enrichAllPending() {
        for p in playlists where p.manifest.tracks.contains(where: { $0.catalogChecked != true }) {
            enrich(folder: p.folder)
        }
    }
}

/// Looks songs up in the iTunes Search API (free, no account needed).
actor Catalog {
    static let shared = Catalog()
    private var lastRequest = Date.distantPast

    func lookup(title: String, artist: String) async -> CatalogMatch? {
        // The API allows roughly 20 requests a minute.
        let wait = 3.2 - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()

        let cleanTitle = Self.stripNoise(title)
        let term = cleanTitle.contains(" - ") ? cleanTitle : "\(artist) \(cleanTitle)"
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            .init(name: "term", value: term),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "15"),
        ]
        guard let url = comps.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return nil }

        let haystack = Self.normalize("\(title) \(artist)")
        let normTitle = Self.normalize(cleanTitle)
        let sourceVersions = Self.versionWords(in: title)
        var candidates: [[String: Any]] = []
        for r in results {
            guard let name = r["trackName"] as? String, let artistName = r["artistName"] as? String else { continue }
            let n = Self.normalize(Self.stripNoise(name))
            let a = Self.normalize(artistName.components(separatedBy: CharacterSet(charactersIn: "&,")).first ?? artistName)
            guard n.count >= 3, a.count >= 2,
                  normTitle.contains(n) || n.contains(normTitle),
                  haystack.contains(a),
                  // Don't label an original as a remix/live/etc. version, or the other way round.
                  Self.versionWords(in: "\(name) \(r["collectionName"] as? String ?? "")") == sourceVersions
            else { continue }
            candidates.append(r)
        }
        // The earliest release is almost always the original album or single.
        let best = candidates.min { ($0["releaseDate"] as? String ?? "9") < ($1["releaseDate"] as? String ?? "9") }
        if let r = best, let name = r["trackName"] as? String, let artistName = r["artistName"] as? String {
            return CatalogMatch(
                trackName: name,
                artistName: artistName,
                albumName: r["collectionName"] as? String,
                releaseDate: (r["releaseDate"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                genre: r["primaryGenreName"] as? String,
                trackNumber: r["trackNumber"] as? Int,
                trackCount: r["trackCount"] as? Int,
                discNumber: r["discNumber"] as? Int,
                explicit: (r["trackExplicitness"] as? String).map { $0 == "explicit" },
                artworkURL: (r["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "3000x3000bb"),
                storeURL: r["trackViewUrl"] as? String,
                artworkFile: nil
            )
        }
        return nil
    }

    static func versionWords(in s: String) -> Set<String> {
        let words = ["remix", "live", "acoustic", "instrumental", "karaoke", "edit", "extended", "remaster", "remastered", "cover", "sped up", "slowed", "lofi", "lo-fi", "mix"]
        let lower = s.lowercased()
        return Set(words.filter { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil })
    }

    static func saveArtwork(_ match: CatalogMatch, trackID: String, folder: URL) async -> String? {
        guard let s = match.artworkURL, let url = URL(string: s),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else { return nil }
        let name = "\(trackID)-catalog.jpg"
        let dest = folder.appendingPathComponent(".fmf/art/\(name)")
        return (try? data.write(to: dest, options: .atomic)) != nil ? name : nil
    }

    /// Removes things like "(Free Download)", "[Official Audio]", "prod. by …".
    static func stripNoise(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(free|download|official|audio|video|out now|prod|premiere)[^\)\]]*[\)\]]"#,
                                       with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+(prod\.?|produced) by .*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let cleaned = folded.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        let alnum = cleaned.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(alnum).split(separator: " ").joined(separator: " ")
    }
}

/// Small downsampling image cache so big covers don't slow down scrolling.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, maxPixels: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
