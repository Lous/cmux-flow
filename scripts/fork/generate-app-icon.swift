// Renders the cmux-flow fork's app icon on cmux's own background.
//
// The background (squircle shape, edge and gradient) is taken from cmux's
// original AppIconLight / AppIconDark artwork: the chevron and its glow are
// painted out with each row's background color, which is uniform across the
// row. The flow glyph is then drawn in the chevron's exact box (386x527 at
// center 538,521 on the 1024 canvas) with the same left-to-right cyan-to-indigo
// gradient and soft glow, so the proportions match the official icon.
//
// Usage: swift scripts/fork/generate-app-icon.swift <official-light.png> <official-dark.png> <output-dir> [A|B|C]
//   A  flow chevron: three steps linked along the chevron's silhouette (default)
//   B  double chevron: a translucent chevron trailing a solid one
//   C  fan-out: one step flowing into two
// Writes icon-light.png and icon-dark.png (1024x1024).

import AppKit
import CoreGraphics

let canvas = 1024
// The official chevron's bounding box, measured on the 1024 artwork.
let glyphBox = CGRect(x: 346, y: 258, width: 386, height: 527)

struct Style {
    let gradientStart: CGColor   // left edge of the glyph box
    let gradientEnd: CGColor     // right edge (the chevron's tip)
    let glow: CGColor
}

func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// Sampled from the official artwork.
let lightStyle = Style(gradientStart: srgb(93, 201, 249), gradientEnd: srgb(88, 108, 235), glow: srgb(70, 150, 245, 0.55))
let darkStyle = Style(gradientStart: srgb(3, 204, 254), gradientEnd: srgb(83, 109, 243), glow: srgb(40, 150, 250, 0.6))

func makeContext() -> CGContext {
    CGContext(
        data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

/// Loads the official artwork and paints out its chevron and glow.
func cleanBackground(from path: String) -> CGContext {
    let image = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let context = makeContext()
    context.draw(image, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: canvas * canvas * 4)
    // Bitmap memory is top-down: row 0 is the top of the icon.
    func index(_ x: Int, _ y: Int) -> Int { (y * canvas + x) * 4 }
    let clearX = 266...812   // glyph box plus its glow
    let clearY = 186...856
    for y in clearY {
        var samples: [[Int]] = []
        for x in Array(140...230) + Array(830...890) {
            let i = index(x, y)
            if pixels[i + 3] == 255 { samples.append([Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]) }
        }
        guard !samples.isEmpty else { continue }
        let median = (0..<3).map { channel in samples.map { $0[channel] }.sorted()[samples.count / 2] }
        for x in clearX {
            let i = index(x, y)
            guard pixels[i + 3] == 255 else { continue }
            pixels[i] = UInt8(median[0]); pixels[i + 1] = UInt8(median[1]); pixels[i + 2] = UInt8(median[2])
        }
    }
    return context
}

/// A rounded "step" card centered on `center`.
func step(_ center: CGPoint, size: CGFloat, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A straight connector of the given thickness with flat ends.
func bar(from a: CGPoint, to b: CGPoint, thickness: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: a)
    path.addLine(to: b)
    return path.copy(strokingWithWidth: thickness, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
}

/// The official chevron's outline, scaled to `box`, with arms `thickness` thick (vertical cut).
func chevron(in box: CGRect, verticalThickness: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let tip = CGPoint(x: box.maxX, y: box.midY)
    let slope = (box.midY - box.minY) / box.width
    let innerTipX = box.maxX - verticalThickness / slope
    path.move(to: CGPoint(x: box.minX, y: box.minY))
    path.addLine(to: tip)
    path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
    path.addLine(to: CGPoint(x: box.minX, y: box.maxY - verticalThickness))
    path.addLine(to: CGPoint(x: innerTipX, y: box.midY))
    path.addLine(to: CGPoint(x: box.minX, y: box.minY + verticalThickness))
    path.closeSubpath()
    return path
}

/// The glyph's shapes and their opacities, in top-left-origin canvas coordinates.
func glyph(_ design: String) -> [(CGPath, CGFloat)] {
    let box = glyphBox
    switch design {
    case "B":
        let front = CGRect(x: box.minX + 150, y: box.minY, width: box.width - 150, height: box.height)
        let back = CGRect(x: box.minX, y: box.minY + 40, width: box.width - 190, height: box.height - 80)
        return [(chevron(in: back, verticalThickness: 92), 0.42), (chevron(in: front, verticalThickness: 112), 1)]
    case "C":
        let size: CGFloat = 150
        let source = CGPoint(x: box.minX + size / 2, y: box.midY)
        let upper = CGPoint(x: box.maxX - size / 2, y: box.minY + size / 2)
        let lower = CGPoint(x: box.maxX - size / 2, y: box.maxY - size / 2)
        func curve(to target: CGPoint) -> CGPath {
            let path = CGMutablePath()
            path.move(to: source)
            path.addCurve(to: target,
                          control1: CGPoint(x: source.x + 150, y: source.y),
                          control2: CGPoint(x: target.x - 150, y: target.y))
            return path.copy(strokingWithWidth: 62, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        }
        return [(curve(to: upper), 1), (curve(to: lower), 1),
                (step(source, size: size, radius: 40), 1),
                (step(upper, size: size, radius: 40), 1),
                (step(lower, size: size, radius: 40), 1)]
    default: // "A"
        let size: CGFloat = 150
        let top = CGPoint(x: box.minX + size / 2, y: box.minY + size / 2)
        let tip = CGPoint(x: box.maxX - size / 2, y: box.midY)
        let bottom = CGPoint(x: box.minX + size / 2, y: box.maxY - size / 2)
        return [(bar(from: top, to: tip, thickness: 62), 1),
                (bar(from: bottom, to: tip, thickness: 62), 1),
                (step(top, size: size, radius: 40), 1),
                (step(tip, size: size, radius: 40), 1),
                (step(bottom, size: size, radius: 40), 1)]
    }
}

func render(background path: String, style: Style, design: String, to url: URL) throws {
    let context = cleanBackground(from: path)
    // Switch to a top-left origin to match the measurements above.
    context.translateBy(x: 0, y: CGFloat(canvas))
    context.scaleBy(x: 1, y: -1)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [style.gradientStart, style.gradientEnd] as CFArray,
                              locations: [0, 1])!
    for (shape, opacity) in glyph(design) {
        // Glow: the shape's soft halo, as on the official chevron.
        context.saveGState()
        context.setAlpha(opacity)
        context.setShadow(offset: .zero, blur: 34, color: style.glow)
        context.addPath(shape)
        context.setFillColor(style.gradientEnd)
        context.fillPath()
        context.restoreGState()
        // Body: the left-to-right gradient.
        context.saveGState()
        context.setAlpha(opacity)
        context.addPath(shape)
        context.clip()
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: glyphBox.minX, y: 0),
                                   end: CGPoint(x: glyphBox.maxX, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write("usage: generate-app-icon.swift <official-light.png> <official-dark.png> <output-dir> [A|B|C]\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
let design = arguments.count > 4 ? arguments[4] : "A"
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try render(background: arguments[1], style: lightStyle, design: design, to: output.appendingPathComponent("icon-light.png"))
try render(background: arguments[2], style: darkStyle, design: design, to: output.appendingPathComponent("icon-dark.png"))
print("wrote design \(design) to \(output.path)")
