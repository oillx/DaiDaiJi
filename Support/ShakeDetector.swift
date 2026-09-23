import Foundation
import CoreMotion
import Combine

// ═══════════════════════════════════════════════════════════════
//  摇一摇互动
//
//  H5 对应：`袋袋集原型/app.js` 的 `handleDeviceMotion()` / `enableMotion()`。
//           设置面板里的开关在 `index.html` 的 `#motionToggle`。
//
//  作用：把设备的**横向晃动**换算成挂袋的摆动冲量 ——
//        「最近收集」那一排袋子会跟着左右晃。
//
//  ⚠️ 与 H5 的两处**有意不同**，两处都是为了在真机上更自然：
//
//   1. 用 `userAcceleration`（已扣掉重力），而不是浏览器的
//      `accelerationIncludingGravity`。
//      后者把重力算在内，手机只要稍微歪一点、x 轴就有一个恒定分量，
//      表现会变成「一直微微摆」而不是「晃了才摆」。
//
//   2. 阈值与增益按 **g ↔ m/s² 重新标定**过：
//      浏览器给的是 m/s²，CoreMotion 给的是 g（1 g = 9.81 m/s²）。
//      直接照抄 1.2 会变成几乎任何动作都触发。
//
//  📌 **不需要权限弹框**：`CMMotionManager` 的加速度 / 设备运动数据
//     不像相册、相机那样会弹权限框 —— 被弹框的是浏览器里的
//     `DeviceMotionEvent.requestPermission()`（H5 那边必须处理，
//     而且要求必须在用户手势里请求，所以才设计成一个开关按钮）。
//     iOS 原生侧没有这一步，开关纯粹是个偏好设置。
//
//     ⚠️ 但 Info.plist 里仍然声明了 `NSMotionUsageDescription`：
//        隐私敏感 API 缺少说明字符串有**崩溃**风险，而且提审时
//        这条说明与设置面板里「仅在本机读取、不会上传」的说法互为印证。
// ═══════════════════════════════════════════════════════════════

final class ShakeDetector: ObservableObject {

    /// 一次有效晃动。
    ///
    /// ⚠️ 用自增的 `id` 标识事件，不能只发力度值 ——
    ///    连续两次力度相同的晃动会得到两个相等的值，
    ///    SwiftUI 的 `onChange` 会判为「没变化」而把它们丢掉（少晃一下）。
    struct Event: Equatable {
        let id: Int
        /// 横向加速度，单位 **g**，正负号即左右方向
        let accelX: Double
    }

    @Published private(set) var event: Event?

    /// `@AppStorage` 的键。
    /// 设置面板与挂袋区各读一次，必须指向同一个键 —— 抽成常量避免两边写歪。
    static let storageKey = "motionEnabled"

    /// 晃动强度阈值（g）。H5 用的是 1.2 —— 单位是 m/s²，换算过来 1.2 / 9.81 ≈ 0.12。
    /// 低于它视为日常手持的细微抖动，忽略（H5 同此判断）。
    private static let threshold: Double = 0.12
    /// 节流间隔。H5 是 60ms，照搬。
    /// 再密下去弹簧会被反复重置，看起来像「抖动」而不是「摆动」。
    private static let throttle: TimeInterval = 0.06

    private let manager = CMMotionManager()
    private var sequence = 0
    private var lastFire: TimeInterval = 0

    /// 本机有没有可用的设备运动传感器。
    /// iPad 模拟器、以及没有陀螺仪的设备上为 false ——
    /// 此时设置面板应当把开关置灰，而不是留一个点了没反应的开关。
    ///
    /// ⚠️ 缓存成常量：它的调用点是 View 的 `body`，
    ///    每次求值都新建一个 `CMMotionManager` 是白开销。
    static var isSupported: Bool { supported }
    private static let supported = CMMotionManager().isDeviceMotionAvailable

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        // 30Hz 足够表现一次晃动，比 H5 的「每个 devicemotion 事件」省电
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        // 回调丢到主队列：`event` 是 @Published，必须在主线程写
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.consume(accelX: motion.userAcceleration.x)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    private func consume(accelX: Double) {
        let now = Date.now.timeIntervalSince1970
        guard now - lastFire >= Self.throttle else { return }
        guard abs(accelX) >= Self.threshold else { return }
        lastFire = now
        sequence += 1
        event = Event(id: sequence, accelX: accelX)
    }
}
