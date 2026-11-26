import SwiftUI
import WebKit

/// Vị trí cần nhảy tới (đổi `token` để ra lệnh nhảy).
struct ReaderTarget: Equatable {
    var chapter: Int
    var fraction: Double
    var token: Int
}

/// WKWebView hiển thị từng chương EPUB, chia trang bằng CSS columns,
/// vuốt hoặc chạm hai bên mép để lật trang.
final class PagedWebView: WKWebView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastWidth) > 1 {
            lastWidth = bounds.width
            onWidthChange?()
        }
    }
}

struct EPUBWebView: UIViewRepresentable {
    let package: EPUBPackage
    let target: ReaderTarget
    let style: ReaderStyle
    var onLocation: (_ chapter: Int, _ page: Int, _ pageCount: Int) -> Void
    var onTapCenter: () -> Void
    var onReachEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PagedWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []
        let webView = PagedWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(hex: style.theme.backgroundHex)
        webView.navigationDelegate = context.coordinator

        let sv = webView.scrollView
        sv.backgroundColor = UIColor(hex: style.theme.backgroundHex)
        sv.contentInsetAdjustmentBehavior = .never
        sv.isPagingEnabled = true
        sv.bounces = true
        sv.alwaysBounceHorizontal = true
        sv.alwaysBounceVertical = false
        sv.isDirectionalLockEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.decelerationRate = .fast
        sv.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        let c = context.coordinator
        c.webView = webView
        c.appliedStyle = style
        c.lastToken = target.token
        webView.onWidthChange = { [weak c] in c?.relayoutKeepingPosition() }
        c.load(chapter: target.chapter, fraction: target.fraction)
        return webView
    }

    func updateUIView(_ webView: PagedWebView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.appliedStyle != style {
            c.appliedStyle = style
            webView.backgroundColor = UIColor(hex: style.theme.backgroundHex)
            webView.scrollView.backgroundColor = UIColor(hex: style.theme.backgroundHex)
            c.restyle()
        }
        if target.token != c.lastToken {
            c.lastToken = target.token
            if target.chapter == c.loadedChapter && c.isReady {
                c.go(fraction: target.fraction)
            } else {
                c.load(chapter: target.chapter, fraction: target.fraction)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: EPUBWebView
        weak var webView: PagedWebView?
        var appliedStyle: ReaderStyle?
        var lastToken = -1
        var loadedChapter = -1
        var pendingFraction = 0.0
        var pageCount = 1
        var currentPage = 0
        var isReady = false
        private var layoutGeneration = 0

        init(parent: EPUBWebView) { self.parent = parent }

        var currentFraction: Double { Double(currentPage) / Double(max(pageCount, 1)) }

        // MARK: Tải chương

        func load(chapter: Int, fraction: Double) {
            guard let webView, parent.package.spine.indices.contains(chapter) else { return }
            isReady = false
            loadedChapter = chapter
            pendingFraction = fraction
            webView.alpha = 0
            installUserScript()
            webView.loadFileURL(parent.package.spine[chapter], allowingReadAccessTo: parent.package.rootDirectory)
        }

        private func installUserScript() {
            guard let webView, let style = appliedStyle else { return }
            let ucc = webView.configuration.userContentController
            ucc.removeAllUserScripts()
            ucc.addUserScript(WKUserScript(source: style.injectionJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

        func restyle() {
            guard let webView, let style = appliedStyle else { return }
            installUserScript()
            guard isReady else { return }
            let keep = currentFraction
            webView.evaluateJavaScript(style.injectionJS) { [weak self] _, _ in
                self?.layout(restoring: keep)
            }
        }

        func relayoutKeepingPosition() {
            guard isReady else { return }
            layout(restoring: currentFraction)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            layout(restoring: pendingFraction)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.alpha = 1
        }

        /// Đợi ảnh & font tải xong rồi đếm số trang.
        func layout(restoring fraction: Double) {
            guard let webView else { return }
            layoutGeneration += 1
            let generation = layoutGeneration
            let js = """
            if (document.fonts && document.fonts.ready) { await document.fonts.ready; }
            await Promise.all(Array.from(document.images).filter(function(i){ return !i.complete; }).map(function(i){
              return new Promise(function(r){ i.addEventListener('load', r); i.addEventListener('error', r); setTimeout(r, 2000); });
            }));
            await new Promise(function(r){ setTimeout(r, 60); });
            var de = document.documentElement;
            de.style.width = 'auto';
            var w = window.innerWidth;
            var n = Math.max(1, Math.ceil((de.scrollWidth - 2) / w));
            de.style.width = (n * w) + 'px';
            return n;
            """
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, let webView = self.webView, generation == self.layoutGeneration else { return }
                var n = 1
                if case .success(let value) = result, let number = value as? NSNumber { n = max(1, number.intValue) }
                self.pageCount = n
                let page = Int((fraction * Double(n)).rounded(.down))
                self.go(to: page, animated: false)
                self.isReady = true
                UIView.animate(withDuration: 0.18) { webView.alpha = 1 }
            }
        }

        // MARK: Lật trang

        func go(fraction: Double) {
            go(to: Int((fraction * Double(pageCount)).rounded(.down)), animated: false)
        }

        func go(to page: Int, animated: Bool) {
            guard let webView else { return }
            currentPage = max(0, min(pageCount - 1, page))
            let width = webView.scrollView.bounds.width
            webView.scrollView.setContentOffset(CGPoint(x: CGFloat(currentPage) * width, y: 0), animated: animated)
            report()
        }

        func nextPage() {
            if currentPage < pageCount - 1 { go(to: currentPage + 1, animated: true) } else { nextChapter() }
        }

        func previousPage() {
            if currentPage > 0 { go(to: currentPage - 1, animated: true) } else { previousChapter() }
        }

        func nextChapter() {
            if loadedChapter + 1 < parent.package.spine.count {
                load(chapter: loadedChapter + 1, fraction: 0)
            } else {
                parent.onReachEnd()
            }
        }

        func previousChapter() {
            if loadedChapter > 0 { load(chapter: loadedChapter - 1, fraction: 1) }
        }

        private func report() {
            let chapter = loadedChapter, page = currentPage, count = pageCount
            DispatchQueue.main.async { [weak self] in
                self?.parent.onLocation(chapter, page, count)
            }
        }

        // MARK: Cuộn & chạm

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.y != 0 { scrollView.contentOffset.y = 0 }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            let width = scrollView.bounds.width
            guard width > 0, isReady else { return }
            let page = Int((scrollView.contentOffset.x / width).rounded())
            if page != currentPage {
                currentPage = max(0, min(pageCount - 1, page))
                report()
            }
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard isReady else { return }
            let width = scrollView.bounds.width
            let maxX = CGFloat(pageCount - 1) * width
            let x = scrollView.contentOffset.x
            if x > maxX + 40 || (currentPage == pageCount - 1 && velocity.x > 0.4 && x >= maxX - 1) {
                nextChapter()
            } else if x < -40 || (currentPage == 0 && velocity.x < -0.4 && x <= 1) {
                previousChapter()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view, isReady else { return }
            let x = gesture.location(in: view).x / max(view.bounds.width, 1)
            if x < 0.28 { previousPage() }
            else if x > 0.72 { nextPage() }
            else { parent.onTapCenter() }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Liên kết trong sách

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            decisionHandler(.cancel)
            if url.isFileURL {
                if let index = parent.package.spineIndex(of: url) { load(chapter: index, fraction: 0) }
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
            }
        }
    }
}
