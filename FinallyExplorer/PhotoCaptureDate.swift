import Foundation
import ImageIO

/// Original camera metadata only; a copied file's creation date is not a capture date.
nonisolated struct PhotoCaptureDate: Hashable, Sendable {
    let date: Date
    let assumedLocalTimeZone: Bool

    static func read(from url: URL, timeZone: TimeZone = .current) -> Self? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]), values.isRegularFile == true else { return nil }
        // Do not download cloud placeholders just to inspect their metadata.
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
            return nil
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return parse(original, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String, timeZone: timeZone)
    }

    static func parse(_ original: String, offset: String?, timeZone: TimeZone) -> Self? {
        let bytes = Array(original.utf8)
        guard bytes.count == 19, bytes[4] == 58, bytes[7] == 58, bytes[10] == 32,
              bytes[13] == 58, bytes[16] == 58 else { return nil }
        let parts = original.split(whereSeparator: { $0 == ":" || $0 == " " })
        guard parts.map(\.count) == [4, 2, 2, 2, 2, 2],
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let hour = Int(parts[3]), let minute = Int(parts[4]), let second = Int(parts[5]),
              (1900...2200).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        if let offset {
            let bytes = Array(offset.utf8)
            guard bytes.count == 6, bytes[0] == 43 || bytes[0] == 45, bytes[3] == 58,
                  [bytes[1], bytes[2], bytes[4], bytes[5]].allSatisfy({ (48...57).contains($0) }) else { return nil }
            let hours = Int(bytes[1] - 48) * 10 + Int(bytes[2] - 48)
            let minutes = Int(bytes[4] - 48) * 10 + Int(bytes[5] - 48)
            guard hours <= 14, minutes < 60, hours < 14 || minutes == 0,
                  let zone = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (bytes[0] == 45 ? -1 : 1)) else { return nil }
            calendar.timeZone = zone
        } else {
            calendar.timeZone = timeZone
        }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components else { return nil }
        return Self(date: date, assumedLocalTimeZone: offset == nil)
    }
}
