import AppKit
import SwiftUI

enum Brand {
    static let name = "Resonance"
    static let fullName = "Resonance Studio"
    static let tagline = "Music that stays with you."
    static let accent = Color(red: 0.47, green: 0.30, blue: 0.95)
    static let gradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.27, blue: 0.86), Color(red: 0.52, green: 0.25, blue: 0.93), Color(red: 0.93, green: 0.36, blue: 0.62)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// A waveform inside a glowing core, with rings of sound spreading outward.
struct ResonanceGlyph: View {
    var size: CGFloat
    var body: some View {
        let ring = size * 0.034
        ZStack {
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: ring).frame(width: size * 0.86, height: size * 0.86)
            Circle().strokeBorder(.white.opacity(0.45), lineWidth: ring).frame(width: size * 0.68, height: size * 0.68)
            Circle().fill(.white).frame(width: size * 0.48, height: size * 0.48)
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.015)
            HStack(spacing: size * 0.032) {
                ForEach(Array([0.34, 0.66, 1.0, 0.66, 0.34].enumerated()), id: \.offset) { _, h in
                    Capsule().frame(width: size * 0.042, height: size * 0.24 * h)
                }
            }
            .foregroundStyle(Brand.gradient)
        }
        .frame(width: size, height: size)
    }
}

struct LogoMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.gradient)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: size * 0.5))
            ResonanceGlyph(size: size * 0.82)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

struct LogoLockup: View {
    var height: CGFloat = 96
    var body: some View {
        HStack(spacing: height * 0.28) {
            LogoMark(size: height)
                .shadow(color: .black.opacity(0.2), radius: height * 0.08, y: height * 0.04)
            VStack(alignment: .leading, spacing: height * 0.02) {
                Text("Resonance").font(.system(size: height * 0.48, weight: .bold, design: .rounded))
                Text("STUDIO").font(.system(size: height * 0.17, weight: .semibold)).tracking(height * 0.09).foregroundStyle(.secondary)
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
