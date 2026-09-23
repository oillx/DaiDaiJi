import SwiftUI

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
//  在分屏下必然出错。所以这里只做一件事：
//
//      把内容约束在一个「阅读列」里，超宽时居中留白。
//
//  这套规则在 iPhone 上是**恒等变换**（iPhone 的屏宽永远小于列宽上限，
//  `maxWidth` 上限根本不会生效），所以不会改变现有观感。
// ═══════════════════════════════════════════════════════════════

enum AppLayout {

    // MARK: - 阅读列宽

    /// 首屏（陈列）的列宽。
    ///
    /// 取 620 而不是更大，是因为「最近收集」满 6 张时天然需要
    /// `110 × 6 − 20 × 5 = 560pt`，再加左右各 12pt 留白 ≈ 584；
    /// 620 刚好容得下这一排，不会逼着挂袋缩小。
    static let showcaseMaxWidth: CGFloat = 620

    /// 全部收藏页的列宽。比首屏宽 —— 分组视图用的是 `adaptive` 列，
    /// 宽度给足才会多长几列，iPad 上更实用。
    static let libraryMaxWidth: CGFloat = 940

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

    /// 卡片的放大上限。再大就会喧宾夺主，也会挤掉「最近收集」的版面。
    static let cardMaxScale: CGFloat = 1.35

    // MARK: - 工具

    /// 容器的实际内容宽度。
    ///
    /// `container` 还没被测到（首帧为 0）时回退到 `phoneWidth`，
    /// 避免首帧按一个错误的宽度排版、再跳一下。
    static func column(_ container: CGFloat, max maxWidth: CGFloat) -> CGFloat {
        container > 0 ? min(container, maxWidth) : phoneWidth
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

// MARK: - 容器宽度探测

/// 只读容器宽度的小工具：不占位、不影响视觉。
///
/// SwiftUI 在 iOS 17 上没有 `onGeometryChange`（iOS 18 才有），
/// 所以沿用项目里已有的 `Color.clear + GeometryReader` 写法（见 `RackStage`）。
///
/// 用途：iPad 旋转 / 分屏拖动都会改变容器宽度，布局要跟着重算
/// （列宽、网格列数、卡片放大倍数都依赖它）。
struct WidthProbe: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        }
    }
}
