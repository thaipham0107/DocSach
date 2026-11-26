import SwiftUI
import SwiftData

/// Kho sách miễn phí hợp pháp (Project Gutenberg) theo chủ đề.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer
    @Query private var books: [Book]

    @State private var category: BookCategory = .business
    @State private var shelf: Shelf? = Shelf.shelves(for: .business).first
    @State private var query = ""
    @State private var results: [GutenBook] = []
    @State private var nextURL: URL?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showLinkSheet = false
    @State private var showFilePicker = false

    private let categories: [BookCategory] = [.business, .detective, .mystery, .comics]

    private var ownedSources: Set<String> { Set(books.compactMap(\.sourceURL)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories) { c in
                                ChipButton(title: c.title, icon: c.icon, color: c.color, isSelected: category == c) {
                                    select(category: c)
                                }
                            }
                        }
                    }

                    if category == .comics {
                        comicsInfo
                    } else {
                        shelvesBar
                        resultsList
                    }

                    sourcesNote
                }
                .padding()
            }
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("Khám phá")
            .searchable(text: $query, prompt: "Tìm sách miễn phí (tiếng Anh)")
            .onSubmit(of: .search) { Task { await load() } }
            .sheet(isPresented: $showLinkSheet) { LinkImportSheet(initialCategory: category) }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: LibraryView.importTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await importer.importFiles(urls, category: category, context: context) }
                }
            }
            .task { if results.isEmpty { await load() } }
        }
    }

    private var shelvesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Shelf.shelves(for: category)) { s in
                    ChipButton(title: s.title, color: category.color, isSelected: shelf == s && query.isEmpty) {
                        query = ""
                        shelf = s
                        Task { await load() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isLoading && results.isEmpty {
            ProgressView("Đang tìm sách…").frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let errorText {
            VStack(spacing: 10) {
                Text(errorText).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Thử lại") { Task { await load() } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if results.isEmpty {
            Text("Không tìm thấy sách phù hợp.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(results) { item in row(item) }
                if let next = nextURL {
                    Button {
                        Task { await loadMore(next) }
                    } label: {
                        if isLoading { ProgressView() } else { Text("Xem thêm") }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func row(_ item: GutenBook) -> some View {
        let owned = item.epubURL.map { ownedSources.contains($0.absoluteString) } ?? false
        return HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                PlaceholderCover(title: item.title, author: "", category: category)
            }
            .frame(width: 64, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                Text(item.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let count = item.downloadCount {
                    Label("\(count.formatted()) lượt tải", systemImage: "arrow.down.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let epub = item.epubURL {
                    Button {
                        Task { await importer.importLink(epub.absoluteString, category: category, context: context) }
                    } label: {
                        Label(owned ? "Đã có trong thư viện" : "Tải về thư viện",
                              systemImage: owned ? "checkmark.circle.fill" : "arrow.down.to.line")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(owned ? .green : category.color)
                    .disabled(owned)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var comicsInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Truyện tranh màu (Conan, Doraemon…)", systemImage: "face.smiling.inverse")
                .font(.headline)
            Text("Conan, Doraemon và các bộ truyện tranh nổi tiếng đều còn bản quyền, nên ứng dụng không tự tải về được. Khi bạn đã có bản truyện (mua ebook, tải từ nguồn bạn được phép dùng), hãy nạp vào đây. Ứng dụng đọc được:")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                Label("CBZ hoặc ZIP chứa ảnh trang (giữ nguyên màu)", systemImage: "photo.stack")
                Label("PDF truyện tranh", systemImage: "doc.richtext")
                Label("EPUB truyện tranh", systemImage: "book")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("Mẹo: truyện Nhật như Conan, Doraemon đọc từ phải sang trái. Khi đọc, chạm giữa màn hình → biểu tượng sách → chọn “Lật phải → trái (manga)”.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button { showFilePicker = true } label: { Label("Nạp tệp", systemImage: "folder") }
                    .buttonStyle(.borderedProminent)
                    .tint(BookCategory.comics.color)
                Button { showLinkSheet = true } label: { Label("Dán link", systemImage: "link") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var sourcesNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Về nguồn sách").font(.footnote.bold())
            Text("Sách ở đây lấy từ Project Gutenberg: hơn 70.000 cuốn đã hết bản quyền, miễn phí và hợp pháp, phần lớn bằng tiếng Anh (Henry Ford, Sherlock Holmes, Edgar Allan Poe…). Sách mới như tiểu sử Elon Musk hay Quỷ Cổ Nữ còn bản quyền: bạn mua ebook rồi nạp vào bằng tệp hoặc link.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Tải dữ liệu

    private func select(category c: BookCategory) {
        category = c
        query = ""
        shelf = Shelf.shelves(for: c).first
        results = []
        nextURL = nil
        errorText = nil
        if c != .comics { Task { await load() } }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let page = try await Gutendex.fetch(shelf: shelf, query: query)
            results = page.results.filter { $0.epubURL != nil }
            nextURL = page.next.flatMap(URL.init(string:))
        } catch {
            results = []
            errorText = "Chưa kết nối được kho sách. Kiểm tra mạng rồi thử lại.\n(\(error.localizedDescription))"
        }
    }

    private func loadMore(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        if let page = try? await Gutendex.fetch(url: url) {
            results += page.results.filter { $0.epubURL != nil }
            nextURL = page.next.flatMap(URL.init(string:))
        }
    }
}
