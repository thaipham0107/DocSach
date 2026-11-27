import SwiftUI
import SwiftData

/// Kho sách PDF miễn phí trên Internet Archive (archive.org).
/// Chỉ tìm sách xuất bản trước 1930 hoặc được ghi là phạm vi công cộng, tải về được tự do.
struct ArchiveItem: Identifiable, Hashable {
    let id: String          // identifier trên archive.org
    let title: String
    let creator: String
    let year: String

    var coverURL: URL? { URL(string: "https://archive.org/services/img/\(id)") }
    var sourceKey: String { "archive:" + id }
}

enum InternetArchive {
    struct Preset: Identifiable, Hashable {
        let title: String
        let query: String
        let category: BookCategory
        var id: String { title }
    }

    static let presets: [Preset] = [
        Preset(title: "Sách tiếng Việt xưa", query: "language:(vie OR vietnamese)", category: .vietnamese),
        Preset(title: "Trinh thám", query: "subject:(detective OR mystery)", category: .detective),
        Preset(title: "Truyện ma, kinh dị", query: "subject:(ghost OR horror OR supernatural)", category: .mystery),
        Preset(title: "Tiểu sử, doanh nhân", query: "subject:(biography OR autobiography OR business)", category: .business),
        Preset(title: "Truyện tranh xưa", query: "subject:(comics OR \"comic books\" OR cartoons)", category: .comics),
        Preset(title: "Sherlock Holmes", query: "title:(sherlock holmes)", category: .detective)
    ]

    private static let legalFilter =
        "mediatype:texts AND format:PDF AND -collection:inlibrary AND -collection:printdisabled "
        + "AND -access-restricted-item:true AND (year:[1000 TO 1929] OR licenseurl:*publicdomain*)"

    static func search(_ text: String) async throws -> [ArchiveItem] {
        var comps = URLComponents(string: "https://archive.org/advancedsearch.php")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "(\(text)) AND \(legalFilter)"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "year"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: "50"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "output", value: "json")
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 40
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else { return [] }

        func text(_ value: Any?) -> String {
            if let s = value as? String { return s }
            if let a = value as? [String] { return a.joined(separator: ", ") }
            if let n = value as? NSNumber { return n.stringValue }
            return ""
        }
        return docs.compactMap { doc in
            guard let id = doc["identifier"] as? String else { return nil }
            return ArchiveItem(id: id, title: text(doc["title"]).isEmpty ? id : text(doc["title"]),
                               creator: text(doc["creator"]), year: text(doc["year"]))
        }
    }

    /// Tìm tệp PDF chính của một mục.
    static func pdfURL(for id: String) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://archive.org/metadata/\(id)")!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { throw ImportError.notABook }
        let pdfs = files.filter { ($0["name"] as? String)?.lowercased().hasSuffix(".pdf") == true }
        let best = pdfs.first { ($0["format"] as? String) == "Text PDF" } ?? pdfs.first
        guard let name = best?["name"] as? String,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/download/\(id)/\(encoded)") else { throw ImportError.notABook }
        return url
    }
}

struct ArchivePDFView: View {
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer
    @Query private var books: [Book]

    @State private var preset: InternetArchive.Preset? = InternetArchive.presets.first
    @State private var query = ""
    @State private var results: [ArchiveItem] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var owned: Set<String> { Set(books.compactMap(\.sourceURL)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sách PDF miễn phí trên Internet Archive. App chỉ tìm sách xuất bản trước năm 1930 hoặc được ghi là thuộc phạm vi công cộng. Nhiều cuốn là bản quét sách giấy nên giữ nguyên hình minh hoạ.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(InternetArchive.presets) { p in
                            ChipButton(title: p.title, color: p.category.color, isSelected: preset == p && query.isEmpty) {
                                query = ""
                                preset = p
                                Task { await load() }
                            }
                        }
                    }
                }

                if isLoading && results.isEmpty {
                    ProgressView("Đang tìm sách…").frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text(errorText).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Thử lại") { Task { await load() } }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                } else if results.isEmpty {
                    Text("Không tìm thấy sách phù hợp.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { item in row(item) }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .navigationTitle("Sách PDF miễn phí")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Tìm sách PDF (tên, tác giả)")
        .onSubmit(of: .search) { Task { await load() } }
        .task { if results.isEmpty { await load() } }
    }

    private func row(_ item: ArchiveItem) -> some View {
        let isOwned = owned.contains(item.sourceKey)
        let category = preset?.category ?? .other
        return HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                PlaceholderCover(title: item.title, author: "", category: category)
            }
            .frame(width: 64, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                Text([item.creator, item.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    Task { await download(item, category: category) }
                } label: {
                    Label(isOwned ? "Đã có trong thư viện" : "Tải PDF",
                          systemImage: isOwned ? "checkmark.circle.fill" : "arrow.down.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(isOwned ? .green : category.color)
                .disabled(isOwned)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        let text: String
        if !query.isEmpty {
            text = "title:(\(query)) OR creator:(\(query))"
        } else {
            text = preset?.query ?? "subject:fiction"
        }
        do {
            results = try await InternetArchive.search(text)
        } catch {
            results = []
            errorText = "Chưa kết nối được Internet Archive. Kiểm tra mạng rồi thử lại."
        }
    }

    private func download(_ item: ArchiveItem, category: BookCategory) async {
        do {
            let url = try await InternetArchive.pdfURL(for: item.id)
            await importer.importLink(url.absoluteString, category: category, context: context,
                                      sourceKey: item.sourceKey)
        } catch {
            importer.errorMessage = "Không tìm thấy tệp PDF của cuốn này."
        }
    }
}
