import SwiftUI
import SwiftData

/// Mở sách đúng trình đọc theo định dạng và đếm thời gian đọc.
struct ReaderContainer: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer = ReadingTimer()
    @State private var state: LoadState = .loading

    enum LoadState {
        case loading
        case epub(EPUBPackage)
        case comic([URL])
        case pdf(URL)
        case failed(String)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ZStack {
                    AppTheme.paper.ignoresSafeArea()
                    ProgressView("Đang mở sách…")
                }
            case .epub(let package):
                EPUBReaderView(book: book, package: package, onClose: close)
            case .comic(let pages):
                ComicReaderView(book: book, pages: pages, onClose: close)
            case .pdf(let url):
                PDFReaderView(book: book, url: url, onClose: close)
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text(message).multilineTextAlignment(.center)
                    Button("Đóng", action: close).buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .task { await load() }
        .onAppear { timer.start() }
        .onDisappear { timer.stop(context: context, bookTitle: book.title) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { timer.start() } else { timer.stop(context: context, bookTitle: book.title) }
        }
    }

    private func close() {
        book.lastOpenedAt = Date()
        try? context.save()
        timer.stop(context: context, bookTitle: book.title)
        dismiss()
    }

    private func load() async {
        book.lastOpenedAt = Date()
        let id = book.id
        let file = book.fileURL
        let format = book.format
        do {
            state = try await Task.detached(priority: .userInitiated) { () throws -> LoadState in
                switch format {
                case .epub:
                    let dir = try BookStorage.ensureExtracted(id: id, archive: file)
                    return .epub(try EPUBPackage.load(from: dir))
                case .comic:
                    let dir = try BookStorage.ensureExtracted(id: id, archive: file)
                    let pages = BookStorage.comicPages(in: dir)
                    return pages.isEmpty ? .failed("Không tìm thấy trang ảnh nào trong tệp.") : .comic(pages)
                case .pdf:
                    return .pdf(file)
                }
            }.value
        } catch {
            state = .failed("Không mở được sách.\n\(error.localizedDescription)")
        }
    }
}
