import Foundation
import SwiftData
import ZIPFoundation

/// Dựng tệp EPUB từ một tác phẩm trên Wikisource tiếng Việt (gộp trang chính và các chương con).
enum WikisourceBook {
    private static let api = "https://vi.wikisource.org/w/api.php"

    static func sourceKey(for title: String) -> String { "wikisource:vi:" + title }

    private struct ParseResponse: Decodable {
        struct Parse: Decodable { let title: String; let text: String }
        let parse: Parse?
    }

    private static func parse(_ page: String) async throws -> (title: String, html: String)? {
        var comps = URLComponents(string: api)!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: page),
            URLQueryItem(name: "prop", value: "text"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "disableeditsection", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 60
        request.setValue("DocSach/1.0 (personal reading app)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                try await Task.sleep(for: .seconds(3 * (attempt + 1)))
                continue
            }
            guard let parsed = try JSONDecoder().decode(ParseResponse.self, from: data).parse else { return nil }
            return (parsed.title, parsed.text)
        }
        throw ImportError.http(429)
    }

    /// Các trang con "Tên/…" theo thứ tự liên kết trong trang chính.
    private static func chapterTitles(in html: String, root: String) -> [String] {
        let want = root.replacingOccurrences(of: "_", with: " ") + "/"
        guard let regex = try? NSRegularExpression(pattern: "href=\"/wiki/([^\"#]+)") else { return [] }
        var result: [String] = []
        let ns = html as NSString
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: m.range(at: 1))
            let t = (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "_", with: " ")
            if t.hasPrefix(want) && !result.contains(t) { result.append(t) }
        }
        return result
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let hideCSS = """
    .mw-editsection, .noprint, .ws-noexport, .ws-header, #headertemplate, .headertemplate, .navbox,
    sup.reference, .mw-references-wrap, .licenseContainer, .licenseBanner, img { display: none !important; }
    """

    private static func page(title: String, body: String) -> String {
        "<!DOCTYPE html><html lang=\"vi\"><head><meta charset=\"utf-8\"/><title>\(escape(title))</title>"
        + "<style>\(hideCSS)</style></head><body><h2>\(escape(title))</h2>\(body)</body></html>"
    }

    /// Trả về đường dẫn tệp EPUB tạm.
    static func build(title: String, progress: @escaping (String) -> Void) async throws -> URL {
        guard let main = try await parse(title) else { throw ImportError.notABook }
        let subs = chapterTitles(in: main.html, root: main.title)
        var chapters: [(String, String)] = []
        for (i, sub) in subs.prefix(200).enumerated() {
            progress("Đang tải chương \(i + 1)/\(min(subs.count, 200))…")
            if let ch = try? await parse(sub) {
                let name = ch.title.components(separatedBy: "/").dropFirst().joined(separator: "/")
                chapters.append((name.isEmpty ? ch.title : name, ch.html))
            }
        }
        if chapters.isEmpty { chapters = [(main.title, main.html)] }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ text: String, compress: Bool = true) throws {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: compress ? .deflate : .none) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        try add("mimetype", "application/epub+zip", compress: false)
        try add("META-INF/container.xml", """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """)
        var manifest = "", spine = "", nav = ""
        for (i, ch) in chapters.enumerated() {
            let name = String(format: "c%03d.html", i + 1)
            try add("OEBPS/" + name, page(title: ch.0, body: ch.1))
            manifest += "<item id=\"c\(i + 1)\" href=\"\(name)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(i + 1)\"/>"
            nav += "<li><a href=\"\(name)\">\(escape(ch.0))</a></li>"
        }
        try add("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">\
        <head><title>Mục lục</title></head><body><nav epub:type="toc"><ol>\(nav)</ol></nav></body></html>
        """)
        try add("OEBPS/content.opf", """
        <?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bid">\
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bid">\(escape(sourceKey(for: main.title)))</dc:identifier>\
        <dc:title>\(escape(main.title))</dc:title><dc:language>vi</dc:language><dc:subject>Văn học Việt Nam</dc:subject></metadata>\
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(manifest)</manifest>\
        <spine>\(spine)</spine></package>
        """)
        return url
    }
}

extension ImportCenter {
    @MainActor
    func importWikisource(title: String, category: BookCategory, context: ModelContext) async {
        guard !isWorking else { return }
        isWorking = true
        status = "Đang tải “\(title)”…"
        defer { isWorking = false }
        do {
            let file = try await WikisourceBook.build(title: title) { [weak self] text in
                Task { @MainActor in self?.status = text }
            }
            let info = try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: file) }
                return try BookImporter.prepare(fileAt: file, suggestedName: title)
            }.value
            insertBook(info, category: category, source: WikisourceBook.sourceKey(for: title), context: context)
            successMessage = "Đã thêm “\(info.title)”"
        } catch {
            errorMessage = "Không tải được “\(title)”.\n\(error.localizedDescription)"
        }
    }
}
