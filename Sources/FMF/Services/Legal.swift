import SwiftUI

enum Legal {
    /// Bump this whenever TERMS.md changes; everyone is asked to accept again.
    static let version = "2026-11-18"

    static var termsMarkdown: String {
        if let url = Bundle.main.url(forResource: "Terms", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return "The Terms of Use could not be loaded. Please reinstall FMF."
    }
}

/// Renders the small subset of Markdown used by TERMS.md.
struct LegalText: View {
    private enum Block: Hashable {
        case title(String), heading(String), paragraph(String), bullet(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        for raw in Legal.termsMarkdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush() }
            else if line.hasPrefix("## ") { flush(); result.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { flush(); result.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { flush(); result.append(.bullet(String(line.dropFirst(2)))) }
            else { paragraph.append(line) }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks, id: \.self) { block in
                switch block {
                case .title(let s):
                    Text(s).font(.title2.bold())
                case .heading(let s):
                    Text(s).font(.headline).padding(.top, 8)
                case .paragraph(let s):
                    Text(inline(s)).fixedSize(horizontal: false, vertical: true)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(s)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
