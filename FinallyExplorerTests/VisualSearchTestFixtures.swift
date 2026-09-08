import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FinallyExplorer

nonisolated enum VisualSearchTestFixtures {
    static func receiptImage() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 1_000, height: 500, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 500))
        let string = NSAttributedString(string: "INVOICE 4827", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 80, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 100, y: 250)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}

nonisolated struct FixedVisualAnalyzer: VisualImageAnalyzing {
    var text = "Invoice 4827"
    func analyze(_ data: Data) async throws -> VisualImageEvidence {
        VisualImageEvidence(labels: [.init(name: "beach", confidence: 0.8), .init(name: "ocean", confidence: 0.6)],
            text: text, textWasTruncated: false, thumbnail: Data())
    }
}

nonisolated struct PausedVisualAnalyzer: VisualImageAnalyzing {
    let gate: FolderComparisonTestGate
    func analyze(_ data: Data) async throws -> VisualImageEvidence {
        await gate.pause()
        return try await FixedVisualAnalyzer().analyze(data)
    }
}
