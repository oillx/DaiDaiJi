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
    /// 单卡原始宽（**布局基准**，本轮不动）
    static let layoutWidth: CGFloat = 110
    /// 相邻重叠（**布局基准**，本轮不动）
    static let layoutOverlap: CGFloat = 20

    // ═══════════════════════════════════════════════════════════
    //  吊卡五金：按原型《挂袋区_轻量调试.html》1:1
    //
    //  原型 `--rack-card-w: 106.00px`，下面所有 px 都是**该基准下的值**，
    //  使用时一律乘 `hardwareScale(cardWidth)`。
    //  ⚠️ 卡宽本身按用户要求先不改（仍 110 基准 / 128 上限），
    //     于是五金相对卡片 = 110/106 ≈ 1.038 倍 —— 与原型观感一致。
    // ═══════════════════════════════════════════════════════════

    /// 原型的设计基准宽（`--rack-card-w: 106`）
    static let designWidth: CGFloat = 106
    /// 五金缩放：以原型基准宽为一倍
    static func hardwareScale(_ cardWidth: CGFloat) -> CGFloat { cardWidth / designWidth }

    /// 轮心（= 亚克力杆轴心）在卡框顶之上 **44.02px** —— **摆动轴心**
    static let pivotAbove: CGFloat = 44.02
    /// 滑轮盒边长（原型 21.496；内含 viewBox 19.541，即 1.1 倍）
    static let pulleyBox: CGFloat = 21.496
    /// 吊线：轮心 → 夹具顶 **36.52px**（再随 `--dy` 变长），线宽 1.6
    static let wireBase: CGFloat = 36.52
    static let wireWidth: CGFloat = 1.6
    /// 夹具：11.6 × 15，**咬住卡顶 7.5px**
    static let gripWidth: CGFloat = 11.6
    static let gripHeight: CGFloat = 15
    static let gripBite: CGFloat = 7.5

    /// 亚克力展示杆：杆体高 **10**、左右各内缩 24、圆角 2.5
    static let railHeight: CGFloat = 10
    static let railInset: CGFloat = 24
    /// 杆端五金（三者一律以**杆轴为中心**）
    static let endcapWidth: CGFloat = 9
    static let endcapHeight: CGFloat = 13.5
    static let endcapInset: CGFloat = 17
    static let studWidth: CGFloat = 13
    static let studHeight: CGFloat = 3.2
    static let studInset: CGFloat = 6
    static let knobDiameter: CGFloat = 8.5
    static let knobInset: CGFloat = 1

    /// 照片区高度 = 卡宽 × 这个比例（原型 `.rack-photo { height: calc(var(--rack-card-w) * 1.29) }`）。
    ///
    /// 📌 沿革：稿面 **1.29** → 上一轮按需求「卡片调高一点点」到 1.36（+5.4%）
    ///    → 本轮按需求「卡片再矮一点点」**回到 1.29**（−5.2pt，−4.7%）。
    ///    卡片高（`frameHeight`）、单卡总高（`itemHeight`）与舞台高（`stageHeight`）
    ///    **全都由它派生**，所以只改这一个数，整排一起变矮、
    ///    行内比例（卡宽 / 五金 / 文字区）完全不变；卡片是**从横杆往下挂**的，
    ///    所以变矮只收底边，卡片顶边与五金位置分毫不动。
    ///    ⚠️ 再矮一档：1.26（卡高 102.6）/ 1.22（99.6）；回上一轮的加高值写 1.36。
    static let photoHeightRatio: CGFloat = 1.29

    /// 袋图在照片区里最多占的高度比例（原型 `.rack-photo .paper-bag { max-height: 100% }`）。
    ///
    /// 📌 沿革：原型 1.0（袋子顶满）→ 按需求「袋子别挤满卡片」收到 0.88
    ///    → 本轮卡片变矮（`photoHeightRatio` 1.36 → 1.29）后，**再放宽到 0.93**。
    ///    0.93 × (74.25 × 1.29) ≈ 89.1pt，与原来的 0.88 × (74.25 × 1.36) ≈ 88.9pt
    ///    **几乎完全相等** —— 也就是「卡片矮一点点，袋子尺寸不变」：
    ///    玻璃卡上下留白由 6.1pt 收到 3.4pt，袋子本身一点没缩。
    ///    ⚠️ 若想让袋子跟着卡片一起变小（整卡等比缩小）：把它写回 0.88
    ///       （袋图 89.1 → 84.3pt）。写 1.0 则回到原型口径（袋子顶满照片区）。
    ///    ⚠️ 只压**高度**，宽度仍按素材本身的长宽比自适应（高瘦袋子等比变窄；
    ///       偏宽的图本来就是被宽度约束，不受这个值影响）。
    static let photoImageHeightRatio: CGFloat = 0.93

    /// 卡框（磨砂玻璃）：圆角 **7**、内边距 5、描边 1。
    ///
    /// 📌 稿面圆角是 **6**；改成 7 是**被螺点位置反推出来的**：
    ///    螺点距外沿挪到 4.5pt（见 `screwInset`）后，按半径 6 的圆角算，
    ///    螺点会有 1.29pt 咬出圆角外面（圆心距 3.39 + 半径 2.10 = 5.49 > 圆角 4.20）。
    ///    半径 7 时：2.40 + 2.10 = 4.50 ≤ 4.90 ✓ 刚好装下（余量 0.40pt）。
    ///    ⚠️ 想回稿面圆角：必须同时把螺点拉回 ≤3.58pt 距外沿、或把 `screwDiameter` 降到 4.4。
    ///    ⚠️ 再想给螺点留更多余量：半径 8（余量 1.29pt）/ 9.42（与螺点完全同心）。
    static let frameRadius: CGFloat = 7
    static let framePadding: CGFloat = 5
    /// 框的描边宽（CSS `border:1px`）—— 单独提出来是因为螺点定位要把它算进去
    static let frameBorderWidth: CGFloat = 1

    /// 四角螺点：`⌀5`，距**内边距盒**（padding box）**6.14px**。
    ///
    /// ⚠️ 口径别搞错：CSS 里 `.rack-screw{position:absolute; top:3px; left:3px}` 的
    ///    包含块是祖先（卡框）的 **padding box** —— 绝对定位不认 border，
    ///    所以它到卡框**外沿**的真实距离是 `border 1px + inset`，也是下面这个数的来源。
    ///
    /// 📌 沿革：稿面 `⌀4 / 距 3`（`挂袋区_轻量调试.html` 18:36 版）
    ///    → 「螺点本身调大一点」：`⌀6`
    ///    → 「距外沿 3.50 → **4.50pt**」：`inset = 4.50 ÷ 0.7005 − border 1 = **5.42**`。
    ///       （0.7005 = iPhone 17 Pro 上 74.25 ÷ 106 的 `hardwareScale`；iPad 上按比例同步放大。）
    ///    → 「四角螺旋按钮再小一点」：`⌀6 → **5**`（实渲染 ⌀4.20 → **3.50pt**）。
    ///    → 「只是位置更靠里、尺寸不变」：⌀**不动**，`inset 5.42 → **6.14**`
    ///       ⇒ 近边距外沿 `4.50 → **5.00pt**`（`5.00 ÷ 0.7005 − border 1 = 6.14`）。
    ///    iPhone 上实渲染：**⌀3.50pt、近边距外沿 5.00pt**。
    ///
    /// ⚠️ 三个数是**耦合**的（螺点直径 / 距外沿 / 卡框圆角）：螺点沿的是卡角的 45° 对角线，
    ///    而圆角恰好把这条对角线往里切得最多。约束是
    ///    `|中心 − 圆角圆心| × √2 + 半径 ≤ 圆角半径`。
    ///    · 半径 6 + ⌀6：「距外沿」上限只有 3.58pt —— 所以上一轮把 `frameRadius` 提到 7；
    ///    · **半径 7 + ⌀5（现值）：上限 5.38pt** —— 现在是 5.00（余量 0.53pt）。
    ///      还想再往里，就先加 `frameRadius`（8 时上限约 6.2pt）。
    ///    ⚠️ 想回稿面：`⌀` 写 4、`inset` 写 3、`frameRadius` 写 6。
    ///    ⚠️ 现在 ⌀5 下圆角余量有 1.24pt —— 若想把 `frameRadius` 收回稿面的 6，
    ///       得同时把「距外沿」收到 ≤ ~3.9pt 或把 `⌀` 降到 ≤ 4.3（R6 时 ⌀5 会咬出 0.45pt）。
    static let screwDiameter: CGFloat = 5
    static let screwInset: CGFloat = 6.14

    /// 文字区：标题 / 副行 / 上垫 的卡宽比例（原型 `.118 / .082 / .064`）
    static let metaTitleRatio: CGFloat = 0.118
    static let metaSubRatio: CGFloat = 0.082
    static let metaPadTopRatio: CGFloat = 0.064
    /// 文字区左右内边距（原型 `3px`）
    static let metaPadH: CGFloat = 3
    /// 文字区总高（上垫 + 两行）≈ 卡宽 × 0.32
    static let metaHeightRatio: CGFloat = 0.32

    /// 选中上浮（原型 `--rack-lift: 4px`，直接扣在 `--dy` 上）
    static let activeLift: CGFloat = 4
    /// 选中红（原型 ⑯：卡环与轮心共用 `#c50205`）
    static let activeRed = Color(red: 197 / 255, green: 2 / 255, blue: 5 / 255)

    /// 单卡宽度上限：设计宽 110 × 1.164 ≈ 128。宽屏（iPad）上袋子因此大一圈。
    ///
    /// 📌 沿革：这个上限原本是防「卡片底色的色块面积」的 —— 旧版 `.rack-photo`
    ///    会铺六色纸底，卡一大就成片色块（用户反馈过「卡片背景色不太搭」）。
    ///    **本轮按原型 ④ 去掉了底色**（真图直接落在磨砂玻璃卡内的透明底上），
    ///    那个约束随之消失；128 保留只是因为用户要求「卡宽先不改」。
    ///    ⚠️ 想抬：现在只剩观感与「一屏挂几张」的取舍。
    ///
    /// ⚠️ 要铺满的是**横杆**，不是卡片 —— 杆宽由下面 `max(rowW, avail)` 单独
    ///    保证，卡片排布窄于容器时整排居中，与本上限互不干扰。
    static let maxCardWidth: CGFloat = 128

    /// 整排布局（H5 `renderRack()` 的「反推缩放、整排铺满」口径）：
    /// ```text
    ///   avail    = 容器宽 − `.rack-bags` 左右 12×2
    ///   naturalW = 110 × n − 20 × (n − 1)
    ///   scale    = min(avail / naturalW, maxCardWidth / 110)   ← 双向适配，不封 1
    ///   卡宽 = 110 × scale，重叠 = 20 × scale
    ///   绳索宽 = max(卡片排布宽, avail)
    /// ```
    /// 交付包这版的挂袋排**整排缩到刚好铺满、不可横向滚动**（`.rack-bags { overflow-x: visible }`），
    /// 之前 iOS 的「固定一屏 3 张 + 横滑 + 先按住再拖」是旧改动，随本轮收回 1:1。
    ///
    /// ⚠️ H5 写的是 `min(1, …)`，因为它的壳恒为 430px（6 张 560px 装不下，只能缩）。
    ///    iOS 上 iPad 是全屏（820 起），照抄那个封顶的后果是：
    ///    **卡片只占左侧 560pt，绳子到屏幕中间就断了**（实测绳子右端 603 / 屏宽 820，
    ///    右边空出 216pt）—— 用户原话「绳子最短要铺满屏幕，不然很奇怪」。
    ///    所以这里改成双向适配：窄了缩、宽了放大，让这一排真正铺满。
    ///
    /// ⚠️ 绳索宽度与卡片排布宽度**本来就是解耦的**（H5 原注释：「绳索铺满整个
    ///    卡片排布宽度…孔环再由 `alignClipsToRope()` 反查绳索真实坐标对齐」），
    ///    所以「卡片没铺满、绳子先铺满」不会让孔环错位 —— 补上 `max(…, avail)`
    ///    正是为了「藏品少 / 触到单卡上限」时绳子依然铺满。
    static func layout(forWidth width: CGFloat, count: Int)
        -> (cardW: CGFloat, overlap: CGFloat, ropeW: CGFloat) {
        guard count > 0 else { return (layoutWidth, layoutOverlap, layoutWidth) }
        let avail = max(1, width - horizontalPadding * 2)
        let naturalW = layoutWidth * CGFloat(count) - layoutOverlap * CGFloat(max(count - 1, 0))
        let scale = min(avail / naturalW, maxCardWidth / layoutWidth)
        let cardW = layoutWidth * scale
        let overlap = layoutOverlap * scale
        let rowW = cardW * CGFloat(count) - overlap * CGFloat(max(count - 1, 0))
        return (cardW, overlap, max(rowW, avail))
    }

    /// `.rack-bags` 左右各 12px 内边距
    static let horizontalPadding: CGFloat = 12
    /// 卡片区顶部留白：原型 `.rack-bags { padding: 60px 12px 12px }`。
    /// 60px 要装下「滑轮盒（盒顶在 −54.77）」，所以比上一版的 34 高。
    static let topInset: CGFloat = 60
    /// `.rack-bags` 底部内边距（原型 12px）
    static let bottomInset: CGFloat = 12

    /// 拖动角度映射：dx × 0.4，限位 ±75°
    static let dragFactor: CGFloat = 0.4
    static let dragLimitDeg: CGFloat = 75
    /// 松手回弹：收进 ±26°
    static let releaseLimitDeg: CGFloat = 26
    /// 轻点判定（H5 pointerup：位移 < 6px 且 按住 < 400ms = 轻点，否则按拨动松手）。
    ///
    /// 这两个数真的参与判定：拨动手势 `onEnded` 里按它们分流「轻点 / 拨动松手」。
    ///
    /// 📌 手势沿革：`DragGesture(minimumDistance: 0)` 直挂（**落指即拖**）
    ///    → 本轮按需求改成「**长按之后才拨动**」—— 挂架区现在能横向滚动了，
    ///      落指即拖会把落在卡片上的横向拖动全部吃掉、根本滚不动：
    ///        · 快速滑动 ⇒ 长按没成立 ⇒ 手势失败 ⇒ 交给外层 `ScrollView` 横向滚动；
    ///        · 按住 `swingHold` 再拖 ⇒ 长按成立、卡片接管，位移全喂给拨动物理；
    ///        · 轻点 ⇒ 两个手势都不成立 ⇒ 走 `.onTapGesture`，仍在这里分流。
    static let tapMoveThreshold: CGFloat = 6
    static let tapHoldLimit: Double = 0.4

    /// 拨动卡片需要**按住**的时长（秒）：长按成立后手势才接管拖动。
    /// 0.25 是「按住」的常规量级 —— 调小更容易拨动、调大更不容易误触。
    static let swingHold: Double = 0.25
    /// 「按住」期间允许的手指抖动（pt）：超过就判定成「在滑动」，
    /// 长按直接失败、让给横向滚动（取 `LongPressGesture` 的默认 10，写出来是为了可调）。
    static let swingHoldSlop: CGFloat = 10

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
    /// ⚠️ 摇一摇的冲量公式已下沉到 `RackStage.applyShake`（直接喂帧物理的 velocity）。
    /// 静止微倾（原型 `RACK_TILTS = [-2.0, 1.7, -1.7, 2.0]`，四张一循环）
    static let tilts: [Double] = [-2.0, 1.7, -1.7, 2.0]
    static func baseAngle(_ i: Int) -> Double { tilts[i % tilts.count] }

    /// 卡片的纵向错落：原型每张卡写死 `--dy-base: 0 / 7 / 14 / 7`（四张一循环）。
    /// 让一排挂袋不在同一条水平线上，像随手挂上去的。
    /// ⚠️ 单位是原型基准（106）下的 px，用前乘 `hardwareScale`。
    static func dropOffset(_ i: Int) -> CGFloat { [0, 7, 14, 7][i % 4] }

    /// 卡片下方文字区高度（上垫 + 两行）≈ 卡宽 × 0.32（原型量得）
    static func metaHeight(cardWidth: CGFloat) -> CGFloat {
        cardWidth * metaHeightRatio
    }

    /// 卡框整体高 = 照片高（卡宽 × `photoHeightRatio`）+ 上下内边距与描边
    static func frameHeight(cardWidth: CGFloat) -> CGFloat {
        let s = hardwareScale(cardWidth)
        return cardWidth * photoHeightRatio + (framePadding * s + 1) * 2
    }

    /// 一张吊卡（框 + 文字区）的总高 —— 摆动轴心的单位换算要用它：
    /// 轴心在卡框顶之上 `pivotAbove`，故 `anchor.y = −pivotAbove × s / 单卡总高`。
    static func itemHeight(cardWidth: CGFloat) -> CGFloat {
        frameHeight(cardWidth: cardWidth) + metaHeight(cardWidth: cardWidth)
    }

    /// 舞台总高：顶部留白 + 单卡高 + 最大纵向错落（0/7/14/7 里取 14）+ 底部内边距
    static func stageHeight(cardWidth: CGFloat) -> CGFloat {
        let s = hardwareScale(cardWidth)
        return topInset * s + itemHeight(cardWidth: cardWidth) + 14 * s + bottomInset
    }
}

/// 「最近收集」区块的文字规格。
///
/// 全部照抄 H5 `styles.css`，每条的出处都写在右边 ——
/// 这一块原来有一批 iOS 自拟的数（标题 19pt 无衬线、计数 11pt、空状态 12pt…），
/// 与稿面差一档，本轮统一按设计规范收口。
private enum RackText {
    /// 全局 `h2 { font-size: 25px; letter-spacing: -.5px; line-height: 1.05 }`
    /// （`h1, h2` 共用同一套衬线字体族）
    ///
    /// 📌 **H5 是 25，这里按需求收到 18 —— 与「全部收藏」页的分组标题（品牌名，
    ///    `ShelfMetrics.titleFont`）取齐**，于是两页的这两行字字号**完全相同**。
    ///    直接引用对方的常量（而不是各写一个 18），杜绝「改一处忘一处」：
    ///    以后想让这两行同时变大/变小，只改 `ShelfMetrics.titleFont` 一处。
    ///    ⚠️ 想回 H5 稿面值：把本行写回 `25`（那就又与收藏页不同字号了）。
    ///    ⚠️ 字号改小**不会**顶动下面的挂袋吧台：这一行的高度由右侧「查看全部」
    ///       按钮的 `minHeight`（38）决定，标题只是在这一行里底对齐。
    static let titleFont: CGFloat = ShelfMetrics.titleFont
    static let titleTracking: CGFloat = -0.5
    static let titleLineHeight: CGFloat = 1.05

    /// `.text-action { min-height: 38px; font-size: 11px; color: var(--muted) }`
    /// + `.text-action span { color: var(--ink); margin-left: 3px }`
    static let actionFont: CGFloat = 11
    static let actionMinHeight: CGFloat = 38

    /// `.stage-count { margin: -6px 22px 12px; color: var(--muted); font-size: 10px }`
    ///
    /// 📌 **按需求与右侧「查看全部」同号** —— 直接引用 `actionFont`（11），
    ///    两处从此共用一个值，不会再各走各的。H5 原值是 10，想回去就写回 10。
    static let countFont: CGFloat = actionFont
    static let countTopGap: CGFloat = -6
    static let countBottomGap: CGFloat = 12

    /// `.section-heading { padding: 0 22px 14px }`
    static let sectionPadH: CGFloat = 22
    static let sectionPadBottom: CGFloat = 14

    /// `.rack-empty { padding: 26px 22px 8px; color: var(--muted); font-size: 11px }`
    static let emptyFont: CGFloat = 11
    static let emptyPadTop: CGFloat = 26
    static let emptyPadBottom: CGFloat = 8

    /// `.rack-hint { margin: 8px 20px 0; font-size: 10px; opacity: .8 }`
    static let hintFont: CGFloat = 10
    static let hintTopGap: CGFloat = 8
    static let hintOpacity: Double = 0.8

    /// H5 `html, body { color: var(--ink) }` → `--ink: #141414`；`--muted: #77736d`
    static let ink = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let muted = Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255)
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
    /// 可排版的容器宽度（由调用方传入，全屏铺满后就是屏幕宽）。
    /// ⚠️ 必须外部给，不能自己量 —— 见 `RackStage.containerWidth` 的说明。
    let containerWidth: CGFloat

    /// 标题/计数/空状态的水平内边距：H5 是 22px，宽屏（iPad）提到 28。
    private var padH: CGFloat { AppLayout.pagePad(RackText.sectionPadH, for: containerWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 标题行 ──
            // H5 `.section-heading { display:flex; align-items:flex-end; padding: 0 22px 14px }`
            //
            // ⚠️ 标题上方原来有一行英文小字（RECENTLY ADDED），已按需求去掉 ——
            //    与首页「MY PRIVATE CABINET」、收藏页「THE FULL ARCHIVE」、
            //    设置面板「SETTINGS」是同一处理。别加回来。
            HStack(alignment: .bottom) {
                // 标题走 H5 的**全局 `h2`**：25px / 衬线 / 字距 -0.5 / 行高 1.05。
                // 原来写成 19pt 无衬线加粗，比稿面小一号、还丢了衬线体。
                // 📌 字号现在与收藏页的品牌名标题取齐（见 `RackText.titleFont`，18）。
                //
                // ⚠️ 这档走宋体 `bold`（700）；`heavy`（900）留给 38pt 的大标题。
                //    也不能退回 `design: .serif` —— 中文会静默回落成苹方黑体。
                Text("最近收集")
                    .font(AppFont.songti(RackText.titleFont))
                    .tracking(RackText.titleTracking)
                    .foregroundStyle(RackText.ink)
                    // `line-height: 1.05`：中文在这个字号下的行盒约 1.2 倍，
                    // 不夹一下标题行会高出几 pt，下面的计数行跟着往下走。
                    .frame(height: RackText.titleFont * RackText.titleLineHeight)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, padH)
            .padding(.bottom, RackText.sectionPadBottom)

            // ── 计数行 ＋「查看全部」──
            //
            // 📌 按需求：**「查看全部」与「最近 N 天 · N 件」顶部对齐**。
            //
            // ⚠️ 它必须挂在 `.overlay` 上、**不能作为 HStack 的兄弟**：
            //    按钮的触控高度是 38pt（H5 `.text-action { min-height: 38px }`），
            //    一旦参与这一行的布局，就会把行高从「计数字约 13pt」撑到 38pt，
            //    下方整个挂袋区被推下去 25pt（用户反馈「挂袋区和上面的文字距离太大」）。
            //    overlay 不参与布局 ⇒ 行高只由计数字决定，而按钮内容仍然顶对齐。
            HStack(spacing: 0) {
                Text("最近 \(Feed.recentWindowDays) 天 · \(items.count) 件")
                    .font(.system(size: RackText.countFont))
                    .foregroundStyle(RackText.muted)

                Spacer(minLength: 8)
            }
            .overlay(alignment: .topTrailing) {
                // ⚠️ 标题行里原来还有一枚「设置」齿轮，已随 H5 退役：
                //    设置入口回归首页右上角的 `.header-settings`，两处并存会有两个入口。
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        // 📌 按需求：箭头与「查看全部」**同色**（都用 muted）。
                        //    H5 原文是 `.text-action span { color: var(--ink) }`，
                        //    即箭头刻意比文字深一档 —— 这里有意偏离。
                        Text("查看全部")
                            .foregroundStyle(RackText.muted)
                        Text("→")
                            .foregroundStyle(RackText.muted)
                    }
                    .font(.system(size: RackText.actionFont))
                    // H5 `.text-action { min-height: 38px }`：够到最小可点尺寸。
                    // `alignment: .top` 让文字贴在 38pt 框的**顶部**，与左侧计数字齐平；
                    // 多出的高度向下溢出这一行（落在挂袋区上方的空白里，不会挡到卡片）。
                    .frame(minHeight: RackText.actionMinHeight, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看全部收藏")
            }
            // H5 `.stage-count { margin: -6px 22px 12px }` —— 上边距是**负的**，
            // 把这一行往标题那里拉近 6px（净间距 ＝ 标题行 14 − 6 ＝ 8）。
            .padding(.top, RackText.countTopGap)
            .padding(.horizontal, padH)
            .padding(.bottom, RackText.countBottomGap)

            // ── 绳索 + 卡片 / 空状态 ──
            if items.isEmpty {
                // 空状态：撤掉绳索与提示，只留一句陈述，避免一条空绳子晾在那里。
                // 文案用 H5 `.rack-empty` 的原文（原来少了「，从 ＋ 添加一只吧。」）
                Text("最近 \(Feed.recentWindowDays) 天内还没有新收藏，从 ＋ 添加一只吧。")
                    .font(.system(size: RackText.emptyFont))
                    .foregroundStyle(RackText.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, RackText.emptyPadTop)
                    .padding(.bottom, RackText.emptyPadBottom)
                    .padding(.horizontal, padH)
            } else {
                // 与计数行之间的间距由 `.stage-count { margin-bottom: 12px }` 提供，
                // 这里不再额外加 padding（原来那 4pt 是补在计数行没有下边距的时候）。
                RackStage(items: items,
                          selectedID: selectedID,
                          containerWidth: containerWidth,
                          onSelect: onSelect)

                Text("⇠ 按住卡片左右拨动 · 轻点在上方查看 ⇢")
                    .font(.system(size: RackText.hintFont))
                    .foregroundStyle(RackText.muted)
                    .opacity(RackText.hintOpacity)
                    .frame(maxWidth: .infinity)
                    .padding(.top, RackText.hintTopGap)
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
/// 单张挂袋的摆动状态（与 H5 `rackStates[]` 的元素 `{angle, velocity, dragging}` 同构）。
private struct SwingState {
    var angle: Double = 0
    var velocity: Double = 0
    var dragging = false
}

/// CADisplayLink 驱动的帧循环 —— H5 `requestAnimationFrame(rackTick)` 的 iOS 等价物。
///
/// 生命周期模仿 H5 的 `rackKick()` / `rackTick()`：
/// · 有卡片在动（或正被拖拽）才跑；全部静止即 `stop()`
/// · 固定 **1/60s 步长**积分：H5 的物理参数（0.018 / 0.952）是「每帧一步」标定的，
///   高刷屏（ProMotion 120Hz）用累加器补齐步数，保证任何刷新率下衰减节奏一致。
@MainActor
private final class RackDisplayLink {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var accumulator: CFTimeInterval = 0
    /// 每个固定步长回调一次（MainActor 上）
    var onStep: (() -> Void)?

    func ensureRunning() {
        guard link == nil else { return }
        lastTimestamp = 0
        accumulator = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        accumulator = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        // ⚠️ 首次回调不能只用来「对齐时间基准」—— 那样等于白等一个 vsync
        //    （约 16.7ms），起摆会看起来慢一拍。这里立刻积分一次。
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            onStep?()
            return
        }
        accumulator += link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        let frame = 1.0 / 60.0
        while accumulator >= frame {
            accumulator -= frame
            onStep?()
        }
    }
}

private struct RackStage: View {
    let items: [BagItem]
    let selectedID: UUID?
    /// 可排版的容器宽度（由调用方给出，铺满后就是屏幕宽）。
    ///
    /// ⚠️ 必须是**外部给的**，不能自己用 `GeometryReader` 去量：
    ///    本视图的 frame 由内容（一排挂袋）撑开，量自己 = 拿「已经长出来的宽度」
    ///    去算「该长多宽」，形成放大回路 —— 实测每帧 ×1.06，
    ///    402 → 417 → 442 → 469 → … → 620（被列的宽度上限夹住）才停，
    ///    于是内容比屏幕还宽、左右被裁。
    let containerWidth: CGFloat
    var onSelect: (BagItem) -> Void = { _ in }

    /// 每张卡片的摆动状态 —— H5 `rackStates[]` 原样移植，**逐帧积分**而非 spring 关键帧。
    @State private var states: [SwingState] = []
    /// 帧循环驱动器（`rackKick` = `ensureRunning`，静止自动停表）
    @State private var linkProxy = RackDisplayLink()
    // MARK: 摇一摇

    /// 设置面板里的「摇一摇互动」。与 `SettingsSheet` 读写同一个键。
    @AppStorage(ShakeDetector.storageKey) private var motionEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shake = ShakeDetector()
    /// 正被手指按住的那张卡的下标。
    /// 摇一摇要跳过它（H5 `if (state.dragging) return;`）——
    /// 否则手机的晃动会跟手指抢同一张卡的角度，手感是「拽不动」。
    @State private var draggingIndex: Int?

    private var layout: (cardW: CGFloat, overlap: CGFloat, ropeW: CGFloat, height: CGFloat) {
        // 还没测到宽度时用一个合理的手机壳宽度先渲染，避免首帧塌成 0 高度
        let width = containerWidth > 0 ? containerWidth : 393
        // ⚠️ 卡宽按**一屏基准张数**算（`Feed.rackLimit` = 6），不按实际张数：
        //    否则 8 张会被缩成「8 张挤在一屏」、越加越多就越小，滚动也就无从发生。
        let size = RackMetrics.layout(forWidth: width, count: min(items.count, Feed.rackLimit))
        // 杆/绳索要铺到**整排**（超出一屏时也铺满），所以这个数按真实张数单独求。
        let rope = RackMetrics.layout(forWidth: width, count: items.count).ropeW
        return (size.cardW, size.overlap, rope,
                RackMetrics.stageHeight(cardWidth: size.cardW))
    }

    /// 舞台整宽 = 一屏宽（卡片排布比它窄时，整排以它为基准居中）
    private var stageWidth: CGFloat { containerWidth > 0 ? containerWidth : 393 }
    /// 横向内容宽 = 杆宽 + 左右内边距
    /// （≤6 张时 `ropeW` = 容器 − 24 ⇒ 这里正好 = 一屏宽，与改前逐像素一致）
    private var contentWidth: CGFloat {
        layout.ropeW + RackMetrics.horizontalPadding * 2
    }
    /// 五金缩放（以原型基准宽 106 为一倍）
    private var hardwareScale: CGFloat { RackMetrics.hardwareScale(layout.cardW) }
    /// 杆轴（= 轮心）在舞台坐标里的 y
    private var railCenterY: CGFloat {
        (RackMetrics.topInset - RackMetrics.pivotAbove) * hardwareScale
    }

    var body: some View {
        // ── 一屏放得下就整排铺满（形态与改前一致）；放不下就横向滚动 ──
        //
        // 绳索（= 亚克力展示杆）画在底层，卡片浮在杆下；卡宽由
        // `RackMetrics.layout(forWidth:count:)` 按**一屏基准张数**算出，于是：
        //   · ≤6 张：这一排恰好铺满，`ScrollView` 无事可做（与改前逐像素一致）；
        //   · >6 张：卡片**不再继续变小**，这一排宽于容器、由 `ScrollView` 横向滚动；
        //            杆与卡片同在内容层里，**一起滚**（杆宽 = 排布宽 + 左右内边距）。
        //
        // ⚠️ 卡片自带 `highPriorityGesture(DragGesture(minDistance: 0))`（拨动摆动），
        //    落在**卡片上**的拖动仍归它 —— 所以现在横向滚动要用**横杆那一条**、
        //    或卡片下方的空白来拖。手势归属按需求本轮不动。
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
            // ── 横杆：亚克力展示杆（底层，卡片吊在杆下）──
            //
            // 杆轴 = 轮心 = 「舞台顶 + 顶部留白 − 44.02×s」；`RackRailView`
            // 内部已把三件五金都按杆轴居中，所以这里只要把它的**中心**摆到杆轴上：
            //     视图顶 = 杆轴 − 端夹块高/2
            RackRailView(stageWidth: contentWidth, scale: hardwareScale)
                .offset(y: railCenterY - RackMetrics.endcapHeight * hardwareScale / 2)
                .zIndex(0)

            // ── 卡片排：靠负 spacing 实现「错落堆叠，后压前」 ──
            HStack(alignment: .top, spacing: -layout.overlap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, bag in
                    rackItem(index, bag)
                }
            }
            .padding(.top, RackMetrics.topInset * hardwareScale)
            .padding(.horizontal, RackMetrics.horizontalPadding)
            // 原型 `.rack-bags { padding: 60px 12px 12px }` 的底部 12
            .padding(.bottom, RackMetrics.bottomInset)
            // 卡片排布比一屏窄时（藏品少、或超大屏被单卡上限夹住）**居中**：
            // 杆是铺满的，卡片吊在正中间才自然。铺满或超出一屏时这一层是恒等变换。
            .frame(minWidth: stageWidth, alignment: .center)
            .zIndex(1)
            }
            .frame(height: layout.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.height)
        .onAppear {
            if states.count != items.count {
                states = Array(repeating: SwingState(), count: items.count)
            }
            syncMotion()
        }
        // ── 摇一摇：四种情况都会改变「该不该跑传感器」──
        .onChange(of: motionEnabled) { _, _ in syncMotion() }
        .onChange(of: scenePhase) { _, _ in syncMotion() }
        .onChange(of: items.count) { _, _ in
            if states.count != items.count {
                states = Array(repeating: SwingState(), count: items.count)
            }
            syncMotion()
        }
        .onChange(of: shake.event) { _, event in
            guard let event else { return }
            applyShake(accelX: event.accelX)
        }
        .onDisappear {
            shake.stop()
            linkProxy.stop()
        }
    }

    // MARK: 帧物理（H5 `rackTick()` / `rackKick()` 原样移植）

    /// 组装一张挂袋卡。
    /// ⚠️ 单独抽成显式类型标注的函数：初始化器参数多，内联在 ForEach 里
    ///    会让类型检查器超时（"unable to type-check in reasonable time"）。
    private func rackItem(_ index: Int, _ bag: BagItem) -> some View {
        let angleValue: Double = angle(index)
        let start: (Int) -> Void = { beginDrag($0) }
        let move: (Int, CGFloat) -> Void = { dragMove($0, dx: $1) }
        let end: (Int, CGFloat, TimeInterval, Bool) -> Void = {
            endDrag($0, dx: $1, held: $2, moved: $3)
        }
        let isActive = bag.id == selectedID
        return RackItemView(bag: bag,
                            index: index,
                            cardWidth: layout.cardW,
                            angle: angleValue,
                            isActive: isActive,
                            onDragStart: start,
                            onDragMove: move,
                            onDragEnd: end)
            // 原型 `.rack-item` 无 z-index（按顺序叠、后压前）+ `.is-active { z-index: 3 }`
            .zIndex(isActive ? 3 : 0)
    }

    private func ensurePhysicsRunning() {
        linkProxy.onStep = { physicsStep() }
        linkProxy.ensureRunning()
    }

    /// 固定 1/60s 步长的积分（与 H5 `rackTick()` 逐行对应）
    private func physicsStep() {
        var stillMoving = false
        for i in states.indices {
            // 拖拽中角度由手势直接控制。除逐卡标志外再比对视图级 `draggingIndex`：
            // 手势被系统取消时 `onEnded` 可能不触发，那面标志会残留，
            // 只靠它会把卡片永久冻住（历史上真的发生过）。
            guard i != draggingIndex, !states[i].dragging else { continue }
            if abs(states[i].velocity) > 0.02 || abs(states[i].angle) > 0.05 {
                states[i].velocity += -states[i].angle * 0.018   // 回复力：越偏离基准角越想弹回去
                states[i].velocity *= 0.952                      // 空气阻尼：让摆动逐渐停下来
                states[i].angle += states[i].velocity
                if states[i].angle > 26 { states[i].angle = 26; states[i].velocity *= -0.45 }
                if states[i].angle < -26 { states[i].angle = -26; states[i].velocity *= -0.45 }
                stillMoving = true
            } else if states[i].angle != 0 || states[i].velocity != 0 {
                states[i].angle = 0
                states[i].velocity = 0
            }
        }
        if !stillMoving { linkProxy.stop() }   // 全部静止即停表（H5 同款）
    }

    private func angle(_ i: Int) -> Double {
        i < states.count ? states[i].angle : 0
    }

    // MARK: 拨动手势上报（对应 H5 的 pointer 事件三支）

    /// pointerdown：进入 dragging，速度清零
    private func beginDrag(_ index: Int) {
        guard index < states.count else { return }
        // 一指只能按一张：顺手清掉别的卡可能残留的 dragging 标志。
        // （手势被系统取消时 `onEnded` 不一定触发，那面标志会残留，
        //   而帧物理靠它决定「这张卡要不要参与积分」—— 早先因此冻住过卡片。）
        for i in states.indices where i != index { states[i].dragging = false }
        states[index].dragging = true
        states[index].velocity = 0
        draggingIndex = index
    }

    /// pointermove：角度 = 视觉位移 × 0.4，限位 ±75°，直接跟手（不过积分器，与 H5 一致）
    private func dragMove(_ index: Int, dx: CGFloat) {
        guard index < states.count else { return }
        // 全屏铺满后没有外层缩放，手势位移就是视觉位移
        let visualDx = dx
        let mapped = min(RackMetrics.dragLimitDeg,
                         max(-RackMetrics.dragLimitDeg, visualDx * RackMetrics.dragFactor))
        states[index].angle = mapped
    }

    /// pointerup：按 H5 判定分流轻点 / 拨动松手
    private func endDrag(_ index: Int, dx: CGFloat, held: TimeInterval, moved: Bool) {
        draggingIndex = nil
        guard index < states.count else { return }

        // ⚠️⚠️ 先把 dragging 放下 —— H5 `pointerup` 的**第一句**就是
        //     `state.dragging = false`。漏掉它，帧物理里的
        //     `guard !states[i].dragging else { continue }` 会让这张卡
        //     **永久退出积分**：轻点不荡（用户反馈的「点挂袋不左右晃动」就是这个）、
        //     拨动松手也不回弹，而且只有碰过的那张坏掉，看着像随机失灵。
        states[index].dragging = false

        if !moved && held < RackMetrics.tapHoldLimit {
            // 轻点：先荡一下（velocity += 7），再把这张卡送到上方主卡位（主从联动）
            states[index].angle = 0
            states[index].velocity += 7
            ensurePhysicsRunning()
            // ⚠️ 起摆的**第一帧立刻算掉**（不等下一次 vsync）：点击即刻见动。
            physicsStep()

            // ⚠️ 主卡切换必须**让开起摆的头几帧**：它会让整个首页重新求值
            //    （`.id(heroBag?.id)` 重建主卡 + 档案架整排重绘），实测占主线程约 28ms。
            //    放在同一帧里，起摆的「点击 → 首个积分」会被拖到 58ms，用户感受到的
            //    就是「点了要等一下才开始晃」。往后挪 50ms（约 3 帧）：起摆当帧就动、
            //    一路 60fps，主卡晚 50ms 切换 —— 这个延迟肉眼看不出来。
            if index < items.count {
                let bag = items[index]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { onSelect(bag) }
            }
            return
        }

        // 拨动松手：角度收进 ±26°（×0.3），往反方向弹回（velocity = −angle × 0.35）
        states[index].angle = min(RackMetrics.releaseLimitDeg,
                                  max(-RackMetrics.releaseLimitDeg, states[index].angle * 0.3))
        states[index].velocity = -states[index].angle * 0.35
        ensurePhysicsRunning()
        physicsStep()   // 当帧起算，别等下一次 vsync（口径同轻点）
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

    /// 把一次晃动摊到每一张卡片上（H5 `handleDeviceMotion()` 同一口径）：
    /// `velocity += shakeForce × 0.3 × dir`，其中 `shakeForce = acc.x × 0.9`，
    /// 相邻卡片方向交错（`dir = i % 2 == 0 ? 1 : -1`）。
    /// ⚠️ 单位换算：H5 的 devicemotion 加速度是 m/s²，`CMDeviceMotion` 给的是 g，×9.81。
    private func applyShake(accelX: Double) {
        let shakeForce = accelX * 9.81 * 0.9
        for i in items.indices where i != draggingIndex {
            let dir: Double = i % 2 == 0 ? 1 : -1
            guard i < states.count else { continue }
            states[i].velocity += shakeForce * 0.3 * dir
        }
        ensurePhysicsRunning()
    }

    // 📌 上一版这里有一支 `clipDropY(index:layout:)`：按绳索贝塞尔曲线求出
    //    每张卡的孔环该落在绳索哪一点（H5 `alignClipsToRope()` 的解析等价）。
    //    换成刚性展示杆后，**所有轮心都在同一条水平杆轴上**（44.02×s），
    //    整套数学随之删除 —— 吊卡自己就能定位（见 `RackItemView`）。
}

// MARK: - 亚克力展示杆

/// 横杆：**刚性亚克力展示杆** + 两端银钢五金（原型 ⑩⑪㉔㉕㉗，取代上一版的麻绳）。
///
/// 原型把「下垂钢索」换成了展示杆，**杆轴 = 轮心**（卡框顶上方 44.02px），
/// 于是滑轮天然压在杆轴上 —— 不再需要按贝塞尔求「孔环落在绳索哪一点」，
/// 上一版的 `ropeY(atFraction:)` 那套数学整段删除。
///
/// ⚠️ 这一层画在**舞台整宽**上（原型 `.rack-cable { left:0; right:0 }`），
///    内部各自内缩：杆体 24 / 夹块 17 / 螺纹杆 6 / 朱红球 1 —— 越靠外越小件，
///    最外沿的红球离边只剩 1×scale，所以「横杆铺满屏幕」依旧成立。
private struct RackRailView: View {
    /// 舞台整宽
    let stageWidth: CGFloat
    /// 五金缩放（`RackMetrics.hardwareScale(cardWidth)`）
    let scale: CGFloat

    /// 杆体净宽（左右各让出 `railInset`）
    private var railWidth: CGFloat { stageWidth - RackMetrics.railInset * scale * 2 }
    /// 芥黄 #F0B425
    private var railColor: Color { Color(red: 240/255, green: 180/255, blue: 37/255) }

    var body: some View {
        ZStack {
            rail
            fittings(inset: RackMetrics.endcapInset) { endcap }
            fittings(inset: RackMetrics.studInset) { stud }
            fittings(inset: RackMetrics.knobInset) { knob }
        }
        .frame(width: stageWidth, height: RackMetrics.endcapHeight * scale)
        .allowsHitTesting(false)
    }

    /// 左右各一颗同样的件（原型左右同款、未做镜像），三者都按杆轴垂直居中
    private func fittings<C: View>(inset: CGFloat,
                                   @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
            content()
        }
        .padding(.horizontal, inset * scale)
    }

    // ── 杆体：半透亚克力（`color-mix` 逐档折算成 srgb 渐变）+ 四缘棱光 + 顶部高光条 ──

    private var rail: some View {
        RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
            .fill(
                LinearGradient(stops: [
                    // color-mix(#F0B425 45%, #fff) = #F8DD9D
                    .init(color: Color(red: 248/255, green: 221/255, blue: 157/255), location: 0),
                    .init(color: railColor.opacity(0.68), location: 0.28),
                    .init(color: railColor.opacity(0.86), location: 0.64),
                    .init(color: railColor.opacity(0.52), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            // `backdrop-filter: blur(3px) saturate(1.25)` —— 杆是半透的，透出被模糊的底
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 2.5 * scale))
            }
            // 四缘棱光：上 `inset 0 1px 0 rgba(255,255,255,.85)`、下 `0 -1px 1px .28`
            .overlay {
                RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
                    .strokeBorder(
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.85), location: 0),
                            .init(color: .white.opacity(0), location: 0.12),
                            .init(color: .white.opacity(0), location: 0.86),
                            .init(color: .white.opacity(0.28), location: 1)
                        ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            // 左右 `inset 1.6px 0 2px rgba(255,255,255,.42)`
            .overlay {
                RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
                    .strokeBorder(
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.42), location: 0),
                            .init(color: .white.opacity(0), location: 0.12),
                            .init(color: .white.opacity(0), location: 0.88),
                            .init(color: .white.opacity(0.42), location: 1)
                        ], startPoint: .leading, endPoint: .trailing), lineWidth: 1.6)
            }
            // 顶部高光条：`left 5% / right 34% / top 1.4 / 高 2.8`
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                    .fill(
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.60), location: 0.20),
                            .init(color: .white.opacity(0.42), location: 0.60),
                            .init(color: .white.opacity(0), location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 2.8 * scale)
                    .padding(.leading, max(0, railWidth * 0.05))
                    .padding(.trailing, max(0, railWidth * 0.34))
                    .padding(.top, 1.4 * scale)
            }
            .shadow(color: Color(red: 90/255, green: 60/255, blue: 10/255).opacity(0.14),
                    radius: 2 * scale, x: 0, y: 2 * scale)
            .frame(width: railWidth, height: RackMetrics.railHeight * scale)
    }

    // ── 端部夹块：9 × 13.5，不锈钢 conic 拉丝 + 上白下暗 ──

    private var endcap: some View {
        RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
            .fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.55), location: 0),
                    .init(color: .white.opacity(0), location: 0.30),
                    .init(color: .black.opacity(0.18), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .background { brushedSteel(cornerRadius: 2 * scale) }
            .overlay {
                RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                    .strokeBorder(.white.opacity(0.60), lineWidth: 0.5 * scale)
            }
            .frame(width: RackMetrics.endcapWidth * scale,
                   height: RackMetrics.endcapHeight * scale)
            .shadow(color: .black.opacity(0.40), radius: 1 * scale, x: 0, y: 1 * scale)
    }

    /// 不锈钢 conic 拉丝（原型 `conic-gradient(from 210deg at 30% 22%, …)`）
    /// ⚠️ CSS 的 0° 在**正上方**、SwiftUI 在**正右方**，所以起始角要减 90°。
    private func brushedSteel(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 244/255, green: 246/255, blue: 248/255), location: 0),
                        .init(color: Color(red: 195/255, green: 202/255, blue: 209/255), location: 0.25),
                        .init(color: Color(red: 151/255, green: 161/255, blue: 171/255), location: 0.50),
                        .init(color: Color(red: 213/255, green: 220/255, blue: 226/255), location: 0.75),
                        .init(color: Color(red: 244/255, green: 246/255, blue: 248/255), location: 1)
                    ]),
                    center: .init(x: 0.30, y: 0.22),
                    angle: .degrees(120)
                )
            )
    }

    // ── 外伸螺纹杆：13 × 3.2（车螺纹纹理 + 上白下灰）──

    private var stud: some View {
        RoundedRectangle(cornerRadius: 1.6 * scale, style: .continuous)
            .fill(Color(red: 195/255, green: 204/255, blue: 213/255))
            .overlay { threadTexture }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.85), location: 0),
                    .init(color: Color(red: 122/255, green: 134/255, blue: 146/255).opacity(0.55),
                          location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(.rect(cornerRadius: 1.6 * scale))
            .frame(width: RackMetrics.studWidth * scale,
                   height: RackMetrics.studHeight * scale)
            .shadow(color: Color(red: 40/255, green: 48/255, blue: 58/255).opacity(0.30),
                    radius: 1 * scale, x: 0, y: 1 * scale)
    }

    /// `repeating-linear-gradient(90deg, transparent 0 1.5px, rgba(96,108,120,.55) 1.5px 2.4px)`
    private var threadTexture: some View {
        Canvas { context, size in
            let step = 2.4 * scale
            let width = 0.9 * scale
            var x = 1.5 * scale
            while x + width < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                             with: .color(Color(red: 96/255, green: 108/255, blue: 120/255)
                                 .opacity(0.55)))
                x += step
            }
        }
    }

    // ── 朱红圆球头：⌀8.5 光面亚克力珠（穹面渐变 + 锐高光点 + 右下次反光）──

    private var knob: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(stops: [
                        .init(color: Color(red: 255/255, green: 138/255, blue: 112/255), location: 0),
                        .init(color: Color(red: 226/255, green: 60/255, blue: 45/255), location: 0.55),
                        .init(color: Color(red: 163/255, green: 36/255, blue: 21/255), location: 1)
                    ], center: .init(x: 0.35, y: 0.30), startRadius: 0,
                       endRadius: RackMetrics.knobDiameter * scale * 0.58)
                )
                .overlay {
                    Circle().strokeBorder(
                        Color(red: 150/255, green: 25/255, blue: 12/255).opacity(0.40),
                        lineWidth: 0.6 * scale)
                }
            // 锐高光点：left 19% / top 17% / 26%
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 2.21 * scale, height: 2.21 * scale)
                .offset(x: 1.62 * scale, y: 1.44 * scale)
            // 次反光：left 60% / bottom 20% / 14%
            Circle()
                .fill(.white.opacity(0.40))
                .frame(width: 1.19 * scale, height: 1.19 * scale)
                .offset(x: 5.1 * scale, y: 5.61 * scale)
        }
        .frame(width: RackMetrics.knobDiameter * scale,
               height: RackMetrics.knobDiameter * scale)
        .shadow(color: Color(red: 120/255, green: 20/255, blue: 10/255).opacity(0.35),
                radius: 1.75 * scale, x: 0, y: 2 * scale)
    }
}

// MARK: - 单张吊卡

/// 一张吊卡：**滑轮 + 吊线 + 夹具 + 卡框 + 文字区**（原型 `.rack-item`）。
///
/// 摆动绕**轮心**（卡框顶之上 44.02px，= 亚克力杆轴心）—— 原型
/// `.swing { transform-origin: 50% -44.02px }`，卡片像挂在杆上摆，
/// 轮心始终钉在杆轴上（原型 ②「轮心压杆心、沿杆滑动」）。
/// SwiftUI 用 `rotationEffect(anchor:)` 表达：`anchor.y = −44.02×s / 单卡总高`。
///
/// ⚠️ 分层要点：`--dy` 只作用于**卡框与夹具**（原型 `margin-top` 与 `.grip{top}`），
///    滑轮与吊线的上端永远钉在轴心 —— 所以五金挂在**未下沉**的卡顶之上，
///    吊线长度 = 36.52 + dy，夹具顶 = dy − 7.5，三者自动自洽。
private struct RackItemView: View {
    let bag: BagItem
    let index: Int
    let cardWidth: CGFloat
    let angle: Double
    let isActive: Bool
    /// pointerdown：进入 dragging（父级清零速度，摇一摇跳过这张卡）
    var onDragStart: (Int) -> Void = { _ in }
    /// pointermove：上报原始 dx，父级按「dx × 0.4、限位 ±75°」直接写角度
    var onDragMove: (Int, CGFloat) -> Void = { _, _ in }
    /// pointerup：上报 dx / 按住时长 / 是否移动过，父级分流「轻点」与「拨动松手」
    var onDragEnd: (Int, CGFloat, TimeInterval, Bool) -> Void = { _, _, _, _ in }

    /// 拖动过程中累计的角度由父级 `angles` 承载，这里只记手势元信息
    @State private var didDrag = false
    @State private var pressStart: Date?
    /// 上一次「拨动路径」结束的时刻 —— 用来屏蔽「按住后原地松手」时
    /// `.onTapGesture` 的重复触发（那条路径已经自己走过轻点分支了）。
    @State private var lastSwingEnd: Date?

    private var s: CGFloat { RackMetrics.hardwareScale(cardWidth) }

    /// 本张的 `--dy`：错落 0/7/14/7，选中再上浮 4（原型 `--dy: calc(dy-base − lift)`）
    private var dy: CGFloat {
        RackMetrics.dropOffset(index) * s - (isActive ? RackMetrics.activeLift * s : 0)
    }
    /// 单卡总高（框 + 文字区）
    private var itemHeight: CGFloat { RackMetrics.itemHeight(cardWidth: cardWidth) }

    var body: some View {
        ZStack(alignment: .top) {
            // ── 卡框 + 文字区：参与布局、撑出单卡高度 ──
            VStack(spacing: 0) {
                RackFrame(bag: bag, cardWidth: cardWidth, isActive: isActive)
                meta
            }
            // 原型 `.rack-frame { margin-top: var(--dy) }`：整框下沉，五金不动
            .offset(y: dy)

            // ── 悬挂五金：一律挂在「未下沉」的卡顶之上 ──
            // 吊线：轮心（−44.02）垂到夹具顶（dy − 7.5），长度天然 = 36.52 + dy
            RackWireView(scale: s, drop: dy)
                .offset(y: -RackMetrics.pivotAbove * s)
            // 夹具：咬住（下沉后的）卡顶 7.5px
            GripView(scale: s, isActive: isActive)
                .offset(y: dy - RackMetrics.gripBite * s)
            // 滑轮：盒中心 = 轮心 = 轴心（盒顶 = −44.02 − 盒边长/2）
            PulleyView(scale: s, isActive: isActive)
                .offset(y: -(RackMetrics.pivotAbove + RackMetrics.pulleyBox / 2) * s)
        }
        .frame(width: cardWidth, height: itemHeight, alignment: .top)
        // 摆动：绕**轮心**（轴心在卡片顶边之上，所以 anchor.y 是负数）
        .rotationEffect(.degrees(RackMetrics.baseAngle(index) + angle),
                        anchor: UnitPoint(x: 0.5,
                                          y: -RackMetrics.pivotAbove * s / max(itemHeight, 1)))
        .contentShape(.rect)
        // ── 手势分三路（按需求）──
        //    普通拖动 = 横向滚动 ｜ 长按后拖动 = 拨动卡片摆动 ｜ 轻点 = 切上方主卡
        // ⚠️ `highPriorityGesture` 必须留着：长按成立之后得由卡片接管拖动，
        //    否则外层 `ScrollView` 会把这一段也抢去滚动。
        .highPriorityGesture(swingGesture)
        .onTapGesture {
            // 轻点：走 H5 的 pointerup 轻点分支（先荡一下、再把这张卡送到主卡位）。
            // ⚠️ 时间戳挡重复：按住后原地松手时，拨动手势那边也会走同一条分支。
            if let t = lastSwingEnd, Date.now.timeIntervalSince(t) < 0.12 { return }
            onDragEnd(index, 0, 0, false)
        }
    }

    /// 文字区：标题 = 卡宽 × .118（原型 Georgia/serif，iOS 走随包宋体）、
    /// 副行 = × .082、上垫 = × .064、左右各 3px（注意顺序：内边距在固定宽度**之内**，
    /// 与原型 `box-sizing: border-box` 同口径）。
    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bag.displayName)
                .font(AppFont.songti(cardWidth * RackMetrics.metaTitleRatio))
                .foregroundStyle(isActive
                                 ? Color(red: 138/255, green: 90/255, blue: 16/255)
                                 : Color(red: 74/255, green: 58/255, blue: 34/255))
                .lineLimit(1)
                .truncationMode(.tail)

            Text("\(bag.displayShelf) · \(DateFormat.monthDayDot(bag.createdAt))")
                .font(.system(size: cardWidth * RackMetrics.metaSubRatio))
                .foregroundStyle(Color(red: 160/255, green: 146/255, blue: 116/255))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, RackMetrics.metaPadH * s)
        .padding(.top, cardWidth * RackMetrics.metaPadTopRatio)
        .frame(width: cardWidth, alignment: .leading)
    }

    // MARK: 摆动

    /// 拨动手势：**长按成立之后**才接管拖动
    /// （`LongPressGesture.sequenced(before: DragGesture)`）。
    ///
    /// 📌 为什么不能再用「落指即拖」：挂架区现在可以横向滚动，
    ///    `DragGesture(minimumDistance: 0)` 会把落在**卡片上**的横向拖动
    ///    全部吃掉，滚动就永远轮不到。推迟接管时机之后三路自然分开：
    ///      · 快速滑动：手指在 `swingHoldSlop`(10pt) 内没停够 `swingHold`(0.25s)
    ///        ⇒ 长按失败 ⇒ **整条手势失败 ⇒ 外层 `ScrollView` 横向滚动**；
    ///      · 按住 0.25s 再拖：长按成立、卡片接管，位移全喂给拨动物理；
    ///      · 轻点：长按与拖动都不成立 ⇒ 交给 `.onTapGesture`（见 `body`）。
    ///
    /// 角度与速度仍全部上报父级、由 `RackStage` 的帧物理接管；
    /// 松手时按 H5 pointerup 的判定分流轻点 / 拨动（见 `RackStage.endDrag`）。
    private var swingGesture: some Gesture {
        LongPressGesture(minimumDuration: RackMetrics.swingHold,
                         maximumDistance: RackMetrics.swingHoldSlop)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    // 长按刚成立：进入 dragging（父级清零速度、摇一摇跳过这张卡）
                    if pressStart == nil {
                        pressStart = .now
                        onDragStart(index)
                    }
                case .second(true, let drag):
                    // 长按成立后的拖动段：跟手写角度
                    if pressStart == nil {
                        pressStart = .now
                        onDragStart(index)
                    }
                    if let drag {
                        if abs(drag.translation.width) > RackMetrics.tapMoveThreshold { didDrag = true }
                        // 函数类型的属性调用不能带参数标签
                        onDragMove(index, drag.translation.width)
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                var dx: CGFloat = 0
                if case .second(true, let drag) = value, let drag { dx = drag.translation.width }
                // ⚠️ `held` 从「长按成立」那一刻算起（不再是落指时刻）：它的作用只剩
                //    区分「按住后原地松手（走轻点分支）」与「拖过再松手（走拨动分支）」。
                let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? .infinity
                pressStart = nil
                let moved = didDrag || abs(dx) > RackMetrics.tapMoveThreshold
                didDrag = false
                lastSwingEnd = .now
                onDragEnd(index, dx, held, moved)
            }
    }

}

// MARK: - 滑环滑轮 / 吊线 / 夹具

/// 滑环式滑轮（原型 ⑰㉓㉕）：**细环 + 两根横臂 + 黄珠轮心**，杆从环心穿过。
///
/// 结构全部按原型 px（盒 21.496 = viewBox 19.541 × 1.1，`d = 盒边长 / 21.496`）：
///   外环 r8.47 / 宽 3.74（银钢线性渐变）· 横臂 1.21 宽 ×2 · 内环 r6.49 / 0.77
///   · 黄珠 r2.42（穹面 `#F9D86C→#F0B425→#C08C10` + 描边 `#E2AC1E→#8F6B0B`）
///   · 锐高光 r0.66 · 次反光 r0.35 · 外圈两道细边（白 .75 / 深 .32）
///
/// 选中态（原型 ⑯⑲）：轮心圆变红 `#c50205`（描边 `#8f0204`），
/// 外侧再套一圈 1px 白细亮边（`inset:-1.2px`、0.25s 淡入）。
private struct PulleyView: View {
    let scale: CGFloat
    var isActive: Bool = false

    private var size: CGFloat { RackMetrics.pulleyBox * scale }
    /// 原型 px → 本视图点：盒边长 21.496 为 1
    private var d: CGFloat { size / 21.496 }

    private var steelRing: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(red: 252/255, green: 253/255, blue: 254/255), location: 0),
            .init(color: Color(red: 238/255, green: 243/255, blue: 247/255), location: 0.26),
            .init(color: Color(red: 216/255, green: 224/255, blue: 231/255), location: 0.58),
            .init(color: Color(red: 186/255, green: 195/255, blue: 204/255), location: 0.82),
            .init(color: Color(red: 157/255, green: 167/255, blue: 177/255), location: 1)
        ], startPoint: .init(x: 0.24, y: 0.06), endPoint: .init(x: 0.78, y: 0.96))
    }

    var body: some View {
        ZStack {
            // 外环：r8.47、宽 3.74（`.stroke` 是描边居中，与 SVG 同心圆一致）
            Circle()
                .stroke(steelRing, lineWidth: 3.74 * d)
                .frame(width: 16.94 * d + 3.74 * d, height: 16.94 * d + 3.74 * d)

            // 两根横臂（`M7.371 9.771H4.021` / `M12.171 9.771H15.521`，宽 1.1、圆头）
            Capsule()
                .fill(Color(red: 154/255, green: 164/255, blue: 174/255))
                .frame(width: 3.69 * d, height: 1.21 * d)
                .offset(x: -4.478 * d)
            Capsule()
                .fill(Color(red: 154/255, green: 164/255, blue: 174/255))
                .frame(width: 3.69 * d, height: 1.21 * d)
                .offset(x: 4.478 * d)

            // 内环：r5.9、宽 0.7
            Circle()
                .stroke(Color(red: 112/255, green: 124/255, blue: 136/255).opacity(0.5),
                        lineWidth: 0.7 * d)
                .frame(width: 11.8 * d + 0.7 * d, height: 11.8 * d + 0.7 * d)

            // 黄珠轮心：r2.2（选中变红）
            Circle()
                .fill(
                    RadialGradient(stops: [
                        .init(color: isActive
                               ? RackMetrics.activeRed
                               : Color(red: 249/255, green: 216/255, blue: 108/255), location: 0),
                        .init(color: isActive
                               ? RackMetrics.activeRed
                               : Color(red: 240/255, green: 180/255, blue: 37/255), location: 0.55),
                        .init(color: isActive
                               ? RackMetrics.activeRed
                               : Color(red: 192/255, green: 140/255, blue: 16/255), location: 1)
                    ], center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 3.4 * d)
                )
                .overlay {
                    Circle().strokeBorder(
                        isActive
                        ? Color(red: 143/255, green: 2/255, blue: 4/255)
                        : Color(red: 226/255, green: 172/255, blue: 30/255),
                        lineWidth: 0.8 * d)
                }
                .frame(width: 4.4 * d, height: 4.4 * d)

            // 锐高光点（cx8.95 cy8.9 r0.6）与右下次反光（cx10.55 cy10.6 r0.32）
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 1.32 * d, height: 1.32 * d)
                .offset(x: -0.90 * d, y: -0.96 * d)
            Circle()
                .fill(.white.opacity(0.40))
                .frame(width: 0.7 * d, height: 0.7 * d)
                .offset(x: 0.86 * d, y: 0.91 * d)

            // 外圈两道细边：r8.905（白 .75 / 0.55）与 r9.325（深 .32 / 0.5）
            Circle()
                .stroke(Color.white.opacity(0.75), lineWidth: 0.55 * d)
                .frame(width: 17.81 * d + 0.55 * d, height: 17.81 * d + 0.55 * d)
            Circle()
                .stroke(Color(red: 88/255, green: 100/255, blue: 112/255).opacity(0.32),
                        lineWidth: 0.5 * d)
                .frame(width: 18.65 * d + 0.5 * d, height: 18.65 * d + 0.5 * d)
        }
        .frame(width: size, height: size)
        // 选中：一圈白细亮边（`.rack-clip::after`，inset −1.2）
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                .frame(width: size + 2.4 * d, height: size + 2.4 * d)
                .opacity(isActive ? 1 : 0)
        }
    }
}

/// 吊线（原型 `.rack-wire`）：轮心垂到夹具顶，**长度 = 36.52 + dy**，
/// 三段银灰渐变。dy 变（错落 / 选中上浮）时线跟着伸缩，夹具随之上移。
private struct RackWireView: View {
    let scale: CGFloat
    /// `--dy`（已含选中上浮、已缩放）
    let drop: CGFloat

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(stops: [
                    .init(color: Color(red: 185/255, green: 193/255, blue: 201/255), location: 0),
                    .init(color: Color(red: 238/255, green: 242/255, blue: 245/255), location: 0.42),
                    .init(color: Color(red: 167/255, green: 176/255, blue: 184/255), location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: RackMetrics.wireWidth * scale,
                   height: RackMetrics.wireBase * scale + drop)
    }
}

/// 夹具（原型 `.grip`）：银钢、**咬住卡顶 7.5px**，下沿有咬口、中部一道横线、上部一颗铆珠。
///
/// 📌 表面处理选定 **卡3 喷砂哑光**（原型第 ㉖ 条给的四方案对比页的结论）：
///    低反差漫射渐变，内高光/暗边都比镜面铬档含蓄一档。
private struct GripView: View {
    let scale: CGFloat
    var isActive: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(stops: [
                    .init(color: Color(red: 242/255, green: 245/255, blue: 247/255), location: 0),
                    .init(color: Color(red: 223/255, green: 229/255, blue: 234/255), location: 0.30),
                    .init(color: Color(red: 203/255, green: 212/255, blue: 219/255), location: 0.64),
                    .init(color: Color(red: 176/255, green: 186/255, blue: 195/255), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            // inset 高光 / 暗边（喷砂档：上 .70、右 .28）
            .overlay {
                shape.strokeBorder(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.70), location: 0),
                        .init(color: .white.opacity(0.20), location: 0.25),
                        .init(color: Color(red: 120/255, green: 132/255, blue: 144/255).opacity(0.28),
                              location: 1)
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 0.7 * scale)
            }
            // `::before`：top 5.6、左右各 1.4 的一道横线
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(red: 112/255, green: 124/255, blue: 136/255).opacity(0.5))
                    .frame(height: 1 * scale)
                    .padding(.horizontal, 1.4 * scale)
                    .padding(.top, 5.6 * scale)
            }
            // `::after`：top 2.0 的一颗铆珠（2.8 × 1.9）
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(
                        RadialGradient(stops: [
                            .init(color: Color(red: 253/255, green: 254/255, blue: 254/255), location: 0),
                            .init(color: Color(red: 174/255, green: 184/255, blue: 194/255), location: 0.62),
                            .init(color: Color(red: 135/255, green: 145/255, blue: 155/255), location: 1)
                        ], center: .init(x: 0.34, y: 0.30), startRadius: 0, endRadius: 1.5 * scale)
                    )
                    .frame(width: 2.8 * scale, height: 1.9 * scale)
                    .padding(.top, 2.0 * scale)
            }
            // `.mouth`：底 3.4 的咬口
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1 * scale, style: .continuous)
                    .fill(
                        LinearGradient(stops: [
                            .init(color: Color(red: 120/255, green: 132/255, blue: 144/255).opacity(0.65),
                                  location: 0),
                            .init(color: Color(red: 72/255, green: 84/255, blue: 96/255).opacity(0.85),
                                  location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 1.9 * scale)
                    .padding(.horizontal, 1.4 * scale)
                    .padding(.bottom, 3.4 * scale)
            }
            .frame(width: RackMetrics.gripWidth * scale,
                   height: RackMetrics.gripHeight * scale)
            .shadow(color: Color(red: 46/255, green: 56/255, blue: 66/255).opacity(0.26),
                    radius: 1.5 * scale, x: 0, y: 1.2 * scale)
    }
}

// MARK: - 卡框（磨砂玻璃 + 四角螺点 + 照片）

/// 卡框：**磨砂玻璃边框** + 四角螺点（原型 ③④⑳㉑）。
///
/// 📌 与上一版的三处差别（都是原型明确要求的）：
///   ① 照片区**不再铺六色纸底**（原型 ④）—— 真图直接落在玻璃卡内的透明底上；
///      这也根治了之前「卡片背景色整体不太搭」的观感问题。
///   ② 描边从「金/棕 1.5pt」换成 `1px rgba(255,255,255,.55)`，圆角 4 → **6**，
///      选中标识改为**红环** `#c50205`（`RackMetrics.activeRed`）。
///   ③ 四角各一颗 **⌀4 不锈钢螺点**。
private struct RackFrame: View {
    let bag: BagItem
    let cardWidth: CGFloat
    let isActive: Bool

    private var s: CGFloat { RackMetrics.hardwareScale(cardWidth) }
    /// 照片区高 = 卡宽 × `RackMetrics.photoHeightRatio`（原型 `.rack-photo`，现 1.36）
    private var photoHeight: CGFloat { cardWidth * RackMetrics.photoHeightRatio }
    /// 照片区宽 = 框宽 − 左右内边距与描边
    private var photoWidth: CGFloat {
        cardWidth - (RackMetrics.framePadding * s + 1) * 2
    }
    /// 框整体高（照片 + 上下内边距与描边）—— 四角螺点定位要用
    private var frameHeight: CGFloat {
        photoHeight + (RackMetrics.framePadding * s + 1) * 2
    }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RackMetrics.frameRadius * s, style: .continuous)
    }

    var body: some View {
        // 走缩略图缓存：最多同时 6 张、尺寸小，避免每次摆动重解码；
        // `ThumbnailImage` 同时兼容「磁盘真实图」与「Assets 演示图」。
        ThumbnailImage(fileName: bag.imageFileName,
                       size: RackMetrics.layoutWidth * 2,
                       contentMode: .fit,
                       interpolation: .high)
            // 📌 真图：**居中 + 按自身比例**（用户确认，不照抄原型里那条
            //    「宽 84% / 比例 92:132 / 靠左」—— 那是纯 CSS 占位纸袋的规格）。
            //
            // ⚠️ 也不回到 H5 老版的「靠左」：iPad 全屏后卡宽会按容器放大，
            //    袋子只占框的一部分，靠左会明显偏在一侧、不像「挂」在框里。
            //
            // 📌 按需求「袋子别挤满卡片」：高度只用到照片区的
            //    `RackMetrics.photoImageHeightRatio`（现 0.88），
            //    袋子不再顶到照片区上下沿，四周留出呼吸空间。
            .frame(maxWidth: photoWidth,
                   maxHeight: photoHeight * RackMetrics.photoImageHeightRatio,
                   alignment: .center)
            .frame(width: photoWidth, height: photoHeight, alignment: .center)
            .clipShape(.rect(cornerRadius: 2 * s))
            .padding(RackMetrics.framePadding * s)
            .background { glass }
            .clipShape(shape)
            .overlay { border }
            .overlay { screws }
            // `0 4px 14px rgba(60,52,40,.16)`（CSS blur 14 → radius 7）
            .shadow(color: Color(red: 60/255, green: 52/255, blue: 40/255).opacity(0.16),
                    radius: 7 * s, x: 0, y: 4 * s)
            // 选中：红环 1.5px + 红晕 —— 原型 `.is-active .rack-frame`：
            // ```css
            // box-shadow:0 0 0 1.5px #c50205, 0 6px 16px rgba(150,10,10,.28), …
            // ```
            // 📌 关键在 `0 0 0 1.5px` 是**向外扩**的 —— box-shadow 只画在**边框盒之外**，
            //    一点不压卡面。原来用 `strokeBorder` 把红环画在卡**内侧**，红环连同红晕
            //    正好糊住四角螺点（看起来就是「螺点位置不对 / 质感发红」）。
            //    这里把圆角矩形先向外撑 1.5 再画内描边 ⇒ 等价于「外侧 1.5px 红环」，
            //    圆角同步 +1.5 保持同心、视觉半径不变。
            .overlay {
                if isActive {
                    // ⚠️ 必须用 `inset(by: -1.5)` 把**图形本身**外扩；
                    //    先前写 `.padding(-1.5)` 只改视图尺寸、图形仍画在原位，
                    //    红环其实还压在卡面（四角螺点上）—— 实测红环外沿只比卡沿外 0.2pt。
                    RoundedRectangle(cornerRadius: RackMetrics.frameRadius * s, style: .continuous)
                        .inset(by: -1.5)
                        .strokeBorder(RackMetrics.activeRed, lineWidth: 1.5)
                        .shadow(color: Color(red: 150/255, green: 10/255, blue: 10/255).opacity(0.28),
                                radius: 8 * s, x: 0, y: 6 * s)
                }
            }
    }

    /// 玻璃底：`linear-gradient(160deg, rgba(255,255,255,.42) 0%, .18 48%, rgba(240,236,229,.30) 100%)`
    /// + `backdrop-filter: blur(7px) saturate(135%)` → `.ultraThinMaterial` 打底
    private var glass: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(stops: [
                .init(color: .white.opacity(0.42), location: 0),
                .init(color: .white.opacity(0.18), location: 0.48),
                .init(color: Color(red: 240/255, green: 236/255, blue: 229/255).opacity(0.30),
                      location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// 描边：`1px solid rgba(255,255,255,.55)` + 上下两道 inset 高光
    /// （`.85` 贴顶、`.28` 贴底；SwiftUI 没有 inset shadow，用细描边带顶替）
    private var border: some View {
        ZStack {
            shape.strokeBorder(.white.opacity(0.55),
                               lineWidth: RackMetrics.frameBorderWidth)
            shape.strokeBorder(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.85), location: 0),
                    .init(color: .white.opacity(0), location: 0.06),
                    .init(color: .white.opacity(0), location: 0.94),
                    .init(color: .white.opacity(0.28), location: 1)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: RackMetrics.frameBorderWidth)
        }
    }

    /// 四角螺点：⌀4、距内边距盒 3（= 距卡框外沿 4，见 `RackMetrics.screwInset`）
    ///
    /// ⚠️ 这里的 overlay 坐标空间是**卡框外沿**（`.overlay` 挂在外框上），
    ///    而 CSS 的 `top:3px` 是从 padding box 量起 —— 所以要先补上描边那 1px。
    private var screws: some View {
        let edge = (RackMetrics.screwInset + RackMetrics.frameBorderWidth) * s
        let inset = edge + RackMetrics.screwDiameter * s / 2
        let dx = cardWidth / 2 - inset
        let dy = frameHeight / 2 - inset
        return ZStack {
            screw.offset(x: -dx, y: -dy)
            screw.offset(x: dx, y: -dy)
            screw.offset(x: -dx, y: dy)
            screw.offset(x: dx, y: dy)
        }
    }

    /// 单颗螺点 —— 逐行复刻 H5 `.rack-screw`（`挂袋区_轻量调试.html` 2026-09-25 18:36 版）：
    /// ```css
    /// .rack-screw{width:4px;height:4px;border-radius:50%;
    ///   background:
    ///     radial-gradient(circle at 34% 26%, rgba(255,255,255,.95) 0 12%, rgba(255,255,255,0) 34%),
    ///     radial-gradient(circle at 50% 50%, rgba(255,255,255,.9) 0 8%, rgba(255,255,255,0) 30%),
    ///     conic-gradient(from 210deg,#f4f6f8,#c3cad1 25%,#97a1ab 50%,#d5dce2 75%,#f4f6f8 100%);
    ///   box-shadow:0 .8px 1.6px rgba(0,0,0,.38), 0 .8px 2.4px rgba(0,0,0,.16),
    ///     inset 0 0 0 .5px rgba(255,255,255,.60), inset 0 -.5px 1px rgba(0,0,0,.30)}
    /// ```
    ///
    /// ⚠️ 三处最容易抄错、也是之前「质感不对」的根因：
    ///   ① **两层白高光的半径**。CSS 的 `circle at …` 默认按 `farthest-corner` 定尺寸 ——
    ///      以 `at 34% 26%` 为例，圆心到最远角（右下 100%,100%）的距离
    ///      = √(.66² + .74²) ≈ **0.9916 × 直径**；`at 50% 50%` 则是
    ///      √(.5² + .5²) ≈ **0.7071 × 直径**。原来写的是 0.12 / 0.08 倍直径，
    ///      小了 8~10 倍 ⇒ 高光缩成针尖、螺点整颗发平发白。
    ///      另外 CSS 的 `0 12%` 在 SwiftUI 里要落成**两个同色停点**（纯白到 12% 再衰减），
    ///      只写「0 → 34%」会把中心渲成渐变、高光发灰。
    ///   ② **投影是两层**（1.6px blur + 2.4px blur，`.38` / `.16`），原来只画了一层 `.30`。
    ///      按本文件惯例，CSS blur → SwiftUI radius 取一半（1.6→0.8、2.4→1.2）。
    ///   ③ **`inset 0 -.5px 1px rgba(0,0,0,.30)`**（底部内圈暗边）：SwiftUI 没有 inset shadow，
    ///      用「细描边 + 上透明/下黑的线性渐变」顶替 —— 与卡框 `border` 同一套做法。
    ///
    /// ⚠️ CSS 的 0° 在正上方、SwiftUI 在正右方，起始角要减 90°（210° → 120°）。
    private var screw: some View {
        let d = RackMetrics.screwDiameter * s
        return ZStack {
            // 底层：conic 拉丝环（冷银调）
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 244/255, green: 246/255, blue: 248/255), location: 0),
                        .init(color: Color(red: 195/255, green: 202/255, blue: 209/255), location: 0.25),
                        .init(color: Color(red: 151/255, green: 161/255, blue: 171/255), location: 0.50),
                        .init(color: Color(red: 213/255, green: 220/255, blue: 226/255), location: 0.75),
                        .init(color: Color(red: 244/255, green: 246/255, blue: 248/255), location: 1)
                    ]),
                    center: .center,
                    angle: .degrees(120)
                )
            )
            // 高光 ①：`circle at 34% 26%`，纯白到 12%、34% 消失（半径 0.9916·⌀）
            Circle().fill(
                RadialGradient(stops: [
                    .init(color: .white.opacity(0.95), location: 0),
                    .init(color: .white.opacity(0.95), location: 0.12),
                    .init(color: .white.opacity(0), location: 0.34)
                ], center: .init(x: 0.34, y: 0.26), startRadius: 0,
                   endRadius: d * 0.9916)
            )
            // 高光 ②：`circle at 50% 50%`，纯白到 8%、30% 消失（半径 0.7071·⌀）
            Circle().fill(
                RadialGradient(stops: [
                    .init(color: .white.opacity(0.90), location: 0),
                    .init(color: .white.opacity(0.90), location: 0.08),
                    .init(color: .white.opacity(0), location: 0.30)
                ], center: .center, startRadius: 0,
                   endRadius: d * 0.7071)
            )
            // 底部内圈暗边（顶替 CSS 的 inset 阴影）
            Circle()
                .strokeBorder(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0), location: 0.45),
                        .init(color: .black.opacity(0.30), location: 1)
                    ], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1 * s)
                .blur(radius: 0.5 * s)
                .clipShape(Circle())
            // `inset 0 0 0 .5px rgba(255,255,255,.60)`：一圈内白边
            Circle().strokeBorder(.white.opacity(0.60), lineWidth: 0.5 * s)
        }
        .frame(width: d, height: d)
        // 两层投影（CSS blur 取一半作 radius）
        .shadow(color: .black.opacity(0.38), radius: 0.8 * s, x: 0, y: 0.8 * s)
        .shadow(color: .black.opacity(0.16), radius: 1.2 * s, x: 0, y: 0.8 * s)
    }
}

// MARK: - 预览

#Preview {
    let bags = PreviewData.samples()
    let base = Feed.demoBase(bags)
    // 预览按 iPhone 宽度给容器宽（写法与 `ShelfView` 一致：宽度由外部传）
    ScrollView {
        RackSection(items: Feed.recent(bags, base: base, limit: Feed.rackMaxItems),
                    base: base,
                    selectedID: bags.first?.id,
                    containerWidth: 393)
            .padding(.vertical, 20)
    }
    .background(Color(red: 0.953, green: 0.953, blue: 0.969))
}
