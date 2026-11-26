import SwiftUI
import SwiftData

struct EPUBReaderView: View {
    let book: Book
    let package: EPUBPackage
    var onClose: () -> Void

    @Environment(\.modelContext) private var context

    @AppStorage("reader.theme") private var themeRaw = ReaderTheme.cream.rawValue
    @AppStorage("reader.fontSize") private var fontSize = 19.0
    @AppStorage("reader.lineHeight") private var lineHeight = 1.6
    @AppStorage("reader.font") private var fontRaw = ReaderFont.original.rawValue
    @AppStorage("reader.margin") private var margin = 22.0
    @AppStorage("reader.warmth") private var warmth = 0.0

    @State private var target: ReaderTarget
    @State private var chapter: Int
    @State private var page = 0
    @State private var pageCount = 1
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showContents = false
    @State private var showFinished = false

    init(book: Book, package: EPUBPackage, onClose: @escaping () -> Void) {
        self.book = book
        self.package = package
        self.onClose = onClose
        let start = min(max(book.positionChapter, 0), package.spine.count - 1)
        _target = State(initialValue: ReaderTarget(chapter: start, fraction: book.positionFraction, token: 0))
        _chapter = State(initialValue: start)
    }

    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .cream }

    private var style: ReaderStyle {
        ReaderStyle(theme: theme, fontSize: fontSize, lineHeight: lineHeight,
                    font: ReaderFont(rawValue: fontRaw) ?? .original, margin: margin)
    }

    private var overallProgress: Double {
        let total = Double(max(package.spine.count, 1))
        return min(1, (Double(chapter) + Double(page + 1) / Double(max(pageCount, 1))) / total)
    }

    private var currentFraction: Double { Double(page) / Double(max(pageCount, 1)) }

    private var currentBookmark: Bookmark? {
        let tolerance = 0.5 / Double(max(pageCount, 1))
        return book.bookmarks.first { $0.chapter == chapter && abs($0.fraction - currentFraction) < tolerance }
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Nút thoát luôn hiện: quay về Thư viện
                    Button(action: onClose) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                            Text("Thư viện")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.text.opacity(0.08), in: Capsule())
                    }
                    .foregroundStyle(theme.text.opacity(0.75))
                    .accessibilityLabel("Thoát về thư viện")

                    Text(package.chapterTitle(for: chapter) ?? book.title)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .frame(height: 40)

                EPUBWebView(package: package, target: target, style: style,
                            onLocation: handleLocation,
                            onTapCenter: { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } },
                            onReachEnd: { book.isFinished = true; book.progress = 1; showFinished = true })

                HStack {
                    Text("Trang \(page + 1)/\(pageCount)")
                    Spacer()
                    Text("\(Int(overallProgress * 100))%")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 24)
                .frame(height: 24)
            }

            // Đèn vàng: phủ một lớp màu ấm để dịu mắt
            Color(hex: "FF9A3C")
                .opacity(warmth * 0.35)
                .blendMode(.multiply)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let mark = currentBookmark {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "bookmark.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "D9534F"))
                            .padding(.trailing, 20)
                            .accessibilityLabel(mark.note)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if showControls { controls.transition(.opacity) }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(themeRaw: $themeRaw, fontSize: $fontSize, lineHeight: $lineHeight,
                                fontRaw: $fontRaw, margin: $margin, warmth: $warmth)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showContents) {
            ContentsSheet(book: book, package: package, currentChapter: chapter) { chapter, fraction in
                jump(chapter: chapter, fraction: fraction)
                showContents = false
            }
        }
        .alert("Bạn đã đọc xong cuốn sách! 🎉", isPresented: $showFinished) {
            Button("Về thư viện") { onClose() }
            Button("Ở lại", role: .cancel) {}
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button(action: onClose) {
                    Image(systemName: "chevron.down.circle.fill").font(.title)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.headline).lineLimit(1)
                    if !book.author.isEmpty { Text(book.author).font(.caption).lineLimit(1).opacity(0.7) }
                }
                Spacer()
                Button(action: toggleBookmark) {
                    Image(systemName: currentBookmark == nil ? "bookmark" : "bookmark.fill").font(.title2)
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 12) {
                HStack {
                    Button { if chapter > 0 { jump(chapter: chapter - 1, fraction: 0) } } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(chapter == 0)
                    ProgressView(value: overallProgress).tint(AppTheme.accent)
                    Button { if chapter + 1 < package.spine.count { jump(chapter: chapter + 1, fraction: 0) } } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(chapter + 1 >= package.spine.count)
                }
                HStack {
                    controlButton("Mục lục", icon: "list.bullet") { showContents = true }
                    controlButton("Giao diện", icon: "textformat.size") { showSettings = true }
                    controlButton(theme.isDark ? "Ngày" : "Đêm", icon: theme.isDark ? "sun.max.fill" : "moon.fill") {
                        themeRaw = theme.isDark ? ReaderTheme.cream.rawValue : ReaderTheme.night.rawValue
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(theme.isDark ? Color.white : AppTheme.ink)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func handleLocation(chapter: Int, page: Int, pageCount: Int) {
        self.chapter = chapter
        self.page = page
        self.pageCount = pageCount
        book.positionChapter = chapter
        book.positionFraction = Double(page) / Double(max(pageCount, 1))
        book.progress = overallProgress
        book.lastOpenedAt = Date()
    }

    private func jump(chapter: Int, fraction: Double) {
        target = ReaderTarget(chapter: chapter, fraction: fraction, token: target.token + 1)
    }

    private func toggleBookmark() {
        if let mark = currentBookmark {
            context.delete(mark)
        } else {
            let title = package.chapterTitle(for: chapter) ?? "Chương \(chapter + 1)"
            let mark = Bookmark(chapter: chapter, fraction: currentFraction, page: page,
                                note: "\(title) · trang \(page + 1)")
            mark.book = book
            context.insert(mark)
        }
        try? context.save()
    }
}

/// Mục lục + danh sách dấu trang.
struct ContentsSheet: View {
    let book: Book
    let package: EPUBPackage
    let currentChapter: Int
    var onSelect: (Int, Double) -> Void

    @Environment(\.modelContext) private var context
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Mục lục").tag(0)
                    Text("Dấu trang (\(book.bookmarks.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == 0 {
                    List {
                        if package.toc.isEmpty {
                            ForEach(package.spine.indices, id: \.self) { i in
                                row(title: "Phần \(i + 1)", level: 0, chapter: i)
                            }
                        } else {
                            ForEach(package.toc) { item in
                                row(title: item.title, level: item.level, chapter: item.spineIndex)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    let marks = book.bookmarks.sorted { ($0.chapter, $0.fraction) < ($1.chapter, $1.fraction) }
                    if marks.isEmpty {
                        ContentUnavailableView("Chưa có dấu trang", systemImage: "bookmark",
                                               description: Text("Chạm giữa màn hình khi đọc rồi bấm biểu tượng dấu trang."))
                    } else {
                        List {
                            ForEach(marks) { mark in
                                Button { onSelect(mark.chapter, mark.fraction) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mark.note).foregroundStyle(.primary)
                                        Text(mark.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for i in offsets { context.delete(marks[i]) }
                                try? context.save()
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private func row(title: String, level: Int, chapter: Int) -> some View {
        Button { onSelect(chapter, 0) } label: {
            HStack {
                Text(title)
                    .padding(.leading, CGFloat(min(level, 4)) * 16)
                    .foregroundStyle(chapter == currentChapter ? AppTheme.accent : .primary)
                    .fontWeight(chapter == currentChapter ? .semibold : .regular)
                Spacer()
            }
        }
    }
}
