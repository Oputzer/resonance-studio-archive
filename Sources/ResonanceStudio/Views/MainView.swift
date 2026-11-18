import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case download
    case playlist(URL)
}

struct MainView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var downloads: DownloadCenter
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var tools: ToolInstaller
    @State private var selection: SidebarItem? = .download
    @State private var trashCandidate: LibraryPlaylist?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("New Download", systemImage: "arrow.down.circle")
                    .badge(downloads.activeCount)
                    .tag(SidebarItem.download)

                Section("Library") {
                    if library.playlists.isEmpty {
                        Text("Your downloads will appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.playlists) { p in
                        SidebarPlaylistRow(playlist: p)
                            .tag(SidebarItem.playlist(p.folder))
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.open(p.folder) }
                                Divider()
                                Button("Move to Trash…", role: .destructive) { trashCandidate = p }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            Group {
                switch selection {
                case .playlist(let url):
                    if let p = library.playlist(at: url) {
                        PlaylistView(playlist: p).id(url)
                    } else {
                        ContentUnavailableView("Playlist Not Found", systemImage: "music.note.list",
                                               description: Text("It may have been moved or deleted in Finder."))
                    }
                default:
                    NewDownloadView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil { NowPlayingBar() }
            }
        }
        .onChange(of: downloads.openRequest) { _, url in
            if let url { selection = .playlist(url); downloads.openRequest = nil }
        }
        .onAppear {
            // Used when taking README screenshots.
            if ProcessInfo.processInfo.environment["RESONANCE_OPEN_FIRST"] != nil, let first = library.playlists.first {
                selection = .playlist(first.folder)
            }
        }
        .task {
            // First launch: fetch the two helper tools automatically. Later launches: keep yt-dlp fresh.
            await tools.installIfNeeded()
            tools.updateYtdlpIfStale()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reload()
        }
        .confirmationDialog("Move “\(trashCandidate?.manifest.title ?? "")” to the Trash?",
                            isPresented: Binding(get: { trashCandidate != nil }, set: { if !$0 { trashCandidate = nil } }),
                            presenting: trashCandidate) { p in
            Button("Move to Trash", role: .destructive) {
                if selection == .playlist(p.folder) { selection = .download }
                library.moveToTrash(p)
            }
        } message: { _ in
            Text("The playlist folder and all of its songs will be moved to the Trash.")
        }
    }
}

private struct SidebarPlaylistRow: View {
    let playlist: LibraryPlaylist
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: playlist.coverURL, size: 30, corner: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.manifest.title).lineLimit(1)
                Text("\(playlist.manifest.tracks.count) \(playlist.manifest.tracks.count == 1 ? "song" : "songs") · \(playlist.manifest.format.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct NewDownloadView: View {
    @EnvironmentObject private var downloads: DownloadCenter
    @EnvironmentObject private var tools: ToolInstaller
    @AppStorage("defaultFormat") private var formatRaw = AudioFormat.original.rawValue
    @State private var link = ""
    private var toolsMissing: Bool { tools.phase != .ready }

    private var format: AudioFormat { AudioFormat(rawValue: formatRaw) ?? .original }
    private var valid: Bool { DownloadCenter.isSoundCloudLink(link) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Download").font(.system(size: 30, weight: .bold))
                    Text("Paste a link to a public SoundCloud playlist or song.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if toolsMissing { SetupCard() }

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(.secondary)
                        TextField("https://soundcloud.com/artist/sets/playlist", text: $link)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .onSubmit(start)
                        if link.isEmpty {
                            Button("Paste") { link = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                                .controlSize(.small)
                        } else {
                            Button { link = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(!link.isEmpty && !valid ? Color.red.opacity(0.6) : Color.primary.opacity(0.12)))

                    if !link.isEmpty && !valid {
                        Label("That doesn't look like a SoundCloud link.", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Format").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            ForEach(AudioFormat.allCases) { f in
                                FormatTile(format: f, selected: f == format) { formatRaw = f.rawValue }
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Label("Saves to \(Paths.displayLibraryPath) › Playlist name — date", systemImage: "folder")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: start) {
                            Label("Download", systemImage: "arrow.down").frame(minWidth: 110)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!valid || toolsMissing)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .card()

                if !downloads.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Activity").font(.title2.bold())
                            Spacer()
                            if downloads.jobs.contains(where: { !$0.isActive }) {
                                Button("Clear Finished") { downloads.clearFinished() }.buttonStyle(.link)
                            }
                        }
                        ForEach(downloads.jobs) { JobCard(job: $0) }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("New Download")
    }

    private func start() {
        guard valid, !toolsMissing else { return }
        downloads.start(url: link, format: format)
        link = ""
    }
}

private struct FormatTile: View {
    let format: AudioFormat
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(format.title).font(.headline)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Brand.accent : Color.secondary.opacity(0.5))
                }
                Text(format.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Brand.accent.opacity(0.12) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct JobCard: View {
    @EnvironmentObject private var downloads: DownloadCenter
    @ObservedObject var job: DownloadJob

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtworkView(url: job.coverURL, size: 56, corner: 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(job.title).font(.headline).lineLimit(1)
                    status
                }
                Text(job.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if job.isActive {
                    ProgressView(value: job.fraction)
                        .progressViewStyle(.linear)
                        .animation(.easeOut(duration: 0.3), value: job.fraction)
                }
                if !job.failures.isEmpty {
                    DisclosureGroup("\(job.failures.count) \(job.failures.count == 1 ? "song" : "songs") skipped") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(job.failures.enumerated()), id: \.offset) { _, f in
                                Text(f).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .card()
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        if job.isActive {
            Button("Cancel") { downloads.cancel(job) }
        } else if let folder = job.folder, FileManager.default.fileExists(atPath: folder.path) {
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(folder) } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
                Button("Open") { downloads.openRequest = folder }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SetupCard: View {
    @EnvironmentObject private var tools: ToolInstaller

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isFailed ? Color.orange : Brand.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                switch tools.phase {
                case .working(let step, let progress):
                    Text("Getting Resonance Studio ready").font(.headline)
                    Text("One-time setup: downloading the free audio tools it uses (about 95 MB). This only happens once.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: progress).progressViewStyle(.linear)
                    Text(step).font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text("Setup didn't finish").font(.headline)
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { Task { await tools.install(force: false) } }
                        .buttonStyle(.borderedProminent)
                default:
                    Text("Getting Resonance Studio ready").font(.headline)
                    Text("One-time setup: downloading the free audio tools it uses (about 95 MB).")
                        .foregroundStyle(.secondary)
                    ProgressView().controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var isFailed: Bool { if case .failed = tools.phase { return true } else { return false } }
    private var icon: String { isFailed ? "exclamationmark.triangle.fill" : "arrow.down.circle.dotted" }
}

struct NowPlayingBar: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        if let item = player.current {
            HStack(spacing: 14) {
                ArtworkView(url: item.artwork, size: 40, corner: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: 260, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 18) {
                    Button(action: player.previous) { Image(systemName: "backward.fill") }
                    Button(action: player.toggle) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                    .keyboardShortcut(.space, modifiers: [.command])
                    Button(action: player.next) { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Text(Fmt.duration(player.time)).monospacedDigit()
                    Slider(value: Binding(get: { player.time }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 1))
                        .controlSize(.small)
                        .frame(width: 200)
                    Text(Fmt.duration(player.duration)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(action: player.stop) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}
