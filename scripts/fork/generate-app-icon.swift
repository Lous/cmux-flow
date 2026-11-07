// Renders the cmux-flow fork's app icon: a git branch graph on a teal
// squircle, deliberately distinct from cmux's blue chevron on white.
//
// Usage: swift scripts/fork/generate-app-icon.swift <output-dir>
// Writes icon-light.png and icon-dark.png (1024x1024, macOS icon grid);
// scripts/fork/apply-app-icon.sh resizes them into the asset catalog.

import AppKit
import CoreGraphics

struct Palette {
    let top: CGColor
    let bottom: CGColor
    let glyph: CGColor
    let nodeFill: CGColor
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let light = Palette(top: color(0x14B08F), bottom: color(0x0A5A4B), glyph: color(0xF2FFFA), nodeFill: color(0x0C6E5B))
let dark = Palette(top: color(0x10443A), bottom: color(0x05201B), glyph: color(0x86F7D4), nodeFill: color(0x08312A))

func render(_ palette: Palette, to url: URL) throws {
    let size = 1024
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "icon", code: 1) }

    // Draw in a top-left-origin space.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)

    // macOS icon grid: an 824pt squircle centered on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, alpha: 0.28))
    context.addPath(tilePath)
    context.setFillColor(palette.bottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [palette.top, palette.bottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()

    // Git branch graph: a trunk with a branch that forks off and rejoins.
    let trunkX: CGFloat = 410
    let branchX: CGFloat = 630
    let topNode = CGPoint(x: trunkX, y: 300)
    let bottomNode = CGPoint(x: trunkX, y: 724)
    let branchNode = CGPoint(x: branchX, y: 400)
    let lineWidth: CGFloat = 50
    let nodeRadius: CGFloat = 64

    context.setStrokeColor(palette.glyph)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)

    let trunk = CGMutablePath()
    trunk.move(to: topNode)
    trunk.addLine(to: bottomNode)
    context.addPath(trunk)
    context.strokePath()

    let branch = CGMutablePath()
    branch.move(to: CGPoint(x: trunkX, y: 650))
    branch.addCurve(
        to: CGPoint(x: branchX, y: 470),
        control1: CGPoint(x: trunkX, y: 540),
        control2: CGPoint(x: branchX, y: 600)
    )
    branch.addLine(to: branchNode)
    context.addPath(branch)
    context.strokePath()

    for center in [topNode, bottomNode, branchNode] {
        let circle = CGRect(x: center.x - nodeRadius, y: center.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
        context.setFillColor(palette.nodeFill)
        context.fillEllipse(in: circle)
        context.setLineWidth(lineWidth * 0.85)
        context.strokeEllipse(in: circle)
    }

    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try data.write(to: url)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try render(light, to: outputDirectory.appendingPathComponent("icon-light.png"))
try render(dark, to: outputDirectory.appendingPathComponent("icon-dark.png"))
print("wrote icon-light.png and icon-dark.png to \(outputDirectory.path)")
