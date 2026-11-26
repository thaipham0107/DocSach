import Foundation
import ImageIO
import UIKit
import ZIPFoundation

/// Nơi lưu tệp sách trên máy.
enum BookStorage {
    static var booksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var extractedDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Extracted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Giải nén EPUB/CBZ (chỉ làm một lần, lưu tạm trong Caches).
    static func ensureExtracted(id: UUID, archive: URL) throws -> URL {
        let fm = FileManager.default
        let dir = extractedDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let marker = dir.appendingPathComponent(".docsach-done")
        if fm.fileExists(atPath: marker.path) { return dir }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.unzipItem(at: archive, to: dir)
        fm.createFile(atPath: marker.path, contents: Data())
        return dir
    }

    static func delete(bookID: UUID, fileName: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: booksDirectory.appendingPathComponent(fileName))
        try? fm.removeItem(at: extractedDirectory.appendingPathComponent(bookID.uuidString, isDirectory: true))
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "avif", "bmp"]

    /// Danh sách trang ảnh của truyện tranh, sắp xếp tự nhiên (1, 2, 10…).
    static func comicPages(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var pages: [URL] = []
        for case let url as URL in enumerator {
            if url.path.contains("__MACOSX") || url.lastPathComponent.hasPrefix(".") { continue }
            if imageExtensions.contains(url.pathExtension.lowercased()) { pages.append(url) }
        }
        let root = dir.standardizedFileURL.path
        return pages.sorted {
            let a = $0.standardizedFileURL.path.replacingOccurrences(of: root, with: "")
            let b = $1.standardizedFileURL.path.replacingOccurrences(of: root, with: "")
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

enum ImageUtil {
    static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return UIImage(contentsOfFile: url.path)
        }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cg)
    }

    static func coverData(from url: URL) -> Data? {
        downsample(url: url, maxPixel: 700)?.jpegData(compressionQuality: 0.8)
    }
}
