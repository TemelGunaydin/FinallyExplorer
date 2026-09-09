import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Only bounded, descriptor-read bytes enter ImageIO/Vision, never a live file URL.
nonisolated struct VisionImageAnalyzer: VisualImageAnalyzing {
    @concurrent func analyze(_ data: Data) async throws -> VisualImageEvidence {
        try Task.checkCancellation()
        guard data.count <= 40 * 1_024 * 1_024 else { throw VisualSearchError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw VisualSearchError.unreadableImage }
        let w = width.doubleValue, h = height.doubleValue
        guard w > 0, h > 0, w <= 20_000, h <= 20_000, w * h <= 80_000_000 else { throw VisualSearchError.imageTooLarge }
        let image = try thumbnail(source, maximumSize: 1_600)
        try Task.checkCancellation()
        let classifications = try await ClassifyImageRequest().perform(on: image, orientation: .up)
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.automaticallyDetectsLanguage = false
        let observations = try await request.perform(on: image, orientation: .up)
        try Task.checkCancellation()
        // Bound retained OCR without constructing an unbounded joined transcript.
        var text = ""
        var truncated = false
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let remaining = 4_000 - text.count
            guard remaining > 1 else { truncated = true; break }
            let line = String(candidate.string.prefix(remaining - 1))
            text += line + "\n"
            if candidate.string.count > line.count { truncated = true; break }
        }
        let preview = try thumbnail(source, maximumSize: 240)
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VisualSearchError.unreadableImage
        }
        CGImageDestinationAddImage(destination, preview, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length <= 100_000 else { throw VisualSearchError.unreadableImage }
        return VisualImageEvidence(
            labels: classifications.filter { $0.confidence >= 0.2 }
                .sorted { $0.confidence > $1.confidence }.prefix(12)
                .map { .init(name: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: $0.confidence) },
            text: text.trimmingCharacters(in: .whitespacesAndNewlines), textWasTruncated: truncated, thumbnail: bytes as Data,
            captureDate: PhotoCaptureDate.read(properties: properties)
        )
    }

    private func thumbnail(_ source: CGImageSource, maximumSize: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { throw VisualSearchError.unreadableImage }
        return image
    }
}
