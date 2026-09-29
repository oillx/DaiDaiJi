import SwiftUI
import Observation
import SwiftData

// ═══════════════════════════════════════════════════════════════
//  首页：陈列（showcase）+ 全部收藏（library）双屏 + 底部导航
//
//  H5 对应：`袋袋集原型/index.html` 的 `.screen[data-screen]` 与 `.bottom-nav`，
//           `app.js` 的 `navigate()` / `renderShowcase()` / `renderLibrary()`
// ═══════════════════════════════════════════════════════════════

struct ShelfView: View {
    /// 全集，按 createdAt 倒序。
    ///
    /// ⚠️ 这个排序只喂给**时间口径**的东西（主卡「最新」、最近收集、组序的
    ///    「首次出现」）。展架**组内**的先后看 `manualOrder`（见 `groupedBags`），
    ///    两者故意分开：拖动排序只允许动组内，不许把整组在页面上搬走。
    @Query(sort: \BagItem.createdAt, order: .reverse) private var allBags: [BagItem]

    @Environment(\.modelContext) private var context

    @State private var screen: Screen = .showcase
    @State private var showAdd = false
    @State private var keyword = ""
    @State private var selectedBagID: UUID?
    /// 从「查看大图」进来的详情
    @State private var detailBag: BagItem?
    /// 从详情卡「更多 · 删除」推入的完整页（编辑已在卡内原地完成，
    /// 那一页现在只承担「删除」这个原生型没有的能力）
    @State private var editBag: BagItem?
    /// 详情卡当前是否处于编辑态。
    ///
    /// ⚠️ 编辑态下「点卡外」不做任何响应。
    ///    原型这一轮的收尾修复（改动记录第 10 条）就是「按 Esc 把整张卡关掉、
    ///    未保存的改动全丢」—— iOS 上没有 Esc，手滑点到遮罩才是同一条路径，
    ///    所以这里必须把遮罩的关闭手势挡住，出口只留底部的 [取消][保存]。
    @State private var detailEditing = false
    /// 正在排序的展示架（H5 的 `.is-sorting` 态）。nil = 未排序。
    /// 长按某组卡片 500ms 进入；拖完**不退出**（排序是连续动作）；
    /// 退出只认双击任意处 / 点击空白处（H5 `exitShelfSort` 的两个出口）。
    @State private var sortingShelf: String?

    /// 主卡翻面复位令牌：每点一次挂袋卡 +1（H5 `showRackHero` 每次都翻回正面）。
    /// 用计数而不是比 id，是因为「点同一张」时 id 不变、但行为要发生。
    @State private var heroFlipToken = 0
    /// 轻提示文案（H5 `#toast`，保存成功后弹「“xxx”已更新」）
    @State private var toast: String?
    /// toast 的计时令牌：连续触发时只让最后一次的定时器生效
    @State private var toastToken = 0
    /// 搜索框的焦点。空状态里点「出路」标签后要把它重新聚焦
    /// （H5 `renderEmptyState` 末尾就是 `$('#searchInput').focus()`）。
    @FocusState private var searchFocused: Bool
    /// 全部收藏的布局：分组横滑（默认）/ 扁平网格。
    /// H5 对应 `libraryView` + `setLibraryView()`。
    @State private var isGrid = false
    @State private var showSettings = false

    /// 网格缩放：当前卡片宽度，41（小档）↔ 82（大档）连续变化。
    /// H5 对应 `--grid-w-num`，是整套尺寸的唯一真源。
    @State private var gridW: CGFloat = GridZoom.maxW
    /// 双指手势开始时的宽度。`MagnifyGesture` 给的是相对倍数，
    /// 必须乘回起始值，否则会自我复利、几帧就冲到上限。
    @State private var zoomStartW: CGFloat?
    /// 滚动偏移与锚针位置。用 `@Observable` 而不是 `@State`：
    /// 滚动时每帧都写 `offset`，而**没有任何视图读它**（只有手势里同步读一次），
    /// 所以不会引发任何重绘 —— 若放进 `@State`，拖一下网格就会整页重算一遍。
    @State private var gridScroll = GridScrollState()
    /// 捏合起始时的：两指中点在视口内的 x、以及当时的滚动偏移（H5 `anchorOf` 的两个分量）
    @State private var pinchStartDX: CGFloat = 0
    @State private var pinchStartOffset: CGFloat = 0

    /// H5 `const MAX_GRID_RENDER = 240` / `localStorage['ddj.gridW']`
    static let maxGridRender = 240
    static let gridWKey = "ddj.gridW"
    /// 锚针的 id（`scrollTo` 的目标）与滚动坐标系名（量偏移用）
    static let gridAnchorTickID = "ddj.grid.anchor"
    static let gridScrollSpace = "ddj.grid.scroll"

    // MARK: - 由容器宽度派生的布局
    //
    // ⚠️ 宽度**只有一个来源**：`body` 里 `GeometryReader` 量到的容器宽度，
    //    逐层以参数传下去。不要用 @State 探针 —— 那会晚一帧，启动 / 旋转时
    //    能看到内容跳一下；也不要再引入「阅读列」上限（iPad 要铺满全屏）。

    /// 主卡放大倍数：以 iPhone 屏宽 393 为 1.0 线性放大，封顶 1.25。
    /// iPhone（≤ 491pt 列宽）与 iPad 分屏下恒为 1.0 上下，与原来一致。
    private func heroScale(_ width: CGFloat) -> CGFloat {
        AppLayout.cardScale(forColumn: width)
    }

    /// 网格视图需要的纵向高度：由当前卡片高度推出来。
    /// SwiftUI 的 ScrollView(.horizontal) 必须有确定高度，否则会向父级要无限空间。
    /// 行数按「已渲染卡片数 ÷ 列数」算，再乘行高与间距。
    ///
    /// ⚠️ viewport 必须用**真正参与排版的容器宽度**，两处口径要一致，
    ///    否则列数与实际布局不符、网格会多出一大片空高度。
    private func gridViewHeight(_ width: CGFloat) -> CGFloat {
        let cols = max(1, GridZoom.columnCount(gridW, viewport: width))
        let rows = max(1, Int(ceil(Double(min(filteredBags.count, Self.maxGridRender)) / Double(cols))))
        // ⚠️ 卡高必须取 `GridZoom.cardHeight`（同一个函数），别在这里再抄一遍公式 ——
        //    它含高度收窄系数，抄漏了网格高度就会与实际卡片对不上（多出空高度）。
        let cardH = GridZoom.cardHeight(gridW)
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

    /// 挂架区的数据：15 天窗口、由新到旧，上限 `Feed.rackMaxItems`
    /// （超出一屏基准张数的部分由挂架区横向滚动展示）
    private var recentBags: [BagItem] {
        Feed.recent(allBags, base: base, limit: Feed.rackMaxItems)
    }

    /// 主展位当前展品：优先用户选中的，其次最近的第一只
    private var heroBag: BagItem? {
        if let id = selectedBagID, let hit = allBags.first(where: { $0.id == id }) {
            return hit
        }
        return recentBags.first ?? allBags.first
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
                    // ⚠️ 编辑态下这一层不再关闭卡片：出口只留 [取消][保存]。
                    //    `allowsHitTesting` 不能用来挡 —— 它会把整个遮罩的
                    //    命中测试关掉，卡片自己也被挡住。用条件手势最直接。
                    .onTapGesture { if !detailEditing { closeDetail() } }

                DetailCardView(
                    bag: bag,
                    base: base,
                    onClose: { closeDetail() },
                    onMore: { editBag = bag; closeDetail() },
                    onEditingChange: { detailEditing = $0 },
                    onSaved: { showToast("“\($0)”已更新") }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                // H5：.92 → 1.0 原地放大淡入
                .transition(.scale(scale: DetailCardMetrics.openScale).combined(with: .opacity))
            }
        }
    }

    /// 关闭详情卡。
    /// ⚠️ 必须同时把编辑态标记复位 —— 否则下一次点开别的藏品时，
    ///    `detailEditing` 还停在 true，遮罩会莫名其妙点不动。
    private func closeDetail() {
        detailBag = nil
        detailEditing = false
    }

    /// 设置半窗：遮罩 + 贴底卡片。
    ///
    /// ⚠️ 与详情卡同理，用 overlay 而不是 `.sheet` —— iOS 26 的 detent 半窗是
    ///    左右内缩的浮层卡片（四角全圆、底部留缝），跟 H5 `.bottom-sheet` 的
    ///    「贴左右、只圆上面两角、贴底、高度随内容」四条全对不上，且系统不给改。
    /// 半窗关闭时往下让出的距离 —— 面板最高约 430pt，给 560 足以整块滑出屏幕。
    private static let sheetHiddenOffset: CGFloat = 560

    /// 半窗**进/出共用的缓动**：`cubic-bezier(0.32, 0.72, 0, 1)`、**0.55s**（曲线按需求统一）。
    ///
    /// 这条曲线的形状就是需求描述的物理感：**起步快、后段长时间柔和减速**——
    ///   进入：被推上来时先快后缓，到位后稳稳停住；
    ///   收起：一开始就"走"，越接近屏幕外越慢地收尾，不拖沓也不生硬。
    /// ⚠️ 别退回原来的 `(0.2, 0.75, 0.22, 1)`：它在 0.38s 里把 ~85% 的位移集中在
    ///    头 0.15s，收起时看起来几乎就是"啪"地消失（用户反馈「收起没有向下滑出」）。
    ///    ⚠️ 时长为什么是 0.55 而不是更短：这条曲线**起步很陡**（初始斜率 2.25×），
    ///       0.45s 时「面板还看得见的那段行程」只占约 0.19s —— 观感偏"啪"地消失。
    ///       0.55s 把可见行程拉到约 0.23s，滑出感清楚、又不拖沓。
    ///    ⚠️ 改这里会同时影响进、出与 `settingsOverlay` 上那条 `.animation`。
    private static let sheetAnimation = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.55)

    /// 设置半窗：遮罩 + 贴底卡片（**常驻**，用位移/透明度跟随 `showSettings`）。
    ///
    /// ⚠️ 这里**故意不写** `if showSettings { … } + .transition(.move(edge: .bottom))`：
    ///    本视图挂在 `.overlay` 里，实测那条 transition **完全不跑** ——
    ///    逐帧量过：面板顶边 6.34s 还在 y 449.7，6.40s 就整个没了，
    ///    0.06s 一帧的密度里连一张中间帧都没有 ⇒ 就是用户看到的「点遮罩直接消失」。
    ///    改成常驻 + `offset`/`opacity`：动画落在**普通可动画属性**上，
    ///    不再依赖 transition 的插入/移除时机，进出都由 `open/closeSettings()` 的
    ///    `withAnimation`（0.38s、`cubic-bezier(.2,.75,.22,1)`）驱动 ⇒ 向下滑出屏幕。
    ///
    /// 📌 常驻带来的两个连带处理：
    ///    · 遮罩用 `opacity(0)` 时**仍然参与命中测试**，所以关着时必须
    ///      `allowsHitTesting(false)`，否则整页点不动；
    ///    · 面板滑到屏幕外后同样关掉命中测试，避免点到看不见的按钮。
    @ViewBuilder
    private var settingsOverlay: some View {
        ZStack(alignment: .bottom) {
            // 遮罩：对应 H5 `.sheet-backdrop { background: rgba(17,15,12,.36); blur(3px) }`
            // （3px 的轻模糊在 SwiftUI 里没有等价物，与详情卡遮罩同样只上色）
            Color(red: 17/255, green: 15/255, blue: 12/255)
                .opacity(showSettings ? 0.36 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(showSettings)
                // 点遮罩 = 关闭（走带下滑动效的 `closeSettings()`）。
                // ⚠️ 落在**半窗面板上**的点击到不了这里 —— 面板的玻璃底色
                //    （`CoolGlassSurface.gradient`）是不透明的实心形状，
                //    命中测试在它那儿就停住了（`Color.clear` 才会漏过去）。
                .onTapGesture { if showSettings { closeSettings() } }

            SettingsSheet(totalCount: allBags.count) { closeSettings() }
                .offset(y: showSettings ? 0 : Self.sheetHiddenOffset)
                .allowsHitTesting(showSettings)
        }
        // ⚠️ **这一层才是有效的**：`.overlay` 的坐标空间只到安全区上沿，
        //    半窗内部再写 `.ignoresSafeArea(edges: .bottom)` 已经晚了 ——
        //    实测半窗面板底边停在 y 839（距物理底还有 35pt 的 Home Indicator 区），
        //    于是按钮下方露出「22pt 面板内边距 + 35pt 遮罩空条」= 57pt 空白。
        //    在这一层忽略底部安全区，ZStack 直接铺到物理底边，面板随之贴底，
        //    半窗内部那 22pt 下内边距就真的成了「按钮到屏幕底边的距离」（H5 口径）。
        .ignoresSafeArea(edges: .bottom)
        // 单纯的状态驱动动画：offset / opacity 都是可动画属性，可靠。
        .animation(Self.sheetAnimation, value: showSettings)
    }

    /// 开 / 关设置半窗 —— **显式**带上动画。
    ///
    /// ⚠️ 为什么不能只靠 `body` 上那条 `.animation(_, value: showSettings)`：
    ///    半窗的消失动效来自 `SettingsSheet` 的 `.transition(.move(edge: .bottom))`，
    ///    而 transition 必须在一个**带动画的事务**里被插入/移除才会跑。
    ///    把状态改动包进 `withAnimation` 就等于给这次事务显式指定曲线 ——
    ///    点遮罩、点「完成」、点右上角「设置」三条路径从此共用同一套进出曲线，
    ///    半窗是**向下滑出屏幕**，不是直接消失。
    ///
    /// 📌 想调快/调慢或换成带回弹的曲线：只改这两个方法里的曲线。
    /// 📌 想再进一步做成「手指跟随下拉关闭」（interactive dismiss）：那是另一套
    ///    `DragGesture` + 位移跟随，需要时再加，不影响这里的进场/退场动画。
    private func openSettings() {
        withTransaction(Self.sheetTransaction) { showSettings = true }
    }

    private func closeSettings() {
        withTransaction(Self.sheetTransaction) { showSettings = false }
    }

    /// 半窗状态变化专用事务。
    ///
    /// ⚠️ 这里是**关不掉动画的关键**：点遮罩走的是**手势回调**，而手势产生的事务里
    ///    `disablesAnimations` 可能为 `true` —— 那种情况下即使写 `withAnimation`
    ///    也会被吞掉，表现就是「收起没有滑出动画、直接不见」。
    ///    用 `withTransaction` 显式把动画塞进去、并把 `disablesAnimations` 清成 false，
    ///    两个方向都不再依赖调用方的事务状态。
    private static var sheetTransaction: Transaction {
        var t = Transaction()
        t.animation = sheetAnimation
        t.disablesAnimations = false
        return t
    }

    /// 轻提示（H5 `showToast`：底部 103px、深色胶囊、11px 白字、2.1s 自动收起）
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .padding(.vertical, 11)
                .padding(.horizontal, 18)
                .background(Color(red: 20/255, green: 20/255, blue: 20/255), in: Capsule())
                .padding(.bottom, 88)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.28)) { toast = message }
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            // 期间又弹了一条就交给它自己收，别把新的提前关掉
            guard token == toastToken else { return }
            withAnimation(.easeInOut(duration: 0.28)) { toast = nil }
        }
    }

    var body: some View {
        // 容器宽度**只在这里量一次**，之后逐层当参数传下去（全工程唯一宽度来源）。
        // 不 ignoresSafeArea：量到的就是安全区内尺寸，安全区交回系统处理。
        GeometryReader { geo in
            ZStack {
                // 整屏底色（自身 ignoresSafeArea，会铺到物理边）
                PageBackground()
                navigationRoot(width: geo.size.width)
            }
        }
    }

    /// 导航根：全部屏幕（首页 / 收藏 / 详情 / 设置 / 相机入口）都活在这棵树里。
    /// `width` = 容器宽度（由 `body` 量得），一切宽度从它派生。
    private func navigationRoot(width: CGFloat) -> some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // ── 屏幕内容 ──
                Group {
                    switch screen {
                    case .showcase: showcaseScreen(width)
                    case .library:  libraryScreen(width)
                    }
                }
                .frame(width: width, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)

                // ── 底部导航（陈列 | ＋ | 全部收藏）──
                BottomNav(screen: $screen) { showAdd = true }
                    // 📌 键盘弹起时**底栏不许被顶上来**。
                    //
                    // 为什么原来会被顶：工程里没有做任何键盘处理，SwiftUI 默认启用
                    // 「键盘避让」—— 键盘一出现，它把整页（连同底栏这一条）往上推。
                    // 而 H5 里底栏是 `position: fixed; bottom: 0`，键盘只是**浮在它上面**，
                    // 页面本身一点不动。
                    //
                    // ⚠️ 只让**底栏这一条**忽略键盘，不要挪到外层 ZStack 上：
                    //    内容区仍要正常避让，否则列表最后几行会被键盘永久盖住、
                    //    再也滚不出来。
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            // ⚠️ 宽度必须**显式钉死**，不能用 `maxWidth: .infinity`：
            //    上层（`NavigationStack`）给出的可能是「未指定宽度」，
            //    那样这个 frame 会退化成「取子视图的理想宽度」，而挂袋行的
            //    理想宽度是 6 张卡片的自然宽（560+）→ 宽度被自己的内容撑开、
            //    再喂回挂袋行的测量，越滚越大（实测 402 → 561 → 620 才停），
            //    最后内容比屏幕还宽、左右被裁。
            .frame(width: width)
            .background(PageBackground())
            .toolbar(.hidden, for: .navigationBar)
            // 详情：居中弹出卡片（不是半窗、也不是推入页）
            .overlay { detailOverlay }
            // 轻提示压在详情卡之上（H5 `z-index: 120` > 卡片的 100）
            .overlay(alignment: .bottom) { toastView }
            .animation(
                .timingCurve(0.2, 0.78, 0.22, 1, duration: DetailCardMetrics.openDuration),
                value: detailBag?.id
            )
            // 「更多 · 删除」推入完整页。编辑已经在详情卡里原地完成，
            // 这一页现在的作用是兜住删除（原型没有删除，iOS 保留这个能力）
            .navigationDestination(item: $editBag) { bag in
                BagDetailView(bag: bag)
            }
            // 「＋」直接拉起拍摄页。拍摄页是带自定义顶栏的整页设计，所以走全屏而非半窗。
            .fullScreenCover(isPresented: $showAdd) {
                ZStack {
                    PageBackground()
                    AddBagView(startsInCamera: true)
                }
            }
            // 设置半窗：自绘 overlay，不用 `.sheet`（原因见 `SettingsSheet` 文件头）
            .overlay { settingsOverlay }
            // ⚠️ 这里原来挂着 `.animation(_, value: showSettings)`：实测它对
            //    `.overlay` 里那套 transition 不生效（见 `settingsOverlay` 的说明）。
            //    进/出动画已改由 `settingsOverlay` 自己的 `.animation` + 两个
            //    `open/closeSettings()` 驱动，这条留着只会变成第二个动画源。

        }
    }

    // MARK: - 陈列屏

    private func showcaseScreen(_ width: CGFloat) -> some View {
        let cardScale = heroScale(width)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 右上角是「设置」入口（H5 `.header-settings`）。
                // ⚠️ 原先这里传的是「最近收藏 N」胶囊 + 一个滚到「最近收集」的闭包，
                //    已随 H5 一并退役 —— 不要为了「一键滚过去」把胶囊加回来。
                ShowcaseHeader(padH: AppLayout.pagePad(20, for: width),
                               onOpenSettings: { openSettings() })


                // ── 主展位 ──
                HeroCardView(
                    bag: heroBag,
                    base: base,
                    resetToken: heroFlipToken,
                    onOpenDetail: { detailBag = $0 }
                )
                // ── 主卡随列宽等比放大 ──
                // 卡片内部所有尺寸（字号 / 圆角 / 投影 / 内边距）都按 393pt 稿面
                // 写死，所以只能整体缩放；只把外框改大只会多出一圈空白，比例反而崩。
                // `scaleEffect` 不改布局尺寸，所以要再补一个等大的 frame，
                // 否则放大后的卡片会视觉溢出、压到下面的「最近收集」。
                //
                // ⚠️ 这一层与等比壳**不是**重复放大：手机列宽 ≤ 393 时它是 1.0，
                //    430 的列（iPad 壳内 / Pro Max）才给到 1.09 —— 它对齐的是
                //    「主卡恒占内容宽 78.4%」这条口径，iPad 上因此与 iPhone 一致。
                .scaleEffect(cardScale)
                .frame(width: HeroMetrics.cardWidth * cardScale,
                       height: HeroMetrics.cardHeight * cardScale)
                // ⚠️ 这行不能省。外层 VStack 是 `alignment: .leading`，而主卡自身
                //    是固定 308pt 宽（`HeroMetrics.cardWidth`），不撑满可用宽度 ——
                //    结果卡片会被贴到左边，右侧空出一大块。这里撑满整行再居中，
                //    卡片才真正落在页面中轴线上。
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppLayout.pagePad(18, for: width))
                .padding(.bottom, 26)
                .id(heroBag?.id)   // 换袋子时重建，避免动画残留

                // ── 最近收集 ──
                // 设置入口已回归首页右上角的「设置」按钮，
                // 这里不再传 `onOpenSettings`（H5 的标题栏里也只剩「查看全部」）。
                RackSection(
                    items: recentBags,
                    base: base,
                    selectedID: heroBag?.id,
                    onSeeAll: { screen = .library },
                    onSelect: { selectBag($0) },
                    containerWidth: width
                )

                .padding(.bottom, 34)
            }
            // ⚠️ 滚动内容必须**显式定宽**，理由与 `navigationRoot` 那层一样：
            //    纵向 ScrollView 的内容宽度取「内容自己的最小宽度」，一旦有子块
            //    （挂袋行这类自带左右内边距的）算出比屏宽多一截，整个 VStack 会被
            //    撑宽、再被 ScrollView 居中 —— 结果是**整页左右各缩进十几点**，
            //    与 H5 的 20/22px 内边距对不上。实测 iPhone：屏 402、内容被撑到 426、
            //    标题左缘变成 9pt（应为 20）。
            .frame(width: width, alignment: .leading)
            // 给底栏让位。H5 写死 152px，是因为它的底栏固定 132px，等于「底栏 + 20」。
            // 这里的底栏高度可调，所以改成由 `BottomNav.navHeight` 派生 ——
            // 否则底栏一变矮，滚动到底部就会多出一大块空白（85 配 152 会剩 67pt）。
            .padding(.bottom, BottomNav.navHeight + 20)
        }
        .scrollIndicators(.hidden)
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
        // H5：showRackHero 每次都会 setHeroFlipped(false) —— 点**同一张**也要翻回正面
        heroFlipToken += 1
    }

    // MARK: - 全部收藏屏

    /// 输入框内容 trim 之后的**原样**文本 —— H5 `renderEmptyState` 回显的就是它
    /// （保留用户输入的大小写与词间空格，不做小写化）。
    private var searchQuery: String {
        keyword.trimmingCharacters(in: .whitespaces)
    }

    /// 搜索关键词 —— 照 H5 `renderLibrary()`：trim → 小写 → 按空格拆开 → 丢掉空段。
    ///
    /// ⚠️ 多关键词是 **AND**（`matchQuery` 的 `every`）：「瑞幸 联名」是收窄，
    ///    不是把两个条件并成一大堆结果。原来 iOS 把整串当一个子串匹配，那句多词
    ///    查询会永远搜不到、直接掉进空状态。
    private var searchKeywords: [String] {
        keyword.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var filteredBags: [BagItem] {
        let keywords = searchKeywords
        guard !keywords.isEmpty else { return allBags }
        return allBags.filter { bag in keywords.allSatisfy { bag.matches($0) } }
    }

    /// 分组：**组序**按展示架在列表里首次出现的先后（H5 `renderLibrary()` 口径），
    /// **组内**按展架手工排序（`manualOrder` 小的在前 —— 长按拖动交换后写回的就是它）。
    ///
    /// ⚠️ 组序与组内序**故意分开定**：组序沿用 `allBags`（createdAt 倒序）的首次
    ///    出现口径，所以拖动只会在组内换位，不会把整个组在页面上搬走。
    /// ⚠️ 等序兜底按 createdAt 倒序 —— 理论上不该出现（迁移与落库都会排成 1…N），
    ///    留着是为了在异常数据下仍有稳定的视觉顺序。
    private var groupedBags: [(shelf: String, bags: [BagItem])] {
        var order: [String] = []
        var buckets: [String: [BagItem]] = [:]
        for bag in filteredBags {
            let key = bag.displayShelf
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(bag)
        }
        return order.map { key in
            let group = buckets[key] ?? []
            let sorted = group.sorted {
                if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
                return $0.createdAt > $1.createdAt
            }
            return (shelf: key, bags: sorted)
        }
    }

    /// 拖动换位落库：把该组按最终顺序重编号为 1…N。
    ///
    /// ⚠️ 只在**松手时**调用一次（拖动过程中组内顺序是 `ShelfGroup` 的本地状态），
    ///    避免 `@Query` 每帧重排、拖动卡顿。重编号而不是「交换两个序号」，
    ///    是为了让上传时「整体后移腾 1 号位」产生的间隙归位。
    /// ⚠️ 只写这一组 —— `manualOrder` 只在组内有意义，别的组不该被碰到。
    private func commitReorder(_ ordered: [BagItem]) {
        for (position, bag) in ordered.enumerated() where bag.manualOrder != position + 1 {
            bag.manualOrder = position + 1
        }
        try? context.save()
    }

    private func libraryScreen(_ width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LibraryHeader(
                    count: filteredBags.count,
                    shelfCount: Set(filteredBags.map(\.displayShelf)).count,
                    isGrid: isGrid,
                    padH: AppLayout.pagePad(20, for: width),
                    onToggleLayout: {
                        withAnimation(.easeInOut(duration: 0.26)) { isGrid.toggle() }
                    }
                )

                // ── 搜索框 ──
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    // 提示文字逐字对齐 H5 `#searchInput` 的 placeholder
                    // （原来是「搜索名称或标签」，H5 是「搜索名称 / 品牌 / 标签」）
                    TextField("搜索名称 / 品牌 / 标签", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                    if !keyword.isEmpty {
                        // H5 `#clearSearch`：清空输入 → 重渲染 → **重新聚焦搜索框**
                        // （`$('#searchInput').focus()`），键盘留着不收起。
                        Button {
                            keyword = ""
                            searchFocused = true
                        } label: {
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
                // 📌 点搜索框的**任意一处**（图标、内边距空白）都把光标落回输入框。
                //    这一层会吃掉自己的点击，所以下面那条「点空白收起键盘」不会误收 ——
                //    点搜索框只聚焦、不收键盘。
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
                .padding(.horizontal, AppLayout.pagePad(20, for: width))
                // H5 `.search-box { margin: 0 18px 13px }` —— 下方 13px。
                // 原先写 22，是给「改回一行统计文案」补呼吸用的；按稿面收回 13。
                .padding(.bottom, 13)

                // ⚠️ 这里原本还有一行「共 N 件 · N 个展示架」（对应 H5 的 `#resultCount`），
                //    已按需求删除。原因：上面的 `LibraryHeader` 三个 chip 传进来的
                //    就是**过滤后**的数量（`filteredBags.count` /
                //    `Set(map(\.displayShelf)).count` / `Feed.tagCount`），
                //    与这行完全同源 —— 同一组数字在同一屏里出现两遍。
                //    H5 里两处并存是因为它的 header 统计离得更远、视觉上分得开；
                //    SwiftUI 这边两行贴得近，读起来就是重复。
                //    网格视图那版「共 N 件 · 点击查看」的提示也一并去掉了。

                // ── 排序态提示条（H5 `.sort-banner`）──
                // H5 里它是 `#collectionGroups` 的第一个子元素（sticky top:0），
                // 静置时就在搜索框与分组之间；iOS 放进文档流同一位置。
                // 差异：H5 滚动时会吸顶，iOS 会随内容滚走 —— 排序态下行本身不可滑，
                // 影响只在整页滚动时，先不做吸顶。
                SortBanner(visible: sortingShelf != nil)

                if filteredBags.isEmpty {
                    LibraryEmptyState(
                        // 大字在 H5 里写死在标签内（`.empty-state__mark`），不随搜索词变
                        mark: "没有结果",
                        // 副文案（H5 `renderEmptyState`）：回显原样输入，让用户看清自己拼了什么；
                        // 输入框为空（说明库里一条都没有）时退到一句泛提示。
                        hint: searchQuery.isEmpty
                            ? "换个关键词试试"
                            : "「\(searchQuery)」不在你的收藏里",
                        // 出路标签：H5 `rankEmptyStateOptions` 取「当前还能搜到的」品牌 / 标签，
                        // 最多 4 个，点下去必定有结果 —— 绝不会再撞一次空状态。
                        chips: SuggestionMatcher.emptyStateOptions(keyword: keyword,
                                                                   in: allBags)
                    ) { text in
                        // H5：整体**替换**搜索词（不是追加），避免越叠越多搜不到
                        keyword = text
                        searchFocused = true
                    }
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
                      ScrollViewReader { scroller in
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
                                    // H5 `bindItemButtons()`：`.js-item` 一点就
                                    // `openDetail(item)` —— 翻出居中详情大卡。
                                    // ⚠️ 原来是「选中它 + 跳回首页主展位」，与原型不是一路。
                                    Button { detailBag = bag } label: {
                                        GridBagCard(bag: bag, base: base, cardW: gridW)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            // H5 `.grid-stage { padding: 0 var(--grid-padx) }` —— 只有左右，
                            // 顶部不留（原来多给过 12pt，会让网格整体下移）
                            .padding(.horizontal, GridZoom.padX(gridW))
                            // ── 滚动偏移探针（H5 用 `win.scrollLeft`，SwiftUI 只能量）──
                            // 内容左缘在滚动坐标系里的 x 就是 −offset。
                            // ⚠️ 写进 `gridScroll`（`@Observable`）而非 `@State`：没有视图读它
                            //    ⇒ 滚动时不会引发重绘，只有捏合开始的那一刻同步读一次。
                            .background {
                                GeometryReader { g in
                                    let x = g.frame(in: .named(Self.gridScrollSpace)).minX
                                    Color.clear
                                        .onChange(of: x) { _, new in gridScroll.offset = -new }
                                }
                            }
                            // ── 锚针（H5 直接写 scrollLeft；SwiftUI 只能 `scrollTo` 某个子视图）──
                            // 1×1 隐形视图，位置 = 手指按住的那个**内容坐标**（捏合时每帧更新），
                            // 再把它对齐到屏幕上的两指中点 ⇒ 该点在缩放中视觉不动。
                            .overlay(alignment: .topLeading) {
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .offset(x: gridScroll.anchorX)
                                    .id(Self.gridAnchorTickID)
                            }
                        }
                        // 双指缩放：与 H5 同一套算法 ——
                        //   起始宽度 × 双指距离比，夹在 [41, 82]
                        //   （H5 `applyGridVars(pinchStartW * (dist() / pinchStartDist))`；
                        //    `MagnifyGesture` 给的就是相对倍数，必须乘回起始值，
                        //    否则会自我复利、几帧就冲到上限）
                        // 焦点锚定（H5 `anchorOf` / `anchorTo` 的本意）：
                        //   contentX = 中点在**内容坐标系**里的 x = 视口内 x + 当时的 scrollLeft
                        //   缩放后它跑到了 contentX × (新宽 / 起始宽) 处，
                        //   于是把滚动位置摆成「让这个内容点仍落在同一个视口 x 上」。
                        // ⚠️ 单指滑动**完全不动**：交给 ScrollView 原生滚动（惯性、无吸附），
                        //    与 H5「单指不 preventDefault、走浏览器原生滚动」一致。
                        .simultaneousGesture(
                            MagnifyGesture(minimumScaleDelta: 0)
                                .onChanged { value in
                                    if zoomStartW == nil {
                                        zoomStartW = gridW
                                        pinchStartDX = value.startLocation.x
                                        pinchStartOffset = gridScroll.offset
                                    }
                                    let startW = zoomStartW ?? gridW
                                    let clamped = min(GridZoom.maxW,
                                                      max(GridZoom.minW, startW * value.magnification))
                                    guard clamped != gridW, startW > 0 else { return }
                                    gridW = clamped
                                    let ratio = clamped / startW
                                    let contentX = pinchStartDX + pinchStartOffset
                                    gridScroll.anchorX = contentX * ratio
                                    withTransaction(Transaction(animation: nil)) {
                                        scroller.scrollTo(
                                            Self.gridAnchorTickID,
                                            anchor: UnitPoint(x: pinchStartDX / max(proxy.size.width, 1), y: 0)
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    zoomStartW = nil
                                    UserDefaults.standard.set(Double(gridW), forKey: Self.gridWKey)
                                }
                        )
                        .coordinateSpace(name: Self.gridScrollSpace)
                      }
                    }
                    .frame(height: gridViewHeight(width))

                    // H5 `.grid-overflow-note`：渲染量封顶时的说明
                    if filteredBags.count > Self.maxGridRender {
                        Text("仅显示前 \(Self.maxGridRender) 件")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 119/255, green: 115/255, blue: 109/255))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                            .padding(.horizontal, GridZoom.padX(gridW))
                    }
                } else {
                    // ── 展架排列：每个展示架一行，横向滑动 + 亚克力层板 ──
                    // ⚠️ 这块原来是「标题 + `LazyVGrid` 网格换行」，与 H5 的
                    //    `.collection-group-scroll`（定宽卡槽横向滑动）不是一回事，
                    //    已整块换成 `ShelfGroup`。规格见 Views/BagCell.swift。
                    ForEach(Array(groupedBags.enumerated()), id: \.element.shelf) { index, group in
                        ShelfGroup(shelf: group.shelf,
                                   bags: group.bags,
                                   index: index,
                                   viewport: width,
                                   isLast: index == groupedBags.count - 1,
                                   // 搜索中禁用拖动：过滤后的槽位 ≠ 真实位置，写回会算错
                                   canReorder: searchKeywords.isEmpty,
                                   isSorting: sortingShelf == group.shelf,
                                   onSortingChange: { on in
                                       sortingShelf = on ? group.shelf : nil
                                   },
                                   onReorder: commitReorder) { bag in
                            // H5 `bindItemButtons()`：点任意卡片都翻出居中详情大卡
                            // （展架卡与网格卡走的是同一个 `.js-item` 处理）
                            detailBag = bag
                        }
                    }
                }
            }
            // 滚动内容显式定宽（原因见 `showcaseScreen` 同一处）
            .frame(width: width, alignment: .leading)
            // 给底栏让位（口径同 `showcaseScreen`）。
            .padding(.bottom, BottomNav.navHeight + 20)
        }
        .scrollIndicators(.hidden)
        // H5：双击任意处退出排序态（document 级 dblclick；单发点击不误触）
        .onTapGesture(count: 2) {
            if sortingShelf != nil { sortingShelf = nil }
        }
        // 📌 点屏幕任意空白处**收起键盘**（H5 是 blur 输入框收键盘）。
        //    ⚠️ 只改焦点，不动 `keyword` —— 输入的内容原样留着。
        //    卡片 / 按钮 / 搜索框都会先吃掉落在自己身上的点击，所以这里只在
        //    「点到没有控件的空白」时触发：点卡片照旧开详情，点搜索框照旧聚焦。
        .onTapGesture { searchFocused = false }
    }
}

// MARK: - 排序态提示条

/// H5 `.sort-banner`：贴在列表顶部、滑入滑出的排序提示。
/// 高 38（收起 0）、底为 `rgba(242,243,247,.97→.86)` 的纵向渐变、
/// 字 11.5/650、图标 13px 描边 1.7 —— 数值全部照抄原型。
private struct SortBanner: View {
    var visible: Bool

    var body: some View {
        HStack(spacing: 7) {
            SortIcon()
                .stroke(Color.primary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 13, height: 13)
            Text("拖动调整顺序 · 双击空白处完成")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: visible ? 38 : 0)
        .opacity(visible ? 1 : 0)
        .background(
            LinearGradient(colors: [Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255).opacity(0.97),
                                    Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255).opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
        )
        // 命中测试关掉：点提示条 = 点它盖住的内容（H5 用 closest('.sort-banner') 排除自己）
        .allowsHitTesting(false)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: visible)
    }
}

/// 提示条图标：H5 svg `M9 6h11M9 12h11M9 18h11`（三条横线）
/// + `m4 8 2-2 2 2M6 6v12`（向上箭头加竖杆），24×24 视框等比缩放。
private struct SortIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width / 24, rect.height / 24)
        for y in [6, 12, 18] {
            p.move(to: CGPoint(x: 9 * s, y: CGFloat(y) * s))
            p.addLine(to: CGPoint(x: 20 * s, y: CGFloat(y) * s))
        }
        p.move(to: CGPoint(x: 4 * s, y: 8 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 6 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 8 * s))
        p.move(to: CGPoint(x: 6 * s, y: 6 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 18 * s))
        return p
    }
}

// MARK: - 头部

/// 两个页面大标题共用的字号：「袋袋集」/「全部收藏」。
///
/// H5 `.bags-title { font-size: 38px; font-weight: 900; letter-spacing: 2px; line-height: 1 }`
/// —— 两个 header 共用同一档，iOS 这边也必须是**同一个数**，否则两页的头「不是一套」。
///
/// 📌 按需求从 **38 收到 32**（−16%）：首页与收藏页标题一起缩小。
///    ⚠️ 字号与 `frame(height:)` 必须**同值** —— 后者是在 SwiftUI 里复刻 `line-height: 1`：
///       38pt 中文的默认行盒约 45.6，不夹一下整条标题栏会高出 7pt 多；
///       字号改了却忘了改它，标题块会留出一截空白、看着「没变小」。
///    ⚠️ 想再小一档、或回稿面值（38）：只改 `titleSize` 这一个数，两个 header 同步生效。
private enum HeaderMetrics {
    static let titleSize: CGFloat = 32
}

/// 「全部收藏 / 一行统计文案 / 右侧布局切换钮」。
///
/// ⚠️ 结构与 `ShowcaseHeader` **必须逐项对齐**（H5 里两个 header 共用同一套 `.bags-title` /
///    `.bags-tagline`）：大标题 serif tracking 2 + 行高夹到字号（见 `HeaderMetrics`，稿面 38 → 现 32）/
///    副文案 12pt `#77736d` / 右上角是同一个 `HeaderEntryButton` 玻璃托底控件。
///    标题上方的英文小字（THE FULL ARCHIVE）与三个统计 chip 都已按 H5 去掉，别加回来。
///     改一边务必同步另一边，否则两个页面的头部会看起来"不是一套"。
///
/// 📌 首页标题下方原本也有一句文案，收藏页这里原本是「把喜欢的东西，留在看得见的地方。」，
///    已按需求删掉。标题的 `padding(.bottom)` 因此从 8 收回 10，
///    补上原来 tagline 与统计行之间的那段呼吸，否则两段会贴在一起。
private struct LibraryHeader: View {
    let count: Int
    let shelfCount: Int
    let isGrid: Bool
    /// 水平内边距（H5 是 20px，宽屏由调用方提到 28）
    var padH: CGFloat = 20
    var onToggleLayout: () -> Void = {}

    /// H5 `--ink: #141414` / `--muted: #77736d`
    private let ink = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    private let muted = Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("全部收藏")
                    // 宋体重字，与首页「袋袋集」同一档（H5 两个 header 共用 `.bags-title`）。
                    // 字号见 `HeaderMetrics.titleSize`（稿面 38 → 现 32）
                    // ⚠️ 不要退回 `design: .serif` —— 那样中文是苹方黑体（见 AppFont）
                    .font(AppFont.songti(HeaderMetrics.titleSize, .heavy))
                    .tracking(2)
                    .foregroundStyle(ink)
                    .frame(height: HeaderMetrics.titleSize)
                    .padding(.bottom, 6)

                // H5 `#libTagline`：`N 件收藏 · M 个展示架`，与首页那句同字号同色。
                // ⚠️ 这里原来是三枚统计 chip（件收藏 / 个展示架 / 个标签）。
                //    改回一行文案后「个标签」这个数字不再展示 —— H5 也没有，
                //    标签总数在设置面板里仍能看到。
                Text("\(count) 件收藏 · \(shelfCount) 个展示架")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
            }

            Spacer(minLength: 8)

            // 布局切换钮：**上图标 + 下文字**，套 `.header-settings` 的玻璃托底。
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
            //
            // ⚠️ 原来这里写过一个 `frame(width: 44, alignment: .trailing)` 来凑
            //    最小可点尺寸（裸图标只有 24pt 宽）。现在底托自带 9/12/7 内边距，
            //    整块就是命中区，那一行随之删掉 —— 留着会把按钮挤偏。
            HeaderEntryButton(label: isGrid ? "展架" : "宫格",
                              action: onToggleLayout) {
                LayoutGlyphView(isGrid: isGrid)
            }
            .accessibilityLabel(isGrid ? "切换为分组视图" : "切换为网格视图")
        }
        .padding(.horizontal, padH)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

/// 网格视图的卡片：**只有图片，不放任何文字**。
///
/// H5 对应 `.grid-card` + `.grid-art`（`itemButton()` 的产物）：
///   · 卡片 82×116、圆角 14，卡面是**冷调斜向渐变 + 1px 内圈白边**，没有外投影
///   · 袋图放在上窄下宽的不对称内边距里、`align-self: start` 贴顶 ——
///     袋子上移、下方留出呼吸位，像「挂在」卡里而不是塞满
///   · 袋图带 `drop-shadow(0 4px 10px rgba(0,0,0,.18))`
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
    ///
    /// 📌 卡高/袋区一律取 `GridZoom` 里的 H5 值（1:1），本视图不自算任何尺寸。
    /// ⚠️ 插值公式**只有 `GridZoom` 那一份**：原来本视图与 `ShelfView.gridViewHeight`
    ///    各写一遍，两处必须永远一致，稍有差池网格就会多出/少掉一段空高度。
    private var cardH: CGFloat { GridZoom.cardHeight(cardW) }
    private var artH: CGFloat { GridZoom.artHeight(cardW) }
    private var radius: CGFloat { cardW / 5.8571 }

    var body: some View {
        ThumbnailImage(fileName: bag.imageFileName, size: 400,
                       contentMode: .fit, interpolation: .high)
            // 袋图可用盒：H5 `.grid-art > img { max-height: var(--grid-art); max-width: 100% }`
            // —— 袋区**没有内边距**（`.grid-art { padding: 0 }`），图片就是「等比缩放到袋区里」：
            //    高瘦的袋子顶到 `artH`（大档 98），偏宽的图受**袋图宽度上限**限制。
            //
            // 📌 宽度上限取 `GridZoom.artMaxWidth`（78 = 大档卡宽 82 − 左右各 2）：
            //    规则是「**高度优先、宽度封顶，超出封顶就按宽度反压**」——与展架同一套逻辑
            //    （展架那边封顶是 `ShelfMetrics.maxCardWidth` 192，所以它几乎永远等高）。
            .frame(maxWidth: min(cardW, GridZoom.artMaxWidth), maxHeight: artH)
            // 袋图落影：H5 `.grid-art .bag-photo { filter: drop-shadow(0 5px 5px rgba(20,20,20,.16)) }`
            // （blur 5 → radius 2.5）。⚠️ 必须挂在**袋图这一层**：卡片另有自己的外投影。
            .shadow(color: .black.opacity(0.16), radius: 2.5, x: 0, y: 5)
            // 袋区：宽 = 卡宽、高 = `artH`，袋图在其中**居中**（H5 `place-items: center`）
            .frame(width: cardW, height: artH)
            // 卡片本体：H5 `.grid-card { display: grid; place-items: center }`
            // ⇒ 袋区在卡内**上下居中**，上下各留 (cardH − artH)/2 —— 也就是 H5 那个 `--grid-pad`
            .frame(width: cardW, height: cardH)
            // 卡片底：**直接复用首页大卡那套玻璃**（用户要求，别再自己拼渐变）。
            // `GlassCardBackground` 的注释写着「配方永远只有一处定义」，这里正是它的第二个宿主。
            // 两处按小卡调整（都写进参数里，不复制样式）：
            //   · `materialOpacity: 0` —— 与主卡同一个理由（实时毛玻璃在滚动时逐帧重采样，
            //     240 张卡会直接拖垮滑动；而且卡片背后是纯色页面，模糊糊不出东西）；
            //   · `scale` = 卡宽 / 大卡宽 —— 高光半径（280）是按 308pt 定的绝对尺寸，
            //     等比缩到 82pt，免得高光糊满卡面；
            //   · `shadowOpacity: 0` —— **按用户要求：卡片不要投影**。
            //     （H5 的 `.grid-card` 其实有一层 6% 轻影，这里有意去掉；卡片成排密布、
            //      横向只隔 9pt，每张各带一圈柔光会连成灰带、卡与卡的边界反而变糊。
            //      ⚠️ 想恢复只改这一个参数，别去动 `GlassCardBackground` 的默认值。）
            .background {
                GlassCardBackground(cornerRadius: radius,
                                    fillOpacity: 0.154,
                                    materialOpacity: 0,
                                    shadowOpacity: 0,
                                    scale: cardW / HeroMetrics.cardWidth)
            }
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


    /// H5 `--grid-card-h: calc(116px - 58px × ratio)` —— **1:1 照抄，不乘任何系数**
    static func cardHeight(_ w: CGFloat) -> CGFloat {
        116 - 58 * zoomT(w)
    }

    /// H5 `--grid-art: calc(98px - 52px × ratio)` —— 1:1 照抄。
    ///
    /// 📌 袋区**没有任何内边距**（H5 `.grid-art { padding: 0 }`），
    ///    袋图可用盒 = `min(cardW, artMaxWidth) × artH`（大档 78 × 98、小档 41 × 46）。
    /// ⚠️ 98→46 不是 0.5 倍（是 0.4694），所以 art 必须单独插值，
    ///    不能由卡高乘系数推出来 —— 否则小档位纸袋会变成 49 而不是 46。
    static func artHeight(_ w: CGFloat) -> CGFloat {
        98 - 52 * zoomT(w)
    }

    /// 袋图可用宽度的上限。
    ///
    /// H5 是 `max-width: 100%`（＝格子内宽，实际上就是被 `cardW` 卡住）；这里按需求收到 **78**
    /// —— 大档（`maxW` 82）下图片不再顶到格子左右边缘，两侧各留 2pt。
    ///
    /// 📌 规则与展架同一套：**高度优先、宽度封顶，超出封顶就按宽度反压**：
    ///      · 比例 ≤ 78 / 98 = **0.796** 的袋子一律顶到 `artH`，同排等高；
    ///      · 更方的图（0.796 ~ 0.837，即原口径 82/98 的那一段）会从「等高」变成「略矮」。
    ///    这是本次改动**唯一**的取舍，也是与稿面的唯一差异（那个 78 是需求值，不是稿面值）。
    ///    ⚠️ 想回稿面口径：写回 `maxW`（82，即卡内满宽）。
    ///    ⚠️ 小档位（`cardW` < 78）仍以卡宽为准 —— 实际取 `min(cardW, artMaxWidth)`。
    static let artMaxWidth: CGFloat = 78

    /// H5 `--grid-ratio: (82 − w) / 41`：缩放档位（0 = 最大档 82，1 = 最小档 41）
    static func zoomT(_ w: CGFloat) -> CGFloat {
        (maxW - w) / (maxW - minW)
    }
    /// H5 `relayoutGrid()`：列数取「一屏放得下的列数 + 1」，
    /// 多渲染一列保证任何缩放级别下内容都溢出、横向滚动永远可用。
    static func columnCount(_ w: CGFloat, viewport: CGFloat) -> Int {
        let gap = self.gap(w)
        let avail = viewport - padX(w) * 2
        let k = max(1, Int(ceil((avail + gap) / (w + gap))))
        return k + 1
    }
}

/// `袋袋集 / 一句文案` + 右侧「设置」玻璃按钮 —— H5 `.bags-header`。
///
/// 版式（H5 逐值）：
///   · 容器 `display:flex; align-items:center; justify-content:space-between; padding: 10px 20px 16px`
///   · `.bags-title`  38px / 900 / letter-spacing 2 / 衬线 / `--ink` / `margin: 0 0 6px`
///     （字号见 `HeaderMetrics.titleSize`：稿面 38 → 现 32）
///   · `.bags-tagline` 12px / `--muted` / line-height 1.4
///   · 右侧 `.header-settings`：图标在上、文字在下的玻璃托底按钮
///
/// ⚠️ 标题上方原来还有一行英文小字（MY PRIVATE CABINET），H5 已按需求去掉，
///    这里同步去掉；那行预留的 6px 上边距随之归零，标题直接顶到容器内边距。
///
/// 📌 右上角的沿革（H5 注释里记着）：三枚统计 chip → 「最近收藏 N」胶囊 →
///    **设置入口**。iOS 停在中间的胶囊那一版，这轮按 H5 换回设置按钮；
///    原来给设置兜底的「最近收集」齿轮同时退役，否则会有两个入口。
private struct ShowcaseHeader: View {
    /// 水平内边距（H5 `.bags-header { padding: 10px 20px 16px }`，宽屏提到 28）
    var padH: CGFloat = 20
    var onOpenSettings: () -> Void = {}

    /// H5 `--ink: #141414` / `--muted: #77736d`
    private let ink = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    private let muted = Color(red: 119 / 255, green: 115 / 255, blue: 109 / 255)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                // H5 `.bags-title`：38px / 900 / 衬线 / 字距 2（字号见 `HeaderMetrics`）。
                //
                // ⚠️ 中文的「衬线」只能靠显式指定宋体拿到：
                //    写 `design: .serif` 时中文会静默回落到苹方黑体（见 `AppFont`）。
                //    H5 那句 900 对应思源宋体的 `Heavy` 字面（随包，见 `Fonts/`）。
                Text("袋袋集")
                    .font(AppFont.songti(HeaderMetrics.titleSize, .heavy))
                    .tracking(2)
                    .foregroundStyle(ink)
                    // H5 `.bags-title { line-height: 1 }`：行盒正好等于字号，不留行距。
                    // SwiftUI 给这个字号的中文行盒约 1.2 倍，不夹一下整条标题栏会高 7pt 多。
                    .frame(height: HeaderMetrics.titleSize)
                    .padding(.bottom, 6)

                Text("收集每一个纸袋的故事")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
            }

            Spacer(minLength: 8)

            HeaderEntryButton(label: "设置", action: onOpenSettings) {
                SettingsGlyphView()
            }
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

// MARK: - 搜索无结果的空状态

/// 「没有结果」空状态 —— 交付包 `.empty-state`，三层结构逐值对齐：
///   · `.empty-state__mark`  34px / 900 / 字距 2 / 行高 1 的淡色大字，文案写死「没有结果」
///   · `.empty-state__sub`   12px 灰色副文案，回显关键词
///   · `.empty-state__chips` 出路标签（最多 4 个），点一下就一定有结果
///
/// ⚠️ 别再退回「`⌕` 字形 + 静态文案 + 25px 标题」那一版 —— 那是更早的稿子。
///    交付包在 `.empty-state` 上方写明了：原来那个 ⌕ 字形和「清空搜索」按钮都撤掉了，
///    标签本身就是出路（搜索框右侧另有原生 × 负责一键清空，再放按钮是重复入口）。
///
/// ⚠️ 原型是**一套组件**同时用于「搜不到」和「库里一条都没有」两种情况，
///    这里保持同一套；两者的差别只落在副文案上（见调用处）。
private struct LibraryEmptyState: View {
    let mark: String
    let hint: String
    var chips: [String] = []
    var onPick: (String) -> Void = { _ in }

    /// H5 `--ink: #141414` / `--muted: #77736d`
    private let ink = Color(red: 20/255, green: 20/255, blue: 20/255)
    private let muted = Color(red: 119/255, green: 115/255, blue: 109/255)

    var body: some View {
        VStack(spacing: 0) {
            // `.empty-state__mark { font-size: 34px; font-weight: 900; letter-spacing: 2px;
            //                      line-height: 1; color: var(--ink); opacity: .16; serif }`
            //
            // 它是「标记」不是标题，压到 16% 透明度才够轻，不会把下面的出路标签压掉。
            // 衬线走随包的思源宋体（900 → `heavy`）：`design: .serif` 对中文不生效。
            Text(mark)
                .font(AppFont.songti(34, .heavy))
                .tracking(2)
                .foregroundStyle(ink.opacity(0.16))

            // `.empty-state__sub { margin: 16px 0 0; font-size: 12px }`（无衬线栈，继承 body）
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .padding(.top, 16)

            if !chips.isEmpty {
                // H5 `.empty-state__chips { gap: 7px; justify-content: center; margin: 18px 0 0 }`
                FlowRow(spacing: 7, alignment: .center) {
                    // ⚠️ 用下标做 id 而不是文本：品牌与同名标签会产出两条
                    //    文本相同的候选（H5 也允许），`id: \.self` 会撞 id。
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        Button { onPick(chip) } label: {
                            Text(chip)
                                // `.empty-state__chip { font-size: 11px; font-weight: 650 }`
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(EmptyChipStyle())
                    }
                }
                .padding(.top, 18)
            }
        }
        // H5 `.empty-state { padding: 58px 20px 30px; text-align: center }`
        .padding(.horizontal, 20)
        .padding(.top, 58)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// 出路标签的按钮样式。
///
/// H5 给了两个态：`:hover`（底色 5% → 9%、文字转墨色）和 `:active`（`scale(.94)`）。
/// 触屏没有 hover，所以按下态把两者合起来给 —— 既缩放，也换那两个色值。
private struct EmptyChipStyle: ButtonStyle {
    /// H5 `rgba(20,20,20,…)`：底色基准是墨色 #141414，不是纯黑
    private let chipInk = Color(red: 20/255, green: 20/255, blue: 20/255)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed
                             ? chipInk
                             : Color(red: 119/255, green: 115/255, blue: 109/255))
            .background(configuration.isPressed
                        ? chipInk.opacity(0.09)
                        : chipInk.opacity(0.05),
                        in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - 底部导航

/// 底部导航：陈列 | ＋ | 全部收藏。
///
/// H5 对应 `.bottom-nav` —— 一层**半透明毛玻璃**盖住 `navHeight`（70pt）高的区域，
/// 内容贴底；`pointer-events: none` 让空白区手势穿透到下层滚动。配方（H5 逐值）：
/// ```css
/// background: linear-gradient(180deg, rgba(255,255,255,.38) 0%, rgba(255,255,255,.66) 60%, rgba(255,255,255,.82) 100%);
/// backdrop-filter: blur(14px) saturate(1.18);
/// box-shadow: 0 -1px 0 rgba(255,255,255,.5) inset, 0 -10px 22px rgba(40,55,85,.05);
/// ```
/// 即「**顶部更透、底部更实**」的白色渐变 + 毛玻璃：滚动内容从底下穿过时会被糊掉、
/// 从渐变里透出来，而不是被一块硬边色块切断。
///
/// ⚠️ 底板不能省。没有它，滚动中的卡片会从图标之间的缝隙里透出来和文字叠在一起；
///     底板也必须盖住整排图标（图标 23 + gap 4 + 文字 10 实际占到约 62px 高）。
///
/// 📝 沿革：纯色（`--paper` #F2F3F7）→ 本轮改回「渐变 + 毛玻璃」。
///     当初退回纯色是因为那条渐变**终点是不透明的 paper**，与页面底色一有色差
///     就成了一条缝；现在的配方终点只有 82% 白、且带毛玻璃，不存在「对不上」的问题。
private struct BottomNav: View {
    @Binding var screen: ShelfView.Screen
    var onAdd: () -> Void = {}
    /// H5 `0 -10px 22px rgba(40,55,85,.05)` 的基色（不是卡片用的 rgb(52,66,92)）
    private static let navShadow = Color(red: 40/255, green: 55/255, blue: 85/255)
    /// H5 `.bottom-nav { height: 132px }`，按用户要求逐轮收到 85 → 70 → **54**。
    ///
    /// ⚠️ 这里是**安全区之上**的内容区高度，不含底部的 safe-bottom。
    ///    实机可见高度 = 54 + 安全区（iPhone 上约 34pt）≈ **88pt**（原 104pt）。
    ///    ⚠️ 它的下限由 `itemHeight` 决定（本值 = itemHeight + 8pt 顶垫），
    ///       再矮就会裁到图标本身。
    ///
    /// 📌 改成 `static` 是为了让 `showcaseScreen` / `libraryScreen` 的滚动底部留白
    ///    能直接由它派生（`BottomNav.navHeight + 20`），底栏高度以后只改这一个数，
    ///    留白自动跟随、不会漂移。
    static let navHeight: CGFloat = 54
    /// 导航项高度：图标框 24 + 间距 4 + 文字行 ≈ 12 ＝ 40，留 6pt 余量给选中圆点。
    ///
    /// ⚠️ 不能再低于 44（最小可点尺寸）—— 现在 46 已贴近下限。
    private let itemHeight: CGFloat = 46

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
        // 宽屏（iPad）把三个控件收拢居中 —— H5 的底栏也是
        // `justify-content: center`（三个控件固定间距居中），不是摊到两端；
        // 不限制的话 `Spacer(minLength: 0)` 会把两个 nav-item 推到屏幕两端，
        // 与中间的 ＋ 相隔上千点，既难看也不好按（手指够不到）。
        // iPhone 上屏宽 < 520，这一层是恒等变换。
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
        // ⚠️ 整条**铺满全宽**（H5 `.bottom-nav { left: 0; right: 0 }`）。
        //    底板必须挂在「满宽」这一层上：挂在上面那个 `contentColumn(520)`
        //    上的话，宽屏上玻璃只铺到中间 520pt 一段，两侧露出页面底色，
        //    看起来就是「底栏没有全屏」（用户反馈过）。
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            navBackdrop
                .allowsHitTesting(false)   // H5 `pointer-events: none`
                // ⚠️ `.ignoresSafeArea(edges: .bottom)` 不能省。
                //    本视图位于安全区内，底板若只铺到安全区底边，屏幕最下方的
                //    34pt 会露出 PageBackground 的底色（#E4E6EC）—— 于是底边留下
                //    一条色差缝，导航栏就「没贴底」。加上它，底板一直铺到物理底边。
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 底栏底板（H5 `.bottom-nav`）：毛玻璃打底 → 白色渐变 → 栏顶内高光 + 向上的一道淡影。
    ///
    /// ⚠️ 层次不能反：毛玻璃在最底、渐变叠在它**上面**。
    ///    另外 SwiftUI 的 `.ultraThinMaterial` 自带一层白，所以成品会比 CSS 略白一档
    ///    （`blur(14px)` 本身不带 tint，material 带）—— 这是 material 的固有行为，
    ///    但「上透下实」的玻璃条观感一致。若嫌偏白，把三个 alpha 各降 0.1 即可。
    private var navBackdrop: some View {
        Rectangle()
            // `backdrop-filter: blur(14px) saturate(1.18)`
            //（SwiftUI 的 material 不暴露模糊半径与饱和度，取最接近的 ultraThin）
            .fill(.ultraThinMaterial)
            // `linear-gradient(180deg, rgba(255,255,255,.38) 0%,
            //                  rgba(255,255,255,.66) 60%, rgba(255,255,255,.82) 100%)`
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.38), location: 0),
                        .init(color: .white.opacity(0.66), location: 0.6),
                        .init(color: .white.opacity(0.82), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // `0 -1px 0 rgba(255,255,255,.5) inset`：栏顶一条内高光线
            //（inset 阴影 iOS 没有原生等价物，用 1pt 纯色条顶替，与卡片描边的处置一致）
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(height: 1)
            }
            // `0 -10px 22px rgba(40,55,85,.05)`：往上投的一道很淡的影
            //（CSS 的 blur 22 → SwiftUI 的 radius 取一半 = 11）
            .shadow(color: Self.navShadow.opacity(0.05), radius: 11, x: 0, y: -10)
    }

    private func navItem(_ target: ShelfView.Screen, systemImage: String) -> some View {
        let isActive = screen == target
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { screen = target }
        } label: {
            VStack(spacing: 4) {
                // 📌 按需求「图标与右上角设置图标大小对齐」：字号 23 → 21、
                //    并显式套上 `HeaderEntryMetrics.settingsIconSide`（24）的方框 ——
                //    两处图标从此同一个框、墨迹也同一量级（实测都是 ~20pt）。
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: HeaderEntryMetrics.settingsIconSide,
                           height: HeaderEntryMetrics.settingsIconSide)
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
                // 📌 随底栏一起收小：字 29 → 25、圆盘 56 → 46（H5 原值 56/30，
                //    但 56 会占满甚至溢出变矮后的底栏）。46 与 `itemHeight` 同高。
                .font(.system(size: 25, weight: .light))   // H5 `font-size: 30px; font-weight: 200`
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)              // H5 `.add-button { 56px }`
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


/// 网格的滚动偏移与缩放锚针位置。
///
/// ⚠️ 用 `@Observable`（而不是 `@State`）是有意的：`offset` 在滚动时**每帧**被写入，
///    而没有任何视图读它（只有捏合开始的那一刻同步读一次）——
///    于是这些写入**不触发任何重绘**。若改成 `@State`，横向拖一下网格就会
///    把整个页面（含 240 张卡片）重算一遍，滑动直接掉帧。
final class GridScrollState {
    /// 当前横向滚动偏移（内容左缘相对滚动视口的位置，取正值）
    var offset: CGFloat = 0
    /// 锚针在**内容坐标系**里的 x（捏合时每帧更新，只有锚针自己读它）
    var anchorX: CGFloat = 0
}
