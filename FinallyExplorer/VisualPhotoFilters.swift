import Foundation

/// Resolved once when a date is requested; a type-only refinement never moves it.
nonisolated struct VisualPhotoFilters: Equatable, Sendable {
    let captureInterval: DateInterval?
    let fileExtensions: [String]

    init(captureInterval: DateInterval? = nil, fileExtensions: [String] = []) throws {
        guard fileExtensions.count <= 6,
              fileExtensions.allSatisfy({ VisualSearchService.extensions.contains($0) }),
              captureInterval.map({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.duration > 0 }) ?? true
        else { throw VisualDescriptionError.unsupportedRequest }
        self.captureInterval = captureInterval
        self.fileExtensions = Array(Set(fileExtensions)).sorted()
    }

    func includes(_ entry: VisualSearchSnapshot.Entry) -> Bool {
        if fileExtensions.isEmpty == false,
           fileExtensions.contains(URL(filePath: entry.relativePath).pathExtension.lowercased()) == false { return false }
        if let captureInterval {
            guard let captured = entry.evidence.captureDate?.date,
                  captured >= captureInterval.start, captured < captureInterval.end else { return false }
        }
        return true
    }

    var summary: String {
        var labels: [String] = []
        if let captureInterval {
            labels.append("Captured (EXIF): \(captureInterval.start.formatted(date: .abbreviated, time: .omitted)) – \(captureInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
        }
        if fileExtensions.isEmpty == false { labels.append("Type: " + fileExtensions.map { $0.uppercased() }.joined(separator: ", ")) }
        return labels.joined(separator: " · ")
    }
}
