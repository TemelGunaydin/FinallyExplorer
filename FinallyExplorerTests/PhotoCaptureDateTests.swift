import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import FinallyExplorer

struct PhotoCaptureDateTests {
    @Test("EXIF camera offsets take precedence over the Mac time zone")
    func explicitOffset() throws {
        let capture = try #require(PhotoCaptureDate.parse("2026:09:03 00:15:00", offset: "+03:00", timeZone: .gmt))
        #expect(capture.date == (try SmartSearchTestFixtures.date("2026-09-02T21:15:00Z")))
        #expect(capture.assumedLocalTimeZone == false)
        let negative = try #require(PhotoCaptureDate.parse("2026:09:03 00:15:00", offset: "-04:30", timeZone: .gmt))
        #expect(negative.date == (try SmartSearchTestFixtures.date("2026-09-03T04:45:00Z")))
    }

    @Test("A missing camera offset is explicitly marked as a local-time assumption")
    func missingOffset() throws {
        let capture = try #require(PhotoCaptureDate.parse("2026:09:03 00:00:00", offset: nil, timeZone: SmartSearchTestFixtures.calendar().timeZone))
        #expect(capture.assumedLocalTimeZone)
        #expect(capture.date == (try SmartSearchTestFixtures.date("2026-09-03T00:00:00+03:00")))
    }

    @Test("Malformed EXIF timestamps are not normalized into another date", arguments: [
        "2026:02:30 12:00:00", "2026:13:01 00:00:00", "2026:09:03 24:00:00", "2026:09:03 12:60:00", "2026:9:3 00:00:00", "",
    ])
    func invalidDates(_ value: String) {
        #expect(PhotoCaptureDate.parse(value, offset: nil, timeZone: .gmt) == nil)
    }

    @Test("Invalid timezone metadata does not fall back silently", arguments: ["Z", "+99:00", "+14:01", "+03:60", "03:00", "+aa:00"])
    func invalidOffset(_ value: String) {
        #expect(PhotoCaptureDate.parse("2026:09:03 00:00:00", offset: value, timeZone: .gmt) == nil)
    }

    @Test("A real JPEG uses DateTimeOriginal, never its new filesystem creation date")
    func readsJPEGMetadata() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        for hasMetadata in [true, false] {
            let url = root.appending(path: "image-\(hasMetadata).jpg")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            let properties: [CFString: Any] = hasMetadata ? [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05"]] : [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            let capture = PhotoCaptureDate.read(from: url, timeZone: .gmt)
            if hasMetadata {
                #expect(capture?.date == (try SmartSearchTestFixtures.date("2020-01-02T03:04:05Z")))
            } else {
                #expect(capture == nil)
            }
        }
    }
}
