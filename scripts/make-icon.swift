// Generates Resources/AppIcon.icns from code, so the icon is reviewable in a diff and
// regenerable at any size rather than being an opaque binary blob.
//
//   swift scripts/make-icon.swift        (or: make icon)
//
// The artwork is original geometry. SF Symbols are deliberately not used: Apple's licence permits
// them in an interface but forbids them in an app icon, and `camera.viewfinder` — which the menu
// bar item does use — would be exactly that.
//
// The motif is the thing Snapper does that macOS's own screenshot tool does not: a captured image,
// behind, and the words taken out of it, in front. Two distinct objects rather than one, because a
// single card with a picture and some lines in it reads as a document or an article — which is what
// the app is *not*.

import SwiftUI
import AppKit

// MARK: - Geometry
//
// Everything is expressed in Apple's 1024pt icon grid. The rounded rectangle is 824pt inside a
// 1024pt canvas — the proportions macOS has used since Big Sur — so Snapper sits at the same
// visual weight as the system's own icons in the Dock and in Finder.

private let canvas: CGFloat = 1024
private let plateInset: CGFloat = 100
private let plateSide = canvas - plateInset * 2      // 824
private let plateRadius: CGFloat = 185.4             // Apple's continuous-corner radius at 824pt

private let cardWidth: CGFloat = 340
private let cardHeight: CGFloat = 268
private let cardRadius: CGFloat = 42

// Card placement. The overlap is set so the whole photo mark stays unoccluded: the front card's
// leading edges land at local x>52, y>66 in the back card's own coordinates, and the mark at
// scale 0.6 spans x[-78,88] y[-53,58] — clear of the corner where those two constraints meet.
// Tightening the overlap past this clips the hill into a meaningless wedge.
private let backCardOffset = CGSize(width: -118, height: -104)
private let frontCardOffset = CGSize(width: 104, height: 96)
private let photoMarkScale: CGFloat = 0.60

/// Ink for text on the white card — the darker end of the plate gradient, so it reads as the same
/// family rather than an unrelated blue.
private let ink = Color(red: 0.07, green: 0.32, blue: 0.85)

/// The hill half of the photo mark.
///
/// A `Shape` rather than a bare `Path` for one reason that cost real time: a `Path` built from
/// literal coordinates is laid out from the view's *top-left origin*, while `Circle().offset()`
/// moves relative to the view's *centre*. Mixing the two put the sun in the middle of the card and
/// the hill off the top-left corner, where clipping ate it — which looked like a clipping problem
/// and was actually a coordinate-space one. Resolving against `rect.mid` centres it honestly.
private struct Hill: Shape {
    var scale: CGFloat
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + x * scale, y: rect.midY + y * scale)
        }
        var path = Path()
        path.move(to: point(-130, 86))
        path.addLine(to: point(-16, -18))
        path.addLine(to: point(62, 52))
        path.addLine(to: point(108, 10))
        path.addLine(to: point(140, 86))
        path.closeSubpath()
        return path
    }
}

/// The universal "this is a picture" mark: a sun and a hill.
private struct PhotoMark: View {
    var scale: CGFloat = photoMarkScale
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 54 * scale, height: 54 * scale)
                .offset(x: -96 * scale, y: -62 * scale)
            Hill(scale: scale)
                .fill(.white)
                .offset(x: 6 * scale, y: 10 * scale)
        }
    }
}

private struct TextLines: View {
    var body: some View {
        // Ragged widths, the way real text sets. Flush left — the alignment on VStack is what does
        // it, not the frame's: a VStack centres its children regardless of the frame around it, and
        // centred ragged bars read as decoration rather than as a paragraph.
        VStack(alignment: .leading, spacing: 24) {
            ForEach([212, 166, 114] as [CGFloat], id: \.self) { width in
                Capsule(style: .continuous)
                    .fill(ink)
                    .frame(width: width, height: 34)
            }
        }
        .frame(width: 212, alignment: .leading)
    }
}

private struct IconArt: View {
    var body: some View {
        ZStack {
            // The plate. Two blues rather than one flat fill: macOS icons are lit from above, and
            // a top-lighter gradient is what stops it looking like a printed sticker.
            RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.60, blue: 0.99),
                            Color(red: 0.07, green: 0.32, blue: 0.85),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // A bright hairline along the top edge, the way a glossy surface catches light.
                .overlay(
                    RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 5
                        )
                )
                .frame(width: plateSide, height: plateSide)

            // The captured image. Translucent with a bright rim so it reads as glass sitting on the
            // plate — present, but clearly behind the result.
            ZStack {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(.white.opacity(0.34))
                PhotoMark()
            }
            .frame(width: cardWidth, height: cardHeight)
            // Clipped before the rim is drawn: without this the hill escapes the card, and at some
            // offsets it escapes the plate entirely.
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 17)
            )
            .rotationEffect(.degrees(-8))
            .offset(x: backCardOffset.width, y: backCardOffset.height)

            // The words that came out of it. Opaque, square to the grid, in front — the result, not
            // the source.
            ZStack {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(.white)
                TextLines()
            }
            .frame(width: cardWidth, height: cardHeight)
            .offset(x: frontCardOffset.width, y: frontCardOffset.height)
        }
        .frame(width: canvas, height: canvas)
    }
}

// MARK: - Rendering

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Every size is rendered from the vector art rather than downsampled from one big PNG, so the
/// 16pt icon is as crisp as the 1024pt one.
@MainActor
func renderPNG(side: CGFloat, to url: URL) throws {
    let renderer = ImageRenderer(content: IconArt())
    renderer.scale = side / canvas
    renderer.isOpaque = false

    guard let cgImage = renderer.cgImage else {
        throw Failure("ImageRenderer produced no image at \(Int(side))pt")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: side, height: side)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw Failure("could not encode PNG at \(Int(side))pt")
    }
    try data.write(to: url)
}

// The set macOS expects in an .icns. Each logical size needs both its 1x and 2x pixel size.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",     32),
    ("icon_32x32",      32),  ("icon_32x32@2x",     64),
    ("icon_128x128",   128),  ("icon_128x128@2x",  256),
    ("icon_256x256",   256),  ("icon_256x256@2x",  512),
    ("icon_512x512",   512),  ("icon_512x512@2x", 1024),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

try MainActor.assumeIsolated {
    for variant in variants {
        let url = iconset.appendingPathComponent("\(variant.name).png")
        try renderPNG(side: variant.pixels, to: url)
        print("  \(variant.name).png  \(Int(variant.pixels))×\(Int(variant.pixels))")
    }
    // A standalone 1024 for anywhere a PNG is wanted — a README, a release page, a website.
    try renderPNG(side: 1024, to: root.appendingPathComponent("Resources/AppIcon.png"))
}
print("wrote \(iconset.path)")
