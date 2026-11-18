import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            MainActor.assumeIsolated { BrandRenderer.renderIcon(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-logo"), i + 1 < args.count {
            MainActor.assumeIsolated { BrandRenderer.renderLogo(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        if args.contains("--selftest-tools") {
            MainActor.assumeIsolated { SelfTest.installTools() }
            RunLoop.main.run()
        }
        if let i = args.firstIndex(of: "--selftest"), i + 2 < args.count {
            MainActor.assumeIsolated { SelfTest.run(url: args[i + 1], format: args[i + 2]) }
            RunLoop.main.run()
        }
        ResonanceApp.main()
    }
}

struct ResonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var account = Account()
    @StateObject private var library: Library = {
        Paths.migrateLegacyLibrary()
        return Library()
    }()
    @StateObject private var downloads = DownloadCenter()
    @StateObject private var player = Player()
    @StateObject private var tools = ToolInstaller()

    var body: some Scene {
        Window("Resonance Studio", id: "main") {
            RootView()
                .environmentObject(account)
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(player)
                .environmentObject(tools)
                .tint(Brand.accent)
                .frame(minWidth: 940, idealWidth: 1120, maxWidth: .infinity,
                       minHeight: 640, idealHeight: 740, maxHeight: .infinity)
                .onAppear {
                    // The library folder (Desktop › Resonance Studio by default) always exists.
                    Paths.migrateLegacyLibrary()
                    try? FileManager.default.createDirectory(at: Paths.libraryRoot, withIntermediateDirectories: true)
                    downloads.attach(library: library)
                    library.enrichAllPending()
                }
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Resonance Studio Terms of Use") { NotificationCenter.default.post(name: .showTerms, object: nil) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(account)
                .environmentObject(library)
                .environmentObject(tools)
                .tint(Brand.accent)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let showTerms = Notification.Name("ResonanceShowTerms")
}
