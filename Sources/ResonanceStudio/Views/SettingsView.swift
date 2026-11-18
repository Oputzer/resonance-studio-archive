import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AccountSettings().tabItem { Label("Account", systemImage: "person.crop.circle") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 340)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var library: Library
    @AppStorage("defaultFormat") private var formatRaw = AudioFormat.original.rawValue
    @State private var location = Paths.libraryRoot
    @State private var tools = Tools.locate()

    var body: some View {
        Form {
            Picker("Default format", selection: $formatRaw) {
                ForEach(AudioFormat.allCases) { Text($0.title).tag($0.rawValue) }
            }
            LabeledContent("Library folder") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack {
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(location)
                        }
                        Button("Change…", action: choose)
                    }
                }
            }
            LabeledContent("Helper tools") {
                if let tools {
                    Label("Ready (\(tools.ytdlp.deletingLastPathComponent().path))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    VStack(alignment: .trailing) {
                        Label("Missing", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                        Text("Run: brew install yt-dlp ffmpeg").font(.caption).textSelection(.enabled)
                        Button("Check Again") { tools = Tools.locate() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = location
        if panel.runModal() == .OK, let url = panel.url {
            Paths.libraryRoot = url
            location = url
            library.reload()
        }
    }
}

private struct AccountSettings: View {
    @EnvironmentObject private var account: Account
    @State private var showTerms = false

    var body: some View {
        Form {
            LabeledContent("Signed in as", value: account.email ?? "—")
            LabeledContent("Terms accepted") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(account.acceptedTermsAt?.formatted(date: .long, time: .shortened) ?? "—")
                        .foregroundStyle(.secondary)
                    Button("View Terms of Use") { showTerms = true }
                }
            }
            if !Backend.isConfigured {
                Text("Test build: not connected to the Resonance Studio server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Sign Out", role: .destructive) { account.signOut() }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showTerms) { TermsSheet() }
    }
}

private struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 84).shadow(color: Brand.accent.opacity(0.3), radius: 12, y: 5)
            Text(Brand.fullName).font(.title.bold())
            Text(Brand.tagline).foregroundStyle(.secondary)
            Text(version).font(.caption).foregroundStyle(.tertiary)
            Text("Built with yt-dlp and FFmpeg. Song details from Apple's iTunes Search API.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
