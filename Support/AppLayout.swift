import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════
//  跨设备布局（iPhone / iPad / iPad 分屏）
//
//  ⚠️⚠️ 类型名**必须叫 `AppLayout`，不能叫 `Layout`** ⚠️⚠️
//
//  `Layout` 是 SwiftUI 自带的协议，本项目有两个自定义布局实现了它：
//      · `FlowRow`    —— HeroCardView.swift（卡片背面标签）
//      · `FlowLayout` —— AddBagView.swift（表单里已选标签）
//
//  一旦这里再定义一个 `enum Layout`，它会在**整个模块**内遮蔽
//  SwiftUI 的 `Layout` 协议，那两处 `struct X: Layout` 立刻报
//  「inheritance from non-protocol type 'Layout'」；而真正用它们的
//  视图（如 DetailCardView 的 `FlowTags`）会报成
//  「extra trailing closure passed in call」+
//  「buildExpression requires that 'FlowRow' conform to 'View'」——
//  错误位置指向调用方，跟根因（这个 enum）看着毫无关系，极难排查。
//
//  设计原则：**按容器宽度自适应，而不是判断 `userInterfaceIdiom`**。
//
//  iPad 允许 Slide Over / Split View，窗口宽度可以在 320 ~ 1366pt 之间连续变化；
//  而 iPhone 也横跨 320（SE）~ 440（Pro Max）。用「是不是 iPad」来分支，
//  在分屏下必然出错。所以：
//
//  ⚠️ 唯一的例外是 `isPad` —— 只用来开「首页大卡与袋子的 iPhone 专属收矮」
//     （`HeroMetrics` 的 `phoneCardShrink` / `phoneBagShrink`）。原因：iPhone 横屏 956pt、iPad 竖屏 820pt，
//     容器宽度区间**重叠**，靠宽度分不开这两者；而口径是「iPhone 收矮、iPad 保持」。
//     其余一切规则仍按宽度自适应。
//
//      **内容铺满容器宽度**（不设「阅读列」上限、两侧不留白），
//      只把两类东西收住：① 固定尺寸的卡片（按容器宽放大，但夹在上限内）；
//      ② 页内水平内边距（宽屏上从 H5 的 20/18/22 提到 24~28）。
//
//  📌 曾经的「等比放大壳」方案（内容按 430 设计宽整体 scaleEffect、居中留白）
//     已废弃：用户要的是 **iPad 铺满全屏**，不是浏览器样机那种窄壳。
//     现在 iPad 上：字号与卡片接近手机尺寸，靠「挂袋摊开、展架一屏多显示几张、
//     网格多长几列」来利用宽度。
//
//  这套规则在 iPhone 上是**恒等变换**（容器 ≤ 453pt 时既不放宽内边距、
//  也不放大卡片），所以不会改变现有观感。
// ═══════════════════════════════════════════════════════════════

enum AppLayout {

    // MARK: - 页面宽度

    /// 相机页的列宽：预览区与底部三控件共用同一列。
    ///
    /// ⚠️ 这个必须限制。不限制的话，iPad 上会变成
    ///    「预览区铺满 1366pt、快门在屏幕正中、补光与相册贴到屏幕两端」，
    ///    三个控件相隔上千点，既难看也不好按。
    static let cameraMaxWidth: CGFloat = 560

    /// 表单类页面（新增纸袋 / 纸袋详情）的列宽。
    /// `Form` 在 iPad 上默认铺满整屏，输入框会拉成一行一千多点，很难读。
    static let formMaxWidth: CGFloat = 620

    /// 底部导航三个控件的跨度上限。
    ///
    /// 底栏用 `Spacer(minLength: 0)` 均分剩余空间，在 iPhone 上这是对的；
    /// 但 iPad 横屏有 1366pt 可用宽，两个 nav-item 会被推到屏幕两端、
    /// 与中间的 ＋ 相隔上千点 —— 既难看，手指也够不到。
    ///
    /// 520 ≈ 三个控件（96 + 84 + 96 = 276）加上两倍呼吸间距，iPhone 上恒等。
    static let bottomNavMaxWidth: CGFloat = 520

    // MARK: - 卡片放大

    /// `HeroMetrics` / `DetailCardMetrics` 是按 iPhone 的 393pt 屏定的 1:1 稿面值。
    /// 宽屏上想让卡片跟着变大，只能**整体等比缩放** ——
    /// 卡片内部所有尺寸（字号、圆角、投影、内边距）都是写死的，
    /// 只把外框改大只会多出一圈空白，比例会崩。
    static let phoneWidth: CGFloat = 393

    /// 卡片的放大上限（iPad 上 1.25：308×348 变 385×435；卡面尺寸见 `HeroMetrics`，
    /// 它在 iPhone 上按需求另收了 28 高）。
    /// 再大就会喧宾夺主，也会挤掉「最近收集」的版面。
    static let cardMaxScale: CGFloat = 1.25

    // MARK: - 工具

    /// 页内水平内边距：iPhone 照 H5 的数值（20 / 18 / 22 / 12），
    /// 宽屏（iPad）统一提到 **24~28**，避免界面在大屏上贴边。
    ///
    /// 规则：`base + 8` 再夹到 `[24, 28]` ——
    ///   20 → 28、18 → 26、22 → 28（夹住）、12 → 24（夹住）。
    ///
    /// ⚠️ iPhone（容器 ≤ 453pt）**原样返回**，一分不改。
    static func pagePad(_ base: CGFloat, for container: CGFloat) -> CGFloat {
        guard isWide(container) else { return base }
        return min(28, max(24, base + 8))
    }

    /// 卡片放大倍数：以 iPhone 屏宽为 1.0，随列宽线性放大到上限。
    /// 窄容器（iPad 分屏 / SE）一律返回 1.0，等价于不缩放。
    static func cardScale(forColumn column: CGFloat) -> CGFloat {
        min(cardMaxScale, max(1, column / phoneWidth))
    }

    /// 详情卡专用：除列宽外还要保证**放大后放得下**。
    ///
    /// 横屏 iPad 的高度只有 768 / 834pt，详情卡原高 560pt，
    /// 放大 1.35 倍就是 756pt —— 不留神就会被上下裁掉。
    /// 所以再按可用空间夹一次，放不下就退回 1.0（保持原尺寸，由调用方自己窄化）。
    static func cardScale(fitting available: CGSize,
                          card: CGSize,
                          sideInset: CGFloat,
                          verticalInset: CGFloat,
                          column: CGFloat) -> CGFloat {
        let byColumn = cardScale(forColumn: column)
        let byWidth  = (available.width  - sideInset)     / max(card.width,  1)
        let byHeight = (available.height - verticalInset) / max(card.height, 1)
        return max(1, min(byColumn, byWidth, byHeight))
    }

    /// 取景框放大倍数（相机页）。
    ///
    /// 稿面取景框是 280×317pt，配 iPhone 上约 359pt 宽的预览区。
    /// iPad 上预览区宽得多，固定尺寸的框会缩成一个小方块、失去取景意义。
    ///
    /// ⚠️ 宽度不超过 480pt 时**恒返回 1**：iPhone（含 Pro Max）与 iPad 分屏
    ///    都落在这个区间内，保证稿面的 1:1 尺寸一分不改。
    static func guideScale(previewWidth: CGFloat) -> CGFloat {
        guard previewWidth > 480 else { return 1 }
        return min(1.5, previewWidth / 420)
    }

    /// 是否 iPad。**全项目唯一按机型判断的地方**（服务「首页大卡只在 iPhone 上收矮」）。
    ///
    /// 为什么不能只看宽度：iPhone 横屏最宽 956pt，iPad 竖屏 820pt ——
    /// 容器宽度区间是**重叠**的，宽度分不出这两者。而口径是
    /// 「iPhone 上把大卡与袋子收矮、iPad 一律保持稿面尺寸」，只能认机型。
    ///
    /// 调用点唯一：`HeroMetrics` 的收矮常量（`Views/HeroCardView.swift`）。
    /// 其余一切（内边距、卡片放大、网格列数…）仍按容器宽度自适应。
    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// 是否属于「真正的宽屏」。
    ///
    /// 用来给「允许放大」这类**会改变观感**的规则设闸门：
    /// 只有明确超出手机极限宽度的容器才放行，iPad 分屏（320~500pt）
    /// 一律按手机处理，保证 iPhone 与小窗下的呈现一分不改。
    ///
    /// iPhone 16 Pro Max 逻辑宽度 440pt，所以阈值取 393 + 60 = 453。
    static func isWide(_ container: CGFloat) -> Bool {
        container > phoneWidth + 60
    }
}

// MARK: - 修饰符

extension View {
    /// 把整块内容约束在 `maxWidth` 内并水平居中。
    ///
    /// 容器比 `maxWidth` 窄时（iPhone / iPad 分屏 / Slide Over）完全无副作用 ——
    /// 只是加了一层宽度上限，实际宽度仍由容器决定。
    ///
    /// ⚠️ 只该加在**内容**上，不要加在带背景色的容器上，
    ///    否则底色会跟着收窄、露出页面底，看起来像内容没铺满。
    func contentColumn(_ maxWidth: CGFloat) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
