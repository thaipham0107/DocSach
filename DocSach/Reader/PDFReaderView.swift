import SwiftUI
import PDFKit

/// Đọc sách PDF: lật trang ngang hoặc cuộn dọc, chế độ đêm, đèn vàng, kéo thanh để nhảy trang.
struct PDFReaderView: View {
    let book: Book
    let url: URL
    var onClose: () -> Void

    @AppStorage("pdf.vertical") private var vertical = false
    @AppStorage("pdf.night") private var night = false
    @AppStorage("reader.warmth") private var warmth = 0.0

    @State private var page = 0
    @State private var pageCount = 1
    @State private var showControls = true
    @State private var jump = PDFJump(page: 0, token: 0)
    @State private var sliderValue = 0.0
    @State private var isDraggingSlider = false

    var body: some View {
        ZStack {
            (night ? Color.black : Color(hex: "E9E4DA")).ignoresSafeArea()

            PDFKitView(url: url, startPage: book.positionPage, vertical: vertical, jump: jump,
                       onTap: { withAnimation { showControls.toggle() } }) { current, total in
                page = current
                pageCount = total
                if !isDraggingSlider { sliderValue = Double(current) }
                book.positionPage = current
                book.progress = Double(current + 1) / Double(max(total, 1))
                book.lastOpenedAt = Date()
                if current == total - 1 { book.isFinished = true }
            }
            .colorInvertIf(night)
            .ignoresSafeArea(edges: .bottom)

            Color(hex: "FF9A3C")
                .opacity(warmth * 0.35)
                .blendMode(.multiply)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if showControls {
                controls.transition(.opacity)
            } else {
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
                        Text("\(page + 1)/\(pageCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .padding(.trailing, 14)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }
        }
        .statusBarHidden(!showControls)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onClose) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Thư viện")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Text(book.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 12) {
                if pageCount > 1 {
                    Slider(value: $sliderValue, in: 0...Double(pageCount - 1), step: 1) { editing in
                        isDraggingSlider = editing
                        if !editing { jump = PDFJump(page: Int(sliderValue), token: jump.token + 1) }
                    }
                    .tint(AppTheme.accent)
                }
                Text("Trang \(Int(sliderValue) + 1) / \(pageCount)").font(.caption.monospacedDigit())
                HStack {
                    controlButton(vertical ? "Lật trang" : "Cuộn dọc",
                                  icon: vertical ? "book.pages" : "arrow.up.and.down.text.horizontal") {
                        vertical.toggle()
                    }
                    controlButton(night ? "Ngày" : "Đêm", icon: night ? "sun.max.fill" : "moon.fill") {
                        night.toggle()
                    }
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb").font(.caption)
                            Slider(value: $warmth, in: 0...1)
                            Image(systemName: "lightbulb.fill").font(.caption).foregroundStyle(.orange)
                        }
                        Text("Đèn vàng").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(night ? Color.white : AppTheme.ink)
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
}

struct PDFJump: Equatable {
    var page: Int
    var token: Int
}

private extension View {
    @ViewBuilder
    func colorInvertIf(_ on: Bool) -> some View {
        if on { self.colorInvert().hueRotation(.degrees(180)) } else { self }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let startPage: Int
    let vertical: Bool
    let jump: PDFJump
    var onTap: () -> Void
    var onPage: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPage: onPage, onTap: onTap) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .clear
        context.coordinator.pdfView = view
        context.coordinator.lastJumpToken = jump.token
        apply(vertical: vertical, to: view)
        context.coordinator.isVertical = vertical
        if let doc = PDFDocument(url: url) {
            view.document = doc
            if let page = doc.page(at: min(max(startPage, 0), max(doc.pageCount - 1, 0))) { view.go(to: page) }
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        DispatchQueue.main.async { context.coordinator.pageChanged() }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let c = context.coordinator
        c.onPage = onPage
        c.onTap = onTap
        if c.isVertical != vertical {
            let current = view.currentPage
            apply(vertical: vertical, to: view)
            c.isVertical = vertical
            if let current { DispatchQueue.main.async { view.go(to: current) } }
        }
        if jump.token != c.lastJumpToken {
            c.lastJumpToken = jump.token
            if let page = view.document?.page(at: jump.page) { view.go(to: page) }
        }
    }

    private func apply(vertical: Bool, to view: PDFView) {
        if vertical {
            view.usePageViewController(false)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        } else {
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(true)
        }
        view.autoScales = true
        view.displaysPageBreaks = vertical
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPage: (Int, Int) -> Void
        var onTap: () -> Void
        weak var pdfView: PDFView?
        var isVertical: Bool?
        var lastJumpToken = 0

        init(onPage: @escaping (Int, Int) -> Void, onTap: @escaping () -> Void) {
            self.onPage = onPage
            self.onTap = onTap
        }

        @objc func pageChanged() {
            guard let view = pdfView, let doc = view.document, let current = view.currentPage else { return }
            onPage(doc.index(for: current), doc.pageCount)
        }

        @objc func tapped() { onTap() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
