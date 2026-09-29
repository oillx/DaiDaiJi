import SwiftUI

// ═══════════════════════════════════════════════════════════════
//  设置半窗
//
//  H5 对应：`袋袋集原型/index.html` 的 `<aside id="settingsSheet">`
//           与 `styles.css` 的 `.bottom-sheet` / `.settings-*` / `.ios-switch`
//
//  📌 入口是首页右上角的「设置」玻璃按钮（H5 `.header-settings`）。
//     沿革：设置圆钮 → 「最近收藏 N」胶囊（入口临时搬到「最近收集」标题栏的齿轮）
//     → 又换回设置按钮。现在全 App 只有这一个入口，别再加第二个。
//
//  ═══ 为什么不用 `.sheet` ═══
//  系统 detent 半窗在 iOS 26 上是**浮层卡片**：左右各内缩约 12pt、四个角全圆、
//  底部还留一道缝，而且高度只能是系统几档（medium / large），内容少时下方挂着
//  一大片空玻璃。与 H5 的「贴屏幕左右、只圆上面两角、贴底、高度随内容」四条全对不上。
//  所以这里和 `DetailCardView` 一样，由宿主 `ShelfView` 用一个 overlay 承载，
//  尺寸与动效全部照 H5 的 `.bottom-sheet` 复刻。
//
//  ═══ 本轮改版：方案 A + B 组合 ═══
//  A（玻璃底座）把半窗材质换成**冷调白玻璃**，与详情卡对齐：
//     底色  #f7f3ed（米黄）        → linear-gradient(160deg,#fff,#fafbfd 56%,#f2f4f8)
//     圆角  32px 32px 0 0          → 30px 30px 0 0
//     投影  0 -20px 70px 纯黑 24%   → 冷调双层 + 内圈白棱
//     把手  #c4beb4（暖）          → rgba(20,20,20,.35)（中性）
//     小标题 `.eyebrow` 10/750/1.75 → 与 `.step-kicker` 统一 10/700/1.5
//  B（纸感规则线）把设置项从「白 55% 卡片」拆成**一条 1px 细线**：
//     4 行之间只留 3 条线，首行上方、末行下方都不加
//     （上方会与标题撞，下方会与提示文字挤）。
//
//  📌 「我的陈列柜」上面那行英文小字（SETTINGS）已按需求去掉 ——
//     与首页「MY PRIVATE CABINET」、收藏页「THE FULL ARCHIVE」同一处理。别加回来。
// ═══════════════════════════════════════════════════════════════

struct SettingsSheet: View {
    /// 收藏总数，对应 H5 的 `#settingsCount`
    let totalCount: Int
    /// 关闭（H5 的 `data-close`：点「完成」或点遮罩）
    var onClose: () -> Void = {}

    /// 摇一摇互动开关，对应 H5 的 `#motionToggle`。
    /// ⚠️ 键名抽在 `ShakeDetector` 里，挂袋区读的是同一个 —— 两边都别写字面量。
    @AppStorage(ShakeDetector.storageKey) private var motionEnabled = false

    /// 本机能不能摇一摇（iPad 模拟器 / 无陀螺仪设备上为 false）。
    /// 不支持时把开关置灰并给出说明 —— 否则就是一个点了没反应的开关。
    private var motionSupported: Bool { ShakeDetector.isSupported }

    // MARK: 度量（全部取自方案文档的「改后」面板）

    private enum M {
        /// `.sheet { border-radius: 30px 30px 0 0; padding: 16px 20px 22px }`
        static let cornerRadius: CGFloat = 30
        /// 半窗**上内边距**（也是「我的陈列柜」到顶边的距离）。
        ///
        /// 📌 稿面是 16（H5 `padding: 16px 20px 22px`），但把手绝对定位在 `top:10`、
        ///    高度 4 ⇒ 稿面上标题距把手只剩 **2px**，太挤。
        ///    按需求「文案到顶部的距离调大一点」：**16 → 28**（把手与标题之间让出 14pt）。
        ///    ⚠️ 半窗是**底部对齐、高度由内容撑**的，所以这一改的效果是：
        ///       半窗顶边往上长 12pt、标题在屏幕上的绝对位置几乎不动
        ///       ——「文案 ↔ 顶边」的距离 +12pt。
        ///    ⚠️ 想回稿面值：写回 16。
        static let padTop: CGFloat = 28
        static let padH: CGFloat = 20
        static let padBottom: CGFloat = 22
        /// H5 `width: min(430px, 100%)` —— 宽屏（iPad）上收成一条居中的板
        static let maxWidth: CGFloat = 430

        /// `.handle { width:38px; height:4px; background:rgba(20,20,20,.35); margin:0 auto 13px }`
        /// H5 把它绝对定位在 `top: 10px`，所以内容从 16px 起、把手占 10~14px。
        static let handleWidth: CGFloat = 38
        static let handleHeight: CGFloat = 4
        static let handleTop: CGFloat = 10

        /// `.sheet h3 { font-size:25px; letter-spacing:-.5px; margin-bottom:15px }`
        static let titleFont: CGFloat = 25
        static let titleTracking: CGFloat = -0.5
        static let titleBottom: CGFloat = 15

        /// `.r { font-size:13px; padding:14px 1px; border-bottom:1px solid rgba(20,20,20,.09) }`
        static let rowFont: CGFloat = 13
        static let rowValueFont: CGFloat = 12
        static let rowPadV: CGFloat = 14
        static let rowPadH: CGFloat = 1
        static let rowLine = Color.black.opacity(0.09)

        /// `.hint { font-size:10.5px; line-height:1.65; color:#8b9099; margin:14px 1px 0 }`
        static let hintFont: CGFloat = 10.5
        static let hintTop: CGFloat = 14

        /// `.done { margin-top:16px; height:46px; border-radius:23px; font-size:15px }`
        /// 📌 沿革：稿面 46 → 按需求提到 56 → 本轮按需求再提到 **64**（圆角同步 32，保持胶囊形）。
        static let doneTop: CGFloat = 16
        static let doneHeight: CGFloat = 64
        static let doneRadius: CGFloat = 32

        /// H5 `--ink: #141414` / `--muted: #77736d`
        static let ink = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
        static let muted = Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255)
        /// 方案文档里提示文字的专用灰 `#8b9099`（比 --muted 浅一档）
        static let hintGray = Color(red: 139 / 255, green: 144 / 255, blue: 153 / 255)
        /// 冷调投影的基色，H5 `rgba(52,66,92,…)`
        static let shadowBase = Color(red: 52 / 255, green: 66 / 255, blue: 92 / 255)
    }

    /// 半窗形状：上面两个角 30，下面两个角 0（贴底）。
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: M.cornerRadius,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0,
                               topTrailingRadius: M.cornerRadius,
                               style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("我的陈列柜")
                // H5 里它是 `<h2>` —— 继承全局 `h2` 的衬线（25px / 700 / 字距 -.5），
                // 不是 `.sheet h3`。所以这一行要走宋体，别改成 `.system(...)`。
                .font(AppFont.songti(M.titleFont))
                .tracking(M.titleTracking)
                .foregroundStyle(M.ink)
                .padding(.bottom, M.titleBottom)

            // ── 设置项：无卡片、无圆角，只留中间三条 1px 细线（方案 B）──
            VStack(spacing: 0) {
                settingRow("收藏统计") {
                    Text("\(totalCount) 件")
                        .font(.system(size: M.rowValueFont, weight: .bold))
                        .foregroundStyle(M.ink)
                }
                rowLine
                settingRow("本地存储") {
                    Text("已启用")
                        .font(.system(size: M.rowValueFont, weight: .bold))
                        .foregroundStyle(M.ink)
                }
                rowLine
                settingRow("iCloud 同步") {
                    // `.r .dim { color:#77736d; font-weight:400 }` —— 未开放的值是常规字重
                    Text("即将支持")
                        .font(.system(size: M.rowFont))
                        .foregroundStyle(M.muted)
                }
                rowLine
                settingRow("摇一摇互动") {
                    Toggle("", isOn: $motionEnabled)
                        .labelsHidden()
                        .tint(M.ink)
                        .disabled(!motionSupported)
                }
            }

            // H5 `#motionHint`。文案与原型逐字对应，包括「不支持」那一档。
            hint(motionHint)
            hint("照片处理和收藏数据默认保存在此设备。不会上传或持久保存图片。")

            Button { onClose() } label: {
                Text("完成")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: M.doneHeight)
                    .background(M.ink, in: .rect(cornerRadius: M.doneRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, M.doneTop)
        }
        .padding(.top, M.padTop)
        .padding(.horizontal, M.padH)
        .padding(.bottom, M.padBottom)
        // H5 `width: min(430px, 100%)`
        .frame(maxWidth: M.maxWidth)
        // ── 方案 A：冷调白玻璃底座 ──
        //
        // ⚠️ 顺序不能变：先把区域撑到**物理底边**（H5 的 `bottom: 0`），
        //    再按形状裁圆角、再描内圈白棱。反过来的话内圈白棱会横在
        //    安全区那条线上，看起来像多了一根分隔线。
        .background {
            CoolGlassSurface.gradient
                .ignoresSafeArea(edges: .bottom)
                .clipShape(shape)
                .overlay {
                    // H5 `box-shadow` 里的 `0 0 0 1px rgba(255,255,255,.9) inset`
                    shape.strokeBorder(CoolGlassSurface.innerRim, lineWidth: 1)
                }
        }
        // H5 `0 -18px 52px rgba(52,66,92,.16), 0 -3px 12px rgba(52,66,92,.07)`
        // （CSS 的 blur 取一半当 SwiftUI 的 radius）
        .shadow(color: M.shadowBase.opacity(0.16), radius: 26, x: 0, y: -18)
        .shadow(color: M.shadowBase.opacity(0.07), radius: 6, x: 0, y: -3)
        // 抽屉把手：H5 `.sheet-handle`（绝对定位在 top:10px，所以不占布局）
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.black.opacity(0.35))
                .frame(width: M.handleWidth, height: M.handleHeight)
                .padding(.top, M.handleTop)
        }
        // ⚠️ 内容不放进 ScrollView：ScrollView 在滚动方向上是**贪婪**的，
        //    会把半窗撑满整屏，而 H5 的半窗高度是随内容自适应的（4 行设置项）。
        //    内容最多也就 400 出头，加上提示文字的换行余量仍在一屏之内。
        //
        // ⚠️ 这里**不要**指望 `.ignoresSafeArea(edges: .bottom)` 能把底座铺到物理底边：
        //    半窗是挂在 `.overlay` 里的，那一层的坐标空间只到安全区上沿，
        //    写在这里已经晚了（实测面板底边停在安全区线、下面露出一条遮罩）。
        //    「贴物理底边」改由宿主 `ShelfView.settingsOverlay` 的 ZStack 统一忽略底部安全区。
        //
        //    于是底部这 22pt 内边距（H5 `padding: … 22px`）就是**按钮到屏幕底边**的距离。
    }

    // MARK: - 局部

    /// 行间细线。只有中间三条 —— 首行上方与末行下方都不加（方案文档明确要求）。
    private var rowLine: some View {
        Rectangle()
            .fill(M.rowLine)
            .frame(height: 1)
    }

    /// 一行设置项：左标题右值，H5 `.r`
    private func settingRow<Content: View>(_ title: String,
                                           @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: M.rowFont))
                .foregroundStyle(M.ink)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, M.rowPadV)
        .padding(.horizontal, M.rowPadH)
    }

    /// H5 `.hint`：10.5px / 行高 1.65 / `#8b9099`
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: M.hintFont))
            .foregroundStyle(M.hintGray)
            .lineSpacing(3.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, M.hintTop)
            .padding(.horizontal, M.rowPadH)
    }

    /// 摇一摇的说明文案。三档，与 H5 `#motionHint` 的三种状态逐字对应
    /// （`enableMotion()` / `disableMotion()` / `typeof DeviceMotionEvent === 'undefined'`）。
    private var motionHint: String {
        guard motionSupported else {
            return "当前设备不支持摇一摇互动。"
        }
        return motionEnabled
            ? "已开启。轻轻晃动手机会让「最近收集」的挂袋跟着摆动。仅在本机读取设备运动数据，不会上传。"
            : "开启后，轻轻晃动手机会让「最近收集」的挂袋跟着摆动。仅在本机读取设备运动数据，不会上传。"
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color(red: 0.894, green: 0.902, blue: 0.925).ignoresSafeArea()
        SettingsSheet(totalCount: 16)
    }
}
