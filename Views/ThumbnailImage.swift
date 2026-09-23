import SwiftUI
import UIKit

/// 图片名字 → `UIImage` 的统一解析。
///
/// 全 App 只用 `BagItem.imageFileName` 一个字段，但它有两个来源：
///  · **真实数据**（相机/相册录入）：文件名，落在 `Documents/bags/`，靠 `ImageStore`
///  · **演示数据**（H5 复刻的 16 只）：素材名，打包在 `Assets.xcassets`
///
/// 这里把两条路合成一条，调用方不用关心是哪一种。
/// 顺序是「先磁盘、后内置」：磁盘上有同名文件就以用户的为准。
enum BagImageResolver {

    /// 同步取图。**仅用于主卡/详情这种单张、且需要立刻出图的场景。**
    /// 网格滚动请用 `ThumbnailImage`（走缓存 + 后台解码），否则会掉帧。
    static func load(_ fileName: String) -> UIImage? {
        if let onDisk = ImageStore.load(fileName) { return onDisk }
        return UIImage(named: fileName)
    }
}

/// 异步缩略图视图：走 `ThumbnailCache`，网格里用它替代直接读原图。
///
/// 直接用 `Image(bag.imageFileName)` 有两个问题：
///  ①**真实数据**根本不认 —— `Image(_:)` 只查 Asset Catalog，
///    用户拍的照片在 `Documents/bags/` 里，会渲染成空白
///  ② 每次滚动都重新解码原图，几十张就会掉帧
/// 这个视图一次解决两件事。
struct ThumbnailImage: View {
    let fileName: String
    var size: CGFloat = 300
    /// 填充方式。
    /// · `.fit`：完整可见，**不会溢出**父容器 —— 默认值，最安全
    /// · `.fill`：铺满并裁切，**必须**由调用方给一个确定尺寸的盒子 + `.clipped()`，
    ///          否则会因为图片超出边界而撑破布局
    var contentMode: ContentMode = .fit

    /// 插值质量。
    /// ⚠️ `.interpolation(_:)` 是 `Image` 的专属修饰符，**不能**写在 `ThumbnailImage`
    ///    外面 —— 它是自定义 View，没有这个方法（写了会报
    ///    `Value of type 'ThumbnailImage' has no member 'interpolation'`）。
    ///    所以在 init 里接收，由内部转交给真正的 `Image`。
    ///    缩略图是从原图**缩小**渲染的，用 `.high` 让缩放边缘更平滑。
    var interpolation: Image.Interpolation = .high

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(interpolation)
                    .aspectRatio(contentMode: contentMode)
            } else {
                // 未就绪时占位：保持透明但**有尺寸**，避免首帧塌成 0
                // 尺寸取缩略图目标边长的一半，够格子用又不会撑开布局
                Color.white.opacity(0.001)
                    .frame(width: size / 2, height: size / 2)
            }
        }
        .task(id: fileName) {
            // 同一张图可能被多个 cell 请求，缓存内部已做去重，这里直接回调即可
            ThumbnailCache.shared.thumbnail(for: fileName, size: size) { image = $0 }
        }
    }
}
