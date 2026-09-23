import SwiftUI
import SwiftData

// MARK: - 详情卡尺寸（对应 H5 `.detail-card`）

/// 详情浮层的几何常量。
/// ⚠️ 每个数字都必须能在 H5 侧找到对应声明，否则两版会漂移：
///  - H5 `styles.css` → `.detail-card { width: min(348px, …); height: min(560px, …) }`
///  - H5 `styles.css` → `.detail-artwork { height: 186px }`
///  - H5 `--detail-radius: 30px`
enum DetailCardMetrics {
    static let cardWidth: CGFloat = 348
    static let cardHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 30
    /// 顶部大图区高度（半窗时代的 290 收窄到 186，给下方信息腾高度）
    static let artworkHeight: CGFloat = 186
    /// 图区自身的内边距（H5 `.detail-artwork { padding: 10px }`）
    static let artworkPadding: CGFloat = 10
    /// 图片实际可用高度 = 图区 − 上下内边距（H5 `calc(var(--art-h) - var(--art-pad) * 2)`）
    static var artworkInnerHeight: CGFloat { artworkHeight - artworkPadding * 2 }
    /// 内容区左右内边距（H5 `.detail-scroll { padding: 22px 24px 4px }`）
    static let paddingH: CGFloat = 24
    static let paddingTop: CGFloat = 22
    /// 窄屏退化：H5 是 `calc(100vw - 36px)` / `calc(100dvh - 96px)`
    static let minSideInset: CGFloat = 36
    static let minVerticalInset: CGFloat = 96
    /// 打开动效（H5 `--detail-open-dur: .30s` + `cubic-bezier(.2,.78,.22,1)`）
    static let openDuration: Double = 0.30
    static let openScale: CGFloat = 0.92

    /// 按可用空间算出实际卡片尺寸（与 H5 的 min() 降级同口径）
    static func size(in available: CGSize) -> CGSize {
        CGSize(
            width: min(cardWidth, available.width - minSideInset),
            height: min(cardHeight, available.height - minVerticalInset)
        )
    }
}

// MARK: - 详情浮层

/// 纸袋详情：居中弹出的液态玻璃卡片。
///
/// 设计对齐 H5 的 `.detail-card`（复刻首页卡片**背面**的观感，整体放大）：
///  顶部继续保留纸袋大图 → 眉标编号 → 衬线名称 → 品牌 → 分隔线
///  → 键值对 → 标签 → 引用式备注 → 固定「完成」按钮。
///
/// 与 `BagDetailView` 的分工：
///  - `DetailCardView`（本文件）= **只读概览浮层**，点击卡片即出，关闭即消失；
///  - `BagDetailView` = 可编辑 / 可删除的完整页，从这里点「编辑」推入。
///    保留它是因为编辑与删除是既有能力，不该在改版里丢掉。
struct DetailCardView: View {
    let bag: BagItem
    /// 在全集中的序号，用于 `NO.xxx`；与首页背面、网格卡共用同一条编号规则
    let index: Int
    var base: Date
    var onClose: () -> Void
    var onEdit: (() -> Void)?

    /// 可读性薄纱的基色（H5 `#f7f3ed`，与半窗面板同色系）
    private static let scrim = Color(red: 247/255, green: 243/255, blue: 237/255)

    private var facts: [(String, String)] {
        [
            ("品牌 / 店铺", bag.displayShelf),
            ("材质", bag.displayMaterial),
            ("收藏日期", DateFormat.dash(bag.createdAt)),
            ("入库时长", RelativeDay.text(bag.createdAt, base: base)),
            ("编号", BagItem.numberText(index: index))
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            // 尺寸只在这里用于定框；卡片内部一律用相对布局，
            // 所以不必把 size 再传进 cardBody（传了是死参数）。
            let size = DetailCardMetrics.size(in: geo.size)

            // ── 宽屏（iPad）等比放大 ──
            // 与首页主卡同一套规则，否则点开详情时卡片反而比主卡小，
            // 观感上是「往回缩」。这里额外按可用高度再夹一次 ——
            // 横屏 iPad 只有 768 / 834pt 高，详情卡原高 560pt，
            // 放大 1.35 倍就是 756pt，不留神会被上下裁掉。
            let scale = AppLayout.cardScale(
                fitting: geo.size,
                card: CGSize(width: DetailCardMetrics.cardWidth,
                             height: DetailCardMetrics.cardHeight),
                sideInset: DetailCardMetrics.minSideInset,
                verticalInset: DetailCardMetrics.minVerticalInset,
                column: AppLayout.column(geo.size.width, max: AppLayout.showcaseMaxWidth)
            )

            cardBody
                .frame(width: size.width, height: size.height)
                // `scaleEffect` 不改布局尺寸，视觉中心与 `size` 的中心重合，
                // 所以外层照旧撑满居中即可，不需要补偿位移。
                .scaleEffect(scale)
                // 与 H5 的 `inset:0 + margin:auto` 等价：在父容器里严格居中
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var cardBody: some View {
        VStack(spacing: 0) {
            // ── 内容区（可滚动）──
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artwork
                    Text(BagItem.numberText(index: index))
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(HeroPalette.captionSub)
                        .padding(.bottom, 6)
                    Text(bag.displayName)
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(HeroPalette.backName)
                        .lineLimit(2)
                    Text(bag.displayShelf)
                        .font(.system(size: 13))
                        .foregroundStyle(HeroPalette.backBrand)
                        .padding(.top, 6)
                    divider
                    factsList
                    if !bag.tags.isEmpty { tagList }
                    if !bag.note.isEmpty { noteBlock }
                    // 只读浮层不承担编辑/删除，但也不该把它们藏掉 ——
                    // 给一个入口继续推入可编辑的完整页（BagDetailView）。
                    if let onEdit {
                        Button(action: onEdit) {
                            Text("编辑这件收藏 →")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(HeroPalette.backName)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DetailCardMetrics.paddingH)
                .padding(.top, DetailCardMetrics.paddingTop)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 关闭按钮绝对定位，所以滚动区不额外留右上角空位
            .scrollIndicators(.hidden)

            // ── 固定底部按钮 ──
            Button(action: onClose) {
                Text("完成")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(HeroPalette.backName, in: Capsule())
            .padding(.horizontal, DetailCardMetrics.paddingH)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        // 玻璃本体：与首页卡片逐值同配方，只把圆角换成 30
        .background {
            GlassCardBackground(cornerRadius: DetailCardMetrics.cornerRadius)
        }
        // ⚠ 可读性薄纱：首页卡片背面浮在干净的页面背景上，.154 的玻璃够用；
        //    详情卡是浮在「一屏彩色纸袋」之上的，纯玻璃会让正文和背景打架。
        //    再叠一层暖白薄纱把对比度拉回来，同时保留通透感。
        //    对应 H5 的 `.detail-glass::before`（同一段渐变）。
        .background {
            LinearGradient(
                stops: [
                    .init(color: Self.scrim.opacity(0.30), location: 0.00),
                    .init(color: Self.scrim.opacity(0.62), location: 0.42),
                    .init(color: Self.scrim.opacity(0.78), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: DetailCardMetrics.cornerRadius,
                                        style: .continuous))
        }
        // 光泽层 + 右上斜射光束（光束压暗到 0.34，与背面一致）
        .overlay {
            ZStack {
                GlassGlow(cornerRadius: DetailCardMetrics.cornerRadius)
                LightBeam(dimmed: true, cornerRadius: DetailCardMetrics.cornerRadius)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        // 光束与光泽都要被圆角裁掉
        .clipShape(RoundedRectangle(cornerRadius: DetailCardMetrics.cornerRadius,
                                    style: .continuous))
    }

    // MARK: - 局部

    private var artwork: some View {
        Group {
            if let image = BagImageResolver.load(bag.imageFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // ⚠ 可用高度 = 图区高度 − 上下内边距，与 H5 的
                    //    max-height: calc(var(--art-h) - var(--art-pad) * 2) 同口径。
                    //    H5 侧这里踩过坑：在 grid 里写 max-height:100% 会与网格区域
                    //    形成循环依赖，浏览器回退成原始尺寸，图片撑破容器盖住文字。
                    .frame(maxWidth: .infinity,
                           maxHeight: DetailCardMetrics.artworkInnerHeight)
            } else {
                Image(systemName: "handbag")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(HeroPalette.captionSub)
            }
        }
        // ⚠ 内边距必须加在「186pt 的盒子内部」：
        //    H5 的 .detail-artwork 是 height:186px + padding:10px + box-sizing:border-box，
        //    即内容区 166px、盒子整体仍是 186px。
        //    SwiftUI 的 .padding 是加在外面的，顺序写错会让整个图区变成
        //    186 + 10×2 + 18 = 224pt，把所有下面的内容往下推 38pt。
        //    所以先 padding 撑出内边区，再 frame 锁死总高。
        .padding(.horizontal, DetailCardMetrics.artworkPadding)
        .padding(.vertical, DetailCardMetrics.artworkPadding)
        .frame(maxWidth: .infinity)
        .frame(height: DetailCardMetrics.artworkHeight)
        .background(
            // 玻璃上再铺一层实色会显脏，所以用半透明渐变（H5 同款）
            LinearGradient(
                colors: [
                    Color(red: 227/255, green: 219/255, blue: 207/255).opacity(0.72),
                    Color(red: 251/255, green: 248/255, blue: 243/255).opacity(0.60)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        // 与下方文字的间距（H5 `margin: 0 0 18px`），如实现在盒子之外
        .padding(.bottom, 18)
    }

    private var divider: some View {
        // H5 `.back-divider { height: 1px; margin: 14px 0 }`
        // 用 VStack 承载间距，避免「padding 加在外侧」改变行的总高
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.black.opacity(0.04), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.vertical, 14)
    }

    private var factsList: some View {
        VStack(spacing: 9) {
            ForEach(facts, id: \.0) { key, value in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(key)
                        .font(.system(size: 11.5))
                        .tracking(0.3)
                        .foregroundStyle(HeroPalette.captionSub)
                    Spacer(minLength: 0)
                    Text(value)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(HeroPalette.factValue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var tagList: some View {
        FlowTags(tags: bag.tags)
            .padding(.top, 16)
    }

    private var noteBlock: some View {
        Text(bag.note)
            .font(.system(size: 12))
            .foregroundStyle(HeroPalette.noteText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 11,
                    bottomTrailingRadius: 11, topTrailingRadius: 11,
                    style: .continuous
                )
                .fill(Color.black.opacity(0.035))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 2)
            }
            .padding(.top, 15)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HeroPalette.factValue)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .accessibilityLabel("关闭")
    }
}

// MARK: - 标签流式布局

/// 标签自动换行。
/// ⚠ 直接复用 `HeroCardView.swift` 里的全局 `FlowRow`，不要在本文件另建一个。
///    本项目已经有 `FlowRow`（HeroCardView，标签用，spacing 5）和
///    `FlowLayout`（AddBagView，输入框下方标签用，spacing 6）两套流式布局；
///    再加第三套同名实现只会带来重名风险与维护负担。
///    H5 对应 `.back-tags { display: flex; flex-wrap: wrap; gap: 7px }`。
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        FlowRow(spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Text("# \(tag)")
                    .font(.system(size: 11))
                    .foregroundStyle(HeroPalette.tagText)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.055), in: Capsule())
            }
        }
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.91, blue: 0.88).ignoresSafeArea()
        DetailCardView(
            bag: PreviewData.sampleManagedBag(),
            index: 0,
            base: .now,
            onClose: {}
        )
        .padding(20)
    }
    .modelContainer(PreviewData.container)
}
