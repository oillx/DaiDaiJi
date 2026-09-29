import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

// MARK: - 设计常量
//
// 全部数值来自设计稿的 1:1 测量。稿面 750×1624px = 375×812pt（@2x），
// 即 2px = 1pt —— 下面所有 pt 值都是这么换算出来的，改动时请保持同一口径。

enum CaptureMetrics {
    // 顶部导航
    static let navHeight: CGFloat = 66          // 稿面：标题/箭头中线距屏顶 79.8pt，安全区 44 + 66/2 = 77
    static let backCenterX: CGFloat = 29        // 箭头中线 x
    static let tapTarget: CGFloat = 44          // 点击热区边长

    // 预览区
    static let previewInset: CGFloat = 17       // 左右外边距
    static let previewRadius: CGFloat = 30      // 圆角（实测满宽收敛于 29.5pt）

    // 取景虚线框（相对预览区）
    static let guideInsetH: CGFloat = 31        // 左右各内缩
    static let guideWidth: CGFloat = 280        // = 342 - 31×2
    /// 取景框高度。稿面 317；📌 按需求「高度加高 1/3」⇒ **317 × 4/3 ≈ 422.7**。
    ///
    /// ⚠️ 框是**以预览区中心为基准**定位的（只做 `guideOffsetY` 上移 15.5），
    ///    所以加高的部分是**上下各摊一半**（±52.8pt）。
    ///    预览区高约 584pt，加高后上下仍各留 ~65 / ~96pt 余量，不会顶出预览区。
    /// ⚠️ 想回稿面值：写回 317。
    static let guideHeight: CGFloat = 317 * 4 / 3
    static let guideOffsetY: CGFloat = -15.5    // 比预览区中心略偏上
    static let guideLineWidth: CGFloat = 4
    static let guideDash: [CGFloat] = [16.5, 17]
    static let guideRadius: CGFloat = 15

    // 底部控件
    static let previewBottomGap: CGFloat = 44   // 预览区底 → 控件顶
    static let controlsInset: CGFloat = 47      // 左右外边距（三控件中线落在 73.8 / 187.5 / 301.2）
    static let controlsBottom: CGFloat = 8.5    // 控件底 → 安全区线
    static let sideButton: CGFloat = 54         // 左右圆形按钮
    static let shutter: CGFloat = 78            // 快门外径
    static let shutterRing: CGFloat = 2         // 红色外环线宽
    static let shutterCore: CGFloat = 68        // 红色实心内圆（与外环之间留 3pt 空隙）
}

enum CapturePalette {
    static let page   = Color(red: 242/255, green: 243/255, blue: 247/255)  // #F2F3F7
    static let canvas = Color(red: 219/255, green: 187/255, blue: 161/255)  // #DBBBA1（预览兜底色）
    /// 取景框：稿面呈 #E8D4C3 —— 正是白色 36% 叠在 #DBBBA1 上的结果。
    /// 写成半透明白而非实色，是为了在实拍画面上也自然（实色只在棕底上成立）。
    static let guide  = Color.white.opacity(0.36)
    static let red    = Color(red: 197/255, green:   4/255, blue:   5/255)  // #C50405
    static let ink    = Color.black                                          // 标题 / 相册图标
    static let glyph  = Color(red:  51/255, green:  51/255, blue:  51/255)  // #333333 手电筒描边
    static let card   = Color.white                                          // 圆形按钮底
}

// MARK: - 拍摄页

/// 「上传纸袋」拍摄页 —— 按设计稿 1:1 还原。
///
/// 结构：顶部导航 → 圆角预览区（内含虚线取景框）→ 底部三控件（补光 / 快门 / 相册）。
/// 拍到的原图与相册选的原图走同一条回调，交给 `BagImagePipeline` 做矫正/抠图/命名。
struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()

    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var capturing = false

    /// 返回按钮的行为。为 nil 时关闭本页（＋ 直接进入拍摄页的情形）；
    /// 由表单里的「拍照」进入时传入闭包，退回到表单。
    var onBack: (() -> Void)?
    /// 拍到 / 选到图片
    var onImage: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            navBar

            previewArea
                .padding(.horizontal, CaptureMetrics.previewInset)
                .frame(maxHeight: .infinity)

            Spacer(minLength: 0)
                .frame(height: CaptureMetrics.previewBottomGap)

            controls
        }
        .padding(.bottom, CaptureMetrics.controlsBottom)
        // ── 宽屏（iPad）把预览区与底部三控件收进同一列 ──
        //
        // ⚠️ 这一层不能省。控件行用 `Spacer(minLength: 0)` 均分，
        //    在 iPad 上会变成「预览区铺满 1366pt、快门在正中、
        //    补光与相册贴到屏幕两端」，三控件相隔上千点，既难看也不好按。
        //    iPhone 上 393 < 560，恒等变换。
        .contentColumn(AppLayout.cameraMaxWidth)
        // ⚠️ 顺序不能颠倒：`contentColumn` 只收**内容**，
        //    若把背景加在它前面，底色会跟着收窄到 560pt，两侧露出黑边。
        //    先撑满整屏，再铺底色。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CapturePalette.page.ignoresSafeArea())
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in loadFromLibrary(item) }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: 顶部导航

    private var navBar: some View {
        ZStack {
            Text("上传纸袋")
                .font(.system(size: 16))
                .foregroundStyle(CapturePalette.ink)

            HStack(spacing: 0) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CapturePalette.ink)
                        .frame(width: CaptureMetrics.tapTarget,
                               height: CaptureMetrics.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            // 热区中线对准稿面的 29pt
            .padding(.leading, CaptureMetrics.backCenterX - CaptureMetrics.tapTarget / 2)
        }
        .frame(height: CaptureMetrics.navHeight)
    }

    private func goBack() {
        if let onBack { onBack() } else { dismiss() }
    }

    // MARK: 预览区

    private var previewArea: some View {
        ZStack {
            // 兜底色：相机未就绪 / 不可用时就是这一块米棕色，与稿面一致
            CapturePalette.canvas

            if camera.auth == .denied {
                permissionNotice
            } else if camera.unavailable {
                unavailableNotice
            } else {
                CameraPreviewView(session: camera.session)
                    // 会话真正跑起来后再淡入，避免开机瞬间闪黑
                    .opacity(camera.isRunning ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: camera.isRunning)
            }

            guideFrame
        }
        .clipShape(RoundedRectangle(cornerRadius: CaptureMetrics.previewRadius,
                                    style: .continuous))
    }

    /// 取景框：虚线圆角矩形。尺寸取自稿面固定值（280×317），只做水平居中 + 上移 15.5pt。
    ///
    /// ⚠️ iPad 上预览区宽得多，固定尺寸的框会缩成一个小方块、失去取景意义，
    ///    所以宽度超过 480pt 时按比例放大（`AppLayout.guideScale`）。
    ///    iPhone 与 iPad 分屏都在 480pt 以下，恒为 1 倍，稿面尺寸不受影响。
    private var guideFrame: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: CaptureMetrics.guideRadius, style: .continuous)
                .strokeBorder(
                    CapturePalette.guide,
                    style: StrokeStyle(lineWidth: CaptureMetrics.guideLineWidth,
                                       lineCap: .butt,
                                       dash: CaptureMetrics.guideDash)
                )
                .frame(width: CaptureMetrics.guideWidth,
                       height: CaptureMetrics.guideHeight)
                // 用 `scaleEffect` 而不是把宽高乘一遍 —— 线宽与虚线节奏
                // 也会跟着等比放大，观感才是真的「同一张框放大」。
                .scaleEffect(AppLayout.guideScale(previewWidth: geo.size.width))
                .position(x: geo.size.width / 2,
                          y: geo.size.height / 2 + CaptureMetrics.guideOffsetY)
        }
        .allowsHitTesting(false)
    }

    /// 未授权时的提示 —— 稿面没有这个状态，但必须有出口（否则整页只剩一块棕底）
    private var permissionNotice: some View {
        VStack(spacing: 12) {
            Text("需要相机权限才能拍摄纸袋")
                .font(.system(size: 14))
                .foregroundStyle(CapturePalette.glyph)

            Button("去设置开启") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(CapturePalette.red)
        }
        .padding(.horizontal, 24)
    }

    /// 设备上拿不到摄像头时的出口 —— 稿面同样没有这个状态。
    ///
    /// ⚠️ 不能只显示「需要相机权限」，因为此时权限往往是**已授权**的，
    ///    提示权限会让人一直去设置里翻、却怎么都对不上。
    ///    典型场景：iPad 模拟器、或摄像机被别的 App 长期占用。
    private var unavailableNotice: some View {
        VStack(spacing: 12) {
            Text("此设备暂时没有可用的摄像头")
                .font(.system(size: 14))
                .foregroundStyle(CapturePalette.glyph)

            Text("可以点右下角的相册按钮，从照片里选一张。")
                .font(.system(size: 12))
                .foregroundStyle(CapturePalette.glyph.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    // MARK: 底部控件

    private var controls: some View {
        HStack(spacing: 0) {
            torchButton
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            libraryButton
        }
        .frame(height: CaptureMetrics.shutter)
        .padding(.horizontal, CaptureMetrics.controlsInset)
    }

    /// 左：补光（手电筒）。开启时按钮内加一层极淡的红，作为开关反馈 ——
    /// 图标上的红点始终保持品牌红，与稿面一致。
    private var torchButton: some View {
        Button {
            camera.toggleTorch()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle().fill(CapturePalette.card)
                if camera.torchOn {
                    Circle().fill(CapturePalette.red.opacity(0.10))
                }

                FlashlightGlyph()
                    .stroke(CapturePalette.glyph,
                            style: StrokeStyle(lineWidth: 2, lineJoin: .miter))
                    .frame(width: FlashlightGlyph.width, height: FlashlightGlyph.height)
                    .overlay {
                        // 灯芯：2×4pt 胶囊，位于握柄中部
                        Capsule()
                            .fill(CapturePalette.red)
                            .frame(width: 2, height: 4)
                            .offset(y: 3.25)
                    }
            }
            .frame(width: CaptureMetrics.sideButton, height: CaptureMetrics.sideButton)
            .opacity(camera.torchAvailable ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!camera.torchAvailable)
        .accessibilityLabel(camera.torchOn ? "关闭补光" : "打开补光")
    }

    /// 中：快门。外环 2pt + 3pt 空隙 + 68pt 实心圆，合起来 78pt。
    private var shutterButton: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .strokeBorder(CapturePalette.red, lineWidth: CaptureMetrics.shutterRing)
                    .frame(width: CaptureMetrics.shutter, height: CaptureMetrics.shutter)

                Circle()
                    .fill(CapturePalette.red)
                    .frame(width: CaptureMetrics.shutterCore,
                           height: CaptureMetrics.shutterCore)
            }
            .frame(width: CaptureMetrics.shutter, height: CaptureMetrics.shutter)
        }
        .buttonStyle(ShutterButtonStyle())
        // 除授权外还要求会话**真的在跑**：停在画布底色（会话被中断 / 抢走）时
        // 点下去会撞上 `capturePhoto` 的异常，所以这里直接禁掉。
        .disabled(capturing || camera.auth != .ready || !camera.isRunning)
        .accessibilityLabel("拍照")
    }

    /// 右：相册
    private var libraryButton: some View {
        Button { showLibrary = true } label: {
            ZStack {
                Circle().fill(CapturePalette.card)
                PhotoLibraryGlyph()
            }
            .frame(width: CaptureMetrics.sideButton, height: CaptureMetrics.sideButton)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("从相册选择")
    }

    // MARK: 动作

    private func capture() {
        guard !capturing else { return }
        capturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        camera.capture { image in
            capturing = false
            if let image { onImage(image) }
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                libraryItem = nil
                onImage(image)
            }
        }
    }
}

/// 按下时轻微回缩，给快门一点手感
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

// MARK: - 定制图标
//
// 两个图标都是手绘矢量：稿面里它们不是任何 SF Symbol，
// 尺寸与笔画都按像素测量还原（手电筒 19×25pt、相册 24×20pt，笔画 2pt）。

/// 手电筒：宽扁灯头 → 收口 → 握柄，外轮廓一笔闭合，另加灯头底沿那道横线。
struct FlashlightGlyph: Shape {
    static let width: CGFloat = 19
    static let height: CGFloat = 25

    /// 设计坐标系下的关键点（同样以 19×25 为画布，笔画中线的位置）
    private static let left: CGFloat = 1
    private static let right: CGFloat = 18
    private static let top: CGFloat = 1
    private static let headBottom: CGFloat = 5
    private static let neckY: CGFloat = 11.5
    private static let handleLeft: CGFloat = 6.25
    private static let handleRight: CGFloat = 13.5
    private static let bottom: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.width
        let sy = rect.height / Self.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        // 外轮廓
        path.move(to: pt(Self.left, Self.top))
        path.addLine(to: pt(Self.right, Self.top))
        path.addLine(to: pt(Self.right, Self.headBottom))
        path.addLine(to: pt(Self.handleRight, Self.neckY))
        path.addLine(to: pt(Self.handleRight, Self.bottom))
        path.addLine(to: pt(Self.handleLeft, Self.bottom))
        path.addLine(to: pt(Self.handleLeft, Self.neckY))
        path.addLine(to: pt(Self.left, Self.headBottom))
        path.closeSubpath()
        // 灯头底沿
        path.move(to: pt(Self.left, Self.headBottom))
        path.addLine(to: pt(Self.right, Self.headBottom))
        return path
    }
}

/// 相册：圆角方框 + 山脊线 + 左上角红日
struct PhotoLibraryGlyph: View {
    static let width: CGFloat = 24
    static let height: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(CapturePalette.ink, lineWidth: 2)

            MountainRidge()
                .stroke(CapturePalette.ink,
                        style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))

            Circle()
                .fill(CapturePalette.red)
                .frame(width: 3.2, height: 3.2)
                .position(x: 6.2, y: 5.5)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

/// 山脊折线：两端落在方框描边中线上，峰谷按稿面位置
private struct MountainRidge: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / PhotoLibraryGlyph.width
        let h = rect.height / PhotoLibraryGlyph.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: pt(1, 14.5))
        path.addLine(to: pt(7.5, 10))
        path.addLine(to: pt(10.5, 12.5))
        path.addLine(to: pt(14.5, 8))
        path.addLine(to: pt(23, 15))
        return path
    }
}

// MARK: - AVCaptureVideoPreviewLayer 的 SwiftUI 封装

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // 画幅会被裁到预览区的比例（比传感器窄），但采集仍是整幅 4:3 ——
        // 也就是说「取景框里的东西一定能拍到」，不会出现框得住却拍不到的情况；
        // 多余的四周由 `BagImagePipeline` 的透视矫正 + 抠图裁掉。
        view.syncRotationAngle()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // 旋转 / 拖分屏都会让本视图重新布局，SwiftUI 会重跑这里，
        // 顺手把预览方向对齐一次（`layoutSubviews` 之外的第二道保险）。
        uiView.syncRotationAngle()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            syncRotationAngle()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncRotationAngle()
        }

        /// 把预览连接的旋转角对齐当前界面方向。
        ///
        /// ⚠️ 这个方法不能省。iPhone 侧 App 锁了竖屏，AVFoundation 的默认
        ///    旋转角（90°）刚好就是对的，所以以前不设也能用；但 **iPad 支持
        ///    横屏**，横着拿的时候默认角不跟着变，预览画面会整个歪 90°。
        ///    竖屏时这里算出来仍是 90°，等于默认值，对 iPhone 零副作用。
        func syncRotationAngle() {
            guard let connection = videoPreviewLayer.connection else { return }
            let angle = CameraRotation.angle(for: window?.windowScene?.interfaceOrientation)
            guard connection.isVideoRotationAngleSupported(angle),
                  connection.videoRotationAngle != angle else { return }
            connection.videoRotationAngle = angle
        }
    }
}

// MARK: - 预览

#Preview("拍摄页") {
    CameraView(onImage: { _ in })
}
