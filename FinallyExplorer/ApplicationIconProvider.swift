//
//  ApplicationIconProvider.swift
//  FinallyExplorer
//

import AppKit

@MainActor
final class ApplicationIconProvider {
    static let shared = ApplicationIconProvider()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 512
    }

    func icon(for applicationURL: URL) -> NSImage {
        let cacheKey = applicationURL.standardizedFileURL as NSURL

        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }
}
