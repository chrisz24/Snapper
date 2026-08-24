// Generates Resources/AppIcon.icns from code, so the icon is reviewable in a diff and
// regenerable at any size rather than being an opaque binary blob.
//
//   swift scripts/make-icon.swift        (or: make icon)
//
// The artwork is original geometry. SF Symbols are deliberately not used: Apple's licence permits
// them in an interface but forbids them in an app icon, and `camera.viewfinder` — which the menu
// bar item does use — would be exactly that.
//
// The motif is what distinguishes Snapper from macOS's own screenshot tool: a capture frame
// (the four corner marks everyone reads as "select a region") wrapped around lines of text
// (recognition). At 16pt the text lines merge into a block and the frame still reads.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Geometry
//
// Everything is expressed in Apple's 1024pt icon grid. The rounded rectangle is 824pt inside a
// 1024pt canvas — the proportions macOS has used since Big Sur — so Snapper sits at the same
// visual weight as the system's own icons in the Dock and in Finder.

private let canvas: CGFloat = 1024
private let plateInset: CGFloat = 100
private let plateSide = canvas - plateInset * 2      // 824
private let plateRadius: CGFloat = 185.4             // Apple's continuous-corner radius at 824pt

private let frameSide: CGFloat = 496                 // capture frame
private let armLength: CGFloat = 132                 // length of each corner arm
private let frameStroke: CGFloat = 36

private let barHeight: CGFloat = 48
private let barSpacing: CGFloat = 40
private let barWidths: [CGFloat] = [400, 312, 224]   // ragged, the way real text sets
private let textBlockWidth: CGFloat = 400            // ~48pt clear inside each frame edge

/// The four corner marks. Drawn as arms rather than a closed rectangle because an unbroken box
/// reads as a window or a photo frame; the gaps are what make it read as *selecting*.
private struct CaptureFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let box = CGRect(
            x: rect.midX - frameSide / 2,
            y: rect.midY - frameSide / 2,
            width: frameSide,
            height: frameSide
        )
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: box.minX, y: box.minY + armLength))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX + armLength, y: box.minY))
        // Top-right
        path.move(to: CGPoint(x: box.maxX - armLength, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + armLength))
        // Bottom-right
        path.move(to: CGPoint(x: box.maxX, y: box.maxY - armLength))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX - armLength, y: box.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: box.minX + armLength, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - armLength))
        return path
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

            // Recognized text, sitting inside the frame.
            //
            // The alignment on VStack is what matters, not the frame's: a VStack centres its
            // children regardless of how the frame around it is aligned, and centred ragged bars
            // read as decoration. Flush left is what makes them read as a paragraph of text.
            VStack(alignment: .leading, spacing: barSpacing) {
                ForEach(Array(barWidths.enumerated()), id: \.offset) { _, width in
                    Capsule(style: .continuous)
                        .fill(.white)
                        .frame(width: width, height: barHeight)
                }
            }
            .frame(width: textBlockWidth, alignment: .leading)

            CaptureFrame()
                .stroke(.white, style: StrokeStyle(lineWidth: frameStroke, lineCap: .round))
        }
        .frame(width: canvas, height: canvas)
    }
}

// MARK: - Rendering

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

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
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
