import UIKit

/// 缩略图内存缓存：避免网格滚动时反复解码大图，保证 60fps 滚动
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.daidaiji.thumbnail", qos: .userInitiated)

    private init() {
        cache.countLimit = 300          // 最多缓存 300 张缩略图
        cache.totalCostLimit = 50 * 1024 * 1024  // 约 50MB
        NotificationCenter.default.addObserver(
            self, selector: #selector(clear),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    func thumbnail(for fileName: String, size: CGFloat, completion: @escaping (UIImage?) -> Void) {
        let key = "\(fileName)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.async {
            // 先磁盘（真实数据）后内置（演示数据），与 `BagImageResolver` 一致
            guard let image = BagImageResolver.load(fileName) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 内置素材本身尺寸就不大，缩到目标边长即可；真实大图才是这里的重点
            let thumb = image.resized(maxDimension: size)
            self.cache.setObject(thumb, forKey: key, cost: thumb.jpegData(compressionQuality: 0.8)?.count ?? 0)
            DispatchQueue.main.async { completion(thumb) }
        }
    }

    @objc func clear() { cache.removeAllObjects() }
}

extension UIImage {
    /// 等比缩放到最长边不超过 maxDimension（用于缩略图）
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false          // 保留透明通道
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
