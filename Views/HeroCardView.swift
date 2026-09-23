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
    static let cardHeight: CGFloat = 348
    static let cornerRadius: CGFloat = 26
    /// 袋子高度锁 248，宽度按素材原始比例自适应
    static let bagHeight: CGFloat = 248
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
    /// 在全集中的位置（从 0 起），用于 `NO.xxx` 编号
    let displayIndex: Int
    /// 基准日，用于「入库时长」
    let base: Date
    /// 点「查看大图」
    var onOpenDetail: (BagItem) -> Void = { _ in }

    @State private var isFlipped = false
    @State private var frontOpacity: Double = 1
    @State private var backOpacity: Double = 0

    private var isEmpty: Bool { bag == nil }

    var body: some View {
        ZStack {
            // ── 玻璃底 + 描边 + 投影：只在卡片本体这一层 ──
            // 首页主卡比详情卡更通透：白底 0.154 → 0.07，毛玻璃保留 85%。
            GlassCardBackground(fillOpacity: 0.07, materialOpacity: 0.85)

            // ── 右上斜射光束 ──
            // 放在底板之上、正/背面之下：既透出玻璃底，又不盖住袋子图
            // （否则这束暖黄氛围光会压在袋子图上，把右上角的颜色染色）。
            // 这里只针对**主卡正面**；详情卡、背面各自在自己的 overlay 里
            // 用 `LightBeam(dimmed: true)`，互不影响。
            LightBeam()
                .allowsHitTesting(false)

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
                         displayIndex: displayIndex,
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
        let targetFront = !flipped
        DispatchQueue.main.asyncAfter(deadline: .now() + FlipTiming.fadeInDelay) {
            withAnimation(.linear(duration: FlipTiming.fadeInDuration)) {
                if targetFront { frontOpacity = 1 } else { backOpacity = 1 }
            }
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
                GlassGlow(cornerRadius: cornerRadius)
            }
            // ⑤ 主投影 0 16 36
            .shadow(color: HeroPalette.shadowBase.opacity(0.16),
                    radius: 18, x: 0, y: 16)
            // ⑥ 贴地投影 0 3 10
            .shadow(color: HeroPalette.shadowBase.opacity(0.07),
                    radius: 5, x: 0, y: 3)
    }
}

// MARK: - 光束

/// 右上角斜射的一束光（展柜射灯）。
/// 用设计给的位图素材，不用渐变拼 —— 光晕衰减与色温都是设计调好的。
struct LightBeam: View {
    /// 背面压暗到 0.34，避免暖黄盖住读字的地方
    var dimmed: Bool = false
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
                .opacity(dimmed ? 0.34 : 0.9)
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
                    endRadius: 280
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius,
                                            style: .continuous))
            }
            .allowsHitTesting(false)
    }
}

// MARK: - 正面的袋子

/// 袋子本体：高度锁 248，宽度按素材原始比例（不拉伸）。
///
/// 有藏品时取该袋子的实拍/演示图；`bag == nil` 时取内置的空袋子示意图
/// （`bag-empty`），两种情况的**高度都是 248**，卡片版式不会跳动。
///
/// ⚠️ 两个 H5 踩过的坑在 iOS 侧的对应风险：
///  1. 外层若有 `frame(maxHeight:)` 会把袋子压小（H5 被压成 248×0.85=210.8px）。
///     **主卡这一处必须显式写死 248，不要复用列表缩略图的尺寸修饰符。**
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
                // 📌 高度按用户要求定为 166（真实袋子是 248），宽度由 `scaledToFit`
                //    等比缩放。外层 `Group` 仍锁 248 高，所以图片会在袋位区里
                //    居中、文字组位置不变，只是占位图体量更小、更克制。
                Image("bag-empty")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 166)
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
/// 📌 空状态略有不同：袋子换成 `Color.clear` 占位、底部提示整行不渲染，
///    于是那 4 + 12 的份额被上方 `Spacer` 吸收，文字组位置不变。
struct HeroFrontView: View {
    let bag: BagItem?

    private var isEmpty: Bool { bag == nil }

    var body: some View {
        VStack(spacing: 0) {
            // ── 袋子 ──
            BagArtwork(bag: bag)
                .padding(.top, HeroMetrics.paddingV)

            // ── 文字信息：品牌做主标题，名字 · 日期并列一行 ──
            VStack(spacing: 5) {
                Text(bag?.displayShelf ?? "最近暂无收藏")
                    .font(.system(size: 21, weight: .bold, design: .serif))
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
            .padding(.top, HeroMetrics.bagCaptionGap)
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
    let displayIndex: Int
    let base: Date
    var onOpenDetail: () -> Void = {}
    /// 点「翻回正面」时回调给 `HeroCardView` 改状态。
    var onFlipBack: () -> Void = {}

    private var isEmpty: Bool { bag == nil }

    /// 固定 5 行：品牌/店铺、材质、收藏日期、入库时长、编号
    /// **不含「尺寸」字段**（已按需求移除）
    private var factRows: [(String, String)] {
        guard let bag else { return [] }
        return [
            ("品牌 / 店铺", bag.displayShelf),
            ("材质",       bag.displayMaterial),
            ("收藏日期",   DateFormat.dash(bag.createdAt)),
            ("入库时长",   RelativeDay.text(bag.createdAt, base: base)),
            ("编号",       BagItem.numberText(index: displayIndex))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 编号眉标 ──
            Text(isEmpty ? BagItem.emptyNumberText
                         : BagItem.numberText(index: displayIndex))
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            // ── 名字 ──
            Text(bag?.displayName ?? "最近暂无收藏")
                .font(.system(size: isEmpty ? 21 : 19,
                              weight: isEmpty ? .regular : .semibold,
                              design: .serif))
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
            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.04), .clear],
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
                            .foregroundStyle(.secondary)
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
                            .background(Color.black.opacity(0.055),
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
                    .background(Color.black.opacity(0.035),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 0, bottomLeadingRadius: 9,
                                    bottomTrailingRadius: 9, topTrailingRadius: 0,
                                    style: .continuous))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.14))
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
        .overlay { LightBeam(dimmed: true) }
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
                .background(Color.black.opacity(0.055), in: .circle)
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
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y),
                      anchor: .topLeading,
                      proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 预览

#Preview("正面") {
    let base = PreviewData.sampleBag()
    return ZStack {
        Color(red: 0.953, green: 0.953, blue: 0.969).ignoresSafeArea()
        HeroCardView(bag: base, displayIndex: 0, base: base.createdAt)
    }
}

#Preview("空状态") {
    ZStack {
        Color(red: 0.953, green: 0.953, blue: 0.969).ignoresSafeArea()
        HeroCardView(bag: nil, displayIndex: 0, base: .now)
    }
}
