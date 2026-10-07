import SwiftUI

/// A stable placeholder occupies the same space while decoding happens off-main.
struct SourceImageView: View {
    let url: URL
    var revision = ""
    var maxPixelSize = 1600
    var contentMode: ContentMode = .fit
    @State private var image: CGImage?
    private var requestID: String { url.path + ":\(maxPixelSize):" + revision }
    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Theme.accent.opacity(0.055)).overlay {
                    Image(systemName: "photo").foregroundStyle(Theme.accent.opacity(0.5)).font(.system(size: 17))
                }.aspectRatio(4 / 3, contentMode: contentMode)
            }
        }.task(id: requestID) {
            image = nil
            let result = await ImagePreviewCache.shared.image(url, maxPixelSize: maxPixelSize, revision: revision)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}

/// Fit the complete source to the actual viewport; zoom changes only presentation.
struct ZoomableSourceImage: View {
    let url: URL
    var revision: String
    @State private var image: CGImage?
    @State private var scale = 1.0
    @State private var failed = false
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if let image {
                    let fit = SourceImageLayout.fit(image: CGSize(width: image.width, height: image.height), viewport: geometry.size)
                    ScrollView([.vertical, .horizontal]) {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high)
                            .frame(width: fit.width * scale, height: fit.height * scale)
                            .padding(12)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                            .accessibilityLabel("原稿图片")
                    }.scrollIndicators(.hidden)
                } else if failed {
                    ContentUnavailableView("图片暂不可用", systemImage: "photo.badge.exclamationmark")
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.clipped()
            HStack(spacing: 6) {
                Button("整页") { scale = 1 }.buttonStyle(FeedbackStyle(compact: true)).padding(.leading, 4).help("适应窗口，完整显示原稿")
                Spacer()
                QuietIconButton(icon: "minus.magnifyingglass", label: "缩小原稿") { scale = max(1, scale - 0.5) }.disabled(scale <= 1)
                Text(scale == 1 ? "适应窗口" : "\(Int(scale * 100))%").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().frame(width: 60)
                QuietIconButton(icon: "plus.magnifyingglass", label: "放大原稿") { scale = min(5, scale + 0.5) }.disabled(scale >= 5)
            }.font(.system(size: 11)).padding(10)
        }.task(id: url.path + revision) {
            image = nil; failed = false; scale = 1
            let result = await ImagePreviewCache.shared.image(url, maxPixelSize: 3600, revision: revision)
            guard !Task.isCancelled else { return }
            image = result; failed = result == nil
        }
    }
}
