import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Query private var days: [ReadingDay]
    @AppStorage(ReadingStats.goalKey) private var goalMinutes = ReadingStats.defaultGoal

    @State private var filter: BookCategory? = nil
    @State private var search = ""
    @State private var showFilePicker = false
    @State private var showLinkSheet = false
    @State private var openBook: Book?
    @State private var bookToDelete: Book?

    static let importTypes: [UTType] = {
        var types: [UTType] = [.epub, .pdf, .zip]
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        types.append(.data)
        return types
    }()

    private var filtered: [Book] {
        books.filter { book in
            (filter == nil || book.category == filter) &&
            (search.isEmpty || book.title.localizedCaseInsensitiveContains(search)
             || book.author.localizedCaseInsensitiveContains(search))
        }
    }

    private var continueBook: Book? {
        books.filter { $0.lastOpenedAt != nil && !$0.isFinished }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private var todayMinutes: Int {
        let key = ReadingStats.key(for: Date())
        return Int((days.first { $0.day == key }?.seconds ?? 0) / 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    todayCard
                    if let book = continueBook, filter == nil, search.isEmpty { continueCard(book) }
                    categoryBar
                    if filtered.isEmpty { emptyState } else { grid }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("Thư viện")
            .searchable(text: $search, prompt: "Tìm theo tên sách, tác giả")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: Self.importTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await importer.importFiles(urls, category: filter, context: context) }
                }
            }
            .sheet(isPresented: $showLinkSheet) { LinkImportSheet(initialCategory: filter) }
            .fullScreenCover(item: $openBook) { book in ReaderContainer(book: book) }
            .confirmationDialog("Xoá sách khỏi máy?", isPresented: Binding(
                get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Xoá", role: .destructive) {
                    if let book = bookToDelete { ImportCenter.delete(book, context: context) }
                    bookToDelete = nil
                }
            } message: {
                Text(bookToDelete?.title ?? "")
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button { showFilePicker = true } label: { Label("Nạp tệp từ máy (Tệp)", systemImage: "folder") }
            Button { showLinkSheet = true } label: { Label("Thêm từ link", systemImage: "link") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
    }

    private var todayCard: some View {
        let progress = min(1, Double(todayMinutes) / Double(max(goalMinutes, 1)))
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%").font(.caption.bold())
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(progress >= 1 ? "Tuyệt vời! Đã đạt mục tiêu 🎉" : "Hôm nay").font(.headline)
                Text("Đã đọc \(todayMinutes) / \(goalMinutes) phút").font(.subheadline).opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding()
        .background(AppTheme.warmGradient, in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 4)
    }

    private func continueCard(_ book: Book) -> some View {
        Button { openBook = book } label: {
            HStack(spacing: 14) {
                BookCoverView(book: book, cornerRadius: 6).frame(width: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Đọc tiếp").font(.caption.bold()).foregroundStyle(AppTheme.accent)
                    Text(book.title).font(.headline).lineLimit(2).foregroundStyle(AppTheme.ink)
                    ProgressView(value: book.progress).tint(AppTheme.accent)
                    Text("\(Int(book.progress * 100))% đã đọc").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(AppTheme.accent)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: "Tất cả (\(books.count))", icon: "square.grid.2x2.fill", isSelected: filter == nil) {
                    filter = nil
                }
                ForEach(BookCategory.allCases) { c in
                    let count = books.filter { $0.category == c }.count
                    ChipButton(title: "\(c.title) (\(count))", icon: c.icon, color: c.color, isSelected: filter == c) {
                        filter = c
                    }
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16)], spacing: 22) {
            ForEach(filtered) { book in
                Button { openBook = book } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        BookCoverView(book: book)
                            .overlay(alignment: .topTrailing) {
                                if book.isFinished {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.white, .green)
                                        .font(.title3)
                                        .padding(4)
                                }
                            }
                        Text(book.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        ProgressView(value: book.progress)
                            .tint(book.category.color)
                            .opacity(book.progress > 0 ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { contextMenu(for: book) }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for book: Book) -> some View {
        Menu {
            ForEach(BookCategory.allCases) { c in
                Button { book.category = c; try? context.save() } label: { Label(c.title, systemImage: c.icon) }
            }
        } label: {
            Label("Chuyển sang mục", systemImage: "folder")
        }
        Button {
            book.isFinished.toggle()
            if book.isFinished { book.progress = 1 }
            try? context.save()
        } label: {
            Label(book.isFinished ? "Đánh dấu chưa đọc xong" : "Đánh dấu đã đọc xong", systemImage: "checkmark.circle")
        }
        Button(role: .destructive) { bookToDelete = book } label: { Label("Xoá sách", systemImage: "trash") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 54))
                .foregroundStyle(AppTheme.accent.opacity(0.7))
            Text(books.isEmpty ? "Thư viện còn trống" : "Không có sách phù hợp").font(.title3.bold())
            Text("Nạp tệp EPUB, CBZ hoặc PDF từ máy, dán link tải sách, hoặc vào tab Khám phá để tải sách miễn phí.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button { showFilePicker = true } label: { Label("Nạp tệp", systemImage: "folder") }
                    .buttonStyle(.borderedProminent)
                Button { showLinkSheet = true } label: { Label("Dán link", systemImage: "link") }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
