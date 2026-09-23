import AVFoundation
import UIKit
import Combine

// MARK: - 界面方向 ↔ 相机连接旋转角

/// `UIInterfaceOrientation` → `AVCaptureConnection.videoRotationAngle` 的换算。
///
/// 📌 为什么必须有这一层：iPhone 侧 App 锁了竖屏，AVFoundation 的默认旋转角
///    （90°）刚好就是对的，所以以前完全不设也能用。但 **iPad 支持横屏**
///    （见 `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`），
///    横着拿的时候默认角不会跟着变 —— 预览画面会整个歪 90°，
///    拍出来的照片 EXIF 方向也还是竖屏，进流水线后袋子会躺倒。
enum CameraRotation {

    /// 竖屏 90 / 横屏左 0 / 横屏右 180 / 倒竖屏 270 ——
    /// 这是 `UIInterfaceOrientation` → `AVCaptureVideoOrientation`
    /// 的标准对应关系（`AVCaptureVideoOrientation.landscapeLeft` 的原始值就是 0°）。
    static func angle(for orientation: UIInterfaceOrientation?) -> CGFloat {
        switch orientation {
        case .landscapeLeft:      return 0
        case .landscapeRight:     return 180
        case .portraitUpsideDown: return 270
        default:                  return 90      // .portrait / .unknown
        }
    }

    /// 当前界面方向。
    /// 取**前台活跃**的那个 window scene；一个都取不到时按竖屏处理。
    static var currentInterfaceOrientation: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
        return (active ?? scenes.first)?.interfaceOrientation ?? .portrait
    }

    /// 当前应该用的旋转角。
    /// iPhone（锁竖屏）恒为 90°，与 AVFoundation 的默认值一致 —— 无副作用。
    static var currentAngle: CGFloat { angle(for: currentInterfaceOrientation) }
}

/// AVFoundation 相机控制器：会话管理 + 拍照 + 补光(手电筒) + 切换镜头
final class CameraController: NSObject, ObservableObject {

    /// 授权 + 会话状态。
    /// 用三态而不是 `Bool`：未决时不该显示「需要权限」提示，否则冷启动会闪一下。
    enum Auth {
        case idle       // 还没问 / 还没答
        case ready      // 已授权
        case denied     // 被拒
    }

    @Published var auth: Auth = .idle
    /// 会话已在跑（预览可以显示了）
    @Published var isRunning = false
    /// 手电筒开着
    @Published var torchOn = false
    /// 当前摄像头是否支持手电筒（模拟器 / 前置通常没有）
    @Published var torchAvailable = false
    /// 这台设备上拿不到摄像头（iPad 模拟器、被其它 App 长期占用等）。
    /// 相机页据此换成「没有摄像头」的出口提示，而不是干留一块棕底。
    @Published var unavailable = false

    /// 「用户希望会话在跑」的**意图**，与 `isRunning`（事实）区分开。
    ///
    /// ⚠️ 这两者必须分开。切后台、来电、iPad 分屏抢相机都会让系统停掉会话，
    ///    此时 `isRunning` 变 false 但用户并没有关闭相机页 —— 回到前台要自动恢复。
    ///    只看 `isRunning` 就永远不知道该不该把会话拉起来。
    private var wantsRunning = false
    /// 通知订阅令牌，`deinit` 里要注销
    private var observers: [NSObjectProtocol] = []

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var captureCompletion: ((UIImage?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.daidaiji.camera.session")

    override init() {
        super.init()
        observeSessionLifetime()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 会话的中断与恢复

    /// 订阅「会话被打断 / 运行时出错 / 回到前台」，保证预览不会黑掉就再也回不来。
    ///
    /// ⚠️ 这一层在 iPhone 上几乎用不到，但 **iPad 是重灾区**：
    ///    iPad 的多任务（分屏、Slide Over、台前调度）会在窗口失焦时中断
    ///    占用摄像头的会话，系统也可能因为别处要相机而把它抢占掉。
    ///    没有恢复逻辑的话，相机页会永久停在一块画布底色上，
    ///    而快门看起来依然可点 —— 审核时非常像「相机功能是坏的」。
    private func observeSessionLifetime() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .AVCaptureSessionWasInterrupted,
            .AVCaptureSessionInterruptionEnded,
            .AVCaptureSessionRuntimeError,
            UIApplication.didBecomeActiveNotification
        ]
        observers = names.map { name in
            // ⚠️ `object` 传 nil 而不是 `session`：`didBecomeActive` 的 object 是
            //    UIApplication，统一传 nil 再在闭包里按 `note.object` 自己过滤，
            //    否则漏收通知（这正是「预览黑掉不恢复」的经典成因）。
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                // 别的会话发的通知不关我们的事
                if let other = note.object as? AVCaptureSession, other !== self.session { return }

                if name == .AVCaptureSessionWasInterrupted {
                    // 中断期间画面会冻住，先把状态放下来，预览随即淡回画布底色
                    self.isRunning = false
                } else {
                    self.resumeIfNeeded()
                }
            }
        }
    }

    /// 把停掉的会话重新拉起来。中断结束、运行时错误、回前台都走这里。
    /// ⚠️ 只在主线程调用（意图标志在主线程读写）。
    private func resumeIfNeeded() {
        guard wantsRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }

            guard self.currentInput != nil else {
                // 之前压根没拿到摄像头（模拟器 / 被占用）：趁这次事件重试一次配置。
                // 摄像头被别的 App 放开后就能自己接上，不必杀掉重进。
                DispatchQueue.main.async { self.configureSession() }
                return
            }

            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            auth = .ready
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.auth = granted ? .ready : .denied
                    if granted { self.configureSession() }
                }
            }
        default:
            auth = .denied
        }
    }

    func stop() {
        // 先撤意图，再停会话 —— 否则中断恢复逻辑会把刚停掉的会话又拉起来
        wantsRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyTorch(false)          // 关掉 LED，别让手电筒留在开着的状态
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.torchOn = false
            }
        }
    }

    // MARK: - 会话配置
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            self.addInput(position: .back)
            let hasInput = self.currentInput != nil

            if hasInput, self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                // 高分辨率拍照。iOS 16 起 `isHighResolutionCaptureEnabled` 已弃用，
                // 改为显式指定 `maxPhotoDimensions`。
                //
                // 语义等价：旧 API 是「开一个开关，让输出尽量给最大分辨率」；
                // 新 API 要求调用方**自己挑一个尺寸**。所以从当前格式支持的那组
                // 尺寸里取面积最大的一个 —— 与旧行为一致。
                //
                // ⚠️ 必须在 `beginConfiguration()` / `commitConfiguration()` 之间设置，
                //    且 `maxPhotoDimensions` 只接受 `supportedMaxPhotoDimensions` 里
                //    列出的值，乱填会直接抛异常。
                if let device = self.currentInput?.device,
                   let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                       Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
                   }) {
                    self.photoOutput.maxPhotoDimensions = largest
                }
            }

            self.session.commitConfiguration()

            // ⚠️ 没有输入就不要 `startRunning()`。
            //    无输入的会话启动起来只会打日志，`isRunning` 依旧是 false —— 白忙一场；
            //    而且后续 `capturePhoto` 会直接抛 Objective-C 异常（闪退级）。
            //    iPad 模拟器、或摄像头被别的 App 占满时会走到这条路径。
            guard hasInput else {
                DispatchQueue.main.async {
                    self.unavailable = true
                    self.isRunning = false
                    self.torchAvailable = false
                }
                return
            }

            if !self.session.isRunning { self.session.startRunning() }

            let torch = self.currentInput?.device.hasTorch ?? false
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.unavailable = false
                self.torchAvailable = torch
                self.isRunning = running
            }
        }
    }

    private func addInput(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if let current = currentInput { session.removeInput(current) }
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            self.position = position
        }
    }

    // MARK: - 交互

    /// 补光开关（连续光，与拍照瞬间的闪光无关）。
    /// 只能在 sessionQueue 上改设备配置，所以这里先切队列再回主线程发状态。
    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentInput?.device, device.hasTorch else { return }
            let on = !self.torchOn
            self.applyTorch(on)
            let applied = device.torchMode == .on
            DispatchQueue.main.async { self.torchOn = applied }
        }
    }

    /// ⚠️ 只能在 `sessionQueue` 上调用
    private func applyTorch(_ on: Bool) {
        guard let device = currentInput?.device, device.hasTorch else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyTorch(false)          // 换镜头前先灭灯
            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            self.addInput(position: newPosition)
            self.session.commitConfiguration()

            let torch = self.currentInput?.device.hasTorch ?? false
            DispatchQueue.main.async {
                self.torchOn = false
                self.torchAvailable = torch
            }
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        // ⚠️ 会话没跑起来的时候调 `capturePhoto` 会直接抛 Objective-C 异常 ——
        //    不是返回 nil、也不是走 error 回调，而是**崩掉**。
        //    iPad 分屏被别人抢走相机、或刚进页面还没就绪时都可能撞上。
        //    这里先挡一道，交回 nil 让上层静默忽略。
        guard session.isRunning, currentInput != nil else {
            completion(nil)
            return
        }
        captureCompletion = completion
        // ⚠️ 拍照前把**输出连接**的旋转角对齐当前界面方向，这一步不能省。
        //
        //  `CameraPreviewView` 里设的是**预览连接**的角，只管取景画面；
        //  照片走的是 `photoOutput` 这条独立连接，两个连接的角互不影响。
        //  只设预览的话：iPad 横着拿，取景画面是正的，拍下来却歪 90°
        //  —— 而且预览是对的，所以这个坑极难自查。
        //
        //  iPhone 锁竖屏，算出来恒为 90°，与默认值一致，零副作用。
        if let connection = photoOutput.connection(with: .video) {
            let angle = CameraRotation.currentAngle
            if connection.isVideoRotationAngleSupported(angle),
               connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            captureCompletion?(nil)
            captureCompletion = nil
            return
        }
        // 前置摄像头拍照会有镜像，这里修正
        let fixed = position == .front ? image.flippedHorizontally() : image
        captureCompletion?(fixed)
        captureCompletion = nil
    }
}

private extension UIImage {
    /// 前置摄像头拍出来是镜像的，翻一下再进流水线。
    ///
    /// ⚠️ 必须用系统自带的 `withHorizontallyFlippedOrientation()`，
    ///    不要自己拼 `UIImage(cgImage:scale:orientation: .leftMirrored)` ——
    ///    那样会把 EXIF 朝向**整个覆盖**掉，而且 `cgImage!` 还是强制解包。
    ///    iPad 横屏时照片朝向可能是 `.right` / `.left`，
    ///    硬写成 `.leftMirrored` 会把它掰回竖屏，照片就歪了。
    func flippedHorizontally() -> UIImage {
        withHorizontallyFlippedOrientation()
    }
}
