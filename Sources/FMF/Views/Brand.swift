import AppKit
import SwiftUI

enum Brand {
    static let name = "FMF"
    static let fullName = "Free Music Foundation"
    static let accent = Color(red: 0.43, green: 0.36, blue: 0.98)
    static let gradient = LinearGradient(
        colors: [Color(red: 0.33, green: 0.38, blue: 0.98), Color(red: 0.55, green: 0.33, blue: 0.96), Color(red: 0.80, green: 0.36, blue: 0.90)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// A waveform whose center bar is a download arrow.
struct WaveArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let heights: [CGFloat] = [0.30, 0.56, 0.36, 1.0, 0.36, 0.56, 0.30]
        let gapRatio: CGFloat = 0.62
        let barW = rect.width / (CGFloat(heights.count) + CGFloat(heights.count - 1) * gapRatio)
        let gap = barW * gapRatio
        for (i, h) in heights.enumerated() {
            let x = rect.minX + CGFloat(i) * (barW + gap)
            if i == heights.count / 2 {
                let cx = x + barW / 2
                let headH = rect.height * 0.30
                let headW = barW * 3.1
                let shaftBottom = rect.maxY - headH * 0.55
                let shaft = Path(roundedRect: CGRect(x: x, y: rect.minY, width: barW, height: shaftBottom - rect.minY),
                                 cornerSize: CGSize(width: barW / 2, height: barW / 2))
                // Rounded triangle: fill the triangle, then add a round-joined outline
                // of it, inset by half the stroke so the overall size stays the same.
                let round = barW * 0.55
                let inset = round / 2
                var head = Path()
                head.move(to: CGPoint(x: cx - headW / 2 + inset * 1.6, y: rect.maxY - headH + inset))
                head.addLine(to: CGPoint(x: cx + headW / 2 - inset * 1.6, y: rect.maxY - headH + inset))
                head.addLine(to: CGPoint(x: cx, y: rect.maxY - inset * 1.8))
                head.closeSubpath()
                let roundedHead = head.union(head.strokedPath(StrokeStyle(lineWidth: round, lineJoin: .round)))
                p.addPath(shaft.union(roundedHead))
            } else {
                let barH = rect.height * h
                p.addRoundedRect(in: CGRect(x: x, y: rect.midY - barH / 2 - rect.height * 0.06, width: barW, height: barH),
                                 cornerSize: CGSize(width: barW / 2, height: barW / 2))
            }
        }
        return p
    }
}

struct LogoMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.gradient)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            WaveArrow()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.01)
                .frame(width: size * 0.56, height: size * 0.50)
        }
        .frame(width: size, height: size)
    }
}

struct LogoLockup: View {
    var height: CGFloat = 96
    var body: some View {
        HStack(spacing: height * 0.28) {
            LogoMark(size: height)
                .shadow(color: .black.opacity(0.2), radius: height * 0.08, y: height * 0.04)
            VStack(alignment: .leading, spacing: height * 0.02) {
                Text("FMF").font(.system(size: height * 0.52, weight: .heavy, design: .rounded))
                Text("Free Music Foundation").font(.system(size: height * 0.2, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Exports the icon and logo images used by the build script and the README.
@MainActor
enum BrandRenderer {
    static func renderIcon(to url: URL) {
        let view = LogoMark(size: 824)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            .frame(width: 1024, height: 1024)
        write(view, to: url, scale: 1)
    }

    static func renderLogo(to url: URL) {
        let view = LogoLockup(height: 120)
            .padding(40)
            .environment(\.colorScheme, .light)
            .foregroundStyle(Color(white: 0.08))
        write(view, to: url, scale: 2)
    }

    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            return
        }
        try? data.write(to: url)
    }
}

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat? = nil
    var corner: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.14)], startPoint: .top, endPoint: .bottom))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: (size ?? 120) * 0.38, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .task(id: url) {
            guard let url else { image = nil; return }
            let px = Int(((size ?? 320) * 2).rounded())
            image = await ArtworkCache.shared.image(for: url, maxPixels: px)
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
