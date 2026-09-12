import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

nonisolated enum DocumentOCRFixtures {
    static func croppedMarkerPDF(rotation: Int) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 40, width: 100, height: 80))
        context.endPDFPage()
        context.closePDF()
        let pdf = try #require(PDFDocument(data: data as Data))
        let page = try #require(pdf.page(at: 0))
        page.setBounds(CGRect(x: 10, y: 20, width: 300, height: 400), for: .cropBox)
        page.rotation = rotation
        return try #require(pdf.dataRepresentation())
    }

    static func pdf(scannedPages: [String], embeddedFirstPage: String? = nil, rotation: Int = 0) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        if let embeddedFirstPage {
            context.beginPDFPage(nil)
            draw(embeddedFirstPage, in: context, fontSize: 16, x: 30, y: 700, lineHeight: 28)
            context.endPDFPage()
        }
        for text in scannedPages {
            context.beginPDFPage(nil)
            context.draw(try image(text), in: box)
            context.endPDFPage()
        }
        context.closePDF()
        let pdf = try #require(PDFDocument(data: data as Data))
        let firstScan = embeddedFirstPage == nil ? 0 : 1
        for index in firstScan..<pdf.pageCount {
            let page = try #require(pdf.page(at: index))
            #expect((page.string ?? "").isEmpty, "The OCR fixture must not contain a hidden text layer")
            page.rotation = rotation
        }
        return try #require(pdf.dataRepresentation())
    }

    static func image(_ text: String) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1_200, height: 1_600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
        draw(text, in: context, fontSize: 32, x: 60, y: 1_400, lineHeight: 56)
        return try #require(context.makeImage())
    }

    static func recordImage(_ image: CGImage, name: String) throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: URL(filePath: "/tmp/FinallyExplorer-\(name).png"))
    }

    private static func draw(_ text: String, in context: CGContext, fontSize: CGFloat, x: CGFloat, y: CGFloat, lineHeight: CGFloat) {
        for (index, line) in text.split(separator: "\n").enumerated() {
            let attributed = NSAttributedString(string: String(line), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: x, y: y - CGFloat(index) * lineHeight)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
    }
}
