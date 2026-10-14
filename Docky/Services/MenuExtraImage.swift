import AppKit

enum MenuExtraImage {
    /// Keep colored state indicators while adapting neutral glyph pixels to the taskbar.
    static func adaptingMonochrome(_ image: NSImage, to color: NSColor) -> NSImage {
        guard !image.isTemplate, let foreground = color.usingColorSpace(.deviceRGB),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: source.width, height: source.height,
                                          bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            let target = [foreground.redComponent, foreground.greenComponent, foreground.blueComponent]
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let opacity = CGFloat(bytes[offset + 3]) / 255
                guard opacity > 0 else { continue }
                let channels = (0..<3).map { CGFloat(bytes[offset + $0]) / (255 * opacity) }
                guard (channels.max() ?? 0) - (channels.min() ?? 0) < 0.2 else { continue }
                for channel in 0..<3 { bytes[offset + channel] = UInt8((target[channel] * opacity * 255).rounded()) }
            }
            guard let result = context.makeImage() else { return image }
            return NSImage(cgImage: result, size: image.size)
        }
    }

    /// Remove a flat menu-bar backdrop from captured pixels. Nonuniform backgrounds
    /// are preserved rather than erasing custom artwork or guessing its shape.
    static func make(_ source: CGImage, size: CGSize) -> NSImage {
        guard source.width > 2, source.height > 2 else { return NSImage(cgImage: source, size: size) }
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return NSImage(cgImage: source, size: size) }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            let corners = [0, (width - 1) * 4, (height - 1) * width * 4, (width * height - 1) * 4]
            let background = (0..<3).map { channel in
                corners.map { Double(bytes[$0 + channel]) / 255 }.sorted()[2]
            }
            guard corners.allSatisfy({ offset in
                bytes[offset + 3] == 255 && (0..<3).allSatisfy {
                    abs(Double(bytes[offset + $0]) / 255 - background[$0]) < 0.04
                }
            }) else { return NSImage(cgImage: source, size: size) }
            let colored = removeBackdrop(bytes, background: background)
            guard let result = context.makeImage() else { return NSImage(cgImage: source, size: size) }
            let image = NSImage(cgImage: result, size: size)
            image.isTemplate = !colored
            return image
        }
    }

    private static func removeBackdrop(_ pixels: UnsafeMutableBufferPointer<UInt8>,
                                       background: [Double]) -> Bool {
        var colored = false
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let values = (0..<3).map { Double(pixels[offset + $0]) / 255 }
            let alpha = (0..<3).map { channel -> Double in
                let delta = values[channel] - background[channel]
                let range = delta > 0 ? 1 - background[channel] : background[channel]
                return abs(delta) / max(0.01, range)
            }.max() ?? 0
            let opacity = alpha < 0.1 ? 0 : min(1, alpha)
            let foreground = (0..<3).map {
                max(0, min(1, (values[$0] - background[$0] * (1 - opacity)) / max(0.01, opacity)))
            }
            if opacity > 0.2, (foreground.max() ?? 0) - (foreground.min() ?? 0) > 0.2 { colored = true }
            for channel in 0..<3 { pixels[offset + channel] = UInt8((foreground[channel] * opacity * 255).rounded()) }
            pixels[offset + 3] = UInt8((opacity * 255).rounded())
        }
        return colored
    }
}
