import Foundation
import CoreImage
import CoreVideo
import ImageIO
import CoreGraphics

/// Wie ein Modell-Input aus dem Kamerabild entstanden ist – zum Zurückrechnen der Koordinaten.
nonisolated struct LetterboxTransform: Sendable {
    /// Ausschnitt im Originalbild (Pixel, Ursprung oben links).
    let roi: CGRect
    let scale: CGFloat
    let padX: CGFloat
    let padY: CGFloat

    func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - padX) / scale + roi.minX, y: (p.y - padY) / scale + roi.minY)
    }
}

/// Bildaufbereitung mit Core Image (GPU): Ausschnitt, Letterbox, JPEG, Vorschaubilder.
/// Wird jeweils nur von einem Actor verwendet; der Puffer-Cache ist zusätzlich per Lock geschützt.
nonisolated final class FrameRenderer: @unchecked Sendable {

    static let shared = FrameRenderer()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var bufferCache: [Int: CVPixelBuffer] = [:]

    /// Schneidet `roi` aus, skaliert seitenverhältnistreu auf `size`×`size` und füllt den Rest grau (114),
    /// genau wie das Ultralytics-Letterboxing beim Training. Ein verzerrtes Strecken würde die Genauigkeit senken.
    func letterbox(_ source: CVPixelBuffer, roi requested: CGRect, size: Int) throws -> (buffer: CVPixelBuffer, transform: LetterboxTransform) {
        let width = CGFloat(CVPixelBufferGetWidth(source))
        let height = CGFloat(CVPixelBufferGetHeight(source))
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        var roi = requested.intersection(full).integral
        if roi.isNull || roi.width < 8 || roi.height < 8 { roi = full }

        let side = CGFloat(size)
        let scale = min(side / roi.width, side / roi.height)
        let padX = (side - roi.width * scale) / 2
        let padY = (side - roi.height * scale) / 2

        // Core Image hat den Ursprung unten links.
        let ciROI = CGRect(x: roi.minX, y: height - roi.maxY, width: roi.width, height: roi.height)
        let image = CIImage(cvPixelBuffer: source)
            .cropped(to: ciROI)
            .transformed(by: CGAffineTransform(translationX: -ciROI.minX, y: -ciROI.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let background = CIImage(color: CIColor(red: 114.0 / 255, green: 114.0 / 255, blue: 114.0 / 255))
            .cropped(to: canvas)
        let composed = image.composited(over: background)

        let output = try buffer(size: size)
        context.render(composed, to: output, bounds: canvas, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (output, LetterboxTransform(roi: roi, scale: scale, padX: padX, padY: padY))
    }

    /// JPEG eines (verkleinerten) Frames – ohne EXIF-Rotation, die Pixel sind bereits aufrecht.
    func jpeg(from source: CVPixelBuffer, maxDimension: CGFloat, quality: CGFloat) throws -> (data: Data, size: CGSize) {
        let (image, size) = scaledImage(from: CIImage(cvPixelBuffer: source), maxDimension: maxDimension)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
              )
        else { throw DetectionError.encodingFailed }
        return (data, size)
    }

    /// Verkleinertes Standbild (z. B. für die Kalibrieransicht).
    func cgImage(from source: CVPixelBuffer, maxDimension: CGFloat) -> CGImage? {
        let (image, size) = scaledImage(from: CIImage(cvPixelBuffer: source), maxDimension: maxDimension)
        return context.createCGImage(image, from: CGRect(origin: .zero, size: size))
    }

    /// Rendert ein beliebiges CIImage (z. B. Testbild) in einen BGRA-Puffer in Originalgröße.
    func pixelBuffer(from image: CIImage) -> CVPixelBuffer? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(extent.width), Int(extent.height),
                                         kCVPixelFormatType_32BGRA, Self.bufferAttributes, &output)
        guard status == kCVReturnSuccess, let output else { return nil }
        context.render(normalized, to: output, bounds: CGRect(x: 0, y: 0, width: extent.width, height: extent.height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return output
    }

    // MARK: - Intern

    private func scaledImage(from image: CIImage, maxDimension: CGFloat) -> (CIImage, CGSize) {
        let extent = image.extent
        let factor = min(1, maxDimension / max(extent.width, extent.height))
        let width = (extent.width * factor).rounded(.down)
        let height = (extent.height * factor).rounded(.down)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: width / extent.width, y: height / extent.height))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return (scaled, CGSize(width: width, height: height))
    }

    private static var bufferAttributes: CFDictionary {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]() as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true
        ]
        return attributes as CFDictionary
    }

    private func buffer(size: Int) throws -> CVPixelBuffer {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bufferCache[size] { return cached }
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA,
                                         Self.bufferAttributes, &created)
        guard status == kCVReturnSuccess, let created else { throw DetectionError.pixelBufferFailed }
        bufferCache[size] = created
        return created
    }
}
