import Foundation
import PDFKit
import UIKit
import ZIPFoundation

struct ImportedBookInfo {
    let id: UUID
    let title: String
    let author: String
    let format: BookFormat
    let fileName: String
    let coverData: Data?
    let suggestedCategory: BookCategory
}

enum ImportError: LocalizedError {
    case rarNotSupported
    case notABook
    case http(Int)
    case badLink

    var errorDescription: String? {
        switch self {
        case .rarNotSupported:
            return "Ứng dụng chưa đọc được tệp CBR/RAR. Bạn hãy đổi sang CBZ (chỉ cần giải nén rồi nén lại dạng ZIP, đổi đuôi thành .cbz)."
        case .notABook:
            return "Tệp này không phải EPUB, CBZ hay PDF. Nếu dùng link, hãy chắc chắn link tải thẳng về tệp (không phải trang web giới thiệu sách)."
        case .http(let code):
            return "Máy chủ trả về lỗi \(code). Hãy kiểm tra lại link."
        case .badLink:
            return "Link không hợp lệ."
        }
    }
}

enum BookImporter {

    /// Chuẩn hoá link chia sẻ thường gặp thành link tải thẳng.
    static func directURL(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard var comps = URLComponents(string: s), let host = comps.host?.lowercased() else { return nil }

        // Google Drive: /file/d/<ID>/view -> uc?export=download&id=<ID>
        if host.contains("drive.google.com") {
            let parts = comps.path.split(separator: "/")
            if let i = parts.firstIndex(of: "d"), i + 1 < parts.count {
                return URL(string: "https://drive.google.com/uc?export=download&id=\(parts[i + 1])")
            }
        }
        // Dropbox: dl=0 -> dl=1
        if host.contains("dropbox.com") {
            var items = comps.queryItems ?? []
            items.removeAll { $0.name == "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            comps.queryItems = items
        }
        return comps.url
    }

    static func download(_ url: URL) async throws -> (URL, String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) DocSach/1.0", forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.http(http.statusCode)
        }
        let name = response.suggestedFilename
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + (name ?? "download"))
        try FileManager.default.moveItem(at: tmp, to: dest)
        return (dest, name)
    }

    /// Nhận dạng định dạng dựa vào đuôi tệp và nội dung.
    static func detectFormat(of url: URL) throws -> BookFormat {
        let ext = url.pathExtension.lowercased()
        if ext == "cbr" || ext == "rar" { throw ImportError.rarNotSupported }

        let handle = try FileHandle(forReadingFrom: url)
        let head = (try? handle.read(upToCount: 8)) ?? Data()
        try? handle.close()
        let bytes = [UInt8](head)

        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }          // %PDF
        if bytes.starts(with: [0x52, 0x61, 0x72, 0x21]) { throw ImportError.rarNotSupported } // Rar!
        guard bytes.starts(with: [0x50, 0x4B]) else { throw ImportError.notABook } // PK (ZIP)

        let archive = try Archive(url: url, accessMode: .read)
        var hasImages = false
        for entry in archive {
            let path = entry.path.lowercased()
            if path == "mimetype" || path == "meta-inf/container.xml" || path.hasSuffix(".opf") { return .epub }
            if BookStorage.imageExtensions.contains((path as NSString).pathExtension) { hasImages = true }
        }
        if hasImages { return .comic }
        throw ImportError.notABook
    }

    /// Chép tệp vào thư viện và đọc thông tin (tên, tác giả, ảnh bìa).
    static func prepare(fileAt source: URL, suggestedName: String?) throws -> ImportedBookInfo {
        let format = try detectFormat(of: source)
        let id = UUID()
        let fileName = "\(id.uuidString).\(format.fileExtension)"
        let dest = BookStorage.booksDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: dest)

        let fallbackTitle = ((suggestedName ?? source.lastPathComponent) as NSString)
            .deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")

        do {
            switch format {
            case .epub:
                let dir = try BookStorage.ensureExtracted(id: id, archive: dest)
                let pkg = try EPUBPackage.load(from: dir)
                let title = pkg.title.isEmpty ? fallbackTitle : pkg.title
                let cover = pkg.coverURL.flatMap(ImageUtil.coverData(from:))
                let guessText = ([title, pkg.author] + pkg.subjects).joined(separator: " ")
                return ImportedBookInfo(id: id, title: title, author: pkg.author, format: .epub, fileName: fileName,
                                        coverData: cover, suggestedCategory: BookCategory.guess(from: guessText, format: .epub))

            case .comic:
                let dir = try BookStorage.ensureExtracted(id: id, archive: dest)
                let pages = BookStorage.comicPages(in: dir)
                guard let first = pages.first else { throw ImportError.notABook }
                return ImportedBookInfo(id: id, title: fallbackTitle, author: "", format: .comic, fileName: fileName,
                                        coverData: ImageUtil.coverData(from: first), suggestedCategory: .comics)

            case .pdf:
                let doc = PDFDocument(url: dest)
                let attrs = doc?.documentAttributes ?? [:]
                let pdfTitle = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
                let title = pdfTitle.isEmpty ? fallbackTitle : pdfTitle
                let cover = doc?.page(at: 0)?.thumbnail(of: CGSize(width: 480, height: 720), for: .mediaBox)
                    .jpegData(compressionQuality: 0.8)
                return ImportedBookInfo(id: id, title: title, author: author, format: .pdf, fileName: fileName,
                                        coverData: cover,
                                        suggestedCategory: BookCategory.guess(from: title + " " + author, format: .pdf))
            }
        } catch {
            BookStorage.delete(bookID: id, fileName: fileName)
            throw error
        }
    }
}
