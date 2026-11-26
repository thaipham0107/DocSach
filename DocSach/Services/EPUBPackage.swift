import Foundation

struct TOCItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let spineIndex: Int
    let level: Int
}

/// Thông tin đã đọc được từ một EPUB đã giải nén.
struct EPUBPackage {
    let rootDirectory: URL
    let title: String
    let author: String
    let subjects: [String]
    let spine: [URL]
    let toc: [TOCItem]
    let coverURL: URL?

    enum ParseError: LocalizedError {
        case noPackage, emptySpine
        var errorDescription: String? {
            switch self {
            case .noPackage: return "Tệp EPUB bị lỗi: không tìm thấy mục lục gói (OPF)."
            case .emptySpine: return "Tệp EPUB không có nội dung để đọc."
            }
        }
    }

    static func load(from root: URL) throws -> EPUBPackage {
        let fm = FileManager.default
        var opfURL: URL?
        if let container = MiniXMLParser.parse(url: root.appendingPathComponent("META-INF/container.xml")),
           let path = container.first("rootfile")?.attr("full-path") {
            let candidate = resolve(path, base: root)
            if fm.fileExists(atPath: candidate.path) { opfURL = candidate }
        }
        if opfURL == nil, let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in e where url.pathExtension.lowercased() == "opf" { opfURL = url; break }
        }
        guard let opfURL, let opf = MiniXMLParser.parse(url: opfURL) else { throw ParseError.noPackage }
        let opfDir = opfURL.deletingLastPathComponent()

        let metadata = opf.first("metadata") ?? opf
        let title = metadata.first("title")?.allText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = metadata.all("creator").map { $0.allText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        let subjects = metadata.all("subject").map { $0.allText.trimmingCharacters(in: .whitespacesAndNewlines) }

        struct Item { let url: URL; let mediaType: String; let properties: String; let id: String; let href: String }
        var items: [String: Item] = [:]
        var itemList: [Item] = []
        for node in (opf.first("manifest") ?? opf).all("item") {
            guard let id = node.attr("id"), let href = node.attr("href") else { continue }
            let item = Item(url: resolve(href, base: opfDir),
                            mediaType: (node.attr("media-type") ?? "").lowercased(),
                            properties: (node.attr("properties") ?? "").lowercased(),
                            id: id, href: href)
            items[id] = item
            itemList.append(item)
        }

        let spineNode = opf.first("spine")
        var spine: [URL] = []
        for ref in spineNode?.all("itemref") ?? [] {
            guard let idref = ref.attr("idref"), let item = items[idref] else { continue }
            if item.mediaType.contains("image") { continue }
            spine.append(item.url)
        }
        guard !spine.isEmpty else { throw ParseError.emptySpine }

        // Ảnh bìa
        var cover: URL?
        if let item = itemList.first(where: { $0.properties.contains("cover-image") }) {
            cover = item.url
        } else if let meta = metadata.all("meta").first(where: { $0.attr("name")?.lowercased() == "cover" }),
                  let id = meta.attr("content"), let item = items[id], item.mediaType.contains("image") {
            cover = item.url
        } else if let item = itemList.first(where: {
            $0.mediaType.contains("image") && ($0.id.lowercased().contains("cover") || $0.href.lowercased().contains("cover"))
        }) {
            cover = item.url
        }

        // Mục lục
        var spineIndex: [String: Int] = [:]
        for (i, url) in spine.enumerated() where spineIndex[url.path] == nil { spineIndex[url.path] = i }
        var toc: [TOCItem] = []

        if let navItem = itemList.first(where: { $0.properties.split(separator: " ").contains("nav") }),
           let nav = MiniXMLParser.parse(url: navItem.url) {
            let navDir = navItem.url.deletingLastPathComponent()
            let navs = nav.all("nav")
            let tocNav = navs.first(where: { $0.attr("type")?.contains("toc") == true }) ?? navs.first ?? nav
            for a in tocNav.all("a") {
                guard let href = a.attr("href") else { continue }
                let target = resolve(href, base: navDir)
                guard let idx = spineIndex[target.path] else { continue }
                let label = a.allText.trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { continue }
                toc.append(TOCItem(title: label, spineIndex: idx, level: max(0, a.ancestorCount(named: "ol") - 1)))
            }
        }
        if toc.isEmpty, let tocID = spineNode?.attr("toc"), let ncxItem = items[tocID],
           let ncx = MiniXMLParser.parse(url: ncxItem.url) {
            let ncxDir = ncxItem.url.deletingLastPathComponent()
            for point in ncx.all("navPoint") {
                guard let src = point.first("content")?.attr("src") else { continue }
                let target = resolve(src, base: ncxDir)
                guard let idx = spineIndex[target.path] else { continue }
                let label = (point.first("navLabel")?.allText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { continue }
                toc.append(TOCItem(title: label, spineIndex: idx, level: point.ancestorCount(named: "navPoint")))
            }
        }

        return EPUBPackage(rootDirectory: root, title: title, author: author, subjects: subjects,
                           spine: spine, toc: toc, coverURL: cover)
    }

    static func resolve(_ href: String, base: URL) -> URL {
        let clean = href.components(separatedBy: "#").first ?? href
        let decoded = clean.removingPercentEncoding ?? clean
        return base.appendingPathComponent(decoded).standardizedFileURL
    }

    func spineIndex(of url: URL) -> Int? {
        let path = url.standardizedFileURL.path
        return spine.firstIndex(where: { $0.path == path })
    }

    func chapterTitle(for chapter: Int) -> String? {
        toc.last(where: { $0.spineIndex <= chapter })?.title
    }
}
