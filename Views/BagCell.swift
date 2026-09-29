import SwiftUI
import UIKit   // UIImpactFeedbackGenerator：拖动抓起/换位的触感反馈

// ═══════════════════════════════════════════════════════════════
//  全部收藏 · 展架排列（按展示架分组横滑）
//
//  H5 对应：`styles.css` 的 `.collection-group*` / `.shelf-hint*` /
//           `.acrylic-shelf`，`app.js` 的 `renderLibrary()` /
//           `collectionCardHTML()` / `bindShelfScrollHints()`。
//
//  ⚠️ 展架排列与网格排列（`.grid-card`）是**两套完全不同的结构**：
//   · 展架：一行展示架 = 一行**等高、宽度随图**的卡槽 + 一块亚克力层板，
//     卡片里**只有袋子**，一个字都不渲染（H5 里连 DOM 都没有文字）；
//   · 网格：定宽卡片 + 双指缩放，卡片里的文字是 `display:none` 的。
//     两者此前在 iOS 上共用了一个「缩略图 + 名称 + 品牌 + 日期」的卡片，
//     与稿面都对不上，这轮按 H5 拆开重做。
//
//  📌 分组顺序沿用 `renderLibrary()` 的口径：**按 items 里首次出现的先后**，
//     不按件数排序（iOS 侧原来按件数降序，与原型不一致）。
// ═══════════════════════════════════════════════════════════════

/// 展架排列的度量，逐条对应 H5 `styles.css`。
enum ShelfMetrics {
    // ── 分组标题行 ──
    /// `.collection-group-title { display:flex; align-items:center; gap:12px; padding: 0 22px 12px }`
    static let titlePadH: CGFloat = 22
    /// 分组标题的**基线抬升量**（把标题底边提到与右侧「共 N 件 / 箭头」齐平）。
    ///
    /// 右侧那组是「11pt 文字 + 22pt 箭头」，实测墨迹底边比 18pt 宋体标题高 4.3pt ——
    /// 宋体的字面重心偏下，同样的行盒里它的墨迹会坐得更低。
    /// 📌 按需求「标题底部对齐右侧的字体、icon」把这一行整体提上去。
    ///    ⚠️ 实测 `Text.baselineOffset` **会撑大文字的行盒**（标题行整体高 4.3pt、
    ///       右侧「共 N 件/箭头」跟着下移 2pt），而墨迹几乎没动 —— 所以改用
    ///       `.offset(y: -值)`：只改绘制位置，行高与下方袋子的位置一点都不变。
    ///    ⚠️ 想回原位：改成 0。
    static let titleBaselineLift: CGFloat = 4.3

    /// 分组标题 ↔ 袋子的间距：H5 `.collection-group-title` 的 `padding-bottom: 12px`。
    ///
    /// 📌 **H5 是 12，这里按需求收到 6**（标题贴着袋子一点）。标题到袋子的实际留白
    ///    由三项相加决定：`titlePadBottom + rowPadTop − |bagLift|`
    ///      · 改前：12 + 16 − 10 = **18pt**（与 H5 的 12 + 6 + 0 一致）
    ///      · 现在： 6 + 16 − 10 = **12pt**
    ///    ⚠️ 想再紧就继续减这个数（最松的旋钮，不牵动别的）。
    ///       也可以减 `rowPadTop` 让整行上移，但它**不能小于 `|bagLift|`(10)** ——
    ///       袋子上移了 10，顶垫不够的话袋钮会被横向 ScrollView 裁掉。
    static let titlePadBottom: CGFloat = 6
    static let titleGap: CGFloat = 12
    /// `.collection-group-title h2 { font-size: 18px }`（继承全局 `h2`：衬线 + 字距 -.5）
    static let titleFont: CGFloat = 18
    static let titleTracking: CGFloat = -0.5

    // ── 右侧滑动提示 ──
    /// `.shelf-hint__count { color: var(--muted); font-size: 11px; margin-right: 5px }`
    static let hintCountFont: CGFloat = 11
    static let hintCountGap: CGFloat = 5
    /// `.shelf-hint__arrow { width:17px; height:22px; opacity:.55 }`
    static let arrowWidth: CGFloat = 17
    static let arrowHeight: CGFloat = 22
    static let arrowOpacity: Double = 0.55
    /// 滑到某一端时对应箭头淡到 `.18`（H5 `.is-at-start / .is-at-end`）
    static let arrowDimOpacity: Double = 0.18
    /// `.shelf-hint__arrow svg { width/height: 15px; stroke-width: 1.7 }`
    static let arrowGlyph: CGFloat = 15
    static let arrowStroke: CGFloat = 1.7

    // ── 横向卡片行 ──
    /// `.collection-group-scroll { display:flex; align-items:start; gap:10px;
    ///  padding:16px 0 8px; scroll-padding-inline:22px }`
    ///（以交付包《袋袋集原型.html》为准，1:1 照抄，别凭直觉「修正」）
    ///
    /// ⚠️ 顶部 16 不是笔误：袋图带 `translateY(-10px)`，若写 6，图片顶会超出
    ///    容器 4px，而 overflow-x:auto 会连带裁掉纵向溢出 —— 顶部被裁。
    ///    H5 特意补到 16（= 6 + 10）给上移完整让位。
    static let rowGap: CGFloat = 10
    static let rowPadTop: CGFloat = 16
    static let rowPadBottom: CGFloat = 8
    /// 首尾留白 22：H5 用 `::before/::after` 各 12px + gap 10 撑出来（12+10=22），
    /// iOS 用 `contentMargins` 直接给 22，效果一致
    static let rowInset: CGFloat = 22
    /// 行的总高 = 上 16 + 袋盒 132 + 下 8 = 156（袋盒高度见 `bagHeight`）
    static var rowHeight: CGFloat { rowPadTop + bagHeight + rowPadBottom }

    // ── 组内排序交互（长按 500ms 进入排序态 → 拖动换位 → 双击/点空白退出）──
    /// 长按判定（H5 `SHELF_HOLD_MS = 500`）
    static let dragHold: Double = 0.5
    /// 长按的位移容差（H5 `SHELF_MOVE_TOL = 8`：超过算横滑，取消长按）
    static let dragTolerance: CGFloat = 8
    /// 被拖卡片跟手时的内联变换（H5：`translateX(dx) scale(1.06) translateY(-4px)`）
    static let dragScale: CGFloat = 1.06
    static let dragLiftY: CGFloat = -4
    /// 排序态全体卡片的抖动（H5 `@keyframes shelfWiggle`：±1.2°、0.32s 往复）。
    ///
    /// 📌 幅度按需求从 H5 的 **1.2° 提到 2.2°**：卡宽 96pt、旋转锚点在 (0.5, 0.85)，
    ///    1.2° 时卡顶只摆动约 2.6pt（3x 屏 8px），实际几乎看不出「在抖」。
    ///    2.2° 时约 4.7pt，小卡的抖动才成立。
    ///    ⚠️ H5 注释里提醒过「再大有快散架的廉价感」—— 继续往上加要谨慎，3° 以上就会飘。
    ///    ⚠️ 周期仍照 H5 的 0.32s（`wiggleDuration`），只改了幅度。
    static let wiggleAngle: CGFloat = 2.2
    static let wiggleDuration: Double = 0.32
    /// 拖到行两端 40pt 内自动续滚（H5 8px/帧 ≈ 480px/s，iOS 折算为约 0.2s 滚过一卡）
    static let autoScrollEdge: CGFloat = 40

    // ── 卡槽与袋子 ──
    /// 卡槽的**标称**宽度（稿面 96）。
    ///
    /// ⚠️ 它不是真实卡宽 —— 真实卡宽是「袋高 × 图片比例」（见 `cardWidth(forRatio:)`）。
    ///    这里只喂给两处与「一格」有关的**近似**计算：
    ///      · `slotPitch`（拖动换位的步长，`ShelfGroup`）；
    ///      · `cardsPerPage`（箭头一下翻几张，`ShelfGroup`）。
    ///    两处都是「大概一格多宽」的意图，卡宽不等时按均值算即可。
    static let slotWidth: CGFloat = 96

    /// 「高度固定、宽度等比」下的卡宽 = 袋高 × 图片宽高比，夹在上下限之间。
    ///
    /// H5 `.collection-group-card .bag-photo { height:148px; width:auto; max-width:100% }`
    /// —— 卡本身**没有定宽**，宽度就是图片实宽，所以同排袋子一律等高。
    /// iOS 原先用「定宽 96 槽 + `.fit`」，偏宽的图（比例 > 96/132 = 0.727）
    /// 会先顶到槽宽、高度反而矮一截（同排就参差了）。
    static func cardWidth(forRatio ratio: CGFloat) -> CGFloat {
        min(maxCardWidth, max(minCardWidth, bagHeight * ratio))
    }

    /// 卡宽下限 44：够到最小可点尺寸。比它更窄的袋子（比例 < 0.33）图片按自身比例
    /// 居中缩小，不做任何拉伸 —— 高度仍是 `bagHeight`。
    static let minCardWidth: CGFloat = 44

    /// 卡宽上限 192（= 132 × 1.4545）：再宽的图若继续等比，一张卡就占掉半屏。
    /// 到顶后图片改为按宽度反压，那张袋子会比同排略矮 —— 极端比例下的有意取舍。
    static let maxCardWidth: CGFloat = 192

    /// `.collection-group-card .bag-photo { height:148px; width:auto; max-width:100%;
    ///  object-fit:contain; transform:translateY(-10px) }`
    ///
    /// ⚠️ H5 里**真图不套** `.paper-bag` 壳 —— 那个 92×132、再 `scale(.9)` 的壳只用于
    ///    「没有图片时」的 CSS 占位纸袋；真图只有一个 `translateY(-10px)`。
    ///    上移 10 与行高顶垫 16 是配套的（见 `rowPadTop`），要动就一起动。
    ///
    /// 📌 **148 是 H5 的原值，这里按需求收到 132（−16pt / −11%）** ——
    ///    手机上它比同屏别的袋子明显大一圈（首页挂袋 ≈86、网格 ≈78），观感「偏大」。
    ///    行高由它派生（`rowHeight` = 16 + 132 + 8 = **156**，原 172），层板挂在行底、
    ///    跟着上移 16，袋子露在层板以上的部分从 95 收到 79（−17%）。
    ///    ⚠️ 想回稿面值：改回 148 即可，其余全部自动跟着走（没有任何地方写死 148/172）。
    static let bagHeight: CGFloat = 132
    /// `translateY(-10px)`：视觉上抬、不占布局 —— 袋底略高于架面上沿
    static let bagLift: CGFloat = -10
    /// 阴影对齐 H5 `drop-shadow(0 4px 10px rgba(0,0,0,.18))`（blur 10 → radius 5）
    static let bagShadowOpacity: Double = 0.18
    static let bagShadowRadius: CGFloat = 5
    static let bagShadowY: CGFloat = 4

    // ── 分组间距 ──
    /// `.collection-group { margin-bottom: 30px }` / `--last { margin-bottom: 4px }`
    static let groupGap: CGFloat = 30
    static let groupGapLast: CGFloat = 4

    // ── 亚克力层板 ──
    /// `.acrylic-shelf { left:14; right:14; bottom:14; height:57; border-radius:9 }`
    static let shelfInset: CGFloat = 14
    static let shelfHeight: CGFloat = 57
    static let shelfRadius: CGFloat = 9
    static let shelfBorder = Color.white.opacity(0.40)
    static let shelfTopGlow = Color.white.opacity(0.16)
    static let shelfTopRim = Color.white.opacity(0.55)
    static let shelfShadow = Color(red: 43 / 255, green: 35 / 255, blue: 29 / 255).opacity(0.13)
    /// `.acrylic-shelf i { width/height:12px }` + `i:first-child { left:11px }`
    static let screwSize: CGFloat = 12
    static let screwInset: CGFloat = 11

    /// 层板配色。H5 先按分组序号轮换（`nth-of-type(3n+1/2/3)`），
    /// 再被品牌规则覆盖（瑞幸 / Peet's）。
    static func shelfFill(index: Int, shelf: String) -> Color {
        switch shelf {
        case "瑞幸咖啡":
            return Color(red: 253 / 255, green: 83 / 255, blue: 192 / 255).opacity(0.72)
        case "Peet's Coffee":
            return Color(red: 163 / 255, green: 118 / 255, blue: 85 / 255).opacity(0.72)
        default:
            break
        }
        // index 是 0 基，CSS 的 nth-of-type 是 1 基：3n+1 → i%3==0，3n+2 → i%3==1
        switch index % 3 {
        case 0:  return Color(red: 240 / 255, green: 154 / 255, blue: 42 / 255).opacity(0.72)   // 暖橙
        case 1:  return Color(red: 34 / 255, green: 158 / 255, blue: 232 / 255).opacity(0.66)   // 亮蓝
        default: return Color(red: 117 / 255, green: 168 / 255, blue: 141 / 255).opacity(0.72)  // 灰绿
        }
    }
}

// MARK: - 一个展示架分组

/// 一个展示架：标题 +「共 N 件」+ 左右箭头 + 横向卡片行 + 亚克力层板。
struct ShelfGroup: View {
    let shelf: String
    let bags: [BagItem]
    /// 该组在列表里的序号（0 基）—— 决定层板配色轮换
    let index: Int
    /// 容器宽度（由宿主的 `WidthProbe` 给），用来算「一屏能放几张」
    let viewport: CGFloat
    var isLast: Bool = false
    /// 是否允许组内长按拖动排序。
    /// ⚠️ 搜索中必须传 false：过滤后的槽位序 ≠ 真实位置，写回 `manualOrder` 会错。
    var canReorder: Bool = true
    /// 本组是否处于「排序态」（长按 500ms 进入；双击任意处 / 点空白退出）。
    /// 状态由宿主持有 —— 同一时刻最多一个组在排序，提示条也挂在列表层级。
    var isSorting: Bool = false
    /// 进入（true）/ 退出（false）排序态时回调宿主
    var onSortingChange: (Bool) -> Void = { _ in }
    /// 拖动结束、组内顺序定稿后的落库回调（宿主重编号写回 `manualOrder`）。
    var onReorder: ([BagItem]) -> Void = { _ in }
    var onSelect: (BagItem) -> Void = { _ in }

    // ── 排序态状态 ──

    /// 拖动期间的工作顺序：**本地先动、松手才落库**（`onReorder`）。
    /// 平时与 `bags` 同步 —— 模型一变（新上传 / 删除）立即跟上。
    @State private var working: [BagItem] = []
    /// 正被拖着的卡片（nil = 没在拖）
    @State private var dragID: UUID?
    /// 拖动卡片的视觉偏移 = 手指平移量 − 已让位的槽距。
    /// 布局换位已经替卡片走掉了一段，减掉它卡片才始终钉在手指下。
    @State private var dragX: CGFloat = 0
    /// 起拖以来已让位的槽位数
    @State private var slotShift = 0
    /// 抖动往复开关：排序态下与 `.repeatForever` 配合让全体卡片 ±1.2° 摆动
    @State private var wiggleOn = false
    /// 抖动的基准角（进入排序态先无动画落到 −1.2°，再往复到 +1.2°，才是对称摆动）
    @State private var wiggleBase: CGFloat = 0
    /// 边缘自动续滚的后台循环（拖到行两端触发，对应 H5 的 rAF 8px/帧）
    @State private var autoScrollTask: Task<Void, Never>?
    /// 手指最后一次的平移量 —— 自动续滚滚动行之后，参照系变了，
    /// 要用它重算让位（H5 在 rAF tick 里做的是同一件事）
    @State private var lastTranslation: CGFloat = 0

    /// 卡槽间距：卡宽 + 组内间隙。拖动换位的「一格」就是它。
    private var slotPitch: CGFloat { ShelfMetrics.slotWidth + ShelfMetrics.rowGap }
    private var isDragging: Bool { dragID != nil }

    /// 当前贴左的那张卡（`.scrollPosition` 反写回来）。
    /// 用它算「还能不能继续滑」——对应 H5 的 `.is-at-start / .is-at-end`。
    @State private var leadingID: UUID?

    /// 一屏放得下几张卡。H5 的箭头点一下滑 `clientWidth` 这么远。
    private var cardsPerPage: Int {
        let usable = max(1, viewport - ShelfMetrics.rowInset * 2)
        return max(1, Int((usable + ShelfMetrics.rowGap) / (ShelfMetrics.slotWidth + ShelfMetrics.rowGap)))
    }

    private var leadingIndex: Int {
        guard let leadingID, let i = working.firstIndex(where: { $0.id == leadingID }) else { return 0 }
        return i
    }

    /// 已经贴到最左 / 最右（对应 H5 的两个淡出状态）
    private var isAtStart: Bool { leadingIndex <= 0 }
    private var isAtEnd: Bool { leadingIndex + cardsPerPage >= working.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // ⚠️ 故意用 HStack 而不是 LazyHStack：懒加载会在换位瞬间把
                    //    未实例化的槽位当场建出来，让位动画掉帧、卡片闪现。
                    //    一组也就几十件，常驻布局的成本可以忽略。
                    HStack(spacing: ShelfMetrics.rowGap) {
                        ForEach(Array(working.enumerated()), id: \.element.id) { index, bag in
                            slotCard(bag, at: index)
                                .id(bag.id)
                        }
                    }
                    // 卡片逐张吸附到左缘（H5 `scroll-snap-align: start`）
                    .scrollTargetLayout()
                    // H5 `.collection-group-scroll { align-items:start }`：袋盒贴行顶垫下，
                    // 不垂直居中（居中会把袋子往层板里推）
                    .padding(.top, ShelfMetrics.rowPadTop)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                // 排序态锁滚动（H5：is-sorting 下 scroll-snap-type:none、overflow-x:hidden）——
                // 手指的横向移动属于「换位」，行的滚动整段停用；箭头也已淡出
                .scrollDisabled(isSorting)
                // H5 的 `scroll-padding-inline: 22px`：吸附位置与首尾留白都锚在 22
                .contentMargins(.horizontal, ShelfMetrics.rowInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                // 贴左的那张卡反写进 `leadingID`，供箭头判断「到头了没」
                .scrollPosition(id: $leadingID, anchor: .leading)
                .frame(height: ShelfMetrics.rowHeight)
                .padding(.top, 0)
                // 箭头点一下 = 整屏滑动（H5 `bindShelfScrollHints`）
                .onChange(of: pendingScroll) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                    pendingScroll = nil
                }
            }
            // ── 亚克力层板：压在卡片脚上，两端各一颗螺钉 ──
            .overlay(alignment: .bottom) {
                AcrylicShelf(fill: ShelfMetrics.shelfFill(index: index, shelf: shelf))
                    .padding(.horizontal, ShelfMetrics.shelfInset)
                    .padding(.bottom, ShelfMetrics.shelfInset)
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, isLast ? ShelfMetrics.groupGapLast : ShelfMetrics.groupGap)
        // H5：点击空白处退出排序态（卡片上的点击会被吞掉，走不到这里；
        // 双击任意处退出挂在列表层级，见 `ShelfView`）
        .onTapGesture {
            if isSorting { onSortingChange(false) }
        }
        .onAppear { working = bags }
        .onChange(of: bags) { _, newValue in
            // 拖动中模型不该变（搜索中禁拖、上传走的是别的页）；万一变了，松手后再对齐
            guard !isDragging else { return }
            working = newValue
        }
        .onChange(of: isSorting) { _, on in
            if on {
                // 先无动画落到 −1.2°，再开始往复 —— 才是 H5 那种对称摆动
                wiggleBase = -ShelfMetrics.wiggleAngle
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    wiggleOn = true
                }
            } else {
                wiggleOn = false
                wiggleBase = 0
            }
        }
    }

    // MARK: - 组内排序（长按 500ms 进入排序态 → 拖动换位 → 双击/点空白退出）

    /// 一张卡槽卡：按状态挂手势 ——
    /// · 排序态中：点住即拖（H5 pointerdown 直接 beginDrag，不再等长按）
    /// · 非排序态：长按 500ms 进入排序态并顺势开始拖
    /// （`.gesture` 不接受 optional，用 @ViewBuilder 分支）
    @ViewBuilder
    private func slotCard(_ bag: BagItem, at displayIndex: Int) -> some View {
        if canReorder {
            if isSorting {
                // 排序态：点住即拖（不再等长按）
                cardVisual(bag, at: displayIndex).gesture(dragGesture(for: bag))
            } else {
                // 常态：长按 500ms 进入排序态并顺势开拖
                cardVisual(bag, at: displayIndex).gesture(holdThenDragGesture(for: bag))
            }
        } else {
            cardVisual(bag, at: displayIndex)
        }
    }

    /// 卡片视觉：
    /// · 排序态：全体 ±1.2° 抖动（0.32s 往复；H5 用负延时做相位错开，SwiftUI 的
    ///   delay 只能正向，这里是「错峰启动、之后同相」的近似）
    /// · 被拖的卡：脱离抖动（H5 `animation:none`），跟手平移 + scale(1.06) +
    ///   translateY(-4px)，投影加深、浮到最上层
    private func cardVisual(_ bag: BagItem, at displayIndex: Int) -> some View {
        let dragging = dragID == bag.id
        let wiggle = isSorting && !dragging
        let rotation: CGFloat = wiggle
            ? (wiggleOn ? ShelfMetrics.wiggleAngle : wiggleBase)
            : 0
        return ShelfSlotCard(bag: bag) {
            // 排序态下点卡片 = 吞掉（H5 在捕获阶段 stopPropagation，防误开详情）
            guard !isSorting, !isDragging else { return }
            onSelect(bag)
        }
        // H5 `.is-lifted`：z-index:5 + drop-shadow(0 12px 18px rgba(0,0,0,.3))
        .shadow(color: .black.opacity(dragging ? 0.30 : 0),
                radius: dragging ? 9 : 0, y: dragging ? 12 : 0)
        .scaleEffect(dragging ? ShelfMetrics.dragScale : 1)
        .offset(x: dragging ? dragX : 0,
                y: dragging ? ShelfMetrics.dragLiftY : 0)
        .zIndex(dragging ? 5 : 0)
        .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: 0.5, y: 0.85))
        // 抖动 keyed 在 wiggleOn 上；被拖的卡 rotation 已是 0，不参与
        .animation(wiggle
                   ? .easeInOut(duration: ShelfMetrics.wiggleDuration / 2)
                       .repeatForever(autoreverses: true)
                       .delay(Double(3 - displayIndex % 3) * 0.11)
                   : .easeOut(duration: 0.12),
                   value: wiggleOn)
        // H5 `.is-lifted { transition: transform .16s ease }`：抓起 / 落下的跟手过渡
        .animation(.easeInOut(duration: 0.16), value: dragging)
    }

    /// 非排序态入口：长按 500ms（位移容差 8pt，超过算横滑、取消长按）
    /// → 进入排序态并顺势开始拖
    private func holdThenDragGesture(for bag: BagItem) -> some Gesture {
        LongPressGesture(minimumDuration: ShelfMetrics.dragHold,
                         maximumDistance: ShelfMetrics.dragTolerance)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if dragID == nil {
                    // 抓起 = 进入排序态（H5 enterSorting：组与容器都打 is-sorting）+ 震动
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSortingChange(true)
                    dragID = bag.id
                    slotShift = 0
                    dragX = 0
                }
                handleDragChange(translation: drag.translation.width)
            }
            .onEnded { _ in finishDrag() }
    }

    /// 排序态入口：点住即拖（H5：已处于排序态时 pointerdown 直接 beginDrag）
    private func dragGesture(for bag: BagItem) -> some Gesture {
        DragGesture(minimumDistance: ShelfMetrics.dragTolerance)
            .onChanged { value in
                beginDragIfNeeded(bag)
                handleDragChange(translation: value.translation.width)
            }
            .onEnded { _ in finishDrag() }
    }

    /// 开始拖某张卡（幂等）：记录被拖对象、清零换位基准
    private func beginDragIfNeeded(_ bag: BagItem) {
        guard dragID == nil else { return }
        dragID = bag.id
        slotShift = 0
        dragX = 0
    }

    /// 拖动中的公共逻辑：换位判定（定宽槽、跨半格换一位）+ 让位 + 边缘续滚
    private func handleDragChange(translation t: CGFloat) {
        guard let dragID, let current = working.firstIndex(where: { $0.id == dragID }) else { return }
        lastTranslation = t

        var shift = slotShift
        var offset = t - CGFloat(shift) * slotPitch

        // 跨过一格就换位（快甩时一次 tick 可能跨多格，所以用循环）
        while Int((offset / slotPitch).rounded()) != 0 {
            let step = Int((offset / slotPitch).rounded())
            let target = current + step
            guard working.indices.contains(target) else { break }
            UISelectionFeedbackGenerator().selectionChanged()
            // H5 `.is-shifting { transition: transform .2s cubic-bezier(.2,.75,.22,1) }`
            withAnimation(.timingCurve(0.2, 0.75, 0.22, 1, duration: 0.2)) {
                let moving = working.remove(at: current)
                working.insert(moving, at: target)
            }
            shift += step
            offset = t - CGFloat(shift) * slotPitch
        }
        slotShift = shift

        // 偏移不参与动画：布局在动，卡片必须钉在手指下
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { dragX = offset }

        // ── 边缘自动续滚（H5：拖到容器两端 40px 内连续滚动）──
        // iOS 简化：以「目标槽位顶到可视范围边缘」为触发，每 0.2s 滚过一张卡
        //（≈ H5 的 480px/s）。复用箭头维护的 leadingID，滚动后让位随之一并重算。
        let lastVisible = leadingIndex + cardsPerPage - 1
        if current >= lastVisible {
            startAutoScroll(+1)
        } else if current <= leadingIndex {
            startAutoScroll(-1)
        } else {
            stopAutoScroll()
        }
    }

    /// 松手：长按后原地松手 = 只进排序态不换位（H5 注释原话：顺序绝不能被改）；
    /// 真拖过才落库。**两种情况都不退出排序态** —— 排序是连续动作，退出只认
    /// 双击任意处 / 点空白处（见 `ShelfView` 的手势）。
    private func finishDrag() {
        stopAutoScroll()
        guard dragID != nil else { return }
        let moved = working.map(\.id) != bags.map(\.id)
        dragID = nil
        slotShift = 0
        dragX = 0
        if moved { onReorder(working) }
    }

    /// 拖到行边缘时的自动续滚：每 0.2s 让贴左卡前进 / 后退一张（≈ H5 的 480px/s）
    private func startAutoScroll(_ direction: Int) {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task {
            while !Task.isCancelled, isSorting, dragID != nil {
                let cards = working
                let next = min(max(leadingIndex + direction, 0), cards.count - 1)
                guard next != leadingIndex else { break }
                withAnimation(.linear(duration: 0.18)) { leadingID = cards[next].id }
                // 滚动后参照系变了：用最后一次手指位移重算让位（H5 同款处理）
                handleDragChange(translation: lastTranslation)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    /// 点箭头要滚到的目标（用状态驱动 `.onChange`，因为 `proxy` 只在闭包里可见）
    @State private var pendingScroll: UUID?

    private var titleRow: some View {
        HStack(spacing: ShelfMetrics.titleGap) {
            Text(shelf)
                // H5 `.collection-group-title h2 { font-size: 18px }` —— 继承全局 `h2` 的衬线
                // （思源宋体 Bold）。⚠️ 不能写 `design: .serif`，中文会回落成苹方黑体。
                .font(AppFont.songti(ShelfMetrics.titleFont))
                .tracking(ShelfMetrics.titleTracking)
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255))
                // 底边与右侧「共 N 件 / 箭头」齐平（见 `titleBaselineLift`）。
                // ⚠️ 必须是 `.offset` 而不是 `.baselineOffset`：后者会撑大行盒。
                .offset(y: -ShelfMetrics.titleBaselineLift)
            Spacer(minLength: ShelfMetrics.titleGap)

            HStack(spacing: 0) {
                // H5 原文是 `共${n}件` —— 数字两侧**没有空格**，别加
                Text("共\(bags.count)件")
                    .font(.system(size: ShelfMetrics.hintCountFont))
                    .foregroundStyle(Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255))
                    .padding(.trailing, ShelfMetrics.hintCountGap)
                    .fixedSize()

                // ⚠️ 两个箭头**恒定占位**（不按能否滑动显隐）——
                //    H5 注释里写明：显隐会让各行右侧宽度在 32 / 80px 之间跳，
                //    右边缘参差 4px。到头只是淡出，不塌陷。
                //    排序态下箭头失去意义（行不可滑），同样淡到 .18 并禁点。
                arrowButton(direction: -1, dimmed: isAtStart || isSorting)
                arrowButton(direction: 1, dimmed: isAtEnd || isSorting)
            }
        }
        .padding(.horizontal, ShelfMetrics.titlePadH)
        .padding(.bottom, ShelfMetrics.titlePadBottom)
    }

    private func arrowButton(direction: Int, dimmed: Bool) -> some View {
        Button {
            let target = min(max(leadingIndex + direction * cardsPerPage, 0), bags.count - 1)
            pendingScroll = bags[target].id
        } label: {
            HintChevron(pointsLeft: direction < 0)
                .stroke(Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255),
                        style: StrokeStyle(lineWidth: ShelfMetrics.arrowStroke,
                                           lineCap: .butt, lineJoin: .miter))
                .frame(width: ShelfMetrics.arrowGlyph, height: ShelfMetrics.arrowGlyph)
                .frame(width: ShelfMetrics.arrowWidth, height: ShelfMetrics.arrowHeight)
                .opacity(dimmed ? ShelfMetrics.arrowDimOpacity : ShelfMetrics.arrowOpacity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(direction < 0 ? "向左滑动" : "向右滑动")
    }
}

// MARK: - 卡槽

/// 展架卡槽：**高度一律 132、宽度按图片比例** —— 同排所有袋子等高。
///
/// ⚠️ 这里**只渲染袋子**。H5 的 `collectionCardHTML()` 产物就是一个
///    `<button>` 套一张 `<img>`，没有任何文字；名字与品牌靠 `aria-label` 传达。
struct ShelfSlotCard: View {
    let bag: BagItem
    var action: () -> Void = {}

    /// 卡宽 = 袋高 × 图片宽高比（`ShelfMetrics.cardWidth(forRatio:)`）。
    ///
    /// 先按标称槽宽 96 占位，读到比例后一次定位；比例读不出来（文件缺失）就一直是 96。
    /// 读取只解析文件头、不解码像素，见 `BagImageResolver.aspectRatio(of:)`。
    @State private var cardWidth: CGFloat = ShelfMetrics.slotWidth

    var body: some View {
        ThumbnailImage(fileName: bag.imageFileName, size: 400,
                       contentMode: .fit, interpolation: .high)
            // 盒子 =「袋高 × 图片比例」，图片正好填满它：高一律 132，宽各随其图。
            .frame(width: cardWidth, height: ShelfMetrics.bagHeight)
            .shadow(color: .black.opacity(ShelfMetrics.bagShadowOpacity),
                    radius: ShelfMetrics.bagShadowRadius,
                    x: 0, y: ShelfMetrics.bagShadowY)
            // `translateY(-10px)`：视觉上抬、不占布局（与行顶垫 16 配套，见 rowPadTop）
            .offset(y: ShelfMetrics.bagLift)
            .contentShape(Rectangle())
            // ⚠️ 故意不用 Button：Button 自带的长按会跟宿主挂上来的
            //    「长按拖动换位」抢仲裁（按住 0.45s 时 Button 可能直接弹起、
            //    拖动手势拿不到后续事件）。tap 手势 + `.isButton` 特质，
            //    轻点照旧、拖动归宿主（`ShelfGroup.reorderGesture`）。
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel("\(bag.displayName)，\(bag.displayShelf)，\(DateFormat.monthDayDot(bag.createdAt))")
            .accessibilityAddTraits(.isButton)
            // 读到真实比例后再定宽（不做动画：首帧即终值，避免一排卡片依次滑动）
            .task(id: bag.imageFileName) {
                guard let ratio = BagImageResolver.aspectRatio(of: bag.imageFileName) else { return }
                cardWidth = ShelfMetrics.cardWidth(forRatio: ratio)
            }
    }
}

// MARK: - 亚克力层板

/// 磨砂亚克力层板 + 两端金属螺钉（H5 `.acrylic-shelf`）。
///
/// H5 是「磨砂均光面 + 顶部一道柔和高光 + 12pt 车削螺钉（conic 拉丝金属环）」。
struct AcrylicShelf: View {
    let fill: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ShelfMetrics.shelfRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(fill)
            // linear-gradient(180deg, rgba(255,255,255,.16), rgba(255,255,255,0) 55%)
            .overlay {
                shape.fill(
                    LinearGradient(stops: [
                        .init(color: ShelfMetrics.shelfTopGlow, location: 0),
                        .init(color: .clear, location: 0.55)
                    ], startPoint: .top, endPoint: .bottom)
                )
            }
            // inset 0 1px rgba(255,255,255,.55)：上沿那道 1px 内高光
            // （SwiftUI 没有 inset shadow，用一条贴顶的 1px 渐变带顶替，随圆角一起裁）
            .overlay {
                shape.fill(
                    LinearGradient(stops: [
                        .init(color: ShelfMetrics.shelfTopRim, location: 0),
                        .init(color: .clear, location: 0.02)
                    ], startPoint: .top, endPoint: .bottom)
                )
            }
            // border: 1px solid rgba(255,255,255,.40)
            .overlay { shape.strokeBorder(ShelfMetrics.shelfBorder, lineWidth: 1) }
            // 0 8px 16px rgba(43,35,29,.13)
            .shadow(color: ShelfMetrics.shelfShadow, radius: 8, x: 0, y: 8)
            .frame(height: ShelfMetrics.shelfHeight)
            .overlay(alignment: .leading) { screw.padding(.leading, ShelfMetrics.screwInset) }
            .overlay(alignment: .trailing) { screw.padding(.trailing, ShelfMetrics.screwInset) }
    }

    /// 车削金属螺钉：conic 拉丝环 + 两处径向高光 + 内孔描边 + 双层落影。
    private var screw: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255),
                        Color(red: 184 / 255, green: 177 / 255, blue: 166 / 255),
                        Color(red: 141 / 255, green: 133 / 255, blue: 122 / 255),
                        Color(red: 207 / 255, green: 200 / 255, blue: 189 / 255),
                        Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255)
                    ]),
                    center: .center,
                    angle: .degrees(210)      // conic-gradient(from 210deg)
                )
            )
            .overlay {
                ZStack {
                    // 两处高光的色标如实照抄（0 12% → 34% / 0 8% → 30%）
                    Circle().fill(radial(.white.opacity(0.95), at: UnitPoint(x: 0.34, y: 0.26),
                                         solid: 0.12, fade: 0.34))
                    Circle().fill(radial(.white.opacity(0.90), at: .center,
                                         solid: 0.08, fade: 0.30))
                }
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.60), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.40), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 2)
            .frame(width: ShelfMetrics.screwSize, height: ShelfMetrics.screwSize)
    }

    /// CSS `radial-gradient(circle at …, color 0 X%, transparent Y%)` 的等价物：
    /// X% 之前保持满色、Y% 处收干。`endRadius` 取 farthest-corner
    /// （12×12 的圆 → √(6²+6²) = 8.49，即 `12 × 0.7075`）。
    private func radial(_ color: Color,
                        at center: UnitPoint,
                        solid: CGFloat,
                        fade: CGFloat) -> RadialGradient {
        RadialGradient(stops: [
            .init(color: color, location: 0),
            .init(color: color, location: solid),
            .init(color: .clear, location: fade)
        ], center: center, startRadius: 0, endRadius: ShelfMetrics.screwSize * 0.7075)
    }
}

// MARK: - 滑动提示用的箭头

/// H5 的箭头 svg：`<path d="m15 5-7 7 7 7"/>`（24×24 框、描边 1.7、不缩放）。
/// 向右就是同一路径水平镜像 —— 原型没有另给一条 path。
struct HintChevron: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let k = side / 24
        let ox = rect.midX - side / 2
        let oy = rect.midY - side / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (pointsLeft ? x : 24 - x) * k, y: oy + y * k)
        }
        var path = Path()
        path.move(to: pt(15, 5))
        path.addLine(to: pt(8, 12))
        path.addLine(to: pt(15, 19))
        return path
    }
}

// MARK: - 预览

#Preview("展架一行") {
    let bags = PreviewData.samples().prefix(6)
    return ZStack {
        Color(red: 0.949, green: 0.953, blue: 0.969).ignoresSafeArea()
        ShelfGroup(shelf: "霸王茶姬", bags: Array(bags), index: 0, viewport: 393)
    }
}
