import SwiftUI

/// Đọc truyện tranh (CBZ/ZIP ảnh): lật trái-phải, phải-trái (manga) hoặc cuộn dọc.
struct ComicReaderView: View {
    let book: Book
    let pages: [URL]
    var onClose: () -> Void

    @State private var page: Int
    @State private var scrollID: Int?
    @State private var showControls = true
    @State private var mode: ComicMode

    init(book: Book, pages: [URL], onClose: @escaping () -> Void) {
        self.book = book
        self.pages = pages
        self.onClose = onClose
        let start = min(max(book.positionPage, 0), max(pages.count - 1, 0))
        _page = State(initialValue: start)
        _scrollID = State(initialValue: start)
        _mode = State(initialValue: book.comicMode)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if mode == .vertical { verticalReader } else { pagedReader }
            }
            .ignoresSafeArea()

            if !showControls {
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }
                        .accessibilityLabel("Thoát về thư viện")
                        .padding(.leading, 14)
                        .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
            }
            if showControls { controls.transition(.opacity) }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(.dark)
        .onChange(of: page) { _, newValue in save(newValue) }
        .onChange(of: scrollID) { _, newValue in
            if let newValue, mode == .vertical, newValue != page { page = newValue }
        }
    }

    private var pagedReader: some View {
        TabView(selection: $page) {
            ForEach(pages.indices, id: \.self) { i in
                ZoomableImageView(url: pages[i]) { x in handleTap(x) }
                    .environment(\.layoutDirection, .leftToRight)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    private var verticalReader: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { i in
                    AsyncPageImage(url: pages[i]).id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollID, anchor: .top)
        .onTapGesture { withAnimation { showControls.toggle() } }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onClose) { Image(systemName: "chevron.down.circle.fill").font(.title) }
                Text(book.title).font(.headline).lineLimit(1)
                Spacer()
                Menu {
                    Picker("Cách đọc", selection: $mode) {
                        ForEach(ComicMode.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "book.pages").font(.title2)
                }
                .onChange(of: mode) { _, newMode in
                    book.comicMode = newMode
                    scrollID = page
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 8) {
                if pages.count > 1 {
                    Slider(value: Binding(
                        get: { Double(page) },
                        set: { newValue in
                            page = Int(newValue.rounded())
                            scrollID = page
                        }), in: 0...Double(pages.count - 1))
                    .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
                }
                Text("Trang \(page + 1) / \(pages.count)").font(.caption.monospacedDigit())
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }

    private func handleTap(_ x: CGFloat) {
        let forward = mode == .rightToLeft ? x < 0.25 : x > 0.75
        let backward = mode == .rightToLeft ? x > 0.75 : x < 0.25
        if forward, page < pages.count - 1 {
            withAnimation { page += 1 }
        } else if backward, page > 0 {
            withAnimation { page -= 1 }
        } else {
            withAnimation { showControls.toggle() }
        }
    }

    private func save(_ page: Int) {
        book.positionPage = page
        book.progress = pages.isEmpty ? 0 : Double(page + 1) / Double(pages.count)
        book.lastOpenedAt = Date()
        if page == pages.count - 1 { book.isFinished = true }
    }
}
