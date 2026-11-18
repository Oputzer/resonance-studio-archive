import AppKit
import SwiftUI

struct PlaylistView: View {
    let playlist: LibraryPlaylist
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library
    @State private var selection: TrackMeta.ID?
    @State private var showInspector = true

    private var tracks: [TrackMeta] { playlist.manifest.tracks }
    private var selectedTrack: TrackMeta? { tracks.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Table(tracks, selection: $selection) {
                TableColumn("#") { t in
                    if player.isCurrent(playlist.fileURL(for: t)) {
                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .foregroundStyle(Brand.accent)
                    } else {
                        Text("\(t.index)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .width(34)
                TableColumn("Title") { t in
                    HStack(spacing: 10) {
                        ArtworkView(url: playlist.artworkURL(for: t), size: 30, corner: 4)
                        Text(t.title).lineLimit(1)
                        if t.catalog?.explicit == true {
                            Image(systemName: "e.square.fill").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
                .width(min: 200, ideal: 280)
                TableColumn("Artist") { t in Text(t.displayArtist).lineLimit(1) }
                    .width(min: 90, ideal: 140)
                TableColumn("Album") { t in Text(t.displayAlbum ?? "—").lineLimit(1).foregroundStyle(.secondary) }
                    .width(min: 70, ideal: 120)
                TableColumn("Genre") { t in Text(t.displayGenre ?? "—").lineLimit(1).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 80)
                TableColumn("Date") { t in
                    Text(t.displayDate?.formatted(date: .abbreviated, time: .omitted) ?? "—").foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 96)
                TableColumn("Time") { t in Text(Fmt.duration(t.duration)).monospacedDigit().foregroundStyle(.secondary) }
                    .width(52)
            }
            .contextMenu(forSelectionType: TrackMeta.ID.self) { ids in
                if let id = ids.first, let t = tracks.first(where: { $0.id == id }) {
                    Button("Play") { play(from: t) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([playlist.fileURL(for: t)]) }
                    if let link = t.sourceURL.flatMap(URL.init(string:)) {
                        Button("Open on SoundCloud") { NSWorkspace.shared.open(link) }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let t = tracks.first(where: { $0.id == id }) { play(from: t) }
            }
        }
        .navigationTitle(playlist.manifest.title)
        .inspector(isPresented: $showInspector) {
            Group {
                if let t = selectedTrack {
                    TrackInspector(track: t, playlist: playlist) { play(from: t) }
                } else {
                    PlaylistInspector(playlist: playlist, enriching: library.enriching.contains(playlist.folder))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                    .help("Show or hide song details")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ArtworkView(url: playlist.coverURL, size: 172, corner: 12)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.manifest.isSingleTrack ? "SONG" : "PLAYLIST")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(playlist.manifest.title)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(2)
                if let uploader = playlist.manifest.uploader {
                    Text(uploader).font(.title3.weight(.medium)).foregroundStyle(Brand.accent)
                }
                Text(summary).font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    actionButtons(compact: false)
                    actionButtons(compact: true)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButtons(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Button { play(from: nil) } label: {
                Label("Play", systemImage: "play.fill").frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            Group {
                Button { play(from: nil, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                    .help("Shuffle")
                Button { NSWorkspace.shared.open(playlist.folder) } label: { Label("Show in Finder", systemImage: "folder") }
                    .help("Show in Finder")
                if let link = URL(string: playlist.manifest.sourceURL) {
                    Button { NSWorkspace.shared.open(link) } label: { Label("SoundCloud", systemImage: "arrow.up.right.square") }
                        .help("Open the original on SoundCloud")
                }
            }
            .labelStyle(AdaptiveLabelStyle(compact: compact))
        }
        .controlSize(.large)
        .fixedSize()
    }

    private var summary: String {
        let m = playlist.manifest
        let songs = "\(m.tracks.count) \(m.tracks.count == 1 ? "song" : "songs")"
        let date = m.downloadedAt.formatted(date: .abbreviated, time: .omitted)
        return [songs, Fmt.longDuration(m.totalDuration), m.format.title, "Downloaded \(date)"].joined(separator: " · ")
    }

    private func play(from track: TrackMeta?, shuffled: Bool = false) {
        var items = tracks.map {
            QueueItem(file: playlist.fileURL(for: $0), title: $0.title, artist: $0.displayArtist,
                      artwork: playlist.artworkURL(for: $0))
        }
        if shuffled { items.shuffle() }
        let start = track.flatMap { t in items.firstIndex { $0.file == playlist.fileURL(for: t) } } ?? 0
        player.play(items, startAt: start)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String?
    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
    }
}

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinkRow: View {
    let label: String
    let url: String?
    var body: some View {
        if let s = url, let u = URL(string: s) {
            HStack(spacing: 10) {
                Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                Link(destination: u) { Label("Open", systemImage: "arrow.up.right") }
                Spacer()
            }
            .font(.callout)
        }
    }
}

struct TrackInspector: View {
    let track: TrackMeta
    let playlist: LibraryPlaylist
    var play: () -> Void

    private var fileURL: URL { playlist.fileURL(for: track) }
    private var fileSize: Int64? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value
    }
    private var fileBitrate: String? {
        guard let size = fileSize, let d = track.duration, d > 0 else { return nil }
        return "\(Int((Double(size) * 8 / d / 1000).rounded())) kbps"
    }
    private var sourceQuality: String? {
        let codec = track.sourceCodec.map { $0 == "mp4a.40.2" ? "AAC" : $0.uppercased() }
        let rate = track.sourceBitrate.map { "\(Int($0.rounded())) kbps" }
        let parts = [codec, rate].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ArtworkView(url: playlist.bestArtworkURL(for: track), corner: 10)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.title3.bold()).textSelection(.enabled)
                    Text(track.displayArtist).foregroundStyle(Brand.accent)
                }

                HStack {
                    Button(action: play) { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }

                InfoSection(title: "Song") {
                    InfoRow(label: "Album", value: track.displayAlbum)
                    InfoRow(label: "Genre", value: track.displayGenre)
                    InfoRow(label: "Released", value: track.catalog?.releaseDate?.formatted(date: .long, time: .omitted))
                    InfoRow(label: "Track", value: track.catalog?.trackNumber.map { n in
                        track.catalog?.trackCount.map { "\(n) of \($0)" } ?? "\(n)"
                    })
                    InfoRow(label: "Length", value: Fmt.duration(track.duration))
                    InfoRow(label: "Explicit", value: track.catalog?.explicit.map { $0 ? "Yes" : "No" })
                }

                InfoSection(title: "SoundCloud") {
                    InfoRow(label: "Uploaded by", value: track.artist)
                    InfoRow(label: "Published", value: track.uploadDate?.formatted(date: .long, time: .omitted))
                    InfoRow(label: "Plays", value: Fmt.count(track.playCount))
                    InfoRow(label: "Likes", value: Fmt.count(track.likeCount))
                    InfoRow(label: "Reposts", value: Fmt.count(track.repostCount))
                    InfoRow(label: "Comments", value: Fmt.count(track.commentCount))
                    InfoRow(label: "License", value: track.license.map(Self.licenseName))
                    LinkRow(label: "Song page", url: track.sourceURL)
                    LinkRow(label: "Artist page", url: track.uploaderURL)
                }

                if let c = track.catalog {
                    InfoSection(title: "Apple Music Catalog") {
                        InfoRow(label: "Title", value: c.trackName)
                        InfoRow(label: "Artist", value: c.artistName)
                        InfoRow(label: "Album", value: c.albumName)
                        LinkRow(label: "Listing", url: c.storeURL)
                    }
                }

                InfoSection(title: "File") {
                    InfoRow(label: "Format", value: playlist.manifest.format.title + " (." + fileURL.pathExtension + ")")
                    InfoRow(label: "Bitrate", value: fileBitrate)
                    InfoRow(label: "Size", value: fileSize.map(Fmt.bytes))
                    InfoRow(label: "Source", value: sourceQuality)
                    InfoRow(label: "File name", value: track.fileName)
                }

                if let d = track.description {
                    InfoSection(title: "Description") {
                        Text(d).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .padding(18)
        }
    }

    static func licenseName(_ raw: String) -> String {
        switch raw {
        case "all-rights-reserved": return "All rights reserved"
        case "no-rights-reserved": return "No rights reserved"
        default: return raw.hasPrefix("cc-") ? "Creative Commons (\(raw.dropFirst(3).uppercased()))" : raw
        }
    }
}

private struct PlaylistInspector: View {
    let playlist: LibraryPlaylist
    let enriching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ArtworkView(url: playlist.coverURL, corner: 10)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                Text(playlist.manifest.title).font(.title3.bold())
                if enriching {
                    Label("Looking up release dates and album info…", systemImage: "sparkle.magnifyingglass")
                        .font(.callout).foregroundStyle(.secondary)
                }
                InfoSection(title: "Playlist") {
                    InfoRow(label: "Curated by", value: playlist.manifest.uploader)
                    InfoRow(label: "Songs", value: "\(playlist.manifest.tracks.count)")
                    InfoRow(label: "Length", value: Fmt.longDuration(playlist.manifest.totalDuration))
                    InfoRow(label: "Format", value: playlist.manifest.format.title)
                    InfoRow(label: "Downloaded", value: playlist.manifest.downloadedAt.formatted(date: .long, time: .shortened))
                    LinkRow(label: "SoundCloud", url: playlist.manifest.sourceURL)
                }
                InfoSection(title: "Location") {
                    Text(playlist.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.callout).textSelection(.enabled)
                    Button { NSWorkspace.shared.open(playlist.folder) } label: { Label("Show in Finder", systemImage: "folder") }
                }
                if let d = playlist.manifest.description {
                    InfoSection(title: "Description") {
                        Text(d).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Text("Select a song to see its details.").font(.callout).foregroundStyle(.tertiary)
            }
            .padding(18)
        }
    }
}

private struct AdaptiveLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: 6) { configuration.icon; configuration.title }
        }
    }
}
