import SwiftUI

// ═══════════════════════════════════════════════════════════════
//  挂袋吧台：「最近收集」
//
//  H5 对应文件：`袋袋集原型/app.js` 的 `renderRack()` / `rackTick()` /
//               `rackBaseAngle()`，`styles.css` 的 `.rack-*`
//
//  ⚠️ 结构来自用户自己给的代码，类名与物理效果都不能动：
//   · 结构：`.rack-item > .rack-hang > (.rack-clip + .rack-frame > .rack-photo) + .rack-meta`
//   · 绳索：`.rack-rope > .rope-core / .rope-twist`，SVG 二次贝塞尔
//   · 轻点：先荡一下，再把这张卡片送到上方主卡位（主从联动），**不弹详情**
// ═══════════════════════════════════════════════════════════════

enum RackMetrics {
    /// 单卡原始宽
    static let layoutWidth: CGFloat = 110
    /// 相邻重叠
    static let layoutOverlap: CGFloat = 20

    /// 卡片放大的上限倍数（只在真正的宽屏上生效）。
    ///
    /// 挂袋排的宽度算式是 `scale = min(cap, avail / naturalW)`，
    /// `avail / naturalW` 这一项保证**永不溢出**，所以 `cap` 只决定
    /// 「还有余量时最多放大到多少」——
    /// 6 张卡在 620pt 的列里算出 1.06（几乎不变），
    /// 只有 2~3 张时才会真正吃到这个上限，此时放大会让版面不至于空荡。
    ///
    /// 手机与 iPad 分屏（宽度 ≤ 453）在调用处直接取 1，不缩放。
    static let maxScale: CGFloat = 1.25
    /// `.rack-bags` 左右各 12px 内边距
    static let horizontalPadding: CGFloat = 12
    /// 卡片区顶部留白（给绳索与孔环）
    static let topInset: CGFloat = 34

    /// 拖动角度映射：dx × 0.4，限位 ±75°
    static let dragFactor: CGFloat = 0.4
    static let dragLimitDeg: CGFloat = 75
    /// 松手回弹：收进 ±26°
    static let releaseLimitDeg: CGFloat = 26
    /// 轻点判定：位移 < 6px 且 按住 < 400ms
    static let tapMoveThreshold: CGFloat = 6
    static let tapHoldLimit: Double = 0.4

    // MARK: 摇一摇（H5 `handleDeviceMotion()`）

    /// 一次晃动给卡片的角度冲量（度）。
    ///
    /// H5 那边累加的是**速度**：`velocity += shakeForce * 0.3 * dir`，
    /// 其中 `shakeForce = acc.x * 0.9`，`dir = i % 2 == 0 ? 1 : -1`；
    /// 然后由它自己的弹簧积分收敛。SwiftUI 侧没有显式的 velocity 量，
    /// **摆角就是唯一状态**，所以这里把冲量直接折算成「目标摆角」，
    /// 再由 `RackStage` 在停手后统一回正。
    ///
    /// 增益 30 是这么标定的：
    ///   · H5 的 velocity→角度换算是 7 → 6°（见 `RackItemView.kick()`），约 0.857°/单位；
    ///     连乘它的各档系数（0.9 × 0.3 × 0.857）只有约 0.23°/（m/s²）。
    ///   · 但这里输入的是 **g**（`CMDeviceMotion.userAcceleration` 的单位），
    ///     换算成 m/s² 是 ×9.81 ≈ 2.3 —— 一次轻晃（约 0.3 g）只摆 0.7°，几乎看不见。
    ///   · H5 靠 60ms 一次的 velocity 累加把幅度堆起来；SwiftUI 侧每次直接设目标角度、
    ///     **不累加**，所以把增益提到 30：0.3 g 的轻晃 → 9°，用力晃被上限收到 16°。
    ///
    /// ⚠️ 上限 16° 取在「松手回收」的 ±26° 之内 ——
    ///    摇一摇比手动拖还猛就显得假。
    ///
    /// 负号的含义：手机向右加速时，挂着的袋子因惯性向左摆（与 H5 一致）。
    static func swayDegrees(accelX: Double, index: Int) -> Double {
        let dir: Double = index % 2 == 0 ? 1 : -1
        let raw = -accelX * 30 * dir
        return min(16, max(-16, raw))
    }

    /// 相邻卡片反向微倾，制造随手夹上去的错落感
    static func baseAngle(_ i: Int) -> Double { i % 2 == 0 ? 2.5 : -2.5 }

    /// 卡片的纵向错落偏移：H5 是 `--dy: ${(i % 3) * 8}px`。
    /// 让一排挂袋不在同一条水平线上，像随手挂上去的。
    static func dropOffset(_ i: Int) -> CGFloat { CGFloat(i % 3) * 8 }

    /// 绳索贝塞尔在横向比例 `t`（0~1）处的 y。
    ///
    /// H5 用 `alignClipsToRope()` **渲染后测量真实坐标**把孔环落到绳子上；
    /// iOS 的 `Path` 是矢量坐标、本身精确，所以这里直接按同一条贝塞尔
    /// 解析求值，不必测量（结论一致，且没有测量误差）。
    ///
    /// 绳索 SVG 的 viewBox 是 400×40，`.rack-rope { height: 28px }`，
    /// 所以 y 要乘 `28/40` 换算到屏幕像素。
    static func ropeY(atFraction t: CGFloat) -> CGFloat {
        // 控制点：M3,6 → Q 200,52 → 397,6（viewBox 400×40）
        let p0y: CGFloat = 6
        let cy: CGFloat = 52
        let p1y: CGFloat = 6
        let u = 1 - t
        // 二次贝塞尔插值
        let y = u * u * p0y + 2 * u * t * cy + t * t * p1y
        return y * (28.0 / 40.0)
    }

    /// 绳索在舞台里的顶部偏移（`.rack-rope { top: 8px }`）
    static let ropeTop: CGFloat = 8

    /// 卡片下方文字区高度（`.rack-meta`，两行：名字 + 品牌·日期）
    static let metaHeight: CGFloat = 30

    /// 孔环原始直径（`.rack-clip { width: 26px; height: 26px }`，
    /// 媒体查询里按 `calc(var(--rack-card-w) * 0.236)` 等比缩放）
    static let clipSize: CGFloat = 26

    /// 绳索舞台需要的总高度。
    ///
    /// 卡片宽度会随容器缩放，所以高度必须跟着算，不能写死。
    /// 组成：顶部留白（绳索 + 孔环）+ 相框高 + 文字区高 + 最大纵向错落。
    static func stageHeight(cardWidth: CGFloat) -> CGFloat {
        let scale = cardWidth / layoutWidth
        // 孔环超出框顶 22pt（框再上移 4pt 盖住它）
        let clipOverhang = 26 * scale
        let frameHeight = cardWidth * 1.29 + 5 * scale * 2   // 照片 + 相框内边距
        // 纵向错落最大是 (2 % 3) * 8 = 16pt，要留出来否则最后一档会被裁
        let maxDrop: CGFloat = 16
        return topInset + clipOverhang + frameHeight + 7 * scale + metaHeight + maxDrop
    }
}

/// 「最近收集」整块：标题 + 数量 + 绳索与卡片。
struct RackSection: View {
    /// 已按「最近优先」排序、已按 15 天窗口过滤并截到 6 张
    let items: [BagItem]
    let base: Date
    /// 当前主卡上是谁
    let selectedID: UUID?
    /// 点「查看全部」
    var onSeeAll: () -> Void = {}
    /// 轻点某张卡片 → 切上方主卡（**不弹详情**）
    var onSelect: (BagItem) -> Void = { _ in }
    /// 打开设置面板。
    /// 📌 设置入口原本是首页右上角的设置圆钮；那个位置改成「最近收藏 N」胶囊后，
    ///    入口搬到这里（H5 是 `.section-heading__actions` 里的 `.icon-action` 齿轮）。
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 标题行 ──
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECENTLY ADDED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)
                    Text("最近收集")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.5), in: .circle)
                            .overlay { Circle().strokeBorder(.black.opacity(0.09), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")

                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("查看全部")
                                .foregroundStyle(.secondary)
                            Text("→")
                                .foregroundStyle(.primary)
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Text("最近 \(Feed.recentWindowDays) 天 · \(items.count) 件")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 20)

            // ── 绳索 + 卡片 / 空状态 ──
            if items.isEmpty {
                // 空状态：撤掉绳索与提示，只留一句陈述，避免一条空绳子晾在那里
                Text("最近 \(Feed.recentWindowDays) 天内还没有新收藏")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 20)
            } else {
                RackStage(items: items,
                          selectedID: selectedID,
                          onSelect: onSelect)
                .padding(.top, 4)

                Text("⇠ 按住卡片左右拨动 · 轻点在上方查看 ⇢")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - 绳索舞台

/// 绳索 + 一排挂袋。
///
/// H5 的 `renderRack()` 用实测宽度反推缩放比，保证一排卡片刚好铺满、不溢出：
/// ```
/// avail    = 容器宽 - 24
/// naturalW = 110 × n - 20 × (n - 1)
/// scale    = min(1, avail / naturalW)
/// ```
/// ⚠️ 6 张按原始尺寸需要 110×6 - 20×5 = 560px，超出 430px 的手机壳，
///    所以必须有这个缩放，否则最后一张会被裁掉。
private struct RackStage: View {
    let items: [BagItem]
    let selectedID: UUID?
    var onSelect: (BagItem) -> Void = { _ in }

    /// 每张卡片的摆动状态。H5 用 `rackStates[]` 存 `{angle, velocity, dragging}`，
    /// SwiftUI 里用 spring 动画等价替代，不必手写帧循环。
    @State private var angles: [Double] = []
    /// 容器实测宽度（用 background 读取，避免 GeometryReader 撑开高度的老问题）
    @State private var containerWidth: CGFloat = 0

    // MARK: 摇一摇

    /// 设置面板里的「摇一摇互动」。与 `SettingsSheet` 读写同一个键。
    @AppStorage(ShakeDetector.storageKey) private var motionEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shake = ShakeDetector()
    /// 正被手指按住的那张卡的下标。
    /// 摇一摇要跳过它（H5 `if (state.dragging) return;`）——
    /// 否则手机的晃动会跟手指抢同一张卡的角度，手感是「拽不动」。
    @State private var draggingIndex: Int?
    /// 「晃完回正」任务的代次。
    /// 每次新晃动都 +1，让上一轮的延迟回正任务自己作废 ——
    /// 不然停手瞬间会有好几个回正动画互相打断，末段会抖一下。
    @State private var swayToken = 0

    private var layout: (cardW: CGFloat, overlap: CGFloat, ropeW: CGFloat, height: CGFloat) {
        let n = items.count
        // 还没测到宽度时用一个合理的手机壳宽度先渲染，避免首帧塌成 0 高度
        let width = containerWidth > 0 ? containerWidth : 393
        guard n > 0 else { return (110, 20, 110, 0) }
        let avail = width - RackMetrics.horizontalPadding * 2
        let naturalW = RackMetrics.layoutWidth * CGFloat(n)
                      - RackMetrics.layoutOverlap * CGFloat(max(n - 1, 0))
        // 宽屏允许适度放大（见 `RackMetrics.maxScale`），手机与 iPad 分屏只缩不放。
        let cap: CGFloat = AppLayout.isWide(width) ? RackMetrics.maxScale : 1
        let fit = naturalW > 0 ? avail / naturalW : 1
        let scale = min(cap, fit)
        let cardW = RackMetrics.layoutWidth * scale
        let overlap = RackMetrics.layoutOverlap * scale
        let ropeW = max(cardW, cardW * CGFloat(n) - overlap * CGFloat(max(n - 1, 0)))
        return (cardW, overlap, ropeW, RackMetrics.stageHeight(cardWidth: cardW))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ── 绳索：底层，卡片浮在绳索之上 ──
            RopeView(width: layout.ropeW)
                .frame(width: layout.ropeW, height: 28)
                .offset(x: RackMetrics.horizontalPadding, y: 8)
                .zIndex(0)
                .allowsHitTesting(false)

            // ── 卡片排：靠负 spacing 实现「错落堆叠，后压前」 ──
            HStack(alignment: .top, spacing: -layout.overlap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, bag in
                    RackItemView(bag: bag,
                                 index: index,
                                 cardWidth: layout.cardW,
                                 angle: angle(index),
                                 isActive: bag.id == selectedID,
                                 // 孔环落到绳索上的 y（H5 `alignClipsToRope()` 的等价解析解）
                                 clipDropY: clipDropY(index: index, layout: layout),
                                 onAngleChange: { setAngle(index, $0) },
                                 // 上报拖动状态：摇一摇要跳过正被按住的那张
                                 onDragActiveChange: { setDragging(index, $0) },
                                 onTap: { onSelect(bag) })
                        .zIndex(Double(index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, RackMetrics.topInset)
            .padding(.horizontal, RackMetrics.horizontalPadding)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: layout.height, alignment: .top)
        // 读容器宽度（不占位、不撑高度）
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in containerWidth = new }
            }
        }
        .onAppear {
            if angles.count != items.count {
                angles = Array(repeating: 0, count: items.count)
            }
            syncMotion()
        }
        // ── 摇一摇：四种情况都会改变「该不该跑传感器」──
        .onChange(of: motionEnabled) { _, _ in syncMotion() }
        .onChange(of: scenePhase) { _, _ in syncMotion() }
        .onChange(of: items.count) { _, _ in syncMotion() }
        .onChange(of: shake.event) { _, event in
            guard let event else { return }
            applyShake(accelX: event.accelX)
        }
        .onDisappear { shake.stop() }
    }

    // MARK: 摇一摇

    /// 按当前状态决定要不要跑传感器。
    ///
    /// 三种「该停」的情况都要停：开关关着、页面离开、App 退到后台 ——
    /// 后台继续 30Hz 采加速度纯属白耗电。
    /// 设备没有传感器（iPad 模拟器 / 无陀螺仪）时也不必启动。
    private func syncMotion() {
        if motionEnabled, scenePhase == .active, !items.isEmpty, ShakeDetector.isSupported {
            shake.start()
        } else {
            shake.stop()
        }
    }

    /// 把一次晃动摊到每一张卡片上。
    ///
    /// 与 H5 `handleDeviceMotion()` 同一口径：相邻卡片方向交错
    /// （`dir = i % 2 == 0 ? 1 : -1`），避免整排完全同步、显得呆板。
    private func applyShake(accelX: Double) {
        swayToken += 1
        let token = swayToken

        // 与「轻点那一下」用同一条弹簧（response 0.35 / damping 0.28），
        // 观感上才是同一排袋子在同一种物理下摆动
        for i in items.indices where i != draggingIndex {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.28)) {
                setAngle(i, RackMetrics.swayDegrees(accelX: accelX, index: i))
            }
        }

        // 晃完自然回正。比阻尼再慢一些，收尾才不像被拽回去的
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard token == swayToken else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.22)) {
                for i in items.indices where i != draggingIndex {
                    setAngle(i, 0)
                }
            }
        }
    }

    /// 拖动开始 / 结束（由 `RackItemView` 上报）
    private func setDragging(_ index: Int, _ active: Bool) {
        if active {
            draggingIndex = index
        } else if draggingIndex == index {
            draggingIndex = nil
        }
    }

    private func angle(_ i: Int) -> Double {
        i < angles.count ? angles[i] : 0
    }

    /// 第 `index` 张卡片的孔环应该落在绳索上的纵向位置（**相对框顶**）。
    ///
    /// 卡片在绳索坐标里的横向中心：
    ///   centerX = cardW/2 + index * (cardW - overlap)
    /// 绳索宽 `ropeW`，所以横向比例 `t = centerX / ropeW`，
    /// 代入同一条贝塞尔求出该处的绳索 y。
    ///
    /// ⚠️ 返回值**不含 `--dy`**：H5 的 `.rack-clip` 挂在 `.rack-hang` 上，
    /// 不受 `.rack-frame` 的 `margin-top` 影响，所以孔环位置与 `--dy` 无关。
    /// 调用方把它用在「未下沉」的框顶 overlay 上（见 `RackItemView.body`）。
    private func clipDropY(index: Int,
                           layout: (cardW: CGFloat, overlap: CGFloat, ropeW: CGFloat, height: CGFloat)) -> CGFloat {
        guard layout.ropeW > 0 else { return 0 }
        let centerX = layout.cardW / 2 + CGFloat(index) * (layout.cardW - layout.overlap)
        let t = min(1, max(0, centerX / layout.ropeW))
        // 绳索在舞台坐标里的 y，换算成「相对框顶」的偏移
        return RackMetrics.ropeTop + RackMetrics.ropeY(atFraction: t) - RackMetrics.topInset
    }

    private func setAngle(_ i: Int, _ value: Double) {
        guard i < angles.count else { return }
        angles[i] = value
    }
}

// MARK: - 绳索

/// 麻绳：两条重叠的二次贝塞尔曲线。
///
/// H5 是 `<path d="M3,6 Q 200,52 397,6">`（viewBox 400×40，
/// `preserveAspectRatio="none"` 横向拉伸到绳索宽度）。
/// iOS 的 `Path` 本身按实际宽度绘制，无需拉伸。
struct RopeView: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            // 绳芯：深棕，带轻微投影
            ropePath
                .stroke(Color(red: 138/255, green: 106/255, blue: 63/255),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Color(red: 60/255, green: 40/255, blue: 10/255).opacity(0.28),
                        radius: 1, x: 0, y: 1)

            // 麻绳的绞纹：浅色虚线
            ropePath
                .stroke(Color(red: 220/255, green: 199/255, blue: 155/255),
                        style: StrokeStyle(lineWidth: 1.7,
                                           lineCap: .round,
                                           dash: [1.6, 3.2]))
        }
    }

    /// `M3,6 Q 200,52 397,6` 按实际宽度等比映射
    private var ropePath: Path {
        let startX = 3.0 / 400.0 * width
        let endX = 397.0 / 400.0 * width
        let controlX = 200.0 / 400.0 * width
        return Path { p in
            p.move(to: CGPoint(x: startX, y: 6))
            p.addQuadCurve(to: CGPoint(x: endX, y: 6),
                           control: CGPoint(x: controlX, y: 52))
        }
    }
}

// MARK: - 单张挂袋

/// 一张挂袋：孔环 + 卡片（照片 + 名称/品牌）。
/// 外层 `.rack-hang` 负责摆动（`transform-origin: 50% 0`，即绕顶部中心转）。
private struct RackItemView: View {
    let bag: BagItem
    let index: Int
    let cardWidth: CGFloat
    let angle: Double
    let isActive: Bool
    /// 孔环落到绳索上的位置（相对框顶）。由父级按绳索贝塞尔算出。
    let clipDropY: CGFloat
    var onAngleChange: (Double) -> Void = { _ in }
    /// 拖动开始 / 结束。父级（`RackStage`）用它在摇一摇的冲量里
    /// 跳过正被手指按住的那张卡。
    var onDragActiveChange: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}

    /// 拖动过程中累计的角度由父级 `angles` 承载，这里只记手势元信息
    @State private var didDrag = false
    @State private var pressStart: Date?

    private var scale: CGFloat { cardWidth / RackMetrics.layoutWidth }

    /// 本张卡片的纵向错落量（H5 `--dy`）
    private var dropOffset: CGFloat { RackMetrics.dropOffset(index) }

    var body: some View {
        VStack(spacing: 0) {
            // ── 悬挂组：绕顶部中心摆动 ──
            //
            // H5 里是 `.rack-hang { position: relative; transform-origin: 50% 0 }`，
            // 内含绝对定位的 `.rack-clip`（`top: -22px; left: 50%`）与 `.rack-frame`。
            // iOS 用 overlay(alignment: .top) 把孔环压在框顶，让框自己撑开高度。
            RackFrame(bag: bag, cardWidth: cardWidth)
                // 纵向错落：H5 是 `.rack-frame { margin-top: var(--dy) }`，
                // 值是 `(i % 3) * 8`。注意是 margin（移动整框）而不是 padding
                // （撑大整框）—— 用 padding 会把照片区顶下去、框变高，
                // 观感是"卡片被拉长"，与 H5 不符。
                .offset(y: dropOffset)
                .frame(width: cardWidth)
                // ⚠️ 孔环必须画在 `dropOffset` **之外**。
                //
                // H5 里 `.rack-clip` 是 `.rack-hang` 的绝对定位子元素
                // （`top:-22px`），而 `--dy` 只作用于 `.rack-frame` 的
                // `margin-top` —— 孔环**不跟着卡片下沉**。
                //
                // SwiftUI 的 `.offset` 只改绘制位置、不改布局位置，
                // 所以把 overlay 挂在 `.offset` **之后**，它贴的就是
                // 未下沉的框顶 —— 正好等价于 H5 里孔环独立于 `--dy`。
                // 最后用 `clipDropY` 把它落到绳索上即可，无需再补偿 `--dy`。
                .overlay(alignment: .top) {
                    // `overlay(alignment: .top)` 把孔环的**顶边**对齐到框顶，
                    // 所以要让它的**中心**落在 `clipDropY` 上，得再上移半个直径。
                    //
                    // ⚠️ 这半个直径必须随卡片宽度缩放（H5 的 width/height 是
                    // `calc(var(--rack-card-w) * 0.236)`），不能用写死的 13。
                    ClipView(size: RackMetrics.clipSize * scale)
                        .offset(y: clipDropY - RackMetrics.clipSize * scale / 2)
                        .zIndex(3)
                }

            // ── 文字区 ──
            VStack(alignment: .leading, spacing: 2) {
                Text(bag.displayName)
                    .font(.system(size: 13 * scale, weight: .regular, design: .serif))
                    .foregroundStyle(isActive
                                     ? Color(red: 138/255, green: 90/255, blue: 16/255)
                                     : Color(red: 74/255, green: 58/255, blue: 34/255))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(bag.displayShelf) · \(DateFormat.monthDayDot(bag.createdAt))")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(Color(red: 160/255, green: 146/255, blue: 116/255))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: cardWidth, alignment: .leading)
            .padding(.top, 7 * scale)
        }
        // 活跃态整体上浮 4pt
        .offset(y: isActive ? -4 : 0)
        .animation(.easeOut(duration: 0.28), value: isActive)
        // 摆动：绕顶部中心
        .rotationEffect(.degrees(RackMetrics.baseAngle(index) + angle),
                        anchor: .top)
        .contentShape(.rect)
        // ⚠️ 只挂一个手势。
        //    如果同时用 `DragGesture(minimumDistance: 0)` + `onTapGesture`，
        //    一次轻点会被两者各触发一次（轻点会荡两下、切两次主卡）。
        //    这里统一在 DragGesture 的 onEnded 里判定轻点，与 H5 一致
        //    ——H5 的切换逻辑也是绑在同一个 pointerdown/up 序列上的。
        .gesture(dragGesture)
    }

    // MARK: 摆动

    /// 拖动：角度映射 dx×0.4，限位 ±75°；松手回弹。
    /// 轻点判定沿用 H5：位移 < 6px 且 按住 < 400ms。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = .now
                    onDragActiveChange(true)   // 通知父级：这张卡在手指上，摇一摇别碰它
                }
                let dx = value.translation.width
                if abs(dx) > RackMetrics.tapMoveThreshold { didDrag = true }
                let mapped = min(RackMetrics.dragLimitDeg,
                                 max(-RackMetrics.dragLimitDeg, dx * RackMetrics.dragFactor))
                // 拖动过程中不加动画，让角度跟手
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { onAngleChange(mapped) }
            }
            .onEnded { _ in
                let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 1
                let wasTap = !didDrag && held < RackMetrics.tapHoldLimit
                pressStart = nil
                didDrag = false
                onDragActiveChange(false)

                if wasTap {
                    // 轻点：先荡一下，再把这张卡片送到上方主卡位（主从联动），
                    // 而不是直接弹详情 —— 用户要的是「点下方、上方出现对应卡片」。
                    onAngleChange(0)
                    kick()
                    onTap()
                } else {
                    // 拨动松手：收进限位内，往反方向弹回
                    let clamped = min(RackMetrics.releaseLimitDeg,
                                      max(-RackMetrics.releaseLimitDeg, angle * 0.3))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.3)) {
                        onAngleChange(clamped)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.25)) {
                            onAngleChange(0)
                        }
                    }
                }
            }
    }

    /// 轻点：先荡一下（H5 `state.velocity += 7`）
    private func kick() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.28)) {
            onAngleChange(-6)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.25)) {
                onAngleChange(0)
            }
        }
    }
}

// MARK: - 金属孔环

/// 金属孔环夹子：暖铜色垫片外圈 + 冷灰钢色孔环内圈。
struct ClipView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // 外圈：暖铜色垫片
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 242/255, green: 226/255, blue: 192/255),
                            Color(red: 229/255, green: 207/255, blue: 162/255),
                            Color(red: 212/255, green: 186/255, blue: 138/255)
                        ],
                        center: .init(x: 0.35, y: 0.28),
                        startRadius: 0, endRadius: size * 0.62
                    )
                )
                .overlay {
                    Circle().strokeBorder(
                        Color(red: 150/255, green: 115/255, blue: 65/255).opacity(0.45),
                        lineWidth: 1)
                }
                .shadow(color: Color(red: 30/255, green: 22/255, blue: 8/255).opacity(0.3),
                        radius: 1, x: 0, y: 1)

            // 内圈：冷灰钢色孔环
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 253/255, green: 254/255, blue: 254/255),
                            Color(red: 215/255, green: 221/255, blue: 227/255),
                            Color(red: 174/255, green: 183/255, blue: 192/255),
                            Color(red: 142/255, green: 153/255, blue: 163/255)
                        ],
                        center: .init(x: 0.35, y: 0.28),
                        startRadius: 0, endRadius: size * 0.24
                    )
                )
                .overlay {
                    Circle().strokeBorder(
                        Color(red: 105/255, green: 115/255, blue: 127/255).opacity(0.65),
                        lineWidth: 1)
                }
                .frame(width: size * 10 / 26, height: size * 10 / 26)

            // 孔洞
            Circle()
                .fill(Color(red: 43/255, green: 48/255, blue: 56/255))
                .frame(width: size * 3.5 / 26, height: size * 3.5 / 26)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 卡框（照片 + 细棕描边 + 磨砂玻璃底）

private struct RackFrame: View {
    let bag: BagItem
    let cardWidth: CGFloat

    private var scale: CGFloat { cardWidth / RackMetrics.layoutWidth }
    /// 照片区高度 = 卡宽 × 1.29（H5 `.rack-photo { height: calc(var(--rack-card-w) * 1.29) }`）
    private var photoHeight: CGFloat { cardWidth * 1.29 }
    /// 照片区宽度：框宽减去左右各 5×scale 的内边距，再减去 1.5 描边
    private var photoWidth: CGFloat { cardWidth - (5 * scale + 1.5) * 2 }

    var body: some View {
        // H5: `.rack-photo .bag-photo { max-width: 96%; max-height: 90% }`
        // —— 在固定尺寸的照片框里「装得下为准」，两个方向都不许超。
        //
        // ⚠️ 不要用 `.frame(width:height:)` 同时锁定两轴：那会把图片
        //    强行拉伸到该尺寸、破坏素材原始纵横比（H5 踩过的替换元素坑）。
        //    正确做法是给一个「最大可用区域」让它等比缩进去
        //    （等比逻辑在 `ThumbnailImage` 的 `contentMode: .fit` 里）。
        //
        // 走缩略图缓存：这里最多同时有 6 张，且都是小尺寸，
        // 用缓存避免每次摆动/重绘都重新解码。`ThumbnailImage` 同时兼容
        // 「磁盘真实图」与「Assets 演示图」——直接用 `Image(_:)` 只认 Assets，
        // 用户自己拍的照片会渲染成空白。
        ThumbnailImage(fileName: bag.imageFileName,
                       size: RackMetrics.layoutWidth * 2,
                       contentMode: .fit,
                       interpolation: .high)
            // 96% / 90% 的道具留白
            .frame(maxWidth: photoWidth * 0.96, maxHeight: photoHeight * 0.90)
            // 照片框：固定尺寸，背景是暖色纸底 + 一层明暗
            .frame(width: photoWidth, height: photoHeight)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.12), .black.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(.rect(cornerRadius: 2))
            .padding(5 * scale)
            .background(Color.white.opacity(0.26), in: .rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(red: 138/255, green: 111/255, blue: 69/255),
                                  lineWidth: 1.5)
            }
            .shadow(color: Color(red: 60/255, green: 45/255, blue: 20/255).opacity(0.14),
                    radius: 5, x: 0, y: 3)
    }
}

// MARK: - 预览

#Preview {
    let bags = PreviewData.samples()
    let base = Feed.demoBase(bags)
    return ScrollView {
        RackSection(items: Feed.recent(bags, base: base),
                    base: base,
                    selectedID: bags.first?.id)
            .padding(.vertical, 20)
    }
    .background(Color(red: 0.953, green: 0.953, blue: 0.969))
}
