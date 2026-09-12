import CoreGraphics
import Foundation

nonisolated enum PDFPageRasterizer {
    /// The caller owns the PDF snapshot and runs off the main actor. Never
    /// renders an unbounded native-size page or writes a temporary image.
    static func image(_ page: CGPDFPage) throws -> CGImage {
        try Task.checkCancellation()
        let box = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
        guard box.origin.x.isFinite, box.origin.y.isFinite,
              box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            throw DocumentQuestionError.unreadable
        }
        let rotated = abs(page.rotationAngle % 180) == 90
        let width = rotated ? box.height : box.width
        let height = rotated ? box.width : box.height
        let scale = min(3, 2_400 / max(width, height))
        let pixelsWide = max(1, min(2_400, Int(ceil(width * scale))))
        let pixelsHigh = max(1, min(2_400, Int(ceil(height * scale))))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DocumentQuestionError.ocrFailed }
        let rect = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        // The PDF drawing transform can center a small page without upscaling
        // it. Apply the point-to-pixel scale before the page's crop/rotation.
        context.scaleBy(x: CGFloat(pixelsWide) / width, y: CGFloat(pixelsHigh) / height)
        let pageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
        context.interpolationQuality = .high
        context.drawPDFPage(page)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw DocumentQuestionError.ocrFailed }
        return image
    }
}
