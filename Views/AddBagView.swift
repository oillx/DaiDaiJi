import SwiftUI
import SwiftData
import PhotosUI

/// 新增纸袋：拍摄/选图 → 自动抠图/矫正/增强 + OCR命名 → 表单 → 保存
///
/// 两个入口，共用同一套流程，只是起点不同：
/// - 首页底部「＋」→ `startsInCamera: true`，**直接进拍摄页**，拍完落到表单
/// - 表单里点「拍照」→ 退回拍摄页，拍完再回表单
struct AddBagView: View {

    /// 两步流程
    enum Step { case camera, form }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var existing: [BagItem]      // 用于分类模糊匹配

    @State private var rawImage: UIImage?        // 用户刚选/拍的原图
    @State private var selectedImage: UIImage?   // 处理后的预览
    @State private var processing = false
    @State private var info: String = ""         // 处理结果提示
    @State private var photoItem: PhotosPickerItem?
    @State private var name = ""
    @State private var category = ""
    /// 已确认的标签（写成 `BagItem.tags`）
    @State private var tags: [String] = []
    /// 标签输入框的草稿（还没按回车/逗号）
    @State private var tagInput = ""
    @State private var note = ""
    @State private var showPicker = false

    /// 当前处于哪一步
    @State private var step: Step
    /// 表单半窗是否在显示（见 `body` 里的 `.sheet`）
    @State private var showForm: Bool

    /// 下划线字段的聚焦态 —— 与编辑半窗同一套样式，聚焦时那条线转品牌红
    @FocusState private var focus: Field?
    private enum Field: Hashable { case name, category, tags, note }

    /// 由「＋」进入：一进来就是拍摄页，且拍摄页的返回＝关闭整页
    private let startsInCamera: Bool

    init(startsInCamera: Bool = false) {
        self.startsInCamera = startsInCamera
        _step = State(initialValue: startsInCamera ? .camera : .form)
        // 直接从表单进入（非拍照流程）时，半窗一开始就该在
        _showForm = State(initialValue: !startsInCamera)
    }

    /// 已有分类（去重、排序）
    private var knownCategories: [String] {
        Array(Set(existing.map { $0.category }.filter { !$0.isEmpty })).sorted()
    }
    /// 当前输入命中的相似分类
    private var categorySuggestions: [String] {
        CategoryMatcher.match(category, in: knownCategories)
            .filter { $0.lowercased() != category.lowercased() }
    }

    var body: some View {
        ZStack {
            switch step {
            case .camera:
                CameraView(
                    // 由「＋」直接进来时，返回＝退出整页；否则退回表单
                    onBack: startsInCamera ? nil : { step = .form; showForm = true },
                    onImage: { image in
                        rawImage = image
                        step = .form      // 拍/选完自动落到表单
                        showForm = true
                    }
                )
                .transition(.opacity)

            case .form:
                // 表单本体在半窗里（见下面的 `.sheet`），这里只铺页面底色当底，
                // 否则半窗背后露出的是相机那一帧。
                PageBackground()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .onChange(of: rawImage) { _, newImage in process(newImage) }
        // 📌 表单走**半窗**（用户要求：复用编辑卡片那套半窗样式）。
        .sheet(isPresented: $showForm) { formScreen }
        .onChange(of: showForm) { _, on in
            // 半窗收起（取消 / 保存 / 下拉）＝ 整个新增流程结束。
            // ⚠️ 点「拍照」是主动收起并回到相机，那一步已经把 step 设回 .camera，
            //    所以这里必须再判一次 step，否则会被顺带退出整个流程。
            if !on && step == .form { dismiss() }
        }
    }

    /// 表单半窗 —— **复用编辑半窗那套样式**
    /// （下划线字段 `EditFieldRow`/`EditUnderline` + 动作条 `EditActionBar` + 外壳 `editSheetChrome`）。
    ///
    /// 📌 与编辑半窗的差异只有三处，都是「新增」这个场景特有的：
    ///    · 顶部是**可换的照片**（编辑态那里是只读的小图）；
    ///    · 分类与标签在输入框下面还挂着候选，点一下直接填；
    ///    · 主要动作是「保存」，且**没选图时禁用**。
    private var formScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photoArea

                    EditFieldRow(key: "名称") {
                        VStack(spacing: 6) {
                            TextField("给这只袋子起个名字", text: $name)
                                .focused($focus, equals: .name)
                                .font(.system(size: 15))
                                .foregroundStyle(EditPalette.ink)
                            EditUnderline(focused: focus == .name)
                        }
                    }

                    EditFieldRow(key: "所属分类") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("如「霸王茶姬」", text: $category)
                                .focused($focus, equals: .category)
                                .font(.system(size: 15))
                                .foregroundStyle(EditPalette.ink)
                            EditUnderline(focused: focus == .category)
                            if !categorySuggestions.isEmpty {
                                suggestChips(categorySuggestions) { category = $0 }
                            }
                        }
                    }

                    EditFieldRow(key: "标签", alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("回车或逗号分隔", text: $tagInput)
                                .focused($focus, equals: .tags)
                                .font(.system(size: 15))
                                .foregroundStyle(EditPalette.ink)
                                .onSubmit { commitTagInput() }
                                .onChange(of: tagInput) { _, newValue in
                                    // 粘贴一整串「茶饮, 艺术」时也能自动拆签
                                    if newValue.contains(",") || newValue.contains("，") {
                                        commitTagInput()
                                    }
                                }
                            EditUnderline(focused: focus == .tags)
                            if !tags.isEmpty {
                                // 已添加的标签，点 × 移除
                                FlowTagRow(tags: tags) { tag in
                                    tags.removeAll { $0 == tag }
                                }
                            }
                        }
                    }

                    EditFieldRow(key: "详情", alignment: .top) {
                        VStack(spacing: 6) {
                            TextField("这只袋子的来历、手感…（选填）", text: $note, axis: .vertical)
                                .focused($focus, equals: .note)
                                .font(.system(size: 15))
                                .foregroundStyle(EditPalette.ink)
                                .lineLimit(2...4)
                            EditUnderline(focused: focus == .note)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DetailCardMetrics.paddingH)
                .padding(.top, DetailCardMetrics.paddingTop)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // 相册选择器挂在半窗内部：选完直接把图交给 `loadPhoto`
            .photosPicker(isPresented: $showPicker, selection: $photoItem)
            .onChange(of: photoItem) { _, newItem in loadPhoto(from: newItem) }

            EditActionBar(secondaryTitle: "取消",
                          onSecondary: { dismiss() },
                          primaryTitle: "保存",
                          primaryEnabled: selectedImage != nil,
                          onPrimary: { save() })
        }
        .editSheetChrome()
    }

    /// 顶部照片区：预览 + 「相册 / 拍照」+ 处理结果提示
    private var photoArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(.rect(cornerRadius: 14))
                } else if processing {
                    ProgressView("处理中…")
                        .frame(maxWidth: .infinity, minHeight: 96)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                        .frame(height: 96)
                        .overlay {
                            Text("尚未选择图片")
                                .font(.system(size: 11))
                                .foregroundStyle(HeroPalette.muted)
                        }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                chipButton("相册") { showPicker = true }
                // 回到相机：先把半窗收起（step 改回 .camera ⇒ 上面那个 onChange 不会退出流程）
                chipButton("拍照") { step = .camera; showForm = false }
                if !info.isEmpty {
                    Text(info)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HeroPalette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 6)
    }

    /// 小号描边按钮：与底部动作条的「次要」同一套描边，只是收小一号
    private func chipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditPalette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    /// 已有分类的候选：点一下直接填进输入框
    private func suggestChips(_ items: [String],
                              onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { c in
                    Button { onTap(c) } label: {
                        Text(c)
                            .font(.system(size: 11.5))
                            .foregroundStyle(EditPalette.ink)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 26)
                            .background(Color.black.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                rawImage = ui
            }
        }
    }

    /// 选/拍到原图后：跑图像处理流水线（后台），回填预览与名称
    private func process(_ image: UIImage?) {
        guard let image else { return }
        processing = true
        info = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                BagImagePipeline.process(image)
            }.value
            processing = false
            if let result {
                selectedImage = result.result
                if name.isEmpty { name = result.suggestedName ?? "" }
                info = "已处理："
                    + (result.didCrop ? "矫正 ✓ " : "矫正 ✗ ")
                    + (result.didRemoveBackground ? "抠图 ✓" : "抠图 ✗")
            } else {
                selectedImage = image
                info = "图像处理失败，已使用原图"
            }
        }
    }

    /// 把输入框里的草稿变成标签。
    /// 同时处理「回车提交」和「粘贴了逗号串」两种情况 —— 所以先按逗号拆，
    /// 再逐个裁剪、去重（忽略大小写）、丢掉空串。
    private func commitTagInput() {
        let pieces = tagInput
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for piece in pieces where !tags.contains(where: {
            $0.caseInsensitiveCompare(piece) == .orderedSame
        }) {
            tags.append(piece)
        }
        tagInput = ""
    }

    private func save() {
        guard let image = selectedImage, let fileName = ImageStore.save(image) else { return }
        // 输入框里可能还留着没按回车的标签，别丢掉
        commitTagInput()

        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)

        // ── 发号 ──
        // `NO.xxx` 在上传时定死（存 `serialNumber`），之后删除、拖动排序都不再改它。
        // 取「现有最大号 + 1」；删号留出的空缺不回收 —— 编号必须稳定。
        let serial = (existing.map(\.serialNumber).max() ?? 0) + 1

        // ── 展架组内位置 ──
        // 新袋子插到所属展示架的**最前**（与「最新在前」的旧口径一致）：
        // 已有组员整体后移一位，给新袋子腾出 1 号位；空组直接占 1。
        let shelfKey = trimmedCategory.isEmpty ? "未分类" : trimmedCategory
        let shelfmates = existing.filter { $0.displayShelf == shelfKey }
        for mate in shelfmates { mate.manualOrder += 1 }

        let bag = BagItem(imageFileName: fileName,
                          name: name.trimmingCharacters(in: .whitespaces),
                          category: trimmedCategory,
                          tags: tags,
                          serialNumber: serial,
                          manualOrder: 1,
                          note: note.trimmingCharacters(in: .whitespaces))
        context.insert(bag)
        dismiss()
    }
}

// MARK: - 标签流式布局

/// 已添加的标签：自动换行铺开，每个带一个 × 可移除。
/// 用 `Layout` 实现而不是 `HStack`，标签多了会自动折行。
private struct FlowTagRow: View {
    let tags: [String]
    var onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag).font(.caption)
                    Button { onRemove(tag) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: .capsule)
            }
        }
    }
}

/// 极简流式布局：按可用宽度自动折行（标签数量不定，`HStack` 会溢出）。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

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
#Preview {
    AddBagView()
        .modelContainer(PreviewData.container)
}
