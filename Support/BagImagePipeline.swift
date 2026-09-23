import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 图片处理流水线的结果
struct ProcessedBag {
    let result: UIImage          // 抠图 + 矫正 + 增强后的最终图（透明背景）
    let suggestedName: String?   // OCR 自动识别出的名称建议
    let didCrop: Bool            // 是否成功做了透视矫正
    let didRemoveBackground: Bool// 是否成功抠图（false 表示回退为不透明图）
}

/// 处理选项：第一阶段全开，后续可做成设置项
struct PipelineOptions {
    var perspectiveCorrect = true
    var enhance            = true
    var recognizeText      = true
    var removeBackground   = true

    static let `default` = PipelineOptions()
}

// MARK: - 坐标辅助
extension CGPoint {
    /// Vision 归一化坐标(左下原点) → CIImage 像素坐标(同为左下原点)，直接缩放，无需翻转
    func scaled(to size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

/// 袋袋集图像流水线：矫正 → 增强 → OCR → 抠图
/// 全部基于 Apple 原生框架，端侧、零第三方库、零联网。
enum BagImagePipeline {

    /// 入口：原图 → 透视矫正 → 色彩增强 → OCR名称 → 抠图去背景
    static func process(_ image: UIImage,
                        options: PipelineOptions = .default) -> ProcessedBag? {
        // ⚠️ 第一步必须归正朝向，不能省。
        //
        //  `UIImage.cgImage` 拿到的永远是**传感器原始像素**，方向只记在
        //  `imageOrientation`（来自 EXIF）里。而下面的 `CIImage(cgImage:)`
        //  只吃原始像素、把方向信息整个丢掉 —— 竖拍的照片进来就是横的。
        //
        //  iPhone 锁竖屏时这个坑不明显（相机输出恒定，观感上「一直如此」），
        //  但 **iPad 支持横屏**，横着拍是常态，方向一定会错，
        //  而且错得很难自查（袋子在详情页里躺倒 90°）。
        let image = upright(image)
        guard let cgImage = image.cgImage else { return nil }
        let context = CIContext()
        var ci = CIImage(cgImage: cgImage)

        // 1) 透视矫正（检测不到纸袋矩形边界则跳过，保留原图）
        var didCrop = false
        if options.perspectiveCorrect, let rect = try? detectRectangle(in: ci) {
            ci = correct(ci, observation: rect)
            didCrop = true
        }

        // 2) 色彩增强（Core Image 自动调色：曝光/对比度/白平衡等）
        if options.enhance {
            ci = enhance(ci)
        }

        // 3) OCR 取字，给出名称建议（在增强后的不透明图上识别，文字更清晰）
        var suggestedName: String?
        if options.recognizeText {
            let lines = (try? TextRecognizer.recognize(in: ci)) ?? []
            suggestedName = TextRecognizer.suggestName(from: lines)
        }

        // 4) 抠图去背景（透明 PNG）
        var didRemoveBackground = false
        if options.removeBackground {
            let (out, ok) = removeBackground(ci)
            ci = out
            didRemoveBackground = ok
        }

        guard let outCG = context.createCGImage(ci, from: ci.extent) else { return nil }
        return ProcessedBag(result: UIImage(cgImage: outCG),
                            suggestedName: suggestedName,
                            didCrop: didCrop,
                            didRemoveBackground: didRemoveBackground)
    }

    // MARK: - 朝向归正

    /// 把 `imageOrientation` 烘焙进像素，返回一张 `.up` 的图。
    ///
    /// `UIImage.size` 本来就是**按方向折算后**的尺寸（横拍的图 `size` 是竖着的），
    /// 所以在 `CGRect(origin: .zero, size: image.size)` 里 `draw` 一次，
    /// 拿到的位图就是正方位的 —— 比手写 4×4 变换表可靠得多。
    ///
    /// 已经 `.up` 时直接返回原图，不做多余的一次全图重绘
    ///（1200 万像素重绘一次约 48MB 内存，能不花就不花）。
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - 透视矫正
    static func detectRectangle(in ciImage: CIImage) throws -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.2
        request.maximumObservations = 1
        request.minimumAspectRatio = VNAspectRatio(0.5)
        request.maximumAspectRatio = VNAspectRatio(2.0)
        request.quadratureTolerance = 15
        request.minimumConfidence = 0.6
        let handler = VNImageRequestHandler(ciImage: ciImage)
        try handler.perform([request])
        return request.results?.first as? VNRectangleObservation
    }

    static func correct(_ ciImage: CIImage, observation: VNRectangleObservation) -> CIImage {
        let size = ciImage.extent.size
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = observation.topLeft.scaled(to: size)
        filter.topRight = observation.topRight.scaled(to: size)
        filter.bottomLeft = observation.bottomLeft.scaled(to: size)
        filter.bottomRight = observation.bottomRight.scaled(to: size)
        return filter.outputImage ?? ciImage
    }

    // MARK: - 色彩增强
    static func enhance(_ ci: CIImage) -> CIImage {
        var input = ci
        for filter in ci.autoAdjustmentFilters() {
            filter.setValue(input, forKey: kCIInputImageKey)
            if let out = filter.outputImage { input = out }
        }
        return input
    }

    // MARK: - 抠图去背景
    /// 返回（处理后的图, 是否成功抠图）
    static func removeBackground(_ ci: CIImage) -> (CIImage, Bool) {
        let handler = VNImageRequestHandler(ciImage: ci)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) } catch { return (ci, false) }
        guard let result = request.results?.first as? VNInstanceMaskObservation else { return (ci, false) }
        guard let mask = try? result.generateScaledMaskForImage(
            forInstances: result.allInstances, from: handler) else { return (ci, false) }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = ci
        blend.maskImage = CIImage(cvPixelBuffer: mask)
        blend.backgroundImage = CIImage.empty()
        guard let out = blend.outputImage else { return (ci, false) }
        return (out, true)
    }
}

// MARK: - OCR 文字识别 + 名称建议
struct TextRecognizer {

    struct Line {
        let text: String
        let confidence: Float
    }

    /// 识别图中文字，返回「文本行 + 置信度」
    static func recognize(in ciImage: CIImage) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(ciImage: ciImage)
        try handler.perform([request])
        // 修复1：guard 的 else 分支返回空数组，匹配函数返回类型 [Line]
        guard let observations = request.results else { return [] }
        return observations.compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            return Line(text: c.string, confidence: c.confidence)
        }
    }

    /// V1 简单策略：取「置信度够高且长度适中」的文本行作为建议名称（用户可改）
    static func suggestName(from lines: [Line]) -> String? {
        let candidates = lines.filter { $0.confidence >= 0.5 && !$0.text.isEmpty }
        // 优先选长度在 2~20 之间的，其次最长
        return candidates
            .sorted { a, b in
                let aOk = (2...20).contains(a.text.count)
                let bOk = (2...20).contains(b.text.count)
                if aOk != bOk { return aOk }
                return a.text.count > b.text.count
            }
            .first?.text
    }
}
