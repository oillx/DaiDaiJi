import Foundation
import UIKit

/// 图片文件存储：把照片存到 Documents/bags 目录，数据库只记文件名。
enum ImageStore {

    /// bags 目录（首次访问时创建）
    static let folder: URL = {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bags", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// 保存图片，返回文件名；失败返回 nil
    /// 抠图后带透明通道，必须用 PNG（JPEG 会把透明背景变成黑色）
    static func save(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let name = UUID().uuidString + ".png"
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ fileName: String) -> UIImage? {
        let url = folder.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(_ fileName: String) {
        let url = folder.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
