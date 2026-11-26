import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Book
    let url: URL
    var onClose: () -> Void

    @State private var page = 0
    @State private var pageCount = 1
    @State private var showControls = true

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            PDFKitView(url: url, startPage: book.positionPage) { current, total in
                page = current
                pageCount = total
                book.positionPage = current
                book.progress = Double(current + 1) / Double(max(total, 1))
                book.lastOpenedAt = Date()
                if current == total - 1 { book.isFinished = true }
            }
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture { withAnimation { showControls.toggle() } }

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
            if showControls {
                HStack(spacing: 14) {
                    Button(action: onClose) { Image(systemName: "chevron.down.circle.fill").font(.title) }
                    Text(book.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(page + 1)/\(pageCount)").font(.caption.monospacedDigit())
                }
                .padding()
                .background(.ultraThinMaterial)
                .transition(.opacity)
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let startPage: Int
    var onPage: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPage: onPage) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true)
        view.autoScales = true
        view.backgroundColor = .systemBackground
        if let doc = PDFDocument(url: url) {
            view.document = doc
            if let page = doc.page(at: min(max(startPage, 0), max(doc.pageCount - 1, 0))) { view.go(to: page) }
        }
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        DispatchQueue.main.async { context.coordinator.pageChanged() }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.onPage = onPage
    }

    final class Coordinator: NSObject {
        var onPage: (Int, Int) -> Void
        weak var pdfView: PDFView?
        init(onPage: @escaping (Int, Int) -> Void) { self.onPage = onPage }

        @objc func pageChanged() {
            guard let view = pdfView, let doc = view.document, let current = view.currentPage else { return }
            onPage(doc.index(for: current), doc.pageCount)
        }
    }
}
