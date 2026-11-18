import Foundation

enum Paths {
    private static let libraryKey = "libraryPath"

    static var defaultLibraryRoot: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FMF", isDirectory: true)
    }

    static var libraryRoot: URL {
        get {
            if let path = ProcessInfo.processInfo.environment["FMF_LIBRARY"]?.nilIfBlank {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            if let path = UserDefaults.standard.string(forKey: libraryKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultLibraryRoot
        }
        set { UserDefaults.standard.set(newValue.path, forKey: libraryKey) }
    }

    static var displayLibraryPath: String {
        let root = libraryRoot.standardizedFileURL
        if root == defaultLibraryRoot.standardizedFileURL { return "Desktop › FMF" }
        return root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FMF", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Makes a playlist title safe to use as a folder or file name.
    static func safeName(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.components(separatedBy: .controlCharacters).joined()
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if s.count > 100 { s = String(s.prefix(100)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Untitled" : s
    }
}
