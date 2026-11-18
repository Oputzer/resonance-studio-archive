import Foundation

/// Adds an ID3v2.3 tag (title, artist, album, track number and cover art) to a WAV file
/// as an "id3 " RIFF chunk. FFmpeg can't put artwork in WAV, but DJ software and most
/// tag-aware players read this chunk.
enum WAVTagger {
    struct Tags {
        var title: String?
        var artist: String?
        var album: String?
        var track: Int?
        var artwork: Data?
    }

    static func embed(_ tags: Tags, into url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 12), header.count == 12,
              header.prefix(4) == Data("RIFF".utf8), header[8..<12] == Data("WAVE".utf8) else {
            throw AppError("Not a WAV file.")
        }
        if try hasID3Chunk(handle) { return }

        var frames = Data()
        if let t = tags.title { frames += textFrame("TIT2", t) }
        if let a = tags.artist { frames += textFrame("TPE1", a) }
        if let a = tags.album { frames += textFrame("TALB", a) }
        if let n = tags.track { frames += textFrame("TRCK", String(n)) }
        if let art = tags.artwork { frames += pictureFrame(art) }
        guard !frames.isEmpty else { return }

        var tag = Data("ID3".utf8) + Data([3, 0, 0]) + synchsafe(frames.count)
        tag += frames

        var chunk = Data("id3 ".utf8) + le32(tag.count) + tag
        if tag.count % 2 == 1 { chunk.append(0) }   // RIFF chunks are word aligned

        let end = try handle.seekToEnd()
        try handle.write(contentsOf: chunk)
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: le32(Int(end) + chunk.count - 8))
    }

    private static func hasID3Chunk(_ handle: FileHandle) throws -> Bool {
        var offset: UInt64 = 12
        let size = try handle.seekToEnd()
        while offset + 8 <= size {
            try handle.seek(toOffset: offset)
            guard let head = try handle.read(upToCount: 8), head.count == 8 else { break }
            let id = String(decoding: head.prefix(4), as: UTF8.self)
            if id.lowercased() == "id3 " { return true }
            let length = UInt64(head[4]) | UInt64(head[5]) << 8 | UInt64(head[6]) << 16 | UInt64(head[7]) << 24
            offset += 8 + length + (length % 2)
        }
        return false
    }

    /// Text frame encoded as UTF-16 with a byte-order mark, the most widely supported form in ID3v2.3.
    private static func textFrame(_ id: String, _ text: String) -> Data {
        var body = Data([1, 0xFF, 0xFE])
        body += text.data(using: .utf16LittleEndian) ?? Data()
        return frame(id, body)
    }

    private static func pictureFrame(_ image: Data) -> Data {
        let png = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
        var body = Data([0])                                    // Latin-1 text encoding
        body += Data((png ? "image/png" : "image/jpeg").utf8) + Data([0])
        body += Data([3])                                       // picture type: front cover
        body += Data([0])                                       // empty description
        body += image
        return frame("APIC", body)
    }

    private static func frame(_ id: String, _ body: Data) -> Data {
        Data(id.utf8) + be32(body.count) + Data([0, 0]) + body
    }

    private static func be32(_ n: Int) -> Data {
        Data([UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
    }

    private static func le32(_ n: Int) -> Data {
        Data([UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)])
    }

    private static func synchsafe(_ n: Int) -> Data {
        Data([UInt8((n >> 21) & 0x7F), UInt8((n >> 14) & 0x7F), UInt8((n >> 7) & 0x7F), UInt8(n & 0x7F)])
    }
}
