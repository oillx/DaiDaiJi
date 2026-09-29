import SwiftUI
import SwiftData

// MARK: - 详情卡尺寸（对应 H5 `.detail-card`）

/// 详情浮层的几何常量。
/// ⚠️ 每个数字都必须能在 H5 侧找到对应声明，否则两版会漂移：
///  - H5 `styles.css` → `.detail-card { width: min(348px, …); height: min(560px, …) }`
///  - H5 `styles.css` → `.detail-artwork { --art-h: 168px }`（编辑态另有 128px）
///  - H5 `--detail-radius: 30px`
enum DetailCardMetrics {
    static let cardWidth: CGFloat = 348
    static let cardHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 30
    /// 顶部大图区高度（只读态）。
    ///
    /// ⚠️ H5 侧 `.detail-artwork { --art-h: 168px }`，这里必须跟着用 168。
    ///    186 是「旧半窗」继承下来的数值（H5 注释里写明了它偏大：
    ///    图区 + 下边距会吃掉滚动视口的 42%，标签行被切在视口外），
    ///    iOS 之前一直按 186 渲染，与原型差 18pt。
    static let artworkHeight: CGFloat = 168
    /// 编辑态图区高度：H5 `.detail-card.is-editing .detail-artwork { --art-h: 128px }`。
    /// 行距从 6 放宽到 14 多吃了 59px，图片从 148 收到 128 省回 20px 作为折中。
    static let editingArtworkHeight: CGFloat = 128
    /// 图区自身的内边距（H5 `.detail-artwork { padding: 10px }`）
    static let artworkPadding: CGFloat = 10
    /// 图片实际可用高度 = 图区 − 上下内边距（H5 `calc(var(--art-h) - var(--art-pad) * 2)`）
    static func artworkInnerHeight(_ areaHeight: CGFloat) -> CGFloat {
        areaHeight - artworkPadding * 2
    }
    /// 内容区左右内边距（H5 `.detail-scroll { padding: 22px 24px 28px }`）
    static let paddingH: CGFloat = 24
    static let paddingTop: CGFloat = 22
    /// 窄屏退化：H5 是 `calc(100vw - 36px)` / `calc(100dvh - 96px)`
    static let minSideInset: CGFloat = 36
    static let minVerticalInset: CGFloat = 96
    /// 打开动效（H5 `--detail-open-dur: .30s` + `cubic-bezier(.2,.78,.22,1)`）
    static let openDuration: Double = 0.30
    static let openScale: CGFloat = 0.92

    /// 底部动作区（H5 `.detail-actions { gap: 10px; margin: 12px 24px 20px }`）
    static let actionGap: CGFloat = 10
    static let actionHeight: CGFloat = 48
    static let actionRadius: CGFloat = 24

    /// 按可用空间算出实际卡片尺寸（与 H5 的 min() 降级同口径）
    static func size(in available: CGSize) -> CGSize {
        CGSize(
            width: min(cardWidth, available.width - minSideInset),
            height: min(cardHeight, available.height - minVerticalInset)
        )
    }
}

/// 详情卡的光效强度。
///
/// ⚠️ 与首页主卡**不同**：H5 在 `.detail-glass` 下各覆盖了一条 ——
///    `.detail-glass .glass-glow { opacity: .85 }`（主卡是 1）
///    `.detail-glass .light-beam { opacity: .26 }`（主卡正面 .9、背面 .34）
///    详情卡比主卡大、又浮在暗遮罩上，光一强就显脏，所以整体压一档。
private enum DetailChrome {
    static let glowOpacity: Double = 0.85
    static let beamOpacity: Double = 0.26
}

// MARK: - 编辑态表单（对应 H5 `.ef-*` 一族）

/// 「下划线 · 纸感」表单的度量。
/// H5 注释里的方案③：撤掉所有方框与底色，每个字段只留一条底线。
enum EditMetrics {
    /// H5 `.ef-row { padding-top: 14px }`（原为 6px，五行挤成一坨）
    static let rowTopPadding: CGFloat = 14
    /// H5 `.ef-key { flex: 0 0 74px }`
    static let keyWidth: CGFloat = 74
    /// H5 `.ef-key { padding-bottom: 9px }` / `.ef-input { padding: 0 0 9px }`
    static let underlineGap: CGFloat = 9

    // 只读条：列宽两端对齐（H5 实测 78 / 148 / 72，总宽 298 ≤ 内容区 300）
    static let readoutNumberWidth: CGFloat = 78
    static let readoutLocationWidth: CGFloat = 130
    static let readoutAgoWidth: CGFloat = 72
    static let readoutCellPadding: CGFloat = 12
    static let readoutGap: CGFloat = 14

    // 长度上界：与 H5 的 maxlength 一一对应
    static let nameLimit = 24
    static let shelfLimit = 20
    static let tagLimit = 12

    // 候选面板
    static let shelfSuggestLimit = 5
    static let tagSuggestLimit = 6
    /// H5 `.ef-row--shelf .ef-suggest { max-height: 176px }`
    static let suggestMaxHeight: CGFloat = 176
}

/// 编辑态用色。都取自 H5 的 `.ef-*` 规则，不引用系统色 ——
/// 系统色会随深浅色模式变，而这张卡是固定浅色纸感的。
/// 编辑态用色。🔻 本类型对模块可见（原 `private`）：新增半窗（`AddBagView`）
/// 复用同一套字段样式，配色必须同源，不能再造一份。
enum EditPalette {
    /// H5 `.ef-input { color: var(--ink) }`
    static let ink = Color(red: 20/255, green: 20/255, blue: 20/255)
    /// H5 `.ef-key { color: var(--muted) }`
    static let key = Color(red: 119/255, green: 115/255, blue: 109/255)
    /// H5 `.ef-input { border-bottom: 1px solid rgba(20,20,20,.13) }`
    static let underline = Color.black.opacity(0.13)
    /// H5 `.ef-readout__v { color: #3a3630 }`
    static let readoutValue = Color(red: 58/255, green: 54/255, blue: 48/255)
    /// H5 `.ef-readout__k { color: #a8a49d }`
    static let readoutKey = Color(red: 168/255, green: 164/255, blue: 157/255)
    /// H5 `.ef-readout__cell { border-left: 1px solid rgba(20,20,20,.085) }`
    static let readoutLine = Color.black.opacity(0.085)
    /// H5 `.ef-chip`
    static let chipText = Color(red: 69/255, green: 65/255, blue: 58/255)
    static let chipFill = Color.black.opacity(0.07)
    static let chipClose = Color.black.opacity(0.17)
    /// H5 `.ef-suggest__item { color: #45413a }`
    static let suggestText = Color(red: 69/255, green: 65/255, blue: 58/255)
    /// H5 `.ef-suggest__hint` / `.ef-suggest__item s { color: #b0aca5 }`
    static let suggestMuted = Color(red: 176/255, green: 172/255, blue: 165/255)
    /// H5 `.ef-suggest__new { color: #2A4DA6 }`（靛蓝，白底对比度 7.75:1）
    static let suggestNew = Color(red: 42/255, green: 77/255, blue: 166/255)
    /// H5 `.ef-area { background: rgba(20,20,20,.032) }`
    static let noteFill = Color.black.opacity(0.032)
    /// H5 `.ef-area { border-left: 2px solid rgba(20,20,20,.16) }`
    static let noteLine = Color.black.opacity(0.16)
}

// MARK: - 详情浮层

/// 纸袋详情：居中弹出的液态玻璃卡片。
///
/// 设计对齐 H5 的 `.detail-card`（复刻首页卡片**背面**的观感，整体放大）：
///  只读态：纸袋大图 → 眉标编号 → 衬线名称 → 品牌 → 分隔线 → 键值对
///          → 标签 → 引用式备注 → 底部 [编辑][完成]
///  编辑态：小图 → 只读三块条 → 下划线表单（名称 / 品牌 / 收藏日期 / 标签 / 备注）
///          → 底部 [取消][保存]
///
/// 编辑是**卡片原地切换**（H5 `.detail-card.is-editing`），不新开浮层；
/// 未保存的改动全部留在草稿里，取消即丢弃 —— 所以下面每个字段都是
/// `draft*` 而不是直接绑到 `bag` 上。直接改 `bag` 再「取消」是回不去的。
struct DetailCardView: View {
    let bag: BagItem
    var base: Date
    var onClose: () -> Void
    /// 次级入口：推入可编辑/可删除的完整页（`BagDetailView`）。
    /// 原型里详情卡没有这一层，但 iOS 的删除能力在那边，保留出口不丢功能。
    var onMore: (() -> Void)?
    /// 编辑态变化上报给宿主 —— 宿主据此决定「点卡外」还要不要响应
    var onEditingChange: (Bool) -> Void = { _ in }
    /// 保存成功（用于弹 toast，H5 `showToast('"xxx"已更新')`）
    var onSaved: (String) -> Void = { _ in }

    /// 呈现形态：
    ///  · `.card`  —— 居中浮层大卡（默认）。首页 / 收藏页点袋子看详情走这个
    ///  · `.sheet` —— **半窗**（系统 sheet + `presentationDetents`）。
    ///               卡片底部点「编辑」时以这个形态弹出（用户要求：编辑不再卡内原地切换）
    enum Form { case card, sheet }
    var form: Form = .card
    /// 半窗形态下进来即处于编辑态（由 `.card` 那侧的「编辑」拉起）
    var startsEditing = false

    @Environment(\.modelContext) private var context
    /// 匹配下拉的数据源：全部已有品牌 / 标签，由现有藏品统计出来
    @Query(sort: \BagItem.createdAt, order: .reverse) private var allBags: [BagItem]

    @State private var isEditing = false
    /// 「编辑」拉起的半窗是否在显示（见 `presentEditSheet`）
    @State private var showEditSheet = false

    /// 半窗形态下用来收起自己
    @Environment(\.dismiss) private var dismiss

    // ── 编辑态草稿 ──
    @State private var draftName = ""
    @State private var draftShelf = ""
    @State private var draftDate = ""
    @State private var draftTags: [String] = []
    @State private var draftTagInput = ""
    @State private var draftNote = ""
    /// 品牌行的值区高度，用来把候选面板**绝对定位**到下划线之下
    /// （H5 `.ef-row--shelf .ef-suggest { position: absolute; top: 100% }`）
    @State private var shelfFieldHeight: CGFloat = 0

    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, shelf, date, tag, note }

    private var facts: [(String, String)] {
        [
            ("品牌 / 店铺", bag.displayShelf),
            ("上传地点", bag.location),
            // 📌 「材质」行按用户要求**去掉**（H5 的 `back-facts` 里有这一行）。
            //    顺带记一笔它为什么显眼：`displayMaterial` 在空值时渲染成「—」而不是空串，
            //    所以它永远过不了下面 `.filter` 的空值过滤 —— 没有材质数据的藏品
            //    也会稳定多出一行「材质　—」。
            ("收藏日期", DateFormat.dash(bag.createdAt)),
            ("入库时长", RelativeDay.text(bag.createdAt, base: base)),
            ("编号", bag.numberText)
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        if form == .sheet {
            sheetLayout
        } else {
            cardLayout
        }
    }

    /// 居中浮层大卡（默认形态）。
    /// 结构与原来完全一致，只多挂了一个「编辑 → 半窗」的 sheet。
    private var cardLayout: some View {
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
                column: geo.size.width
            )

            cardBody
                .frame(width: size.width, height: size.height)
                // `scaleEffect` 不改布局尺寸，视觉中心与 `size` 的中心重合，
                // 所以外层照旧撑满居中即可，不需要补偿位移。
                .scaleEffect(scale)
                // 与 H5 的 `inset:0 + margin:auto` 等价：在父容器里严格居中
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        // 点「编辑」→ 拉起**半窗**（用户要求：编辑不再在卡内原地切换）。
        // 半窗里是同一个 `DetailCardView`，只是 `form: .sheet`。
        .sheet(isPresented: $showEditSheet) {
            DetailCardView(bag: bag,
                           base: base,
                           onClose: {},
                           onMore: nil,
                           onEditingChange: onEditingChange,
                           onSaved: onSaved,
                           form: .sheet,
                           startsEditing: true)
        }
    }

    /// 半窗形态：小图 + 编辑表单 + 底部 [取消][保存]。
    ///
    /// 与卡片形态共用同一份 `editForm`（那几百行表单与候选面板**一个字没搬**），
    /// 只是不套卡片的玻璃边框与投影 —— 半窗自己就是一层系统面板。
    private var sheetLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artwork
                    editForm
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DetailCardMetrics.paddingH)
                .padding(.top, DetailCardMetrics.paddingTop)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            actions
        }
        // 半窗外壳：与「新增纸袋」共用同一份定义
        .editSheetChrome()
        // 由卡片的「编辑」拉起 ⇒ 进来就是编辑态（铺草稿 + 聚焦名称）
        .onAppear { if startsEditing { beginEdit() } }
    }

    private var cardBody: some View {
        VStack(spacing: 0) {
            // ── 内容区（可滚动）──
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artwork
                    if isEditing {
                        editForm
                    } else {
                        readOnlyBody
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
            // ⚠️ 换态时把滚动位置归零。
            //    H5 `enterDetailEdit` 里显式 `scroller.scrollTop = 0`
            //    （图区从 168 收到 128，内容整体变矮，不归零会停在旧位置）。
            //    这里用 `.id` 重建整个滚动区，顺带把上一次的滚动偏移丢掉。
            .id(isEditing)

            // ── 固定底部按钮 ──
            actions
        }
        // 面层：H5 `.detail-card { background: linear-gradient(160deg,
        //   #ffffff 0%, #fafbfd 56%, #f2f4f8 100%) }` —— **不透明**的冷调白，
        //   不是首页主卡那种半透明玻璃（两处配方不同，别混用）。
        //   iOS 之前用的是 `.154` 玻璃 + 一层暖白薄纱（#f7f3ed 30→78%），
        //   那是更早一版的处置：稿面这里是实色，暖纱会把整张卡压成暖灰。
        //   ⚠️ 光泽层与斜射光束**必须留在内容之下**（放进这层 background 里）：
        //      它们原来挂在内容**之上**的 `.overlay` 里，正好压在卡片顶部的袋图上 ——
        //      那束白色径向高光会把袋子左上角洗白、颜色发灰。
        //      首页主卡当初踩过同一个坑（`GlassCardBackground` 的注释原话：
        //      「这层原先放在 `.overlay` 最上层，正好压在袋子图上，是图片被遮住颜色的根因」）。
        .background {
            ZStack {
                CoolGlassSurface.gradient
                // H5 `.detail-glass .light-beam { opacity: .26 }` —— 右上斜射光束
                LightBeam(opacity: DetailChrome.beamOpacity,
                          cornerRadius: DetailCardMetrics.cornerRadius)
            }
        }
        // 边缘三道（H5 `.detail-card` 的 border + 三条 inset 阴影）：
        //   ① border: 1px solid rgba(255,255,255,.62)
        .overlay { cardShape.strokeBorder(Color.white.opacity(0.62), lineWidth: 1) }
        //   ② 上沿 1.0 → 下沿 .34 的 inset 高光（`0 1px 0 #fff inset` + `0 -1px 0 #fff6 inset`）
        .overlay {
            cardShape.strokeBorder(
                LinearGradient(colors: [.white, .white.opacity(0.34)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        //   ③ 内圈白棱 `0 0 0 1px rgba(255,255,255,.9) inset`
        .overlay { cardShape.strokeBorder(CoolGlassSurface.innerRim, lineWidth: 1) }
        // 光泽层（`GlassGlow`）已**去掉** —— 按需求「详情卡顶部那片白色会遮挡图片颜色」。
        // 它是 H5 `.detail-glass .glass-glow { opacity: .85 }` 那颗白色径向高光，
        // 一心要盖在卡顶、正好压住袋图，于是袋子左上角被洗白。
        // ⚠️ 想恢复：不要加回这里的 `.overlay`（那又是盖在图上），
        //    应当加进上面那层 `background` 的 ZStack 里（与斜射光束同址）。
        //    参数仍在 `DetailChrome.glowOpacity`，没删。
        // ⚠ 编辑态不显示右上角「×」：
        //    出口收成底部的 [取消][保存]（与 H5 编辑态一致），
        //    免得「×」和「取消」两个都能退出、语义还不同（一个丢弃一个保留）。
        .overlay(alignment: .topTrailing) {
            if !isEditing { closeButton }
        }
        // 光束与光泽都要被圆角裁掉
        .clipShape(cardShape)
        // ③ 投影：两道冷调近影 + 一道很大的柔影（H5 `0 16px 36px …` /
        //    `0 3px 10px …` / `0 30px 80px rgba(0,0,0,.26)`；CSS blur 取一半当 radius）
        .shadow(color: HeroPalette.shadowBase.opacity(0.16), radius: 18, x: 0, y: 16)
        .shadow(color: HeroPalette.shadowBase.opacity(0.07), radius: 5, x: 0, y: 3)
        .shadow(color: .black.opacity(0.26), radius: 40, x: 0, y: 30)
    }

    /// 卡片轮廓。所有描边 / 裁剪都以它为准，避免各处重复写圆角。
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DetailCardMetrics.cornerRadius, style: .continuous)
    }

    // MARK: - 只读态

    @ViewBuilder
    private var readOnlyBody: some View {
        Text(bag.numberText)
            // H5 `.detail-card .back-eyebrow { font-size: 10.5px; letter-spacing: 1.8px }`
            // 颜色仍是 `.back-eyebrow` 的 `var(--muted)` #77736d（不是正面那档 #8d877c）
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(HeroPalette.muted)
            .padding(.bottom, 6)
        Text(bag.displayName)
            // H5 `.detail-name { font-size: 25px; font-weight: 600 }` + 衬线。
            // 600 那一档（SemiBold）没随包，先用 Bold 顶（差一档、肉眼几乎看不出）。
            .font(AppFont.songti(25))
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
        // 原生型没有「删除」这个概念，iOS 侧仍保留完整页出口，
        // 免得删不掉藏品 —— 文案与「编辑」区分开，避免两个入口都叫编辑。
        if let onMore {
            Button(action: onMore) {
                Text("更多 · 删除 →")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(HeroPalette.backName)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    // MARK: - 编辑态

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            readout
            nameRow
            shelfRow
            dateRow
            tagRow
            noteRow
        }
    }

    /// ① 只读条：编号 / 上传地点 / 入库时长，三块并排。
    ///
    /// 版式要点（都是本轮原型改动的落地）：
    ///  · 去底色、去描边，只留两条 1px 细竖线
    ///  · 顺序倒成「值在上、名在下」，与下方可编辑行的视觉重心对齐
    ///  · 宽度不再三等分：首末列按内容固定，中间列吃掉剩余空间，
    ///    三块因此形成两端对齐（否则「上海市黄浦区」会被截成「上海市黄浦区…」）
    private var readout: some View {
        HStack(alignment: .top, spacing: 0) {
            readoutCell(value: bag.numberText,
                        key: "编号",
                        width: EditMetrics.readoutNumberWidth,
                        alignment: .leading,
                        padding: 0)

            readoutSeparator

            readoutCell(value: bag.displayLocation,
                        key: "上传地点",
                        width: EditMetrics.readoutLocationWidth,
                        alignment: .leading,
                        padding: EditMetrics.readoutCellPadding)
                // 中间列吃掉剩余空间 → 首块贴左、末块贴右
                .frame(minWidth: EditMetrics.readoutLocationWidth, maxWidth: .infinity)

            readoutSeparator

            readoutCell(value: draftAgoText,
                        key: "入库时长",
                        width: EditMetrics.readoutAgoWidth,
                        alignment: .trailing,
                        padding: EditMetrics.readoutCellPadding)
        }
        .padding(.bottom, EditMetrics.readoutGap)
    }

    private var readoutSeparator: some View {
        Rectangle()
            .fill(EditPalette.readoutLine)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func readoutCell(value: String,
                             key: String,
                             width: CGFloat,
                             alignment: Alignment,
                             padding: CGFloat) -> some View {
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EditPalette.readoutValue)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(key)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(EditPalette.readoutKey)
                .lineLimit(1)
        }
        .frame(minWidth: width, alignment: alignment)
        // ⚠️ 竖线在 cell 的**左边缘**（H5 是 border-left），
        //    所以间距用 leading padding 表达，右边不加 —— 末列才能真的贴右。
        .padding(.leading, padding)
    }

    /// 只读条里的「入库时长」跟着编辑中的日期实时变
    /// （H5 注释：「只读的『入库时长』由这个日期推算，改这里它会跟着变」）。
    private var draftAgoText: String {
        // 解析不出来时回退到原值 —— 用户正在打字的中途状态不该让这一格跳成「—」
        RelativeDay.text(DateFormat.parseDash(draftDate) ?? bag.createdAt, base: base)
    }

    /// ② 可编辑行：左标签 + 右值，值下方一条底线
    /// 转发到两个半窗共用的 `EditFieldRow`（见 `HalfSheetForm.swift`）。
    /// 留这个薄壳只为不动下面 5 个调用点 —— 定义只有那一份。
    private func fieldRow<Content: View>(_ key: String,
                                         alignment: VerticalAlignment = .bottom,
                                         @ViewBuilder value: @escaping () -> Content) -> some View {
        EditFieldRow(key: key, alignment: alignment) { value() }
    }

    /// 转发到共用件 `EditUnderline`（定义见 `HalfSheetForm.swift`）。
    private func underline(focused isFocused: Bool) -> some View {
        EditUnderline(focused: isFocused)
    }

    private var nameRow: some View {
        fieldRow("名称") {
            VStack(spacing: 0) {
                TextField("给它起个名字", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(EditPalette.ink)
                    .focused($focus, equals: .name)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.bottom, EditMetrics.underlineGap)
                    // H5 `maxlength="24"`：超出的字直接不收，而不是等到保存才截
                    .onChange(of: draftName) { _, new in
                        if new.count > EditMetrics.nameLimit {
                            draftName = String(new.prefix(EditMetrics.nameLimit))
                        }
                    }
                underline(focused: focus == .name)
            }
        }
    }

    private var shelfRow: some View {
        fieldRow("品牌 / 店铺") {
            VStack(spacing: 0) {
                TextField("选一个或直接输入", text: $draftShelf)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(EditPalette.ink)
                    .focused($focus, equals: .shelf)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    // H5：回车选中第一条候选
                    .onSubmit { if let first = shelfMatches.first { draftShelf = first.text } }
                    .padding(.bottom, EditMetrics.underlineGap)
                    .onChange(of: draftShelf) { _, new in
                        if new.count > EditMetrics.shelfLimit {
                            draftShelf = String(new.prefix(EditMetrics.shelfLimit))
                        }
                    }
                underline(focused: focus == .shelf)
            }
            // 量一下这一行的高度，好把面板绝对定位到下划线之下
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { shelfFieldHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, new in shelfFieldHeight = new }
                }
            }
            // ⚠️ 面板是**绝对定位浮层**，不参与流式布局 ——
            //    否则一弹出就把下面的「收藏日期」整行顶下去（H5 也是这么改的）。
            .overlay(alignment: .topLeading) {
                if showsShelfSuggest {
                    shelfSuggestPanel
                        .offset(y: shelfFieldHeight + 8)
                }
            }
        }
        // ⚠️ zIndex 必须加在**整行**上，加在里面那层值视图上是没用的：
        //    决定绘制顺序的是父级 VStack 里的兄弟顺序 ——「收藏日期」行排在
        //    后面，不用 zIndex 把整行抬起来，面板就会被那一行盖住。
        .zIndex(showsShelfSuggest ? 2 : 0)
    }

    private var dateRow: some View {
        fieldRow("收藏日期") {
            VStack(spacing: 0) {
                // 与 H5 一致用文本框（inputmode: numeric），而不是 DatePicker：
                // 下划线版式里塞一个带边框的日期控件会把「纸感」破掉。
                TextField("2026-09-13", text: $draftDate)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(EditPalette.ink)
                    .focused($focus, equals: .date)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.bottom, EditMetrics.underlineGap)
                underline(focused: focus == .date)
            }
        }
    }

    private var tagRow: some View {
        fieldRow("标签", alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                TagFieldLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(draftTags, id: \.self) { tag in
                        tagChip(tag)
                    }
                    TextField(draftTags.isEmpty ? "加标签，空格或回车分隔" : "",
                              text: $draftTagInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(EditPalette.ink)
                        .focused($focus, equals: .tag)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { commitTag(draftTagInput) }
                        .onChange(of: draftTagInput) { _, new in
                            // H5：敲空格时把前面几段收成胶囊，最后一段留在框里
                            if new.contains(" ") { commitTagsFromInput() }
                        }
                }
                .padding(.bottom, EditMetrics.underlineGap)
                underline(focused: focus == .tag)

                // 标签的候选面板在流内（H5 只有品牌那处是绝对定位）
                if showsTagSuggest { tagSuggestPanel }
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Text("# \(tag)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditPalette.chipText)
            Button {
                draftTags.removeAll { $0 == tag }
            } label: {
                Text("×")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(EditPalette.chipClose, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除标签 \(tag)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(EditPalette.chipFill, in: .rect(cornerRadius: 11))
        // 胶囊高度钉在 26 —— 自定义 Layout 按固定行高排布，这里必须一致
        .frame(height: 26)
    }

    private var noteRow: some View {
        fieldRow("备注", alignment: .top) {
            VStack(spacing: 0) {
                TextField("留一句话，可留空", text: $draftNote, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(EditPalette.ink)
                    .lineLimit(2...3)
                    .focused($focus, equals: .note)
                    .padding(.vertical, 8)
                    .padding(.leading, 11)
                    .frame(minHeight: 66, alignment: .topLeading)
                    .background(EditPalette.noteFill)
                    .overlay(alignment: .leading) {
                        // H5 `.ef-area { border-left: 2px }`，聚焦转品牌红
                        Rectangle()
                            .fill(focus == .note ? HeroPalette.focus : EditPalette.noteLine)
                            .frame(width: 2)
                    }
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 9,
                        bottomTrailingRadius: 9, topTrailingRadius: 0,
                        style: .continuous
                    ))
            }
        }
    }

    // MARK: 候选面板

    private var shelfPool: [Suggestion] { SuggestionMatcher.shelves(in: allBags) }
    private var tagPool: [Suggestion] { SuggestionMatcher.tags(in: allBags) }

    private var shelfMatches: [Suggestion] {
        guard !shelfKeyword.isEmpty else { return [] }
        // H5 排除「与输入完全相同」的那条（已经选好了，不必再列一遍）
        return SuggestionMatcher.matches(shelfKeyword, in: shelfPool,
                                         excluding: [shelfKeyword],
                                         limit: EditMetrics.shelfSuggestLimit)
    }

    private var tagMatches: [Suggestion] {
        SuggestionMatcher.matches(draftTagInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                  in: tagPool,
                                  excluding: Set(draftTags),
                                  limit: EditMetrics.tagSuggestLimit)
    }

    private var shelfKeyword: String {
        draftShelf.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tagKeyword: String {
        draftTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shelfNeedsCreateRow: Bool {
        !shelfKeyword.isEmpty && !SuggestionMatcher.hasExact(shelfKeyword, in: shelfPool)
    }

    private var tagNeedsCreateRow: Bool {
        !tagKeyword.isEmpty && !SuggestionMatcher.hasExact(tagKeyword, in: tagPool)
            && !draftTags.contains(tagKeyword)
    }

    private var showsShelfSuggest: Bool {
        !shelfMatches.isEmpty || shelfNeedsCreateRow
    }

    private var showsTagSuggest: Bool {
        !tagMatches.isEmpty || tagNeedsCreateRow
    }

    private var shelfSuggestPanel: some View {
        suggestPanel(hint: shelfMatches.isEmpty ? "没有匹配的已有品牌" : "已有品牌",
                     matches: shelfMatches,
                     keyword: shelfKeyword,
                     createText: shelfNeedsCreateRow ? shelfKeyword : nil,
                     createKey: "新建品牌") { text in
            draftShelf = text
        }
    }

    private var tagSuggestPanel: some View {
        suggestPanel(hint: tagMatches.isEmpty ? "没有匹配的已有标签" : "已有标签",
                     matches: tagMatches,
                     keyword: tagKeyword,
                     createText: tagNeedsCreateRow ? tagKeyword : nil,
                     createKey: "新建标签") { text in
            commitTag(text)
        }
    }

    private func suggestPanel(hint: String,
                              matches: [Suggestion],
                              keyword: String,
                              createText: String?,
                              createKey: String,
                              onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hint)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(EditPalette.suggestMuted)
                .padding(.horizontal, 7)
                .padding(.top, 3)
                .padding(.bottom, 5)

            ForEach(matches) { item in
                Button { onPick(item.text) } label: {
                    HStack(spacing: 7) {
                        // 只高亮命中的那几个字（H5 `highlightMatch`）
                        Text(SuggestionMatcher.highlight(item.text, keyword: keyword))
                            .font(.system(size: 12.5))
                            .foregroundStyle(EditPalette.suggestText)
                        Spacer(minLength: 0)
                        Text("已有 \(item.count) 件")
                            .font(.system(size: 10))
                            .foregroundStyle(EditPalette.suggestMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(SuggestRowStyle())
            }

            if let createText {
                Button { onPick(createText) } label: {
                    Text("＋ \(createKey)「\(createText)」")
                        .font(.system(size: 12.5))
                        .foregroundStyle(EditPalette.suggestNew)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(SuggestRowStyle())
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color(red: 52/255, green: 66/255, blue: 92/255).opacity(0.10),
                radius: 10, x: 0, y: 8)
        // 品牌面板高度封顶后自己滚（H5 `max-height: 176px; overflow-y: auto`）
        .frame(maxHeight: EditMetrics.suggestMaxHeight, alignment: .top)
    }

    // MARK: - 底部动作区

    /// 底部动作条：两个半窗共用（见 `HalfSheetForm.swift` 的 `EditActionBar`）。
    private var actions: some View {
        if isEditing {
            EditActionBar(secondaryTitle: "取消", onSecondary: cancelEdit,
                          primaryTitle: "保存", onPrimary: save)
        } else {
            EditActionBar(secondaryTitle: "编辑", onSecondary: presentEditSheet,
                          primaryTitle: "完成", onPrimary: onClose)
        }
    }

    // MARK: - 编辑态进出

    /// 点「编辑」：拉起半窗（编辑在那边进行，卡片自身保持只读）。
    ///
    /// ⚠️ 先 `onEditingChange(true)` 再弹窗：宿主据此在这段时间不响应
    ///    「点卡外关闭」，否则半窗弹出的那一帧可能被背景手势顺手把卡片也关掉。
    private func presentEditSheet() {
        onEditingChange(true)
        showEditSheet = true
    }

    /// 铺草稿并进入编辑态。两个形态共用：
    ///  · `.card`：历史上是原地切换（现在改由半窗编辑，这条路只剩半窗在用）；
    ///  · `.sheet`：`sheetLayout.onAppear` 调它。
    private func beginEdit() {
        draftName = bag.name
        draftShelf = bag.category
        draftDate = DateFormat.dash(bag.createdAt)
        draftTags = bag.tags
        draftTagInput = ""
        draftNote = bag.note

        isEditing = true
        onEditingChange(true)
        // H5：等切换的样式落定再聚焦，否则会在布局变化中途触发滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            focus = .name
        }
    }

    /// 取消：不写回任何值，草稿丢弃
    private func cancelEdit() {
        focus = nil
        isEditing = false
        onEditingChange(false)
        // 半窗形态：收起半窗，退回卡片
        if form == .sheet { dismiss() }
    }

    private func save() {
        // 输入框里可能还留着没敲空格的半截词 —— 保存时一并收进去，
        // 否则用户打了「蓝色」直接点保存，这个词会静默丢掉。
        commitTagsFromInput()

        // 名称兜底 + 截断：maxlength 只管键盘打字，程序化赋值（候选点选）绕得过去
        let name = String(draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(EditMetrics.nameLimit))
        bag.name = name.isEmpty ? "未命名收藏" : name

        // 品牌留空则回落到原值 —— 避免用户误删后整条藏品挂到空品牌下
        // （首页陈列会多出一个空分组）
        let trimmedShelf = draftShelf.trimmingCharacters(in: .whitespacesAndNewlines)
        bag.category = trimmedShelf.isEmpty
            ? bag.category
            : String(trimmedShelf.prefix(EditMetrics.shelfLimit))

        bag.tags = draftTags.map { String($0.prefix(EditMetrics.tagLimit)) }
        bag.note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)

        // 日期：合法才写回；清空或写了看不懂的内容就保持原值，
        // 不要把手上的数据弄丢。
        if let parsed = DateFormat.parseDash(draftDate) {
            bag.createdAt = parsed
        }

        try? context.save()

        focus = nil
        isEditing = false
        onEditingChange(false)
        // 退回详情态，让用户看见改完的结果 —— 比直接关掉卡片更让人放心
        onSaved(bag.displayName)
        // 半窗形态：保存完自己收起来，卡片上已经是新数据
        if form == .sheet { dismiss() }
    }

    private func commitTagsFromInput() {
        // H5 `commitTagsFromInput`：按空白拆，最后一段是正在输入的词，留在框里。
        //
        // ⚠️ 必须 `omittingEmptySubsequences: false`：
        //    H5 的 `'霸王 '.split(/\s+/)` 得到 ['霸王', '']，尾段是空串 ——
        //    于是「霸王」被收成胶囊、框被清空。用默认的 true 会得到 ['霸王']，
        //    数量不足 2，整段又被塞回输入框，表现成「敲了空格也没变成标签」。
        let pieces = draftTagInput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: " ", omittingEmptySubsequences: false) }
            .map(String.init)
        guard pieces.count > 1 else {
            draftTagInput = pieces.first ?? ""
            return
        }
        for piece in pieces.dropLast() { _ = commitTag(piece) }
        draftTagInput = pieces.last ?? ""
    }

    /// 把一个词加进标签列表。返回是否真的加了。
    @discardableResult
    private func commitTag(_ raw: String) -> Bool {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return false }
        // 重复标签不重复加（H5 同此）
        guard !draftTags.contains(tag) else {
            draftTagInput = ""
            return false
        }
        // ⚠️ 再按 12 个字截一刀：input 上的 maxlength 管不到
        //    「一次塞进多个词」和「点候选行」这两条路，超长胶囊会把行撑破。
        draftTags.append(String(tag.prefix(EditMetrics.tagLimit)))
        draftTagInput = ""
        return true
    }

    // MARK: - 局部

    private var artwork: some View {
        let areaHeight = isEditing
            ? DetailCardMetrics.editingArtworkHeight
            : DetailCardMetrics.artworkHeight
        return Group {
            if let image = BagImageResolver.load(bag.imageFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // ⚠ 可用高度 = 图区高度 − 上下内边距，与 H5 的
                    //    max-height: calc(var(--art-h) - var(--art-pad) * 2) 同口径。
                    //    H5 侧这里踩过坑：在 grid 里写 max-height:100% 会与网格区域
                    //    形成循环依赖，浏览器回退成原始尺寸，图片撑破容器盖住文字。
                    .frame(maxWidth: .infinity,
                           maxHeight: DetailCardMetrics.artworkInnerHeight(areaHeight))
            } else {
                Image(systemName: "handbag")
                    .font(.system(size: isEditing ? 34 : 44, weight: .light))
                    .foregroundStyle(HeroPalette.captionSub)
            }
        }
        // ⚠ 内边距必须加在「图区的盒子内部」：
        //    H5 的 .detail-artwork 是 height + padding + box-sizing:border-box，
        //    即内容区高度 = 图区 − 20，盒子整体不变。
        //    SwiftUI 的 .padding 是加在外面的，顺序写错会让整个图区变成
        //    「图区 + 10×2 + 18」，把所有下面的内容往下推。
        //    所以先 padding 撑出内边区，再 frame 锁死总高。
        .padding(.horizontal, DetailCardMetrics.artworkPadding)
        .padding(.vertical, DetailCardMetrics.artworkPadding)
        .frame(maxWidth: .infinity)
        .frame(height: areaHeight)
        // ⚠️ 图区**没有底色**：H5 最终版 `.detail-artwork { background: none }`。
        //    早一版给过一块暖灰渐变底（`linear-gradient(145deg,#e3dbcf,#fbf8f3)`、
        //    圆角 25、高 290），已被同名的后一条规则整体覆盖，别再画回来 ——
        //    那样会让图区变成一块显眼的色块，和稿面差得最明显。
        //    （20px 圆角只服务于 `overflow: hidden`，没有底色时不可见。）
        // 与下方文字的间距：只读态 18px，编辑态收到 14px（H5 `.is-editing`）
        .padding(.bottom, isEditing ? 14 : 18)
    }

    private var divider: some View {
        // H5 `.back-divider { height: 1px; margin: 14px 0 }`
        // 用 VStack 承载间距，避免「padding 加在外侧」改变行的总高
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    // H5 `.back-divider`：`linear-gradient(90deg, rgba(20,20,20,.12),
                    //   rgba(20,20,20,.04) 70%, transparent)` —— 底色基准是墨色 #141414，
                    //   第三档落在 70%（不是三色默认均分的 50%）。
                    LinearGradient(
                        stops: [
                            .init(color: HeroPalette.ink(0.12), location: 0),
                            .init(color: HeroPalette.ink(0.04), location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
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
                        // H5 `.detail-card .back-facts__row dt { font-size: 11.5px }`
                        // + `.back-facts__row dt { color: var(--muted) }` → #77736d
                        .font(.system(size: 11.5))
                        .tracking(0.3)
                        .foregroundStyle(HeroPalette.muted)
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
                // H5 `.detail-card .back-note { border-radius: 0 11px 11px 0 }`
                // —— 左上 / 左下都是直角（左边那条竖线要顶到端点）
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 11, topTrailingRadius: 11,
                    style: .continuous
                )
                // H5 `.back-note { background: rgba(20,20,20,.035) }`（墨色基准，不是纯黑）
                .fill(HeroPalette.ink(0.035))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    // H5 `.back-note { border-left: 2px solid rgba(20,20,20,.14) }`
                    .fill(HeroPalette.ink(0.14))
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

/// 候选行的按下反馈：H5 是 `:hover { background: rgba(197,4,5,.08) }`，
/// 触屏没有 hover，改用按下态，颜色取同一个值。
private struct SuggestRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed
                        ? Color(red: 197/255, green: 4/255, blue: 5/255).opacity(0.08)
                        : .clear,
                        in: .rect(cornerRadius: 8))
    }
}

// MARK: - 标签行布局（胶囊 + 输入框同排自动换行）

/// 标签框：已选胶囊在前，输入框跟在后面；放不下时输入框整块换行。
///
/// H5 是 `.ef-tagbox { display:flex; flex-wrap:wrap }` —— 输入框就是
/// flex 里的最后一个子项，剩余宽度不足 `flex: 1 1 62px` 的下限时
/// 自己换到下一行。
///
/// ⚠️ 不能直接用 `FlowRow`（HeroCardView 那套）：它给每个子项的都是
///    `sizeThatFits(.unspecified)`，输入框拿不到「剩余宽度」这个约束，
///    会按自己的理想宽度排版，胶囊一多就会溢出。
private struct TagFieldLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// 输入框能并排时的最小宽度（H5 `min-width: 62px`）
    var minFieldWidth: CGFloat = 62
    /// 行高钉死：胶囊与输入框都居中在这一行里，不用两趟测量
    var lineHeight: CGFloat = 26

    private func lines(chips: [LayoutSubview], maxWidth: CGFloat) -> Int {
        guard !chips.isEmpty else { return 1 }
        var count = 1
        var x: CGFloat = 0
        for chip in chips {
            let width = chip.sizeThatFits(.unspecified).width
            if x > 0, x + spacing + width > maxWidth {
                count += 1
                x = 0
            }
            x += (x > 0 ? spacing : 0) + width
        }
        // 末行还剩多少给输入框；不够就再占一行
        if maxWidth - (x + spacing) < minFieldWidth { count += 1 }
        return count
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let chips = Array(subviews.dropLast())
        let count = lines(chips: chips, maxWidth: maxWidth)
        return CGSize(width: maxWidth == .infinity ? 0 : maxWidth,
                      height: CGFloat(count) * lineHeight + CGFloat(count - 1) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard let field = subviews.last else { return }
        let maxWidth = bounds.width
        let chips = Array(subviews.dropLast())

        var x: CGFloat = 0
        var line = 0
        for chip in chips {
            let size = chip.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                line += 1
                x = 0
            }
            if x > 0 { x += spacing }
            chip.place(at: CGPoint(x: bounds.minX + x,
                                   y: bounds.minY + CGFloat(line) * (lineHeight + lineSpacing)
                                       + (lineHeight - size.height) / 2),
                       anchor: .topLeading,
                       proposal: ProposedViewSize(size))
            x += size.width
        }

        // 输入框：本行放得下就并排，否则整块换到下一行
        let remaining = maxWidth - (x > 0 ? x + spacing : 0)
        var fieldX: CGFloat = 0
        if x > 0, remaining < minFieldWidth {
            line += 1
            fieldX = 0
        } else {
            fieldX = x > 0 ? x + spacing : 0
        }
        let fieldWidth = maxWidth - fieldX
        let fieldSize = field.sizeThatFits(ProposedViewSize(width: fieldWidth, height: lineHeight))
        field.place(at: CGPoint(x: bounds.minX + fieldX,
                                y: bounds.minY + CGFloat(line) * (lineHeight + lineSpacing)
                                    + (lineHeight - fieldSize.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: fieldWidth, height: lineHeight))
    }
}

// MARK: - 标签流式布局

/// 标签自动换行。
/// ⚠ 直接复用 `HeroCardView.swift` 里的全局 `FlowRow`，不要在本文件另建一个。
///    本项目已经有 `FlowRow`（HeroCardView，标签用，spacing 5）和
///    `TagFieldLayout`（本文件，编辑态标签框）两套流式布局；
///    再加第三套同名实现只会带来重名风险与维护负担。
///    H5 对应 `.back-tags { display: flex; flex-wrap: wrap; gap: 7px }`。
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        FlowRow(spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Text("# \(tag)")
                    // H5 `.detail-card .back-tags span { padding: 6px 12px;
                    //      border-radius: 12px; font-size: 11px }`
                    //   + `.back-tags span { background: rgba(20,20,20,.055); color: #5d594f }`
                    //   圆角是明确的 12（不是胶囊：胶囊会跟着高度变化）
                    .font(.system(size: 11))
                    .foregroundStyle(HeroPalette.tagText)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(HeroPalette.ink(0.055), in: .rect(cornerRadius: 12))
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
            base: .now,
            onClose: {}
        )
        .padding(20)
    }
    .modelContainer(PreviewData.container)
}

// ═══════════════════════════════════════════════════════════════
//  MARK: - 两个半窗共用的表单件（编辑详情 / 新增纸袋）
//
//  📌 用户要求：「上传新增袋子的半窗要复用编辑卡片的半窗样式 UI」。
//     字段原语与半窗外壳抽到这里 —— 两处**只有一份定义**。
//
//  ⚠️ 为什么不开单独的文件：本工程的 `DaiDaiJi.xcodeproj` 是手工维护的
//     （`project.yml` 只是留档，机器上没有 xcodegen），新文件不会自动进 target。
//     等哪天工程改成用 XcodeGen 生成，再把它单独拆出去。
// ═══════════════════════════════════════════════════════════════

// ── 下面这一段的原始文件头（保留以说明各件用途）──
// ═══════════════════════════════════════════════════════════════
//  「编辑详情」与「新增纸袋」两个半窗共用的表单件
//
//  📌 用户要求：「上传新增袋子的半窗要复用编辑卡片的半窗样式 UI」。
//     于是把编辑态的字段原语与半窗外壳抽到这里 —— 两处**只有一份定义**：
//       · `EditFieldRow`     一行下划线字段（左 key 右值，H5 `.ef-row`）
//       · `EditUnderline`    字段下划线（聚焦时转品牌红）
//       · `EditActionBar`    底部「次要 + 主要」两个动作
//       · `.editSheetChrome()`  半屏 detent + 拖拽指示条 + 圆角 30 + 冷调白底
//
//  ⚠️ 数值一律取 `EditMetrics` / `DetailCardMetrics` / `EditPalette`
//     （`DetailCardView.swift` 里那几套）。**不要在本文件里写新数字** ——
//     那正是两个半窗慢慢跑偏的开始。
// ═══════════════════════════════════════════════════════════════

/// 一行下划线字段（H5 `.ef-row`）：左侧 10.5pt 粗体 key（定宽 `EditMetrics.keyWidth`），
/// 右侧值区占满剩余。
///
/// ⚠️ 下划线不在这一层 —— 它由值区自己挂（`EditUnderline`），
///    因为每条下划线要跟随**各自那一个**输入框的聚焦态。
struct EditFieldRow<Content: View>: View {
    let key: String
    var alignment: VerticalAlignment = .bottom
    @ViewBuilder var value: () -> Content

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(key)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(EditPalette.key)
                .frame(width: EditMetrics.keyWidth, alignment: .leading)
                .padding(.bottom, alignment == .bottom ? EditMetrics.underlineGap : 0)

            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, EditMetrics.rowTopPadding)
    }
}

/// 字段下划线：聚焦时整条转品牌红
/// （H5 `.ef-input:focus { border-bottom-color: var(--focus) }`）。
struct EditUnderline: View {
    var focused: Bool

    var body: some View {
        Rectangle()
            .fill(focused ? HeroPalette.focus : EditPalette.underline)
            .frame(height: 1)
    }
}

/// 底部动作条：左「次要」（描边、定宽 96）+ 右「主要」（实心胶囊、占满剩余）。
///
/// 详情卡编辑态是 [取消][保存]，新增半窗是 [取消][保存]（未选图时禁用），
/// 两处尺寸 / 圆角 / 字重只有这一份定义。
struct EditActionBar: View {
    var secondaryTitle: String
    var onSecondary: () -> Void
    var primaryTitle: String
    /// 主要动作是否可用（新增表单没选图时就是 false）
    var primaryEnabled: Bool = true
    var onPrimary: () -> Void

    var body: some View {
        HStack(spacing: DetailCardMetrics.actionGap) {
            Button(action: onSecondary) {
                Text(secondaryTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EditPalette.ink)
                    .frame(width: 96)
                    .frame(minHeight: DetailCardMetrics.actionHeight)
                    .background(Color.black.opacity(0.001))   // 保证整块都可点
                    .overlay {
                        RoundedRectangle(cornerRadius: DetailCardMetrics.actionRadius,
                                         style: .continuous)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: DetailCardMetrics.actionHeight)
                    .background(HeroPalette.backName, in: Capsule())
                    // 禁用时压一档 —— 比灰掉整块更看得出来「还差一张图」
                    .opacity(primaryEnabled ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, DetailCardMetrics.paddingH)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

extension View {
    /// 「编辑详情 / 新增纸袋」两个半窗共用的外壳：
    /// 半屏 detent（可上拉全屏）+ 拖拽指示条 + 圆角 30 + 冷调白底。
    ///
    /// ⚠️ 底色用 `presentationBackground` 而不是内容自己的 `.background`：
    ///    前者连安全区一起铺（底部不留系统灰），后者只铺内容那一块 ——
    ///    设置半窗当初踩过同一件事。
    func editSheetChrome() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(DetailCardMetrics.cornerRadius)
            .presentationBackground(CoolGlassSurface.gradient)
    }
}
