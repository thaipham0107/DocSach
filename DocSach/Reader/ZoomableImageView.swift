import SwiftUI
import UIKit

/// Một trang truyện tranh: chụm 2 ngón để phóng to, chạm 2 lần để phóng/thu,
/// chạm 1 lần báo vị trí (để lật trang hoặc hiện thanh điều khiển).
struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    var onTap: (CGFloat) -> Void   // vị trí ngang 0…1

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let sv = ZoomScrollView()
        sv.delegate = context.coordinator
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.backgroundColor = .clear

        let imageView = sv.imageView
        imageView.contentMode = .scaleAspectFit
        sv.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap(_:)))
        singleTap.require(toFail: doubleTap)
        sv.addGestureRecognizer(singleTap)

        context.coordinator.scrollView = sv
        context.coordinator.load(url)
        return sv
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        context.coordinator.onTap = onTap
        if context.coordinator.loadedURL != url { context.coordinator.load(url) }
    }

    final class ZoomScrollView: UIScrollView {
        let imageView = UIImageView()
        override func layoutSubviews() {
            super.layoutSubviews()
            if zoomScale == 1 { imageView.frame = bounds }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (CGFloat) -> Void
        weak var scrollView: ZoomScrollView?
        var loadedURL: URL?

        init(onTap: @escaping (CGFloat) -> Void) { self.onTap = onTap }

        func load(_ url: URL) {
            loadedURL = url
            let maxPixel = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale * 1.5
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = ImageUtil.downsample(url: url, maxPixel: maxPixel)
                DispatchQueue.main.async {
                    guard let self, self.loadedURL == url else { return }
                    self.scrollView?.imageView.image = image
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { self.scrollView?.imageView }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.zoomScale > 1 {
                sv.setZoomScale(1, animated: true)
            } else {
                let point = g.location(in: sv.imageView)
                let size = CGSize(width: sv.bounds.width / 2.5, height: sv.bounds.height / 2.5)
                sv.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                   width: size.width, height: size.height), animated: true)
            }
        }

        @objc func singleTap(_ g: UITapGestureRecognizer) {
            guard let sv = scrollView, sv.zoomScale == 1 else { return }
            onTap(g.location(in: sv).x / max(sv.bounds.width, 1))
        }
    }
}

/// Ảnh tải bất đồng bộ (dùng cho chế độ cuộn dọc).
struct AsyncPageImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
                    .aspectRatio(0.7, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .task(id: url) {
            let maxPixel = UIScreen.main.bounds.width * UIScreen.main.scale * 1.5
            image = await Task.detached(priority: .userInitiated) {
                ImageUtil.downsample(url: url, maxPixel: maxPixel)
            }.value
        }
    }
}
