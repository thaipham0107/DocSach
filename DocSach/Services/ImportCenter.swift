import Foundation
import SwiftData
import Observation

/// Điều phối việc nạp sách (từ tệp, từ link, từ kho sách) và hiển thị tiến trình.
@Observable
final class ImportCenter {
    var isWorking = false
    var status = ""
    var errorMessage: String?
    var successMessage: String?

    @MainActor
    func importFiles(_ urls: [URL], category: BookCategory?, context: ModelContext) async {
        isWorking = true
        defer { isWorking = false }
        var added: [String] = []
        for url in urls {
            status = "Đang nạp \(url.lastPathComponent)…"
            let access = url.startAccessingSecurityScopedResource()
            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try BookImporter.prepare(fileAt: url, suggestedName: url.lastPathComponent)
                }.value
                insert(info, category: category, source: nil, context: context)
                added.append(info.title)
            } catch {
                errorMessage = "Không nạp được “\(url.lastPathComponent)”.\n\(error.localizedDescription)"
            }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        if !added.isEmpty {
            successMessage = added.count == 1 ? "Đã thêm “\(added[0])”" : "Đã thêm \(added.count) cuốn sách"
        }
    }

    /// Tự nạp các tệp chép vào thư mục Documents (qua Finder/iTunes) hoặc Documents/Inbox (mở từ app khác).
    @MainActor
    func importDocumentsFolder(context: ModelContext) async {
        guard !isWorking else { return }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let allowed: Set<String> = ["epub", "cbz", "zip", "pdf"]
        var found: [URL] = []
        for dir in [docs, docs.appendingPathComponent("Inbox")] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            found += items.filter { allowed.contains($0.pathExtension.lowercased()) }
        }
        guard !found.isEmpty else { return }
        await importFiles(found, category: nil, context: context)
        for url in found { try? fm.removeItem(at: url) }
    }

    /// Nạp bộ sách miễn phí đóng gói sẵn trong app (tên tệp dạng "business__7213.epub").
    /// Mỗi cuốn chỉ nạp một lần; nếu bạn xoá thì sẽ không tự nạp lại.
    @MainActor
    func importBundledSeedBooks(context: ModelContext) async {
        guard !isWorking else { return }
        let doneKey = "seedBooks.imported"
        var done = Set(UserDefaults.standard.stringArray(forKey: doneKey) ?? [])
        let urls = (Bundle.main.urls(forResourcesWithExtension: "epub", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.contains("__") && !done.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }
        var count = 0
        for (i, url) in urls.enumerated() {
            status = "Đang chuẩn bị tủ sách miễn phí… (\(i + 1)/\(urls.count))"
            let prefix = String(url.lastPathComponent.split(separator: "_").first ?? "")
            let category = BookCategory(rawValue: prefix)
            if let info = try? await Task.detached(priority: .userInitiated, operation: {
                try BookImporter.prepare(fileAt: url, suggestedName: url.lastPathComponent)
            }).value {
                insert(info, category: category, source: "bundle:" + url.lastPathComponent, context: context)
                count += 1
            }
            done.insert(url.lastPathComponent)
            UserDefaults.standard.set(Array(done), forKey: doneKey)
        }
        if count > 0 { successMessage = "Đã thêm \(count) cuốn sách miễn phí vào thư viện" }
    }

    @MainActor @discardableResult
    func importLink(_ text: String, category: BookCategory?, context: ModelContext) async -> Bool {
        guard let url = BookImporter.directURL(from: text) else {
            errorMessage = ImportError.badLink.localizedDescription
            return false
        }
        let source = url.absoluteString
        let existing = (try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.sourceURL == source }))) ?? []
        if let book = existing.first {
            successMessage = "“\(book.title)” đã có trong thư viện"
            return true
        }

        isWorking = true
        status = "Đang tải sách về…"
        defer { isWorking = false }
        do {
            let (tmp, name) = try await BookImporter.download(url)
            status = "Đang xử lý…"
            let info = try await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: tmp) }
                return try BookImporter.prepare(fileAt: tmp, suggestedName: name ?? url.lastPathComponent)
            }.value
            insert(info, category: category, source: source, context: context)
            successMessage = "Đã thêm “\(info.title)”"
            return true
        } catch {
            errorMessage = "Không tải được sách.\n\(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    func insertBook(_ info: ImportedBookInfo, category: BookCategory?, source: String?, context: ModelContext) {
        insert(info, category: category, source: source, context: context)
    }

    @MainActor
    private func insert(_ info: ImportedBookInfo, category: BookCategory?, source: String?, context: ModelContext) {
        let book = Book(id: info.id, title: info.title, author: info.author,
                        category: category ?? info.suggestedCategory, format: info.format,
                        fileName: info.fileName, coverData: info.coverData, sourceURL: source)
        context.insert(book)
        try? context.save()
    }

    @MainActor
    static func delete(_ book: Book, context: ModelContext) {
        BookStorage.delete(bookID: book.id, fileName: book.fileName)
        context.delete(book)
        try? context.save()
    }
}
