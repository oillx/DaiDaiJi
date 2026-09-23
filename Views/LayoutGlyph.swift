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
    static let labelFont: CGFloat = 12

    /// 图标框底边 → 标签**行盒**顶的间距。
    ///
    /// 设计稿量到的是「图标墨迹底 → 标签墨迹顶」＝ 27px；
    /// 扣掉宫格墨迹在框内留的 0.77pt、再扣掉苹方 12pt 行盒在墨迹上方的
    /// 约 2.8pt 空白（CoreText 实测 ascent − 墨迹顶），取整得 6。
    /// 实测结果：宫格那档的墨迹间隙 27px、展架 32px，与设计稿一致。
    static let labelSpacing: CGFloat = 6

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
