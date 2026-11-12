import AppKit

let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let ratio = min(CGFloat(pixels) / source.size.width, CGFloat(pixels) / source.size.height)
        let width = source.size.width * ratio
        let height = source.size.height * ratio
        source.draw(in: NSRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2,
                               width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
