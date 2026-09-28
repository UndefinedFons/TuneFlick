import AppKit

enum StatusBarIconFactory {
    private static let sourcePixels = 96
    private static let targetPixels = 36
    private static let targetPoints: CGFloat = 18
    private static let bytesPerPixel = 4
    private static let bitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    )

    static func makeIcon() -> NSImage? {
        guard let sourceURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
              let sourceImage = NSImage(contentsOf: sourceURL),
              let sourceCGImage = sourceImage.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ),
              let sourceRGBA = render(sourceCGImage, width: sourcePixels, height: sourcePixels),
              let maskPixels = makeDarkMarkMask(from: sourceRGBA),
              let sourceBounds = bounds(of: maskPixels),
              let maskCGImage = makeImage(from: maskPixels, width: sourcePixels, height: sourcePixels)
        else {
            return nil
        }

        let inset: CGFloat = 2
        let available = CGFloat(targetPixels) - inset * 2
        let scale = min(available / sourceBounds.width, available / sourceBounds.height)
        let targetSize = CGSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
        let targetRect = CGRect(
            x: (CGFloat(targetPixels) - targetSize.width) / 2,
            y: (CGFloat(targetPixels) - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let drawRect = CGRect(
            x: targetRect.minX - sourceBounds.minX * scale,
            y: targetRect.minY - sourceBounds.minY * scale,
            width: CGFloat(sourcePixels) * scale,
            height: CGFloat(sourcePixels) * scale
        )

        var iconPixels = Data(repeating: 0, count: targetPixels * targetPixels * bytesPerPixel)
        let rendered = iconPixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let address = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: targetPixels,
                      height: targetPixels,
                      bitsPerComponent: 8,
                      bytesPerRow: targetPixels * bytesPerPixel,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(maskCGImage, in: drawRect)
            return true
        }

        guard rendered,
              thickenAlpha(in: &iconPixels, width: targetPixels, height: targetPixels, radius: 1),
              let iconCGImage = makeImage(from: iconPixels, width: targetPixels, height: targetPixels)
        else {
            return nil
        }

        let icon = NSImage(
            cgImage: iconCGImage,
            size: NSSize(width: targetPoints, height: targetPoints)
        )
        icon.isTemplate = true
        return icon
    }

    private static func render(_ image: CGImage, width: Int, height: Int) -> Data? {
        var pixels = Data(repeating: 0, count: width * height * bytesPerPixel)
        let rendered = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let address = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * bytesPerPixel,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return rendered ? pixels : nil
    }

    private static func thickenAlpha(
        in pixels: inout Data,
        width: Int,
        height: Int,
        radius: Int
    ) -> Bool {
        guard pixels.count == width * height * bytesPerPixel else { return false }
        let originalPixels = pixels

        pixels.withUnsafeMutableBytes { destinationBuffer in
            originalPixels.withUnsafeBytes { sourceBuffer in
                guard let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }

                for y in 0..<height {
                    for x in 0..<width {
                        var strongestAlpha: UInt8 = 0
                        for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                            for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                                let sampleOffset = (sampleY * width + sampleX) * bytesPerPixel + 3
                                strongestAlpha = max(strongestAlpha, source[sampleOffset])
                            }
                        }

                        let destinationOffset = (y * width + x) * bytesPerPixel + 3
                        destination[destinationOffset] = strongestAlpha
                    }
                }
            }
        }

        return true
    }

    private static func makeDarkMarkMask(from pixels: Data) -> Data? {
        guard pixels.count == sourcePixels * sourcePixels * bytesPerPixel else {
            return nil
        }

        var mask = Data(repeating: 0, count: pixels.count)
        for y in 0..<sourcePixels {
            for x in 0..<sourcePixels {
                let offset = (y * sourcePixels + x) * bytesPerPixel
                let alpha = CGFloat(pixels[offset + 3]) / 255
                guard alpha > 0.02 else { continue }

                let red = min(1, CGFloat(pixels[offset]) / 255 / alpha)
                let green = min(1, CGFloat(pixels[offset + 1]) / 255 / alpha)
                let blue = min(1, CGFloat(pixels[offset + 2]) / 255 / alpha)
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let opacity = max(0, min(1, (0.64 - luminance) / 0.32)) * alpha
                guard opacity > 0.02 else { continue }

                mask[offset + 3] = UInt8((opacity * 255).rounded())
            }
        }

        return mask
    }

    private static func bounds(of pixels: Data) -> CGRect? {
        var minX = sourcePixels
        var minY = sourcePixels
        var maxX = -1
        var maxY = -1

        for y in 0..<sourcePixels {
            for x in 0..<sourcePixels {
                let offset = (y * sourcePixels + x) * bytesPerPixel
                guard pixels[offset + 3] > 5 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private static func makeImage(from pixels: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
