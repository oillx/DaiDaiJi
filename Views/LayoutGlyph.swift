// ═══════════════════════════════════════════════════════════════
//  「全部收藏」右上角布局切换钮
//
//  ⚠️ 两个图标**不是 SF Symbol**，是按设计稿 1:1 复刻的自绘 Shape。
//     系统符号里既没有「实心方块 + 镂空 4×4 宫格」，也没有「3 条空心横条」，
//     所以不能简单换个 systemName 了事。
//
//  设计基准：**24×24 的 viewBox**（下面所有常量都是这个坐标系里的数）。
//  量法：设计稿截图是 @3x，所以「px ÷ 3 = 这个坐标系里的单位数」，1 单位 = 1pt。
//
//  📐 设计稿实测（px；尺寸一律取 **α=0.5 的亚像素边界**，整数游程会被
//     抗锯齿带偏 ±0.5px —— 早期按整数量的结果是「墨迹 68、展架条宽 56」，
//     比真实几何各大了 1px，已全部改用亚像素值）
//  ┌──────────────┬──────────┬──────────┐
//  │              │ 宫格     │ 展架     │
//  ├──────────────┼──────────┼──────────┤
//  │ 墨迹         │ 67.4×67.4│ 55×58.1  │
//  │ 图标框       │ 72×72（＝24pt，两个图标同一个框）│
//  │ 线宽 / 描边  │ 6.1      │ 6.1      │
//  │ 与标签的间隙 │ 图标墨迹底 → 标签墨迹顶 = 27   │
//  │ 标签字号     │ 12pt（墨迹 69~70×34，已用苹方栅格化比对）│
//  │ 标签色       │ #969696                          │
//  │ 图标色       │ #333333                          │
//  └──────────────┴──────────┴──────────┘
//
//  ⚠️ 两个图标**墨迹占框比不同**（宫格 22.47/24，展架 18.33×19.35/24），
//     这不是量错 —— 设计稿里宫格就明显比展架大一圈。别为了「看起来一致」
//     把两个图形调成一样大。
//
//  改常量前先回去量设计稿，别凭手感调 —— 尤其是「几条」「几列」这种结构性的数。
// ═══════════════════════════════════════════════════════════════

import SwiftUI

/// 切换钮的规格：图标框、标签字号/间距、两个颜色。
///
/// 数值来历见文件头。**唯一真源**，`LayoutGlyphView` 与页面里的按钮都读这里，
/// 不要在调用点再写一遍字面量。
enum LayoutToggleMetrics {
    /// 图标框边长（24 基准的 viewBox 直接当 pt 用）。
    ///
    /// 设计稿里两个图标画在同一尺寸的框内，墨迹各占各的比例，
    /// 所以框一样大、图形不一样大 —— 见 `GridGlyph.inkSide` / `ShelfGlyph.barWidth`。
    static let box: CGFloat = 24

    /// 标签字号。
    ///
    /// 不是估的：把「宫格 / 展架」按 12pt×3 = 36px 用 CoreText 栅格化，
    /// 墨迹正好 68~70 × 34 px，与设计稿的 69/70 × 34 一致（11pt 会小一号）。
    ///
    /// 📌 **按需求从 12 收到 11** —— 右上角那枚按钮的标签，首页「设置」与收藏页
    ///    「宫格 / 展架」同源（都走 `HeaderEntryButton`），一起变小。
    ///    它与 `labelSpacing`(6→5) 及 `HeaderEntryMetrics` 的上下内边距一起收，
    ///    药丸总高 60 → **54pt**。
    ///    ⚠️ 想回设计稿值：写回 12（只影响这枚按钮与文末的 `#Preview`）。
    static let labelFont: CGFloat = 11

    /// 图标框底边 → 标签**行盒**顶的间距。
    ///
    /// 设计稿量到的是「图标墨迹底 → 标签墨迹顶」＝ 27px；
    /// 扣掉宫格墨迹在框内留的 0.77pt、再扣掉苹方 12pt 行盒在墨迹上方的
    /// 约 2.8pt 空白（CoreText 实测 ascent − 墨迹顶），取整得 6。
    /// 实测结果：宫格那档的墨迹间隙 27px、展架 32px，与设计稿一致。
    ///
    /// 📌 **按需求从 6 收到 5**：上面那套 27px 的推导是配 **12pt** 标签算的，
    ///    标签收到 11 后间隙同步收一档，两行才不会被撑开。想回设计稿值写回 6。
    static let labelSpacing: CGFloat = 5

    /// 图标色 #333333（设计稿实测的实心区颜色，**不是** `.primary` 的纯黑）。
    static let iconColor = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)

    /// 标签色 #969696。
    ///
    /// ⚠️ 不能用 `.secondary` 代替：`.secondary` 叠在 #F2F3F7 上约是 #858585，
    ///    比设计稿深一档。本项目强制浅色外观，硬编码这个值没有适配风险。
    static let labelColor = Color(red: 150 / 255, green: 150 / 255, blue: 150 / 255)
}

/// 宫格图标：实心圆角方块 + 镂空 4×4 方格。
///
/// 设计稿按 **α=0.5 亚像素边界**量得（整数像素游程会被抗锯齿带偏 ±0.5px）：
///     墨迹 22.47、格线 2.03、白格 3.08、方块圆角 1.83。
///     校验：5×2.03 + 4×3.08 = 22.47 ✓（与实测墨迹宽 67.4px 一致）
///
/// ⚠️ 格线宽必须与白格边长满足 `5·line + 4·cell == inkSide`
///    （宫格是「5 道线 + 4 格」的结构）。`cell` 因此写成**计算属性**，
///    只改 `line` 不会把方格挤歪、也不会让最后一列被裁掉一截。
///
/// ⚠️ 这是**镂空**图形，必须用 even-odd 规则填充：
///     `.fill(color, style: FillStyle(eoFill: true))`
///    用默认的 non-zero 规则会把 16 个方格一起填实，变成一个纯色方块。
struct GridGlyph: Shape {
    /// 墨迹边长（24 框内）
    static let inkSide: CGFloat = 22.47
    /// 墨迹到框边的留白，两面对称
    static var inset: CGFloat { (24 - inkSide) / 2 }
    /// 格线宽（＝外框厚，设计稿里两者一致）
    static let line: CGFloat = 2.03
    /// 白格边长 —— 由 `5·line + 4·cell == inkSide` 反解，别写死
    static var cell: CGFloat { (inkSide - 5 * line) / 4 }
    /// 一行白格的个数（高向同样是 4 行）
    static let columns = 4
    /// 方块整体圆角
    static let boxRadius: CGFloat = 1.83
    /// 白格自身的小圆角
    static let cellRadius: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let k = side / 24
        let ox = rect.midX - side / 2
        let oy = rect.midY - side / 2

        var p = Path()

        // 外框：一个实心圆角方块
        p.addRoundedRect(
            in: CGRect(x: ox + k * Self.inset, y: oy + k * Self.inset,
                       width: k * Self.inkSide, height: k * Self.inkSide),
            cornerSize: CGSize(width: k * Self.boxRadius, height: k * Self.boxRadius)
        )

        // 内部 4×4 个白格：在 even-odd 下被挖成孔
        let step = Self.line + Self.cell
        for row in 0..<Self.columns {
            for col in 0..<Self.columns {
                let x = Self.inset + Self.line + CGFloat(col) * step
                let y = Self.inset + Self.line + CGFloat(row) * step
                p.addRoundedRect(
                    in: CGRect(x: ox + k * x, y: oy + k * y,
                               width: k * Self.cell, height: k * Self.cell),
                    cornerSize: CGSize(width: k * Self.cellRadius, height: k * Self.cellRadius)
                )
            }
        }
        return p
    }
}

/// 展架图标：三条独立的空心横条。
///
/// 设计稿按 α=0.5 亚像素边界量得：
///     条宽 18.33、条高 5.09、间隙 2.04、描边 2.03、圆角 0.77。
///     校验：单条横截面「描边 2.03 + 内孔 14.27 + 描边 2.03 = 18.33 ✓」
///           （内孔实测 42.8px ÷ 3 = 14.27）、
///           三条总高 3×5.09 + 2×2.04 = 19.35 ✓（实测 58.1px）。
///
/// 📌 整数像素游程量到的是 56×58、描边 7，那是抗锯齿溢出的假象，
///    不是真实几何 —— 别拿它回来改这里的数。
///
/// ⚠️ 圆角 0.77 **小于**描边 2.03，所以内孔是**直角**矩形，
///    不能拿「外圆角 − 描边」去推内圆角（会算成负数）。与设计稿一致。
///
/// ⚠️ 同样是镂空图形，填充要带 `FillStyle(eoFill: true)`。
struct ShelfGlyph: Shape {
    /// 条宽（24 基准）
    static let barWidth: CGFloat = 18.33
    /// 单条高度
    static let barHeight: CGFloat = 5.09
    /// 条与条的间隙
    static let gap: CGFloat = 2.04
    /// 描边厚度
    static let stroke: CGFloat = 2.03
    /// 三条 → 总高，用于垂直居中
    static let totalHeight: CGFloat = 3 * barHeight + 2 * gap
    /// 单条圆角
    static let radius: CGFloat = 0.77

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let k = side / 24
        let ox = rect.midX - side / 2
        let oy = rect.midY - side / 2

        var p = Path()
        let left = (24 - Self.barWidth) / 2          // 水平居中 → 3
        let top = (24 - Self.totalHeight) / 2        // 垂直居中

        for i in 0..<3 {
            let y = top + CGFloat(i) * (Self.barHeight + Self.gap)
            // 外轮廓（圆角）
            p.addRoundedRect(
                in: CGRect(x: ox + k * left, y: oy + k * y,
                           width: k * Self.barWidth, height: k * Self.barHeight),
                cornerSize: CGSize(width: k * Self.radius, height: k * Self.radius)
            )
            // 内孔（直角）
            p.addRect(
                CGRect(x: ox + k * (left + Self.stroke),
                       y: oy + k * (y + Self.stroke),
                       width: k * (Self.barWidth - 2 * Self.stroke),
                       height: k * (Self.barHeight - 2 * Self.stroke))
            )
        }
        return p
    }
}

/// 切换钮上的一个图标槽：负责统一尺寸、颜色与镂空填充规则。
///
/// ⚠️ `FillStyle(eoFill: true)` 不能省 —— 两个图形都是「实心块挖孔」的画法，
///    默认的 non-zero 会把孔一起填掉。放在这里集中处理，
///    免得每个调用点各写一遍、漏掉一处就变成一块纯色。
struct LayoutGlyphView: View {
    /// 切换钮当前是否为网格视图（true ＝ 显示展架图标，与 H5 `layoutIcon` 同步）
    let isGrid: Bool

    var body: some View {
        // ⚠️ 用 `AnyShape` 擦除类型后再 `.fill(...)`。
        //    不能写成 `Group { if … ShelfGlyph() else GridGlyph() }.fill(...)` ——
        //    `Group` 只符合 `View`，**不转发** `Shape` 一致性，那样会报
        //    「value of type 'Group<…>' has no member 'fill'」。
        glyphShape
            .fill(LayoutToggleMetrics.iconColor, style: FillStyle(eoFill: true))
            .frame(width: LayoutToggleMetrics.box, height: LayoutToggleMetrics.box)
    }

    private var glyphShape: AnyShape {
        isGrid ? AnyShape(ShelfGlyph()) : AnyShape(GridGlyph())
    }
}

// MARK: - 标题栏右上角的入口按钮（H5 `.header-settings`）

/// 首页 / 全部收藏右上角那枚「玻璃托底按钮」的规格。
///
/// H5 注释原文：左侧是「大标题 + 小文案」的上下两行文字块，右侧只有一枚裸图标
/// 会显得单薄，加底托后右侧成为一块有分量的实体，与左侧文字块配平。
///
/// ⚠️ 标签字号沿用 iOS 侧按**设计稿**量得的 12pt（`LayoutToggleMetrics.labelFont`），
///    而不是 H5 的 `font-size: 9px` —— 两个来源在这一点上打架，已确认以设计稿为准
///    （9px 的按钮文字在 24pt 图标下明显偏小）。
///    📌 该字号现按需求收到 **11**；连同 `padTop/padBottom`(9/7→7/5) 与 `gap`(6→5)，
///       药丸总高 60 → 54pt —— 见各常量上的说明。
enum HeaderEntryMetrics {
    /// H5 `border-radius: 16px`
    static let cornerRadius: CGFloat = 16
    /// H5 `padding: 9px 12px 7px`（上下不对称：图标重心比文字高）
    ///
    /// 📌 **按需求各自收 2pt（9→7 / 7→5）**：这枚按钮原来比左侧「大标题 + 小文案」
    ///    那两行还高，整条标题栏被它撑到 60pt。收完 54pt，仍高于 44pt 的最小可点尺寸。
    ///    ⚠️ 再往下收要注意：左侧文字块本身约 52pt 高，低于它之后按钮不再是
    ///       「决定标题栏高度的那一项」，继续减内边距只会让按钮在栏内显得更小，
    ///       但标题栏不会再变矮。
    static let padTop: CGFloat = 7
    static let padBottom: CGFloat = 5
    static let padHorizontal: CGFloat = 12
    /// 图标与标签之间。
    ///
    /// 取 `LayoutToggleMetrics.labelSpacing`（现 5；设计稿是 6 —— 图标墨迹底
    /// → 标签墨迹顶 27px）而不是 H5 的 `gap: 3px` —— 那个 3 是配 9px 小字算的；
    /// 既然标签字号是按设计稿量出来的，间距也跟着它走，
    /// 否则「图标 24 + 小字 + 间隙 3」会把两行挤在一起。
    static let gap: CGFloat = LayoutToggleMetrics.labelSpacing
    /// H5 `background: rgba(255,255,255,.6)` / `border: 1px solid rgba(255,255,255,.75)`
    static let fill = Color.white.opacity(0.6)
    static let border = Color.white.opacity(0.75)
    /// H5 `box-shadow: 0 6px 14px rgba(52,66,92,.08)`
    /// （CSS 的 blur 14 → SwiftUI 的 radius 取一半 = 7）
    static let shadowColor = Color(red: 52 / 255, green: 66 / 255, blue: 92 / 255)
    static let shadowOpacity: Double = 0.08
    static let shadowRadius: CGFloat = 7
    static let shadowY: CGFloat = 6
    /// H5 `letter-spacing: 1px`
    static let labelTracking: CGFloat = 1
    /// 「设置」入口的六角螺帽图标框（H5 `width: 24px`）
    static let settingsIconSide: CGFloat = 24
}

/// 右上角玻璃托底按钮：**图标在上、文字在下**。
///
/// 首页那枚是「设置」，收藏页那枚是布局切换 —— 外观完全同构，
/// 所以做成一个组件，两处只换图标与文字。
struct HeaderEntryButton<Icon: View>: View {
    let label: String
    var action: () -> Void = {}
    @ViewBuilder var icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: HeaderEntryMetrics.gap) {
                icon
                Text(label)
                    .font(.system(size: LayoutToggleMetrics.labelFont))
                    .tracking(HeaderEntryMetrics.labelTracking)
                    .foregroundStyle(LayoutToggleMetrics.labelColor)
            }
            .padding(.top, HeaderEntryMetrics.padTop)
            .padding(.bottom, HeaderEntryMetrics.padBottom)
            .padding(.horizontal, HeaderEntryMetrics.padHorizontal)
            .background(
                HeaderEntryMetrics.fill,
                in: RoundedRectangle(cornerRadius: HeaderEntryMetrics.cornerRadius,
                                     style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HeaderEntryMetrics.cornerRadius,
                                 style: .continuous)
                    .strokeBorder(HeaderEntryMetrics.border, lineWidth: 1)
            }
            .shadow(color: HeaderEntryMetrics.shadowColor
                        .opacity(HeaderEntryMetrics.shadowOpacity),
                    radius: HeaderEntryMetrics.shadowRadius,
                    x: 0, y: HeaderEntryMetrics.shadowY)
            // 底托是圆角矩形，命中区要跟上，否则四角点不到
            .contentShape(RoundedRectangle(cornerRadius: HeaderEntryMetrics.cornerRadius,
                                           style: .continuous))
        }
        .buttonStyle(HeaderEntryButtonStyle())
    }
}

/// H5 `.header-settings:active { transform: scale(.94) }`
private struct HeaderEntryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// 「设置」入口的六角螺帽。
///
/// ⚠️ 下面这串路径是**从设计给的 SVG 直接转过来的**（`d` 属性逐条命令转成
///    `move / addLine / addCurve / closeSubpath`），不是照着画一个六边形。
///    它由四条子路径叠成：外六边形 → 内六边形 → r4 圆 → r2 圆，
///    靠 even-odd 挖出「螺帽外框 + 中间圆环」。
///    手画一个六边形再挖个圆，观感接近，但圆角、粗细、环宽都不是这几个数。
///
/// ⚠️ H5 侧用的是 `fill-rule: evenodd`，填充必须带 `FillStyle(eoFill: true)`，
///    否则中间该挖空的地方会被填实、四个圆环全糊成一坨。
struct SettingsNutGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let k = side / 24
        let ox = rect.midX - side / 2
        let oy = rect.midY - side / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + k * x, y: oy + k * y)
        }

        var p = Path()
        p.move(to: pt(10.5281, 1.93003))
        p.addCurve(to: pt(12.0001, 1.54407),
                   control1: pt(10.9774, 1.677),
                   control2: pt(11.4844, 1.54407))
        p.addCurve(to: pt(13.4721, 1.93003),
                   control1: pt(12.5158, 1.54407),
                   control2: pt(13.0227, 1.677))
        p.addLine(to: pt(20.1321, 5.68003))
        p.addCurve(to: pt(21.2501, 6.78011),
                   control1: pt(20.5957, 5.94109),
                   control2: pt(20.9815, 6.32077))
        p.addCurve(to: pt(21.6601, 8.29403),
                   control1: pt(21.5186, 7.23946),
                   control2: pt(21.6601, 7.76196))
        p.addLine(to: pt(21.6601, 15.706))
        p.addCurve(to: pt(21.2501, 17.2199),
                   control1: pt(21.6601, 16.2381),
                   control2: pt(21.5186, 16.7606))
        p.addCurve(to: pt(20.1321, 18.32),
                   control1: pt(20.9815, 17.6793),
                   control2: pt(20.5957, 18.059))
        p.addLine(to: pt(13.4721, 22.07))
        p.addCurve(to: pt(12.0001, 22.456),
                   control1: pt(13.0227, 22.3231),
                   control2: pt(12.5158, 22.456))
        p.addCurve(to: pt(10.5281, 22.07),
                   control1: pt(11.4844, 22.456),
                   control2: pt(10.9774, 22.3231))
        p.addLine(to: pt(3.86809, 18.32))
        p.addCurve(to: pt(2.75012, 17.2199),
                   control1: pt(3.40447, 18.059),
                   control2: pt(3.01863, 17.6793))
        p.addCurve(to: pt(2.34009, 15.706),
                   control1: pt(2.48161, 16.7606),
                   control2: pt(2.3401, 16.2381))
        p.addLine(to: pt(2.34009, 8.29403))
        p.addCurve(to: pt(2.75012, 6.78011),
                   control1: pt(2.3401, 7.76196),
                   control2: pt(2.48161, 7.23946))
        p.addCurve(to: pt(3.86809, 5.68003),
                   control1: pt(3.01863, 6.32077),
                   control2: pt(3.40447, 5.94109))
        p.addLine(to: pt(10.5281, 1.93003))
        p.closeSubpath()

        p.move(to: pt(12.4911, 3.67403))
        p.addCurve(to: pt(12.0001, 3.54519),
                   control1: pt(12.3412, 3.58956),
                   control2: pt(12.1721, 3.54519))
        p.addCurve(to: pt(11.5091, 3.67403),
                   control1: pt(11.8281, 3.54519),
                   control2: pt(11.6589, 3.58956))
        p.addLine(to: pt(4.85009, 7.42303))
        p.addCurve(to: pt(4.47714, 7.78946),
                   control1: pt(4.69547, 7.50993),
                   control2: pt(4.56676, 7.6364))
        p.addCurve(to: pt(4.34009, 8.29403),
                   control1: pt(4.38752, 7.94252),
                   control2: pt(4.34022, 8.11666))
        p.addLine(to: pt(4.34009, 15.706))
        p.addCurve(to: pt(4.47714, 16.2106),
                   control1: pt(4.34022, 15.8834),
                   control2: pt(4.38752, 16.0575))
        p.addCurve(to: pt(4.85009, 16.577),
                   control1: pt(4.56676, 16.3636),
                   control2: pt(4.69547, 16.4901))
        p.addLine(to: pt(11.5101, 20.327))
        p.addCurve(to: pt(12.0011, 20.4559),
                   control1: pt(11.6599, 20.4115),
                   control2: pt(11.8291, 20.4559))
        p.addCurve(to: pt(12.4921, 20.327),
                   control1: pt(12.1731, 20.4559),
                   control2: pt(12.3422, 20.4115))
        p.addLine(to: pt(19.1521, 16.577))
        p.addCurve(to: pt(19.525, 16.2106),
                   control1: pt(19.3067, 16.4901),
                   control2: pt(19.4354, 16.3636))
        p.addCurve(to: pt(19.6621, 15.706),
                   control1: pt(19.6147, 16.0575),
                   control2: pt(19.662, 15.8834))
        p.addLine(to: pt(19.6621, 8.29403))
        p.addCurve(to: pt(19.525, 7.78946),
                   control1: pt(19.662, 8.11666),
                   control2: pt(19.6147, 7.94252))
        p.addCurve(to: pt(19.1521, 7.42303),
                   control1: pt(19.4354, 7.6364),
                   control2: pt(19.3067, 7.50993))
        p.addLine(to: pt(12.4911, 3.67403))
        p.closeSubpath()

        p.move(to: pt(12.0001, 8.00003))
        p.addCurve(to: pt(14.8285, 9.1716),
                   control1: pt(13.061, 8.00003),
                   control2: pt(14.0784, 8.42145))
        p.addCurve(to: pt(16.0001, 12),
                   control1: pt(15.5787, 9.92174),
                   control2: pt(16.0001, 10.9392))
        p.addCurve(to: pt(14.8285, 14.8285),
                   control1: pt(16.0001, 13.0609),
                   control2: pt(15.5787, 14.0783))
        p.addCurve(to: pt(12.0001, 16),
                   control1: pt(14.0784, 15.5786),
                   control2: pt(13.061, 16))
        p.addCurve(to: pt(9.17166, 14.8285),
                   control1: pt(10.9392, 16),
                   control2: pt(9.92181, 15.5786))
        p.addCurve(to: pt(8.00009, 12),
                   control1: pt(8.42151, 14.0783),
                   control2: pt(8.00009, 13.0609))
        p.addCurve(to: pt(9.17166, 9.1716),
                   control1: pt(8.00009, 10.9392),
                   control2: pt(8.42151, 9.92174))
        p.addCurve(to: pt(12.0001, 8.00003),
                   control1: pt(9.92181, 8.42145),
                   control2: pt(10.9392, 8.00003))
        p.closeSubpath()

        p.move(to: pt(12.0001, 10))
        p.addCurve(to: pt(11.2347, 10.1523),
                   control1: pt(11.7374, 10),
                   control2: pt(11.4774, 10.0518))
        p.addCurve(to: pt(10.5859, 10.5858),
                   control1: pt(10.9921, 10.2528),
                   control2: pt(10.7716, 10.4001))
        p.addCurve(to: pt(10.1523, 11.2347),
                   control1: pt(10.4002, 10.7715),
                   control2: pt(10.2528, 10.992))
        p.addCurve(to: pt(10.0001, 12),
                   control1: pt(10.0518, 11.4773),
                   control2: pt(10.0001, 11.7374))
        p.addCurve(to: pt(10.1523, 12.7654),
                   control1: pt(10.0001, 12.2627),
                   control2: pt(10.0518, 12.5227))
        p.addCurve(to: pt(10.5859, 13.4142),
                   control1: pt(10.2528, 13.008),
                   control2: pt(10.4002, 13.2285))
        p.addCurve(to: pt(11.2347, 13.8478),
                   control1: pt(10.7716, 13.6),
                   control2: pt(10.9921, 13.7473))
        p.addCurve(to: pt(12.0001, 14),
                   control1: pt(11.4774, 13.9483),
                   control2: pt(11.7374, 14))
        p.addCurve(to: pt(13.4143, 13.4142),
                   control1: pt(12.5305, 14),
                   control2: pt(13.0392, 13.7893))
        p.addCurve(to: pt(14.0001, 12),
                   control1: pt(13.7894, 13.0392),
                   control2: pt(14.0001, 12.5305))
        p.addCurve(to: pt(13.4143, 10.5858),
                   control1: pt(14.0001, 11.4696),
                   control2: pt(13.7894, 10.9609))
        p.addCurve(to: pt(12.0001, 10),
                   control1: pt(13.0392, 10.2107),
                   control2: pt(12.5305, 10))
        p.closeSubpath()
        return p
    }
}

/// 「设置」图标槽：统一尺寸、颜色与镂空填充规则（与 `LayoutGlyphView` 同一套口径）。
struct SettingsGlyphView: View {
    var body: some View {
        SettingsNutGlyph()
            .fill(LayoutToggleMetrics.iconColor, style: FillStyle(eoFill: true))
            .frame(width: HeaderEntryMetrics.settingsIconSide,
                   height: HeaderEntryMetrics.settingsIconSide)
    }
}

#Preview("宫格 / 展架") {
    VStack(spacing: 28) {
        HStack(spacing: 28) {
            LayoutGlyphView(isGrid: false)
            LayoutGlyphView(isGrid: true)
        }
        // 与页面里的按钮同构：图标在上、名称在下
        HStack(spacing: 28) {
            VStack(spacing: LayoutToggleMetrics.labelSpacing) {
                LayoutGlyphView(isGrid: false)
                Text("宫格")
                    .font(.system(size: LayoutToggleMetrics.labelFont))
                    .foregroundStyle(LayoutToggleMetrics.labelColor)
            }
            VStack(spacing: LayoutToggleMetrics.labelSpacing) {
                LayoutGlyphView(isGrid: true)
                Text("展架")
                    .font(.system(size: LayoutToggleMetrics.labelFont))
                    .foregroundStyle(LayoutToggleMetrics.labelColor)
            }
        }
    }
    .padding(40)
    .background(Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255))
}
