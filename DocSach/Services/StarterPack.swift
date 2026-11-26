import Foundation
import SwiftData

/// Tủ sách miễn phí khởi đầu (Project Gutenberg, đã hết bản quyền).
/// Nếu bản cài chưa đóng gói sẵn sách, app tự tải danh sách này về ở lần mở đầu tiên.
/// Giữ khớp với scripts/seed_books.tsv.
enum StarterPack {
    static let items: [(BookCategory, Int)] = [
        (.business, 7213), (.business, 17976), (.business, 20203), (.business, 8581),
        (.business, 820), (.business, 2376),
        (.detective, 1661), (.detective, 244), (.detective, 2097), (.detective, 2852),
        (.detective, 863), (.detective, 58866), (.detective, 204), (.detective, 6133), (.detective, 155),
        (.mystery, 2147), (.mystery, 2148), (.mystery, 345), (.mystery, 583), (.mystery, 209),
        (.mystery, 43), (.mystery, 8486), (.mystery, 175),
        (.detective, 834), (.detective, 108), (.detective, 61262), (.detective, 1155),
        (.mystery, 84), (.mystery, 68283), (.mystery, 70652), (.mystery, 50133)
    ]

    static let doneKey = "starterPack.done"

    static func url(for id: Int) -> String { "https://www.gutenberg.org/ebooks/\(id).epub3.images" }
}

extension ImportCenter {
    /// Tải các cuốn trong tủ sách khởi đầu còn thiếu. Bỏ qua cuốn đã có (kể cả bản đóng gói sẵn).
    @MainActor
    func importStarterPack(context: ModelContext, force: Bool = false) async {
        guard !isWorking else { return }
        if !force && UserDefaults.standard.bool(forKey: StarterPack.doneKey) { return }

        let bundled = Set((UserDefaults.standard.stringArray(forKey: "seedBooks.imported") ?? [])
            .compactMap { name -> Int? in
                let base = (name as NSString).deletingPathExtension
                return base.components(separatedBy: "__").last.flatMap(Int.init)
            })
        let owned = Set(((try? context.fetch(FetchDescriptor<Book>())) ?? []).compactMap(\.sourceURL))
        let todo = StarterPack.items.filter { !bundled.contains($0.1) && !owned.contains(StarterPack.url(for: $0.1)) }
        guard !todo.isEmpty else {
            UserDefaults.standard.set(true, forKey: StarterPack.doneKey)
            return
        }

        isWorking = true
        defer { isWorking = false }
        var added = 0
        var failed = 0
        for (i, item) in todo.enumerated() {
            status = "Đang tải tủ sách miễn phí… (\(i + 1)/\(todo.count))"
            guard let url = URL(string: StarterPack.url(for: item.1)) else { continue }
            do {
                let (tmp, name) = try await BookImporter.download(url)
                let info = try await Task.detached(priority: .userInitiated) {
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    return try BookImporter.prepare(fileAt: tmp, suggestedName: name ?? "\(item.1).epub")
                }.value
                insertBook(info, category: item.0, source: url.absoluteString, context: context)
                added += 1
            } catch {
                failed += 1
            }
        }
        if failed == 0 { UserDefaults.standard.set(true, forKey: StarterPack.doneKey) }
        if added > 0 { successMessage = "Đã thêm \(added) cuốn sách miễn phí vào thư viện" }
        if failed > 0 && added == 0 {
            errorMessage = "Chưa tải được tủ sách miễn phí (kiểm tra mạng). Bạn có thể thử lại trong tab Khám phá."
        }
    }
}
