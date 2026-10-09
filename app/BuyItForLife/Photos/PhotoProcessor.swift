import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

/// The stored versions of one photo, ready to save on an `Item`.
nonisolated struct ProcessedPhoto: Sendable, Equatable {
    var original: Data
    var originalThumbnail: Data
    var originalTint: String
    /// nil when Vision found no clear subject.
    var cutout: Data?
    var cutoutThumbnail: Data?
    var cutoutTint: String?
}

/// Turns a camera or library image into the stored photo versions: a 1200 px
/// original, an optional cutout with transparent background, 600 px
/// thumbnails, and a dark tint colour. Runs off the main actor.
nonisolated enum PhotoProcessor {
    static let fullSize: CGFloat = 1200
    static let thumbnailSize: CGFloat = 600

    @concurrent
    static func process(_ image: UIImage) async -> ProcessedPhoto? {
        guard let original = render(image, maxSide: fullSize, opaque: true),
              let originalData = encode(original, hasAlpha: false),
              let originalThumb = render(UIImage(cgImage: original), maxSide: thumbnailSize, opaque: true),
              let originalThumbData = encode(originalThumb, hasAlpha: false)
        else { return nil }

        var result = ProcessedPhoto(
            original: originalData,
            originalThumbnail: originalThumbData,
            originalTint: tintHex(for: original)
        )

        if let cutout = cutout(of: original),
           let cutoutData = encode(cutout, hasAlpha: true),
           let cutoutThumb = render(UIImage(cgImage: cutout), maxSide: thumbnailSize, opaque: false),
           let cutoutThumbData = encode(cutoutThumb, hasAlpha: true) {
            result.cutout = cutoutData
            result.cutoutThumbnail = cutoutThumbData
            result.cutoutTint = tintHex(for: cutout)
        }
        return result
    }

    // MARK: - Steps

    /// Draws the image at most `maxSide` pixels on its long side, with the
    /// orientation baked in.
    static func render(_ image: UIImage, maxSide: CGFloat, opaque: Bool) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width * image.scale, size.height * image.scale)) * image.scale
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            .cgImage
    }

    /// The image's foreground subjects on a transparent background, cropped to
    /// them. nil when there is no clear subject or Vision isn't available
    /// (e.g. some simulators).
    static func cutout(of image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        } catch {
            return nil
        }
    }

    /// HEIC, falling back to PNG (with alpha) or JPEG where HEIC encoding isn't
    /// available.
    static func encode(_ image: CGImage, hasAlpha: Bool) -> Data? {
        if let heic = encode(image, as: .heic, quality: 0.75) { return heic }
        return encode(image, as: hasAlpha ? .png : .jpeg, quality: 0.8)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Re-renders a stored image as a thumbnail, e.g. when switching between
    /// original and cutout on an item saved earlier.
    @concurrent
    static func thumbnail(from data: Data, hasAlpha: Bool) async -> Data? {
        guard let image = UIImage(data: data),
              let thumb = render(image, maxSide: thumbnailSize, opaque: !hasAlpha)
        else { return nil }
        return encode(thumb, hasAlpha: hasAlpha)
    }

    /// Tint for a stored image, e.g. when switching version on an item saved earlier.
    @concurrent
    static func tintHex(from data: Data) async -> String? {
        guard let image = UIImage(data: data),
              let cgImage = render(image, maxSide: thumbnailSize, opaque: false)
        else { return nil }
        return tintHex(for: cgImage)
    }

    // MARK: - Tint

    /// The image's average colour (ignoring transparent pixels), darkened to
    /// sit behind it in the dark theme. "#RRGGBB".
    static func tintHex(for image: CGImage) -> String {
        let input = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        if let output = filter?.outputImage {
            CIContext(options: [.workingColorSpace: NSNull()]).render(
                output, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: nil
            )
        }
        let alpha = max(Double(pixel[3]) / 255, 0.001)
        let rgb = (0..<3).map { min(1, Double(pixel[$0]) / 255 / alpha) }
        return darkTint(red: rgb[0], green: rgb[1], blue: rgb[2])
    }

    /// Keeps the hue, mutes the saturation and drops the brightness so any
    /// colour works as a dark background.
    static func darkTint(red: Double, green: Double, blue: Double) -> String {
        let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let dark = UIColor(hue: hue, saturation: min(saturation, 0.6) * 0.75, brightness: 0.17, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        dark.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
