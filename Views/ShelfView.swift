import SwiftUI
import SwiftData

// ═══════════════════════════════════════════════════════════════
//  首页：陈列（showcase）+ 全部收藏（library）双屏 + 底部导航
//
//  H5 对应：`袋袋集原型/index.html` 的 `.screen[data-screen]` 与 `.bottom-nav`，
//           `app.js` 的 `navigate()` / `renderShowcase()` / `renderLibrary()`
// ═══════════════════════════════════════════════════════════════

struct ShelfView: View {
    @Query(sort: \BagItem.createdAt, order: .reverse) private var allBags: [BagItem]

    @State private var screen: Screen = .showcase
    @State private var showAdd = false
    @State private var keyword = ""
    @State private var selectedBagID: UUID?
    /// 从「查看大图」进来的详情
    @State private var detailBag: BagItem?
    /// 从详情卡「编辑」进入的可编辑整页（详情卡本身是只读浮层）
    @State private var editBag: BagItem?
    /// 全部收藏的布局：分组横滑（默认）/ 扁平网格。
    /// H5 对应 `libraryView` + `setLibraryView()`。
    @State private var isGrid = false
    /// 点首页「最近收藏 N」后滚到「最近收集」区。
    /// H5 对应 `bindRecentPill()` 里的 `scrollIntoView`。
    @State private var scrollToRecent = false
    /// 「最近收集」区的滚动锚点（`.scrollPosition(id:)` 用）
    @State private var scrolledAnchor: String?
    @State private var showSettings = false
    private let recentAnchorID = "recentSection"

    /// 容器（＝屏幕或 iPad 分屏窗口）的实测宽度。
    ///
    /// ⚠️ 这是整个跨设备适配的**唯一输入**：列宽、主卡放大倍数、
    ///    网格列数、底栏跨度全部由它派生。所以 `body` 里那个
    ///    `WidthProbe` 不能省 —— 少了它这里恒为 0，
    ///    `AppLayout.column` 会一路回退到 `phoneWidth`(393)，
    ///    iPad 上「卡片不放大、底栏铺满全宽、网格列数按手机算」，
    ///    整套适配会静默失效（不报错、只是看起来没生效）。
    @State private var containerWidth: CGFloat = 0

    /// 网格缩放：当前卡片宽度，41（小档）↔ 82（大档）连续变化。
    /// H5 对应 `--grid-w-num`，是整套尺寸的唯一真源。
    @State private var gridW: CGFloat = GridZoom.maxW
    /// 双指手势开始时的宽度。MagnificationGesture 给的是相对倍数，
    /// 必须乘回起始值，否则会自我复利、几帧就冲到上限。
    @State private var zoomStartW: CGFloat?

    /// H5 `const MAX_GRID_RENDER = 240` / `localStorage['ddj.gridW']`
    static let maxGridRender = 240
    static let gridWKey = "ddj.gridW"

    /// 首屏阅读列宽（由容器宽度派生；宽屏封顶 620）
    private var showcaseColumn: CGFloat {
        AppLayout.column(containerWidth, max: AppLayout.showcaseMaxWidth)
    }

    /// 收藏页阅读列宽（宽屏封顶 940，比首屏宽 —— 网格列多）
    private var libraryColumn: CGFloat {
        AppLayout.column(containerWidth, max: AppLayout.libraryMaxWidth)
    }

    /// 主卡放大倍数。iPhone 上列宽 ≤ 393，恒为 1.0（等价于没缩放）。
    private var heroScale: CGFloat { AppLayout.cardScale(forColumn: showcaseColumn) }

    /// 网格视图需要的纵向高度：由当前卡片高度推出来。
    /// SwiftUI 的 ScrollView(.horizontal) 必须有确定高度，否则会向父级要无限空间。
    /// 行数按「已渲染卡片数 ÷ 列数」算，再乘行高与间距。
    ///
    /// ⚠️ viewport 原来写死 430（手机壳宽度）。iPad 上列宽 940，
    ///    一屏能放的列数是手机的两倍多 —— 用 430 算出来的行数偏多，
    ///    整个网格会多出一大片空高度。必须用实测列宽。
    private var gridViewHeight: CGFloat {
        let cols = max(1, GridZoom.columnCount(gridW, viewport: libraryColumn))
        let rows = max(1, Int(ceil(Double(min(filteredBags.count, Self.maxGridRender)) / Double(cols))))
        let cardH = 116 - 58 * ((82 - gridW) / 41)
        let gap = GridZoom.gap(gridW)
        return CGFloat(rows) * cardH + CGFloat(rows - 1) * gap + 12
    }

    enum Screen: String, CaseIterable {
        case showcase = "陈列"
        case library  = "全部收藏"
    }

    /// 时间基准。
    ///
    /// 演示数据日期写死在 2026 年，必须用「数据集里最新的那一天」当今天，
    /// 否则「最近 15 天」会全部失效。真实用户数据走 `.now`。
    /// 这里用「数据是否落在过去 60 天内」来判断是不是演示数据，
    /// 让同一个构建既能演示、也能装真实数据。
    private var base: Date {
        let newest = allBags.map(\.createdAt).max() ?? .now
        let isDemoData = Feed.daysAgo(newest, base: .now) > 60
        return isDemoData ? newest : .now
    }

    private var recentBags: [BagItem] { Feed.recent(allBags, base: base) }

    /// 主展位当前展品：优先用户选中的，其次最近的第一只
    private var heroBag: BagItem? {
        if let id = selectedBagID, let hit = allBags.first(where: { $0.id == id }) {
            return hit
        }
        return recentBags.first ?? allBags.first
    }

    private var heroIndex: Int {
        guard let heroBag else { return 0 }
        return allBags.firstIndex(where: { $0.id == heroBag.id }) ?? 0
    }

    /// 详情卡里的 NO.xxx 要跟首页背面、网格卡用同一条规则：
    /// 序号取自同一份 `allBags`（按 createdAt 倒序），不是「最近 15 天」的子集。
    /// ⚠️ 编号是「在数据集里的位置」，删掉中间某一只后后面会整体前移 —— H5 同此口径。
    private func indexInAll(_ bag: BagItem) -> Int {
        allBags.firstIndex(where: { $0.id == bag.id }) ?? 0
    }

    /// 详情浮层：遮罩 + 居中卡片。
    /// 用 overlay 而不是 .sheet / .navigationDestination ——
    /// 参考对象是 H5 的 `.detail-card`（居中弹出卡片，不是半窗也不是推入页）。
    @ViewBuilder
    private var detailOverlay: some View {
        if let bag = detailBag {
            ZStack {
                // 遮罩：对应 H5 `.sheet-backdrop { background: rgba(17,15,12,.36); blur(3px) }`
                Color(red: 17/255, green: 15/255, blue: 12/255).opacity(0.36)
                    .ignoresSafeArea()
                    .onTapGesture { detailBag = nil }

                DetailCardView(
                    bag: bag,
                    index: indexInAll(bag),
                    base: base,
                    onClose: { detailBag = nil },
                    onEdit: { editBag = bag; detailBag = nil }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                // H5：.92 → 1.0 原地放大淡入
                .transition(.scale(scale: DetailCardMetrics.openScale).combined(with: .opacity))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // ── 屏幕内容 ──
                Group {
                    switch screen {
                    case .showcase: showcaseScreen
                    case .library:  libraryScreen
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // ── 底部导航（陈列 | ＋ | 全部收藏）──
                BottomNav(screen: $screen) { showAdd = true }
            }
            .background(PageBackground())
            // 读一次容器宽度。放在背景层里，不占位、不撑高、不影响视觉；
            // iPad 旋转与分屏拖动都会触发 onChange，布局随之重算。
            .background { WidthProbe(width: $containerWidth) }
            .toolbar(.hidden, for: .navigationBar)
            // 详情：居中弹出卡片（不是半窗、也不是推入页）
            .overlay { detailOverlay }
            .animation(
                .timingCurve(0.2, 0.78, 0.22, 1, duration: DetailCardMetrics.openDuration),
                value: detailBag?.id
            )
            // 从详情卡点「编辑」才进入可编辑的完整页，保留原有的编辑/删除能力
            .navigationDestination(item: $editBag) { bag in
                BagDetailView(bag: bag)
            }
            // 「＋」直接拉起拍摄页。拍摄页是带自定义顶栏的整页设计，所以走全屏而非半窗。
            .fullScreenCover(isPresented: $showAdd) {
                AddBagView(startsInCamera: true)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(totalCount: allBags.count)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 陈列屏

    private var showcaseScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShowcaseHeader(
                    recentCount: Feed.recentCount(allBags, base: base)
                ) {
                    // 点「最近收藏 N」滚到下面的「最近收集」区
                    withAnimation(.easeOut(duration: 0.35)) { scrollToRecent = true }
                }

                // ── 主展位 ──
                HeroCardView(
                    bag: heroBag,
                    displayIndex: heroIndex,
                    base: base,
                    onOpenDetail: { detailBag = $0 }
                )
                // ── 宽屏（iPad）等比放大 ──
                // 卡片内部所有尺寸（字号 / 圆角 / 投影 / 内边距）都按 iPhone 393pt
                // 稿面写死，所以只能整体缩放；只把外框改大只会多出一圈空白，
                // 比例反而崩。`scaleEffect` 不改布局尺寸，所以要再补一个等大的 frame，
                // 否则放大后的卡片会视觉溢出、压到下面的「最近收集」。
                // iPhone 上 `heroScale` 恒为 1.0，这两行是恒等变换。
                .scaleEffect(heroScale)
                .frame(width: HeroMetrics.cardWidth * heroScale,
                       height: HeroMetrics.cardHeight * heroScale)
                // ⚠️ 这行不能省。外层 VStack 是 `alignment: .leading`，而主卡自身
                //    是固定 308pt 宽（`HeroMetrics.cardWidth`），不撑满可用宽度 ——
                //    结果卡片会被贴到左边，右侧空出一大块。这里撑满整行再居中，
                //    卡片才真正落在页面中轴线上。
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.bottom, 26)
                .id(heroBag?.id)   // 换袋子时重建，避免动画残留

                // ── 最近收集 ──
                // 设置面板原本只能从首页右上角圆钮进入，圆钮改成「最近收藏 N」之后
                // 入口搬到了这里（H5 是 `.section-heading__actions` 里的齿轮按钮）。
                RackSection(
                    items: recentBags,
                    base: base,
                    selectedID: heroBag?.id,
                    onSeeAll: { screen = .library },
                    onSelect: { selectBag($0) },
                    onOpenSettings: { showSettings = true }
                )
                .id(recentAnchorID)
                .padding(.bottom, 34)
            }
            // 宽屏（iPad）把整屏内容收进阅读列居中。
            //
            // ⚠️ 这一层不能省，而且必须与 `heroScale` 用同一个列宽口径：
            //    少了它，「袋袋集」标题会被顶到屏幕最左、右上角「最近收藏 N」
            //    胶囊被甩到最右（相隔上千点），挂袋区也会铺满全宽；
            //    而主卡又按列宽放大了 1.35 倍 —— 一屏之内两套宽度标准，
            //    看起来就是「散架」。iPhone 上 393 < 620，恒等变换。
            .contentColumn(AppLayout.showcaseMaxWidth)
            // 给底栏让位。H5 写死 152px，是因为它的底栏固定 132px，等于「底栏 + 20」。
            // 这里的底栏高度可调，所以改成由 `BottomNav.navHeight` 派生 ——
            // 否则底栏一变矮，滚动到底部就会多出一大块空白（85 配 152 会剩 67pt）。
            .padding(.bottom, BottomNav.navHeight + 20)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledAnchor, anchor: .top)
        .onChange(of: scrollToRecent) { _, go in
            guard go else { return }
            scrolledAnchor = recentAnchorID
            // 滚完复位，方便下次再点
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { scrollToRecent = false }
        }
        // 恢复上次的缩放宽度。两端都夹在 [41, 82]，
        // 防止旧版本或异常写值把尺寸带到范围外。
        .onAppear {
            let saved = UserDefaults.standard.double(forKey: Self.gridWKey)
            if saved > 0 {
                gridW = min(GridZoom.maxW, max(GridZoom.minW, CGFloat(saved)))
            }
        }
    }

    /// 点挂袋：先翻回正面（由 HeroCardView 内部 onChange 处理），再换主卡。
    /// H5 `showRackHero()` 里就是先 `setHeroFlipped(false)` 再换内容。
    private func selectBag(_ bag: BagItem) {
        selectedBagID = bag.id
    }

    // MARK: - 全部收藏屏

    private var filteredBags: [BagItem] {
        allBags.filter { $0.matches(keyword) }
    }

    private var groupedBags: [(shelf: String, bags: [BagItem])] {
        let groups = Dictionary(grouping: filteredBags) { $0.displayShelf }
        return groups
            .map { (shelf: $0.key, bags: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.bags.count > $1.bags.count }
    }

    private var libraryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LibraryHeader(
                    count: filteredBags.count,
                    shelfCount: Set(filteredBags.map(\.displayShelf)).count,
                    tagCount: Feed.tagCount(filteredBags),
                    isGrid: isGrid,
                    onToggleLayout: {
                        withAnimation(.easeInOut(duration: 0.26)) { isGrid.toggle() }
                    }
                )

                // ── 搜索框 ──
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索名称或标签", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !keyword.isEmpty {
                        Button { keyword = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.7), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                }
                .padding(.horizontal, 20)
                // 上面那行统计文案删掉后，搜索框与下方内容之间就只剩 0 间距了 ——
                // 原来这段呼吸是靠它的 `.padding(.top, 10)` + 约 13pt 行高撑起来的。
                // 补回到搜索框上，视觉节奏与改动前一致。
                .padding(.bottom, 22)

                // ⚠️ 这里原本还有一行「共 N 件 · N 个展示架」（对应 H5 的 `#resultCount`），
                //    已按需求删除。原因：上面的 `LibraryHeader` 三个 chip 传进来的
                //    就是**过滤后**的数量（`filteredBags.count` /
                //    `Set(map(\.displayShelf)).count` / `Feed.tagCount`），
                //    与这行完全同源 —— 同一组数字在同一屏里出现两遍。
                //    H5 里两处并存是因为它的 header 统计离得更远、视觉上分得开；
                //    SwiftUI 这边两行贴得近，读起来就是重复。
                //    网格视图那版「共 N 件 · 点击查看」的提示也一并去掉了。

                if filteredBags.isEmpty {
                    // ⚠️ 两种「空」是不同的状态，文案不能共用一套：
                    //      · 库里一条记录都没有 → 引导用户去记录第一只纸袋；
                    //      · 搜索没命中         → 库里其实有东西，该提示换关键词
                    //        （这时说「暂无纸袋记录」是错的）。
                    //    H5 原型（index.html `#emptyState`）只有后者那一套文案，
                    //    这里按需求把「全空」拆出来单独给文案。
                    VStack(spacing: 8) {
                        Text("⌕").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text(keyword.isEmpty ? "暂无纸袋记录" : "没有找到收藏")
                            .font(.system(size: 15, weight: .semibold))
                        Text(keyword.isEmpty ? "每一个纸袋都有故事，期待你的记录。"
                                             : "换一个名称或标签试试。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                } else if isGrid {
                    // ── 网格视图：打散分组，全部卡片连成一片，可双指缩放 + 横向拖动 ──
                    // 与 H5 的 `renderLibrary()` 一致：切到网格时走另一套 DOM，
                    // 不再按展示架分块（否则每组末尾会落下孤零零一张卡）。
                    //
                    // H5 的结构是 .grid-window(overflow-x:auto) > .grid-stage(width:max-content)
                    // > .collection-grid(repeat(k+1, w))。SwiftUI 侧的对应关系：
                    //   ScrollView(.horizontal)         ↔ .grid-window
                    //   LazyVGrid(定宽列, .leading)      ↔ .collection-grid
                    //   列数由 GridZoom.columnCount 算     ↔ relayoutGrid()
                    //
                    // 📌 缩放：H5 用 pointer events 自己算两指距离；SwiftUI 用
                    //    MagnificationGesture。注意 SwiftUI 的 MagnificationGesture 给的是
                    //    **相对倍数**，所以在 onChanged 里必须乘回手势开始时的宽度
                    //    （`zoomStartW`），只乘 gridW 会自我复利、几帧就冲到上限。
                    GeometryReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(
                                        .fixed(gridW),
                                        spacing: GridZoom.gap(gridW)
                                    ),
                                    count: GridZoom.columnCount(gridW, viewport: proxy.size.width)
                                ),
                                alignment: .leading,
                                spacing: GridZoom.gap(gridW)
                            ) {
                                ForEach(Array(filteredBags.prefix(Self.maxGridRender))) { bag in
                                    Button {
                                        selectedBagID = bag.id
                                        screen = .showcase
                                    } label: {
                                        GridBagCard(bag: bag, base: base, cardW: gridW)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, GridZoom.padX(gridW))
                            .padding(.top, 12)
                        }
                        // 双指缩放：手指落下时记下起始宽度，之后按倍数换算并夹在 [41, 82]
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    if zoomStartW == nil { zoomStartW = gridW }
                                    let next = (zoomStartW ?? gridW) * value
                                    gridW = min(GridZoom.maxW, max(GridZoom.minW, next))
                                }
                                .onEnded { _ in
                                    zoomStartW = nil
                                    UserDefaults.standard.set(Double(gridW), forKey: Self.gridWKey)
                                }
                        )
                    }
                    .frame(height: gridViewHeight)
                } else {
                    // ── 分组视图：按展示架分块 + 横滑 + 亚克力层板 ──
                    ForEach(groupedBags, id: \.shelf) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(group.shelf)
                                    .font(.system(size: 13, weight: .bold))
                                Text("\(group.bags.count)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(group.bags) { bag in
                                    Button {
                                        selectedBagID = bag.id
                                        screen = .showcase
                                    } label: {
                                        BagCell(bag: bag, base: base)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 16)
                    }
                }
            }
            // 收藏页用更宽的列（940）：分组视图是 `adaptive` 列，
            // 宽度给足才会多长几列，iPad 上比「一条窄列居中」实用得多。
            .contentColumn(AppLayout.libraryMaxWidth)
            // 给底栏让位。H5 写死 152px，是因为它的底栏固定 132px，等于「底栏 + 20」。
            // 这里的底栏高度可调，所以改成由 `BottomNav.navHeight` 派生 ——
            // 否则底栏一变矮，滚动到底部就会多出一大块空白（85 配 152 会剩 67pt）。
            .padding(.bottom, BottomNav.navHeight + 20)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 头部

/// 「THE FULL ARCHIVE / 全部收藏 / 三个统计 chip / 右侧布局切换钮」。
///
/// ⚠️ 结构与 `ShowcaseHeader` **必须逐项对齐**（H5 里两个 header 共用同一套字号字距）：
///     小字 11pt bold tracking 1.4 / 大标题 38pt black serif tracking 2 /
///     chip 11pt（数字 bold）/ 布局切换钮（上图标下文字，规格见 `LayoutToggleMetrics`）。
///     改一边务必同步另一边，否则两个页面的头部会看起来"不是一套"。
///
/// 📌 首页标题下方原本也有一句文案，收藏页这里原本是「把喜欢的东西，留在看得见的地方。」，
///    已按需求删掉。标题的 `padding(.bottom)` 因此从 8 收回 10，
///    补上原来 tagline 与统计行之间的那段呼吸，否则两段会贴在一起。
private struct LibraryHeader: View {
    let count: Int
    let shelfCount: Int
    let tagCount: Int
    let isGrid: Bool
    var onToggleLayout: () -> Void = {}

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("THE FULL ARCHIVE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                Text("全部收藏")
                    .font(.system(size: 38, weight: .black, design: .serif))
                    .tracking(2)
                    .padding(.bottom, 10)

                HStack(spacing: 10) {
                    chip(count, "件收藏")
                    chip(shelfCount, "个展示架")
                    chip(tagCount, "个标签")
                }
            }

            Spacer(minLength: 8)

            // 布局切换钮：**上图标 + 下文字**，无底色、无描边。
            //
            // ⚠️ 这里原来是一个 43×43 的圆形按钮（白底 + 描边，图标居中）。
            //    设计稿的新样式是「裸控件」：图标在上、名称在下。
            //    别再加回 `.background(..., in: .circle)` /
            //    `.overlay { Circle().strokeBorder(...) }`。
            //
            // 图标与文字都显示**点了会切到哪种布局**（与 H5 `layoutIcon` 同步）：
            //     当前分组视图 → 宫格图标 +「宫格」
            //     当前网格视图 → 展架图标 +「展架」
            //
            // ⚠️ 图标是**自绘**的 `LayoutGlyphView`（见 Views/LayoutGlyph.swift），
            //    不是 SF Symbol —— 设计稿的「实心方块 + 镂空 4×4 宫格」和
            //    「3 条空心横条」系统符号里都没有，最近的近似
            //    （`square.grid.3x3.fill` 是 3×3、`rectangle.grid.1x2` 是 2 条）
            //    格子数与条数都对不上。别为了省事换回去。
            Button(action: onToggleLayout) {
                VStack(spacing: LayoutToggleMetrics.labelSpacing) {
                    LayoutGlyphView(isGrid: isGrid)
                    Text(isGrid ? "展架" : "宫格")
                        .font(.system(size: LayoutToggleMetrics.labelFont))
                        .foregroundStyle(LayoutToggleMetrics.labelColor)
                }
                // 命中区：墨迹只有 24pt 宽，够不到 44pt 的最小可点尺寸。
                // 用 `.trailing` 对齐把命中区往**左**扩到 44（右侧不动）——
                // 若用默认的居中对齐，墨迹会跟着往左挪 10pt、右边距与设计稿对不上。
                .frame(width: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isGrid ? "切换为分组视图" : "切换为网格视图")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private func chip(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// 网格视图的卡片：**只有图片，不放任何文字**。
///
/// H5 对应 `.grid-card`（`itemButton()` 的产物）：
///     卡片 82×116 / 圆角 14 / 纯白底 / 无内边距，纸袋等比缩放、高度固定 98。
///
/// 📌 名字与「展示架 · 日期」在 H5 里仍然写在 DOM 中（被 CSS `display:none` 藏掉），
///    这里直接不渲染，改由无障碍标签承担 —— 否则读屏用户面对的是一排没有标签的图片。
private struct GridBagCard: View {
    let bag: BagItem
    let base: Date
    /// 卡片宽度由外层缩放状态传入（82 → 41 连续变化）。
    /// 其余尺寸全部由它派生，与 H5 的 `--grid-w-num` 派生链保持同一套比例。
    var cardW: CGFloat = 82

    /// H5 `.library-body` 的派生系数，逐个对应：
    ///   --grid-ratio: (82 − w) / 41
    ///   --grid-card-h: 116 − 58t
    ///   --grid-art:    98 − 52t
    ///   --grid-pad:    (card-h − art) / 2      ← 由前两者导出，不独立插值
    ///   --grid-radius: w / 5.8571（82 ÷ 14）
    ///   --grid-card-gap / --grid-padx 在外部用同一系数算
    ///
    /// ⚠ 98→46 不是 0.5 倍（是 0.4694），所以 art 必须单独插值，
    ///   不能由 cardW 乘系数推出来 —— 否则小档位纸袋会变成 49 而不是 46。
    private var t: CGFloat { (82 - cardW) / 41 }
    private var cardH: CGFloat { 116 - 58 * t }
    private var artH: CGFloat { 98 - 52 * t }
    private var radius: CGFloat { cardW / 5.8571 }

    var body: some View {
        ThumbnailImage(fileName: bag.imageFileName, size: 400,
                       contentMode: .fit, interpolation: .high)
            .frame(maxWidth: artH, maxHeight: artH)   // 等比缩放到高 artH，不拉伸
            .frame(width: cardW, height: cardH)       // 卡片本体
            .background(.white, in: .rect(cornerRadius: radius))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(bag.displayName)，\(bag.displayShelf)，\(DateFormat.monthDayDot(bag.createdAt))")
    }
}

/// 网格视图的缩放范围。H5 里由 `GRID_W_MAX / GRID_W_MIN` 定义。
enum GridZoom {
    /// H5 `const GRID_W_MAX = 82`
    static let maxW: CGFloat = 82
    /// H5 `const GRID_W_MIN = 41`
    static let minW: CGFloat = 41
    /// H5 `--grid-gap: w / 9.1111`
    static func gap(_ w: CGFloat) -> CGFloat { w / 9.1111 }
    /// H5 `--grid-padx: w / 6.8333`
    static func padX(_ w: CGFloat) -> CGFloat { w / 6.8333 }
    /// H5 `relayoutGrid()`：列数取「一屏放得下的列数 + 1」，
    /// 多渲染一列保证任何缩放级别下内容都溢出、横向滚动永远可用。
    static func columnCount(_ w: CGFloat, viewport: CGFloat) -> Int {
        let gap = self.gap(w)
        let avail = viewport - padX(w) * 2
        let k = max(1, Int(ceil((avail + gap) / (w + gap))))
        return k + 1
    }
}

/// `MY PRIVATE CABINET / 袋袋集 / 一句文案` + 右侧「最近收藏 N」胶囊。
///
/// H5 对应 `.bags-header`。原来这里有三个统计 chip（件收藏 / 件最近 / 个标签）和一枚设置圆钮，
/// 已按需求改成：**统计全部去掉，只留一句「收集每一个纸袋的故事」**，
/// 右上角圆钮换成能点的「最近收藏 N」胶囊（点了滚到下面「最近收集」区）。
///
/// 📌 设置面板的入口因此从首页搬到了「最近收集」标题栏右侧，
///    见 `showcaseScreen` 里 `RackSection` 上方的齿轮按钮。不然设置就点不开了。
private struct ShowcaseHeader: View {
    let recentCount: Int
    var onOpenRecent: () -> Void = {}

    /// H5 `--paper: #F2F3F7`
    private let paper = Color(red: 242/255, green: 243/255, blue: 247/255)

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("MY PRIVATE CABINET")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                Text("袋袋集")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .tracking(2)
                    .padding(.bottom, 8)

                // 替掉原来的三枚统计 chip
                Text("收集每一个纸袋的故事")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            recentPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    /// 「最近收藏 N」胶囊：43pt 高，和标题基线齐平。
    private var recentPill: some View {
        Button(action: onOpenRecent) {
            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .regular))
                Text("最近收藏")
                    .font(.system(size: 12))
                Text("\(recentCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .frame(height: 43)
            .background(.white.opacity(0.5), in: .capsule)
            .overlay { Capsule().strokeBorder(.black.opacity(0.09), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看最近收藏，共 \(recentCount) 件")
    }
}

// MARK: - 底部导航

/// 底部导航（无底板）：陈列 | ＋ | 全部收藏。
///
/// H5 对应 `.bottom-nav` —— 去掉玻璃底板后，用**一层纯色**（`--paper` #F2F3F7）
/// 覆盖 `navHeight`（70pt）高的区域，内容贴底；`pointer-events: none` 让空白区手势穿透到下层滚动。
///
/// ⚠️ 底色不能省。没有它，滚动中的卡片会从图标之间的缝隙里透出来和文字叠在一起。
///     底色必须盖住整排图标 —— 图标 23px + gap 4px + 文字 10px 实际占到约 62px 高。
///
/// 📝 沿革：这一层原本是 `linear-gradient`（全透明 → paper），现已按设计改为纯色。
///     代价是与滚动内容之间不再有柔和过渡，边界是一条硬线；好处是不会再有
///     「渐变色 vs 页面底色对不上」的色差缝，也不依赖 stops 比例去适配安全区。
private struct BottomNav: View {
    @Binding var screen: ShelfView.Screen
    var onAdd: () -> Void = {}

    /// H5 `--paper: #F2F3F7`
    private let paper = Color(red: 242/255, green: 243/255, blue: 247/255)
    /// H5 `.bottom-nav { height: 132px }`，按用户要求先收到 85、再收到 70。
    ///
    /// ⚠️ 这里是**安全区之上**的内容区高度，不含底部的 safe-bottom。
    ///    实机可见高度 = 70 + 安全区（iPhone 上约 34pt）≈ 104pt。
    ///    不要把它理解成「屏幕上的整条高度」—— 70 只比 `itemHeight`(62)
    ///    多 8pt，已接近下限；再矮就会裁到图标本身。
    ///
    /// 📌 改成 `static` 是为了让 `showcaseScreen` / `libraryScreen` 的滚动底部留白
    ///    能直接由它派生（`BottomNav.navHeight + 20`），底栏高度以后只改这一个数，
    ///    留白自动跟随、不会漂移。
    static let navHeight: CGFloat = 70
    /// H5 `.nav-item { height: 62px }`
    private let itemHeight: CGFloat = 62

    var body: some View {
        // 三个控件之间用弹性 Spacer 均分剩余空间，间距随屏宽自适应。
        //
        // 原来固定 `spacing: 4`，而每个 nav-item 本身就是 96pt 宽（图标居中，
        // 两侧是空白），导致图标中心间距只有 94pt，在宽屏上明显偏挤。
        // 换成 Spacer 后间距会被撑开（iPhone 15 上图标中心间距约 119pt），
        // 且窄屏（SE 320pt）也不会溢出——固定大间距做不到这一点。
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            navItem(.showcase, systemImage: "square.stack.3d.up")
            Spacer(minLength: 0)
            addButton
            Spacer(minLength: 0)
            navItem(.library, systemImage: "square.grid.2x2")
            Spacer(minLength: 0)
        }
        // 宽屏（iPad）把三个控件收在一列里居中。
        //
        // 不限制的话 `Spacer(minLength: 0)` 会把两个 nav-item 推到屏幕两端，
        // 与中间的 ＋ 相隔上千点 —— 既难看也不好按（手指够不到）。
        // iPhone 上 393 < 620，这一层是恒等变换，观感与原来完全一致。
        .contentColumn(AppLayout.bottomNavMaxWidth)
        // 内容贴到安全区底边（＝ Home Indicator 上沿）。
        //
        // H5 写的是 `padding-bottom: max(14px, var(--safe-bottom))`，在 iPhone 上
        // 就是 safe-bottom（34pt）本身 —— 而 SwiftUI 的安全区**已经**把这 34pt
        // 让出来了。这里再补 14 会变成 34 + 14 = 48pt，导航就「浮」在底边之上。
        // 所以补 0，让安全区自己承担这段距离。
        .frame(height: itemHeight, alignment: .bottom)
        // 在内容上方留出 navHeight - itemHeight（= 8pt），
        // 使整条底栏的内容区高度等于 navHeight。
        .padding(.top, Self.navHeight - itemHeight)
        .background(alignment: .bottom) {
            // 纯色底：H5 `--paper: #F2F3F7`。
            //
            // ⚠️ `.ignoresSafeArea(edges: .bottom)` 不能省。
            //    本视图位于安全区内，底色若只铺到安全区底边，屏幕最下方的
            //    34pt 会露出 PageBackground 的底色（#E4E6EC）—— 于是底边留下
            //    一条色差缝，导航栏就「没贴底」。加上它，底色一直铺到物理底边。
            paper
                .allowsHitTesting(false)   // H5 `pointer-events: none`
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func navItem(_ target: ShelfView.Screen, systemImage: String) -> some View {
        let isActive = screen == target
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { screen = target }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .regular))
                Text(target.rawValue)
                    .font(.system(size: 10, weight: .semibold))
            }
            // H5：未选中 #9d9890，选中 var(--ink) #141414
            .foregroundStyle(isActive ? Color(red: 20/255, green: 20/255, blue: 20/255)
                                      : Color(red: 157/255, green: 152/255, blue: 144/255))
            .frame(width: 96, height: itemHeight)   // H5 `.nav-item { width: 96px; height: 62px }`
            // H5 `.nav-item.is-active::after` —— 图标下方一枚 4px 小圆点
            .overlay(alignment: .bottom) {
                if isActive {
                    Circle()
                        .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                        .frame(width: 4, height: 4)
                        .offset(y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Text("＋")
                .font(.system(size: 29, weight: .light))   // H5 `font-size: 30px; font-weight: 200`
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)              // H5 `.add-button { 56px }`
                .background(Color(red: 20/255, green: 20/255, blue: 20/255), in: .circle)
                .shadow(color: .black.opacity(0.26), radius: 11, x: 0, y: 8)
                .padding(.horizontal, 14)                  // H5 `margin: 0 14px`
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加收藏")
    }
}

// MARK: - 页面背景

/// H5：`--paper: #F2F3F7`，body 用 #e4e6ec + 径向渐变做层次。
struct PageBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.894, green: 0.902, blue: 0.925)
            RadialGradient(
                colors: [Color(red: 0.949, green: 0.953, blue: 0.969), .clear],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - 预览

#Preview {
    ShelfView()
        .modelContainer(PreviewData.container)
}
