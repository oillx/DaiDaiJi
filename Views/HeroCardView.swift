import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════
//  主展位：白色液态玻璃卡 + 3D 翻面
//
//  H5 对应文件：`袋袋集原型/index.html` 的 `.stage-section`、
//               `styles.css` 的 `.flip-card` / `.flip-face` / `.front-caption` / `.back-*`
//
//  设计要点（照抄 H5）：
//   · 卡面纯白、几乎无边框，靠极淡阴影浮起（液态玻璃质感）
//   · 正面只放袋子 + 下方一行品牌与「名字 · 日期」
//   · 右上角一束暖色斜光，像展柜射灯打下来
//   · 轻点卡片整体绕 Y 轴翻面，背面展示详细信息
//   · 翻面时卡片经过 90° 会有一瞬「变窄」（几何必然，用户已接受）
// ═══════════════════════════════════════════════════════════════

// MARK: - 尺寸常量（实测锁定，不可改）

enum HeroMetrics {
    static let cardWidth: CGFloat = 308
    static let cornerRadius: CGFloat = 26

    // ── iPhone 专属收矮（iPad 保持稿面值）──
    //
    // 📌 用户要求：**首页大卡在 iPhone 上矮一档、卡内袋子再小一圈，iPad 尺寸全部保持**。
    //
    // 卡片高度是**逐项相加**出来的（见 `HeroFrontView` 的版式注释）：
    //     348 = 18(上留白) + 248(袋子) + 8(间距) + 40(两行文字) + 4 + 12(提示) + 18(下留白)
    // 于是收矮拆成**两个独立旋钮**（都只作用在 iPhone 上）：
    //     · `phoneCardShrink` —— 卡片本身矮多少；
    //     · `phoneBagShrink`  —— 袋子矮多少（比卡片多收的那部分，会变成卡内留白）。
    // 上一轮两者同步收 28（348/248 → 320/220：整卡等比收矮，不留白）；
    // 这一轮只把袋子再收 30（→ 190），卡片高度保持 320 —— 见 `phoneBagShrink`。
    //
    // ⚠️ 判定用 `AppLayout.isPad`（机型，不是容器宽度）：iPhone 横屏最宽 956pt、
    //    iPad 竖屏 820pt，两者宽度区间重叠，靠宽度分不开。iPad 上这两个数恒为 0，
    //    于是 cardHeight 恒为 348、bagHeight 恒为 248，与改动前完全一致。
    /// 卡片在 iPhone 上的收矮量（稿面 348 → 320）。想回稿面值改成 0。
    static let phoneCardShrink: CGFloat = 28

    /// 袋子在 iPhone 上的收矮量（稿面 248 → **190**，即袋图比原来再小 30pt）。
    ///
    /// 📌 它比 `phoneCardShrink` 多收 30 —— 也就是「只把卡内的袋子调小、卡片保持 320」。
    ///    多出来的 30pt **不会挤乱版式**：正面是 `VStack(spacing: 0)` + 底部一根
    ///    `Spacer(minLength: 0)`，袋子变小腾出的空间全部落进那根 Spacer ——
    ///    文字组仍紧贴袋子下沿（间距 8 不变）、底部提示仍贴卡底，
    ///    只是「文字组 ↔ 底部提示」之间多出一段留白。
    ///    ⚠️ 想让**卡片跟着一起矮**（袋子 190 + 卡片 290、卡内不留白）：
    ///       把 `phoneCardShrink` 也改成 58。反之只动卡片就只改上面那个数。
    ///    ⚠️ 想再小一档：加大这个数即可 —— 宽度按素材原始比例算，袋子会等比变窄。
    static let phoneBagShrink: CGFloat = 58

    /// 卡片高度：稿面 348 − iPhone 收矮量（iPad 恒 348）
    static var cardHeight: CGFloat { 348 - shrink(phoneCardShrink) }
    /// 袋子高度：稿面 248 − iPhone 收矮量（iPad 恒 248）。
    /// 宽度按素材原始比例自适应，所以袋子会随之变矮、并按比例变窄。
    static var bagHeight: CGFloat { 248 - shrink(phoneBagShrink) }

    /// 实际生效的收矮量（iPad 上恒为 0）
    private static func shrink(_ amount: CGFloat) -> CGFloat { AppLayout.isPad ? 0 : amount }

    // ── 袋图与右上角「最新」角标的对齐 ──

    /// 袋图上内边距的**额外补偿**（只作用 iPhone；iPad 保持稿面值）。
    ///
    /// 角标：H5 `.brand-badge { top:12px; padding:4px 10px }` + 9.5pt 文字
    /// ⇒ **盒底落在卡顶下方 31.3pt**（实测「最新」墨迹底 26.3 + 下内边距 4 + 行盒余量）。
    /// 而袋图原先的可见顶（袋柄上沿）在卡顶下方 **19.7pt**（= `paddingV` 18 + 素材自带的
    /// 透明上边距约 1.7），视觉上比角标底边**高 11.6pt**。
    /// 📌 按需求「图片顶部对齐最新标签的底部」把上内边距加 11.6pt（实测校准）。
    ///
    /// ⚠️ 只加上内边距、**不动袋子高度**：袋子连同下方文字整体下移 11.6pt，
    ///    卡片内底部的富余留白相应少吃这么多（原本约 30pt，够用，不会顶到提示行）。
    /// ⚠️ iPad 不给这个补偿：那边「卡片高 348」与 H5 的高度等式是**恰好相等**的，
    ///    再加会顶出卡片（提示行被挤出下沿）。想给 iPad 加，得同时减底部留白。
    static let phoneBagTopLift: CGFloat = 11.6
    private static var bagTopLift: CGFloat { AppLayout.isPad ? 0 : phoneBagTopLift }

    /// 袋图在「已对齐角标底边」的基础上**再往下压**的量（只作用 iPhone）。
    ///
    /// 📌 按需求「首页大卡里图片的位置再往下移一点」新增这个旋钮：**+10pt**
    ///    （袋图可见顶由卡顶下方 29.6 → **39.6pt**）。
    ///    刻意**不去改 `phoneBagTopLift`(11.6)** —— 那条是按「图片顶部对齐最新标签底部」
    ///    实测校准出来的值，留着它，一眼就能看出「角标对齐」与「额外下压」各占多少。
    ///
    /// ⚠️ 袋子与下方文字在一个 `VStack(spacing: 0)` 里，所以是**整体下移**；
    ///    卡片高度、卡顶、提示行都不动，少吃的是「文字组 ↔ 底部提示」之间的富余。
    ///    余量推算（iPhone）：320 − (29.6 上垫 + 190 袋高 + 8 间距 + 40 文字组 + 12 提示 + 6 底垫)
    ///    ≈ **30pt** —— 也就是这个数**最多加到约 30** 就会把提示行顶出卡底。
    ///    ⚠️ iPad 不给：那边「卡高 348 = 版式各项之和」是**恰好相等**的，再加会溢出
    ///       （与 `phoneBagTopLift` 同一条理由）。
    static let phoneBagExtraDrop: CGFloat = 10

    /// 实际生效的额外下压（iPad 恒 0）
    private static var bagExtraDrop: CGFloat { AppLayout.isPad ? 0 : phoneBagExtraDrop }

    /// 袋图的上内边距 = 正面内边距 + 角标对齐补偿 + 额外下压
    static var bagTopPadding: CGFloat { paddingV + bagTopLift + bagExtraDrop }

    /// 空状态占位图（`bag-empty`）的高度：刻意比真袋子小，占位更克制。
    ///
    /// ⚠️ 它在袋位里是**居中**的，图下方天然多出 `emptyBagSlack` 的空白；
    ///    文字组若不把这 41pt 抵消掉，空状态的「图 → 字」会比有藏品时多空近 50pt。
    ///
    /// 📌 它**不跟着收矮**（收的是真袋子）：iPhone 上袋位 220、占位图仍 166，
    ///    于是占位图在袋位里的占比略变大一点，观感上不必跟着变。
    static let emptyBagHeight: CGFloat = 166
    /// 占位图在袋位里上下各让出的空白：稿面 (248 − 166) / 2 = 41，iPhone 上 (220 − 166) / 2 = 27
    static var emptyBagSlack: CGFloat { (bagHeight - emptyBagHeight) / 2 }
    /// 空状态「图 → 字」的目标间距：占位图比真袋子小一圈，给得比 8 松一点才不局促
    static let emptyBagCaptionGap: CGFloat = 20
    /// 空状态文字组的上间距：先抵消占位图下方的 41pt 空白，再留出目标间距。
    /// 结果为负值 —— 文字组向上「钻进」袋位区那段空白里，视觉上贴近占位图。
    static var emptyCaptionTopPadding: CGFloat {
        emptyBagCaptionGap - emptyBagSlack
    }
    /// 正面内边距：上下 18 / 左右 20
    static let paddingV: CGFloat = 18
    static let paddingH: CGFloat = 20
    /// 袋子与文字间距
    static let bagCaptionGap: CGFloat = 8
    /// 提示文字距卡底
    static let hintBottom: CGFloat = 6
    /// 背面内边距
    static let backPadding = EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18)
}

// MARK: - 色板（与 H5 逐值对齐）

enum HeroPalette {
    /// 正面品牌名 #1a1815
    static let captionBrand = Color(red: 26/255, green: 24/255, blue: 21/255)
    /// H5 `--muted: #77736d` —— 背面眉标、键值对的键、搜索框等处的次级灰。
    /// ⚠️ 不要用 `.secondary` 代替：它在浅色下约 #858585，比稿面浅一档。
    static let muted = Color(red: 119/255, green: 115/255, blue: 109/255)

    /// H5 里大量出现的 `rgba(20, 20, 20, α)` —— 底色基准是**墨色 #141414**，不是纯黑。
    ///
    /// 直接用 `Color.black.opacity(...)` 会深一档（#000 vs #141414），
    /// 在 5% 这种极低不透明度上仍能看出来。集中在这里，别在各处再写 black。
    static func ink(_ alpha: Double) -> Color {
        Color(red: 20/255, green: 20/255, blue: 20/255).opacity(alpha)
    }
    /// 正面名字 / 日期 #8d877c
    static let captionSub = Color(red: 141/255, green: 135/255, blue: 124/255)
    /// 底部提示 #c0bab1
    static let hint = Color(red: 192/255, green: 186/255, blue: 177/255)
    /// 正面右上角「最新」角标文字 #96703a
    static let badge = Color(red: 150/255, green: 112/255, blue: 58/255)
    /// 背面名字 #1d1a15
    static let backName = Color(red: 29/255, green: 26/255, blue: 21/255)
    /// 背面品牌行 #6f6a62
    static let backBrand = Color(red: 111/255, green: 106/255, blue: 98/255)
    /// 背面键值对的值 #2b2720
    static let factValue = Color(red: 43/255, green: 39/255, blue: 32/255)
    /// 背面标签文字 #5d594f
    static let tagText = Color(red: 93/255, green: 89/255, blue: 79/255)
    /// 背面备注文字 #5f5b53
    static let noteText = Color(red: 95/255, green: 91/255, blue: 83/255)
    /// 卡片主投影基色 rgb(52,66,92)
    static let shadowBase = Color(red: 52/255, green: 66/255, blue: 92/255)
    /// 袋子投影基色 rgb(60,48,34)
    static let bagShadow = Color(red: 60/255, green: 48/255, blue: 34/255)
    /// 挂袋区金属孔环铜色
    static let clipBronze = Color(red: 0.55, green: 0.48, blue: 0.40)
    /// 品牌红 #C50405 —— 详情卡编辑态的聚焦色（输入框下划线 / 备注左侧竖线），
    /// 也是匹配下拉里「命中的那几个字」的颜色。
    /// H5 侧就是 `:root { --focus: #C50405 }`（白底对比度 6.19:1，达 WCAG AA）。
    static let focus = Color(red: 197/255, green: 4/255, blue: 5/255)
}

// MARK: - 翻面时序（数值与 H5 一一对应）

enum FlipTiming {
    /// 整卡旋转时长 0.78s
    static let rotateDuration: Double = 0.78
    /// 旋转曲线 cubic-bezier(.2, .78, .22, 1)
    static let curve: (Double, Double, Double, Double) = (0.2, 0.78, 0.22, 1)
    /// 先出的一面淡出：0.06s，无延时
    static let fadeOutDuration: Double = 0.06
    /// 后进的一面淡入：0.1s
    static let fadeInDuration: Double = 0.1
    /// 后进的一面淡入延时 110ms
    ///
    /// ⚠️ 这个延时**绑在 `curve` 上**：它对应「父级转过 90°」的时刻
    /// （实测 94~100ms）。低于它，背面会在卡片还很宽时出现，露出镜像内容；
    /// 换了曲线，90° 出现的时刻就变，这个值必须重算。
    static let fadeInDelay: Double = 0.11

    static var rotateAnimation: Animation {
        .timingCurve(curve.0, curve.1, curve.2, curve.3, duration: rotateDuration)
    }
}

// MARK: - 主卡片

/// 主展位玻璃卡：正面袋子 + 背面详情，整卡轻点翻面。
struct HeroCardView: View {
    /// 当前展品；为 nil 时进入空状态（不可翻面，也不响应点击）
    let bag: BagItem?
    /// 基准日，用于「入库时长」
    let base: Date
    /// 翻面复位令牌：宿主每展示一次主卡就 +1（H5 `showRackHero` 每次都
    /// `setHeroFlipped(false)`，点同一张挂袋卡也要翻回正面）
    var resetToken: Int = 0
    /// 点「查看大图」
    var onOpenDetail: (BagItem) -> Void = { _ in }

    @State private var isFlipped = false
    @State private var frontOpacity: Double = 1
    @State private var backOpacity: Double = 0

    private var isEmpty: Bool { bag == nil }

    var body: some View {
        ZStack {
            // ── 玻璃底 + 描边 + 投影：只在卡片本体这一层 ──
            //
            // ⚠️ 首页主卡**不带毛玻璃**，用的是 H5 的正面配方：
            //    白底 .154，`backdrop-filter: none`。
            //
            //    H5 原文（`.flip-card:not(.is-flipped)`）：
            //      「父层这层玻璃对正面不再有意义，但它的 backdrop-filter
            //        仍会为「正面 + 背景」多做一次模糊合成。所以在正面可见期间
            //        把父层滤镜关掉。」
            //
            //    对 iOS 来说这还多一层原因：卡片整块挂在 `rotation3DEffect` 上，
            //    而实时毛玻璃（`ultraThinMaterial`）在 3D 变换下**每帧都要重新
            //    采样背景重做一次模糊** —— 那是翻面掉帧的头号开销。
            //    H5 在浏览器里之所以带 blur 也不卡，是因为卡片早已被提升为独立
            //    合成图层、背景又不动的，模糊结果可以缓存；UIKit 这边没有对应机制。
            //
            //    代价：卡片少一层「白度」。所以白底从 0.07 提到 H5 的 **0.154**
            //    （0.07 是当年为了跟毛玻璃搭配才降下来的）。卡片背后是纯色页面背景，
            //    模糊本来也糊不出东西，观感几乎不变。
            //
            //    📌 详情卡（`DetailCardView`）继续用毛玻璃 —— 它浮在彩色纸袋之上，
            //       那儿模糊是有意义的，而且它只做缩放淡入、不做 3D 旋转。
            GlassCardBackground(fillOpacity: 0.154, materialOpacity: 0)

            // ── 正面 ──
            // 背面预旋转 180°（固定值，**不跟随父级**），正面不预旋转。
            // 两个面都常驻在 ZStack 里，靠 opacity 切换 ——
            // H5 里 `backdrop-filter` 会压平 3D 上下文、`backface-visibility` 失效，
            // 所以翻面只能靠 opacity，不能用左右两面互斥渲染。
            HeroFrontView(bag: bag)
                .opacity(frontOpacity)
                .zIndex(1)
                // 不可见的那一面必须整体让出点击，否则它的按钮会截走本该
                // 落到正面（或落到整卡翻转）上的点击
                .allowsHitTesting(frontOpacity > 0.5)

            // ── 背面 ──
            HeroBackView(bag: bag,
                         base: base,
                         onOpenDetail: {
                             if let bag { onOpenDetail(bag) }
                         },
                         onFlipBack: { setFlipped(false) })
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(backOpacity)
                .zIndex(2)
                .allowsHitTesting(backOpacity > 0.5)
        }
        .frame(width: HeroMetrics.cardWidth, height: HeroMetrics.cardHeight)
        // 卡片整体绕 Y 轴旋转。
        // ⚠️ H5 是 `rotateY(-180deg)`（CSS 负角度视觉上是顺时针）；
        //    SwiftUI 正角度才是顺时针，所以这里写 `+180`，符号要反过来。
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0),
                          anchor: .center,
                          anchorZ: 0,
                          perspective: 0.35)
        .animation(FlipTiming.rotateAnimation, value: isFlipped)
        // 让透明区域也响应点击
        .contentShape(.rect)
        // 整卡轻点翻面。
        // ⚠️ 不能用 `.simultaneousGesture`：`Button` 会先于 onTapGesture 消费事件，
        //    用了之后会出现「点按钮的同时卡片也翻了」。
        .onTapGesture {
            guard !isEmpty else { return }
            setFlipped(!isFlipped)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isEmpty ? "最近暂无收藏" : "展品卡片：\(bag?.displayName ?? "")")
        // 换了一只袋子 → 立刻回到正面（H5 `showRackHero()` 的行为）
        .onChange(of: bag?.id) { _, _ in
            setFlipped(false, animated: false)
        }
        .onChange(of: resetToken) { _, _ in
            // H5：showRackHero 每次调用都翻回正面（含点同一张挂袋卡）
            setFlipped(false, animated: false)
        }
    }

    // MARK: 翻面

    /// 切换翻面状态（对应 H5 `setHeroFlipped`）
    private func setFlipped(_ flipped: Bool, animated: Bool = true) {
        guard !isEmpty else { return }
        guard isFlipped != flipped else { return }

        isFlipped = flipped

        guard animated else {
            // 换袋子时不做动画：直接把两个面归位，避免残留的镜像中间态
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                frontOpacity = flipped ? 0 : 1
                backOpacity  = flipped ? 1 : 0
            }
            return
        }

        // ① 先出的一面立刻淡出（0.06s 无延时）——
        //    不让会变成镜像的那一面压住目标面
        withAnimation(.linear(duration: FlipTiming.fadeOutDuration)) {
            if flipped { frontOpacity = 0 } else { backOpacity = 0 }
        }

        // ② 后进的一面延时 110ms 再淡入（0.1s）——
        //    等父级转过 90°（卡片最窄）之后再让目标面出现，避免露出镜像
        //
        // ⚠️ 用 `.delay()` 而不是 `DispatchQueue.main.asyncAfter`：
        //    H5 那边这两段本来就是两条并行的 CSS transition
        //    （`opacity .06s linear 0s` 与 `opacity .1s linear .11s`），
        //    一次提交就能把整条时间轴交给合成器；而 asyncAfter 会在
        //    动画**中途**再发一次状态变更，多一次 SwiftUI 提交 ——
        //    那一下正好落在翻面最费帧的时刻。
        withAnimation(.linear(duration: FlipTiming.fadeInDuration)
            .delay(FlipTiming.fadeInDelay)) {
            if flipped { backOpacity = 1 } else { frontOpacity = 1 }
        }
    }

    /// 外部（如挂袋区点击）请求翻回正面
    func flipToFront() { setFlipped(false) }
}

// MARK: - 玻璃底

/// 卡片本身的玻璃质感：半透明白底 + 毛玻璃 + 白描边 + 双层投影。
///
/// H5 对应：
/// ```css
/// background: rgba(255,255,255,.154);          /* 在 .22 白底基础上再降 30% */
/// backdrop-filter: blur(22px) saturate(180%);
/// border: 1px solid rgba(255,255,255,.62);
/// box-shadow: 0 1px 0 #fff9 inset, 0 -1px 0 #fff47 inset,
///             0 16px 36px rgba(52,66,92,.16), 0 3px 10px rgba(52,66,92,.07);
/// ```
/// 冷调白玻璃的**不透明**底色（H5 `linear-gradient(160deg,#fff 0%,#fafbfd 56%,#f2f4f8 100%)`）。
///
/// H5 里这条声明**同时用在两处**：`.detail-card`（详情卡）与 `.bottom-sheet`（半窗底座）。
/// 详情卡是基准，设置半窗是这轮对齐过来的 —— 两处必须逐值一致，
/// 免得「同一种材质」在两个页面上出现两种白。
///
/// ⚠️ 与 `GlassCardBackground` 的分工：
///    · `GlassCardBackground` 是**半透明毛玻璃**（卡片浮在页面上时用）；
///    · 这里是**不透明渐变**（详情卡 / 半窗这种「盖满一块区域」的实体面）。
///    别拿其中一个去替另一个。
enum CoolGlassSurface {
    static let gradient = LinearGradient(
        stops: [
            .init(color: .white, location: 0.00),
            .init(color: Color(red: 250 / 255, green: 251 / 255, blue: 253 / 255), location: 0.56),
            .init(color: Color(red: 242 / 255, green: 244 / 255, blue: 248 / 255), location: 1.00)
        ],
        // CSS 的 160deg ≈ 自上而下略偏右，用 topLeading → bottomTrailing 近似
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 内圈白棱：H5 `box-shadow` 里的 `0 0 0 1px rgba(255,255,255,.9) inset`。
    /// iOS 没有原生 inset shadow，用一圈描边顶替（与 `GlassCardBackground` 的处置一致）。
    static let innerRim = Color.white.opacity(0.9)
}

struct GlassCardBackground: View {
    /// 圆角默认取主卡的 26；详情浮层传入 30（整体放大后圆角同步放大）。
    /// 参数化而不是复制一份，是为了让两处的玻璃配方永远只有一处定义。
    var cornerRadius: CGFloat = HeroMetrics.cornerRadius

    /// 白底的不透明度。H5 原值 0.154。
    /// 首页主卡降到 0.07 让页面底色透上来；详情卡保持 0.154 ——
    /// 它浮在彩色纸袋之上、另有可读性薄纱兜底，不需要靠这层提亮。
    var fillOpacity: Double = 0.154

    /// 毛玻璃层的不透明度（1 = 不打折）。
    ///
    /// ⚠️ 「透不透」的真正杠杆在这一层，不在白底。
    ///    `ultraThinMaterial` 在浅色模式下本身就接近一层半透明白，而首页主卡背后
    ///    只是同色系的页面底色（≈#F2F3F7），白底 0.154 → 0.07 只差约 2 个 RGB 单位，
    ///    肉眼几乎看不出。H5 用 `backdrop-filter` 直接透出下层、没有这层白度叠加，
    ///    所以这里按比例打折来补偿这个差异。
    var materialOpacity: Double = 1.0

    /// 投影强度：1 = 两层投影照旧（主卡 / 详情卡）；0 = 完全不要投影。
    ///
    /// ⚠️ 宫格卡按用户要求传 0 —— 它成排密布，卡片之间只隔 9pt，
    ///    每张都带一圈柔光会连成一片灰带、卡与卡的边界反而变糊。
    var shadowOpacity: Double = 1

    /// 整套玻璃的等比缩放：主卡 1.0；小卡片按「卡宽 / 主卡宽」传。
    ///
    /// ⚠️ 光泽层的高光半径与两层投影都是**绝对尺寸**（为主卡 308pt 宽定的），
    ///    直接套到 82pt 的宫格卡上会变成「整片糊白 + 一圈脏影」——
    ///    所以按尺寸等比缩，而不是给小卡另写一套（配方仍然只有这一处）。
    var scale: CGFloat = 1

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            // ① 半透明白底：H5 `rgba(255,255,255,.154)`
            .fill(Color.white.opacity(fillOpacity))
            // ② 毛玻璃：对应 backdrop-filter blur(22px) saturate(180%)
            .background {
                shape.fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
            }
            // ③ 描边：H5 是 `border: 1px solid rgba(255,255,255,.62)`
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
            }
            // ④ 两条 inset 高光的替代（iOS 无原生 inset shadow）：
            //    上沿更亮、下沿更暗，叠在 ③ 的描边之上形成玻璃的立体边
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.28)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            // ④½ 玻璃光泽层：**叠在底板这一层，位于袋子图之下**。
            //    它本质是「玻璃面」的高光，属于卡片底色的一部分，不该盖住上面的
            //    袋子图 —— 否则那束白色径向高光会洗掉袋子左上角的颜色。
            //    （历史：这层原先放在 `HeroFrontView` 的 `.overlay` 最上层，
            //      正好压在袋子图上，是「图片被遮住颜色」的根因。）
            .overlay {
                GlassGlow(cornerRadius: cornerRadius, endRadius: 280 * scale)
            }
            // ⑤ 主投影 0 16 36
            .shadow(color: HeroPalette.shadowBase.opacity(0.16 * shadowOpacity),
                    radius: 18 * scale, x: 0, y: 16 * scale)
            // ⑥ 贴地投影 0 3 10
            .shadow(color: HeroPalette.shadowBase.opacity(0.07 * shadowOpacity),
                    radius: 5 * scale, x: 0, y: 3 * scale)
    }
}

// MARK: - 光束

/// 右上角斜射的一束光（展柜射灯）。
/// 用设计给的位图素材，不用渐变拼 —— 光晕衰减与色温都是设计调好的。
struct LightBeam: View {
    /// 光束强度。三个宿主取值都不同，所以直接传数值（不再是 `dimmed` 布尔）：
    ///   · 主卡正面 `0.9`（H5 无覆盖，取素材原强度）
    ///   · 主卡背面 `0.34`（H5 `.light-beam--back { opacity: .34 }`）
    ///   · 详情卡 `0.26`（H5 `.detail-glass .light-beam { opacity: .26 }`）
    var opacity: Double = 0.9
    /// 右上角圆角跟随宿主卡片；详情浮层传 30
    var cornerRadius: CGFloat = HeroMetrics.cornerRadius

    var body: some View {
        GeometryReader { geo in
            Image("light-beam")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                // 遮罩收紧：光只留在右上角那一块，否则素材的暖黄会顺着
                // 右边一路铺到卡底，整张卡发浑
                .mask(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.78), location: 0.38),
                            .init(color: .clear, location: 0.74)
                        ],
                        center: .init(x: 1.0, y: 0.0),
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * 0.92
                    )
                )
                .opacity(opacity)
                .clipShape(
                    .rect(topLeadingRadius: 0, topTrailingRadius: cornerRadius)
                )
        }
        .allowsHitTesting(false)
    }
}

/// 玻璃表面光泽：左上角冷白高光 + 一道极淡斜向反光。
/// H5 是 `.glass-glow`，用于补足 iOS 无法表达的 inset 高光观感。
struct GlassGlow: View {
    /// 圆角默认取主卡的 26；详情浮层传 30
    var cornerRadius: CGFloat = HeroMetrics.cornerRadius
    /// 左上角那束径向高光的半径。主卡 308pt 宽时是 280；
    /// ⚠️ 小卡片必须等比缩（见 `GlassCardBackground.scale`），否则高光会糊满整卡。
    var endRadius: CGFloat = 280

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.5), location: 0),
                        .init(color: .clear, location: 0.34),
                        .init(color: .clear, location: 0.66),
                        .init(color: .white.opacity(0.34), location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                RadialGradient(
                    colors: [.white.opacity(0.95), .clear],
                    center: .init(x: 0.16, y: -0.12),
                    startRadius: 0,
                    endRadius: endRadius
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius,
                                            style: .continuous))
            }
            .allowsHitTesting(false)
    }
}

// MARK: - 正面的袋子

/// 袋子本体：高度锁 `HeroMetrics.bagHeight`（稿面 248，iPhone 上 190），
/// 宽度按素材原始比例（不拉伸）。
///
/// 有藏品时取该袋子的实拍/演示图；`bag == nil` 时取内置的空袋子示意图
/// （`bag-empty`），两种情况的**袋位高度相同**，卡片版式不会跳动。
///
/// ⚠️ 两个 H5 踩过的坑在 iOS 侧的对应风险：
///  1. 外层若有 `frame(maxHeight:)` 会把袋子压小（H5 被压成 248×0.85=210.8px）。
///     **主卡这一处必须显式写死袋位高度，不要复用列表缩略图的尺寸修饰符。**
///  2. 用 `scaledToFit` 而不是 `scaledToFill`，否则会裁掉袋子提手。
struct BagArtwork: View {
    let bag: BagItem?

    /// 主卡同一时刻只有一张图，且高度固定 —— 直接同步取图即可，
    /// 不必走缩略图缓存（也避免首帧闪空）。
    /// `BagImageResolver` 负责兼容「磁盘真实图」与「Assets 演示图」。
    private var artwork: UIImage? {
        guard let name = bag?.imageFileName else { return nil }
        return BagImageResolver.load(name)
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: HeroMetrics.bagHeight)
                    .frame(maxWidth: .infinity)
                    // CSS drop-shadow 贴合图片轮廓，SwiftUI 的 .shadow 是矩形投影。
                    // 按用户要求把模糊从 12 加大到 22，投影更柔和、更有立体感。
                    .shadow(color: HeroPalette.bagShadow.opacity(0.28),
                            radius: 22, x: 0, y: 14)
            } else {
                // 空状态：显示内置的「空袋子」示意图（`Assets.xcassets/bag-empty`）。
                //
                // 📌 与 H5 的差异：H5 在 `.flip-card.is-empty` 下是 `display:none`，
                //    即**什么都不画**；这里改为画一张占位图。
                // 📌 高度按用户要求定为 `emptyBagHeight`（166，真实袋子是 248），宽度由
                //    `scaledToFit` 等比缩放。外层 `Group` 仍锁 248 高，所以图片在袋位区里
                //    **居中**，上下各让出 `emptyBagSlack`（41）—— 图下方那 41pt 由
                //    `HeroFrontView` 的负上间距抵消，文字才不会被推远。
                Image("bag-empty")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: HeroMetrics.emptyBagHeight)
                    .frame(maxWidth: .infinity)
                    .shadow(color: HeroPalette.bagShadow.opacity(0.28),
                            radius: 22, x: 0, y: 14)
                    // 纯装饰图，对 VoiceOver 隐藏；空状态的语义已由文字与
                    // `HeroCardView` 的 accessibilityLabel 表达
                    .accessibilityHidden(true)
            }
        }
        .frame(height: HeroMetrics.bagHeight)
    }
}

// MARK: - 正面

/// 正面：袋子 + 下方文字信息 + 底部提示。
///
/// H5 的高度分配：348 = 18(上留白) + 248(袋子) + 8(间距) + 40(两行文字)
///              + 4 + 12(提示) + 18(下留白)
///
/// 📌 iPhone 上收矮两项（见 `HeroMetrics`）：卡片 348→320、袋子 248→**190**。
///    袋子比卡片多收 30，那 30pt 被下方 `Spacer` 吃掉 —— 文字组仍紧贴袋子、
///    底部提示仍贴卡底，等式里除前两项外其余不变，只是 Spacer 不再为 0。
///
/// 📌 空状态的不同：袋位换成更小的占位图（`bag-empty`，166 高、居中在袋位里），
///    底部提示整行不渲染 —— 那 4 + 12 的份额被上方 `Spacer` 吸收。
///    文字组还会**额外上提**（见 `emptyCaptionTopPadding`）：占位图居中后，
///    图下方多出的 41pt 空白必须抵消，否则「图 → 字」会拉开近 50pt 的空档。
struct HeroFrontView: View {
    let bag: BagItem?

    private var isEmpty: Bool { bag == nil }

    var body: some View {
        VStack(spacing: 0) {
            // ── 袋子 ──
            BagArtwork(bag: bag)
                // 上内边距 = 正面内边距 + 与「最新」角标底边的对齐补偿（`phoneBagTopLift`）
                //            + 需求追加的「再往下移一点」（`phoneBagExtraDrop`）
                .padding(.top, HeroMetrics.bagTopPadding)

            // ── 文字信息：品牌做主标题，名字 · 日期并列一行 ──
            VStack(spacing: 5) {
                Text(bag?.displayShelf ?? "最近暂无收藏")
                    // H5 `.front-caption__brand { font-size: 21px; font-weight: 700 }` + 衬线
                    // （思源宋体 Bold）。⚠️ 别退回 `design: .serif`：中文会回落成苹方黑体。
                    .font(AppFont.songti(21))
                    .foregroundStyle(isEmpty ? HeroPalette.captionSub : HeroPalette.captionBrand)
                    // 品牌名过长时限一行省略，避免把 248px 的袋子挤小、整张卡变形
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 7) {
                    // 空状态没有名字可写，整行换成一句引导语（原先是占位符「—」）
                    Text(bag?.displayName ?? "每一个纸袋都有故事，期待你的记录")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    // 圆点与日期只在有藏品时出现。
                    // 空状态下日期是空串，若保留会落下一个孤零零的分隔圆点。
                    if let bag {
                        // 两段之间的分隔圆点：3pt，opacity .55
                        Circle()
                            .fill(HeroPalette.captionSub.opacity(0.55))
                            .frame(width: 3, height: 3)

                        Text(DateFormat.slash(bag.createdAt))
                            .fixedSize()
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(HeroPalette.captionSub)
            }
            // 空状态：负上间距，抵消占位图居中后多出的 41pt 空白（见 `HeroMetrics`）
            .padding(.top, isEmpty ? HeroMetrics.emptyCaptionTopPadding
                                   : HeroMetrics.bagCaptionGap)
            .padding(.horizontal, HeroMetrics.paddingH)

            Spacer(minLength: 0)

            // ── 底部提示：贴卡片底部通栏居中 ──
            // 放左上角会撞袋子提手；跟在文字组下面会被读成第三行，所以拉开到卡底。
            //
            // 空状态**不显示**这行：此时卡片不可翻面，写「轻点翻面」是误导；
            // 引导语已由文字组第二行的「每一个纸袋都有故事…」承担。
            // 少掉这行后，其上方 `Spacer` 会多吃 16pt（4 + 12），
            // 文字组位置不变，只是卡片底部多一段留白。
            if !isEmpty {
                Text("轻点翻面 · 查看详情")
                    .font(.system(size: 8.5))
                    .foregroundStyle(HeroPalette.hint)
                    .padding(.bottom, HeroMetrics.hintBottom)
            }
        }
        .frame(width: HeroMetrics.cardWidth, height: HeroMetrics.cardHeight)
        // ── 右上斜射光束（正面专属）──
        //
        // ⚠️ 这一层必须留在**正面内部**，不能提到 `HeroCardView` 的共享 ZStack 里：
        //    卡片翻面时父级会绕 Y 轴转 180°，放在父层里的光束会跟着一起转 ——
        //    结果背面左上角冒出一束本该只属于正面的暖黄光（H5 里
        //    `.light-beam` 就写在 `.flip-face--front` 内，会随正面一起淡出）。
        //
        // 压在正面内容**之下**：既透出玻璃底，又不盖住袋子图
        // （否则暖黄氛围光会压在袋子图上，把右上角的颜色染色）。
        // 背面另有一束自己的 `.light-beam--back`（opacity .34），见 `HeroBackView`。
        .background { LightBeam() }
        // ── 右上角「最新」角标 ──
        // H5 `.brand-badge`：top/right 12、padding 4×10、radius 12、
        // 半透明白底 + blur(10px)、文字 #96703a 9.5pt 加粗。空状态隐藏。
        .overlay(alignment: .topTrailing) {
            if !isEmpty {
                Text("最新")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(HeroPalette.badge)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.58), in: .rect(cornerRadius: 12))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
    }
}

// MARK: - 背面

/// 背面：固定 5 行字段 + 标签 + 备注 + 「查看大图」。
///
/// ⚠️ 间距是绑定的：内容要压进 346pt（348 减上下 2px 边框）。
/// 以后若再加字段，必须同步减内边距或行距，否则内容会被裁。
struct HeroBackView: View {
    let bag: BagItem?
    let base: Date
    var onOpenDetail: () -> Void = {}
    /// 点「翻回正面」时回调给 `HeroCardView` 改状态。
    var onFlipBack: () -> Void = {}

    private var isEmpty: Bool { bag == nil }

    /// 键值对：品牌/店铺、上传地点、收藏日期、入库时长、编号
    /// **不含「尺寸」字段**（已按需求移除）
    ///
    /// ⚠️ 空值行照 H5 `heroFactsHTML` 的 `filter` **整行丢掉**，而不是渲染成「—」。
    ///    「上传地点」是新增字段，新上传的藏品（走相机/相册那条链路）拿不到地点，
    ///    不过滤就会在卡面上多出一行 `上传地点   —`。
    private var factRows: [(String, String)] {
        guard let bag else { return [] }
        return [
            ("品牌 / 店铺", bag.displayShelf),
            ("上传地点",   bag.location),
            // 📌 「材质」行按用户要求**去掉**（H5 的 `back-facts` 里有这一行）。
            //    起因：演示数据的材质统一是「白卡纸覆哑膜」，于是**每张卡**都会多出
            //    一模一样的一行，成了噪音。数据本身还留着（模型字段未动），
            //    只是卡面上不再展示。
            ("收藏日期",   DateFormat.dash(bag.createdAt)),
            ("入库时长",   RelativeDay.text(bag.createdAt, base: base)),
            ("编号",       bag.numberText)
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 编号眉标 ──
            // 空状态固定 NO.000；有藏品则读**上传时发放**的固定编号（见 `BagItem.numberText`）
            Text(bag?.numberText ?? BagItem.emptyNumberText)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.6)
                // H5 `.back-eyebrow { color: var(--muted) }` —— 固定 #77736d，
                // 不用 `.secondary`（浅色下约 #858585，比稿面浅一档）。
                .foregroundStyle(HeroPalette.muted)

            // ── 名字 ──
            Text(bag?.displayName ?? "最近暂无收藏")
                // H5 `.back-name { font-size: 19px; font-weight: 600 }` + 衬线。
                // 尺寸仍按 iOS 侧的两档（空状态 21 / 有藏品 19）；字重统一到宋体 Bold
                // —— 600 那档（SemiBold）没随包，用 Bold 顶（空状态原来刻意用的 regular 一并收拢）。
                .font(AppFont.songti(isEmpty ? 21 : 19))
                .foregroundStyle(isEmpty ? HeroPalette.captionSub : HeroPalette.backName)
                .lineLimit(1)
                .padding(.top, 4)

            // ── 品牌 / 空状态提示 ──
            Text(bag?.displayShelf
                 ?? "最近 \(Feed.recentWindowDays) 天内添加的藏品会出现在这里")
                .font(.system(size: 11))
                .foregroundStyle(HeroPalette.backBrand)
                .lineLimit(2)
                .padding(.top, 5)

            // ── 分隔线：右端渐隐 ──
            //
            // H5 `.back-divider { background: linear-gradient(90deg,
            //      rgba(20,20,20,.12), rgba(20,20,20,.04) 70%, transparent) }`
            // ⚠️ 第三档在 **70%** 处，不是 50% —— 三色 LinearGradient 的默认
            //    均分会让右端渐隐开始得太早、整条线看着比稿面淡。
            LinearGradient(
                stops: [
                    .init(color: HeroPalette.ink(0.12), location: 0),
                    .init(color: HeroPalette.ink(0.04), location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.vertical, 11)

            // ── 5 行键值对 ──
            VStack(spacing: 6) {
                ForEach(factRows, id: \.0) { key, value in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(key)
                            .font(.system(size: 9.5))
                            .tracking(0.3)
                            // H5 `.back-facts__row dt { color: var(--muted) }` → #77736d
                            .foregroundStyle(HeroPalette.muted)
                        Spacer(minLength: 8)
                        Text(value)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(HeroPalette.factValue)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            // ── 标签 ──
            if let bag, !bag.tags.isEmpty {
                FlowRow(spacing: 5) {
                    ForEach(bag.tags, id: \.self) { tag in
                        Text("# \(tag)")
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            // H5 `.back-tags span { background: rgba(20,20,20,.055) }`
                            .background(HeroPalette.ink(0.055),
                                        in: .rect(cornerRadius: 10))
                            .foregroundStyle(HeroPalette.tagText)
                    }
                }
                .padding(.top, 12)
            }

            // ── 备注：引用式小字 ──
            if let bag, !bag.note.isEmpty {
                Text(bag.note)
                    .font(.system(size: 10))
                    .lineSpacing(3.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // H5 `.back-note { border-left: 2px solid rgba(20,20,20,.14);
                    //                  border-radius: 0 9px 9px 0; background: rgba(20,20,20,.035) }`
                    .background(HeroPalette.ink(0.035),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 0, bottomLeadingRadius: 9,
                                    bottomTrailingRadius: 9, topTrailingRadius: 0,
                                    style: .continuous))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(HeroPalette.ink(0.14))
                            .frame(width: 2)
                    }
                    .foregroundStyle(HeroPalette.noteText)
                    .padding(.top, 11)
            }

            Spacer(minLength: 0)

            // ── 查看大图 ──
            // ⚠️ 只留 10pt 间距：不要再在 label 里加 padding，
            //    否则会和 margin 叠加成 20pt 的视觉空隙。
            if !isEmpty {
                Button(action: onOpenDetail) {
                    Text("查看大图 →")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(HeroMetrics.backPadding)
        .frame(width: HeroMetrics.cardWidth, height: HeroMetrics.cardHeight, alignment: .topLeading)
        // 背面另有一束自己的光束，H5 `.light-beam--back { opacity: .34 }`
        .overlay { LightBeam(opacity: 0.34) }
        // 背面的「翻回正面」按钮：压在内容之上
        .overlay(alignment: .topTrailing) {
            if !isEmpty { flipBackButton }
        }
    }

    /// 背面右上角「翻回正面」按钮。
    /// ⚠️ 在 SwiftUI 里 `Button` 天然先于外层的 `onTapGesture` 消费事件，
    ///    所以不需要像 H5 那样手动 `stopPropagation`，也不会触发整卡翻转。
    private var flipBackButton: some View {
        Button(action: onFlipBack) {
            Text("↺")
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 109/255, green: 103/255, blue: 94/255))
                .frame(width: 28, height: 28)
                // H5 `.flip-back { background: rgba(20,20,20,.055) }`
                .background(HeroPalette.ink(0.055), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("翻回正面")
    }
}

// MARK: - 流式布局

/// 自动换行的横向排列（用于标签区）。
/// H5 是 `.back-tags { flex-wrap: wrap }`。
struct FlowRow: Layout {
    var spacing: CGFloat = 5
    /// 行内对齐方式。
    ///
    /// 默认左对齐（背面标签区 / 详情卡标签区都是这个口径）；
    /// 「搜索无结果」的出路标签要居中 —— H5 那条是
    /// `.empty-state__chips { justify-content: center }`。
    /// 加一个参数而不是再写一套居中的 Layout：本项目已经有
    /// `FlowRow` / `FlowLayout` / `TagFieldLayout` 三套流式实现，
    /// 再复制一份「只差一个对齐」的出来，以后改间距就得改四处。
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth,
                      height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        // 先分行再摆放：居中需要知道整行的总宽，边算边放做不到。
        // 换行判据与 `sizeThatFits` 完全同一套（游标 + 本项宽度越界就换行），
        // 只是把游标换成相对 bounds 原点的偏移量。
        var lines: [[(index: Int, size: CGSize)]] = []
        var current: [(index: Int, size: CGSize)] = []
        var cursor: CGFloat = 0

        for (index, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if cursor > 0, cursor + size.width > bounds.width {
                lines.append(current)
                current = []
                cursor = 0
            }
            cursor += size.width + spacing
            current.append((index, size))
        }
        if !current.isEmpty { lines.append(current) }

        var y = bounds.minY
        for line in lines {
            let rowWidth = line.reduce(0) { $0 + $1.size.width }
                + spacing * CGFloat(max(0, line.count - 1))
            let rowHeight = line.map(\.size.height).max() ?? 0

            var x = bounds.minX
            switch alignment {
            case .center:   x += max(0, (bounds.width - rowWidth) / 2)
            case .trailing: x += max(0, bounds.width - rowWidth)
            default:        break          // .leading 与原来完全一致
            }

            for item in line {
                subviews[item.index].place(at: CGPoint(x: x, y: y),
                                           anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}

// MARK: - 预览

#Preview("正面") {
    let base = PreviewData.sampleBag()
    return ZStack {
        Color(red: 0.953, green: 0.953, blue: 0.969).ignoresSafeArea()
        HeroCardView(bag: base, base: base.createdAt)
    }
}

#Preview("空状态") {
    ZStack {
        Color(red: 0.953, green: 0.953, blue: 0.969).ignoresSafeArea()
        HeroCardView(bag: nil, base: .now)
    }
}

