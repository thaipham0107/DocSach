import SwiftUI
import SwiftData
import WebKit

/// Trang web nguồn do bạn tự thêm. Mở trong trình duyệt của app;
/// khi bạn bấm tải tệp EPUB / CBZ / PDF trên trang, sách tự vào thư viện.
struct SourceSite: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}

enum SourceSites {
    static let key = "sourceSites.v1"

    static let defaults: [SourceSite] = [
        SourceSite(name: "BDeBooks", url: "https://bdebooks.com/vi"),
        SourceSite(name: "LibVui", url: "https://libvui.com"),
        SourceSite(name: "iBook", url: "https://ibook.com.vn/"),
        SourceSite(name: "Welib", url: "https://welib.gd"),
        SourceSite(name: "Wikisource tiếng Việt", url: "https://vi.wikisource.org"),
        SourceSite(name: "Project Gutenberg", url: "https://www.gutenberg.org")
    ]

    static func load() -> [SourceSite] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sites = try? JSONDecoder().decode([SourceSite].self, from: data) else { return defaults }
        return sites
    }

    static func save(_ sites: [SourceSite]) {
        if let data = try? JSONEncoder().encode(sites) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct SourceSitesView: View {
    @State private var sites = SourceSites.load()
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        List {
            Section {
                ForEach(sites) { site in
                    NavigationLink {
                        SourceBrowserView(site: site)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name).font(.headline)
                            Text(site.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    sites.remove(atOffsets: offsets)
                    SourceSites.save(sites)
                }
                Button { showAdd = true } label: { Label("Thêm trang web", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Mở trang, tìm sách rồi bấm nút tải EPUB / PDF / CBZ của trang đó: sách sẽ tự vào thư viện. Hãy chỉ tải những sách bạn được phép dùng.")
            }
        }
        .navigationTitle("Trang web nguồn")
        .alert("Thêm trang web", isPresented: $showAdd) {
            TextField("Tên", text: $newName)
            TextField("https://…", text: $newURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Huỷ", role: .cancel) { newName = ""; newURL = "" }
            Button("Thêm") {
                var link = newURL.trimmingCharacters(in: .whitespaces)
                if !link.lowercased().hasPrefix("http") { link = "https://" + link }
                let name = newName.isEmpty ? (URL(string: link)?.host ?? link) : newName
                sites.append(SourceSite(name: name, url: link))
                SourceSites.save(sites)
                newName = ""; newURL = ""
            }
        }
    }
}

struct SourceBrowserView: View {
    let site: SourceSite
    @Environment(\.modelContext) private var context
    @Environment(ImportCenter.self) private var importer
    @State private var model = BrowserModel()

    var body: some View {
        BrowserWebView(startURL: URL(string: site.url), model: model) { fileURL in
            Task { await importer.importFiles([fileURL], category: nil, context: context) }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(model.title.isEmpty ? site.name : model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { model.webView?.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!model.canGoBack)
                Button { model.webView?.goForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!model.canGoForward)
                Spacer()
                if model.isLoading {
                    ProgressView()
                } else if let pdf = model.pdfURL {
                    Button {
                        Task { await importer.importLink(pdf.absoluteString, category: nil, context: context) }
                    } label: {
                        Label("Lưu PDF vào thư viện", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
                Spacer()
                Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}

@Observable
final class BrowserModel {
    var title = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var pdfURL: URL?          // trang đang mở là một tệp PDF
    weak var webView: WKWebView?
}

struct BrowserWebView: UIViewRepresentable {
    let startURL: URL?
    let model: BrowserModel
    var onDownloaded: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, onDownloaded: onDownloaded) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView
        if let startURL { webView.load(URLRequest(url: startURL)) }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onDownloaded = onDownloaded
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let model: BrowserModel
        var onDownloaded: (URL) -> Void
        private var destinations: [ObjectIdentifier: URL] = [:]

        init(model: BrowserModel, onDownloaded: @escaping (URL) -> Void) {
            self.model = model
            self.onDownloaded = onDownloaded
        }

        private static let bookExtensions: Set<String> = ["epub", "cbz", "pdf", "zip"]
        private static let bookMimes: Set<String> = ["application/epub+zip", "application/vnd.comicbook+zip",
                                                     "application/zip", "application/x-zip-compressed",
                                                     "application/octet-stream", "application/pdf"]

        private func update(_ webView: WKWebView) {
            model.title = webView.title ?? ""
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
            model.isLoading = webView.isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { update(webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { update(webView) }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response
            let ext = (response.suggestedFilename as NSString?)?.pathExtension.lowercased()
                ?? response.url?.pathExtension.lowercased() ?? ""
            let mime = response.mimeType?.lowercased() ?? ""
            let isAttachment = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") ?? false
            let isBook = Self.bookExtensions.contains(ext) && mime != "application/pdf"
                || mime == "application/epub+zip" || mime == "application/vnd.comicbook+zip"
                || (isAttachment && (Self.bookMimes.contains(mime) || Self.bookExtensions.contains(ext)))
            if navigationResponse.isForMainFrame {
                model.pdfURL = (mime == "application/pdf" && !isAttachment) ? response.url : nil
            }
            if isBook || !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            model.isLoading = true
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            model.isLoading = true
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(suggestedFilename)
            destinations[ObjectIdentifier(download)] = dest
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            model.isLoading = false
            if let url = destinations.removeValue(forKey: ObjectIdentifier(download)) {
                onDownloaded(url)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            model.isLoading = false
            destinations.removeValue(forKey: ObjectIdentifier(download))
        }
    }
}
