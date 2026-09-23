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
    @State private var material = ""
    /// 已确认的标签（写成 `BagItem.tags`）
    @State private var tags: [String] = []
    /// 标签输入框的草稿（还没按回车/逗号）
    @State private var tagInput = ""
    @State private var note = ""
    @State private var showPicker = false

    /// 当前处于哪一步
    @State private var step: Step

    /// 由「＋」进入：一进来就是拍摄页，且拍摄页的返回＝关闭整页
    private let startsInCamera: Bool

    init(startsInCamera: Bool = false) {
        self.startsInCamera = startsInCamera
        _step = State(initialValue: startsInCamera ? .camera : .form)
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
                    onBack: startsInCamera ? nil : { step = .form },
                    onImage: { image in
                        rawImage = image
                        step = .form      // 拍/选完自动落到表单
                    }
                )
                .transition(.opacity)

            case .form:
                formScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .onChange(of: rawImage) { _, newImage in process(newImage) }
    }

    private var formScreen: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                        } else if processing {
                            ProgressView("处理中…")
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Color.gray.opacity(0.1)
                                .frame(height: 120)
                                .overlay(Text("尚未选择图片").foregroundStyle(.secondary))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        Button("相册") { showPicker = true }
                        Button("拍照") { step = .camera }
                    }

                    if !info.isEmpty {
                        Text(info).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("信息") {
                    TextField("纸袋名称", text: $name)

                    TextField("所属分类", text: $category)
                    if !categorySuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(categorySuggestions, id: \.self) { c in
                                    Button(c) { category = c }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    // 材质：背面「材质」字段。H5 空值渲染成「—」，这里留空即可。
                    TextField("材质（选填，如「白卡纸覆哑膜」）", text: $material)

                    // 标签：背面标签区 + 搜索匹配。
                    // H5 是逗号分隔的字符串数组，这里做成「输入 + 回车/逗号成签」，
                    // 与粘贴逗号串都能用。
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("标签（选填，回车或逗号分隔）", text: $tagInput)
                            .onSubmit { commitTagInput() }
                            .onChange(of: tagInput) { _, newValue in
                                // 粘贴一整串「茶饮, 艺术」时也能自动拆签
                                if newValue.contains(",") || newValue.contains("，") {
                                    commitTagInput()
                                }
                            }

                        if !tags.isEmpty {
                            // 已添加的标签，点 × 移除
                            FlowTagRow(tags: tags) { tag in
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }

                    TextField("详情（选填）", text: $note, axis: .vertical)
                }
            }
            // iPad 上 `Form` 默认铺满整屏，输入框会被拉成一行一千多点，很难读。
            // 收进 620pt 的列里居中。iPhone 上 393 < 620，这一层是恒等变换。
            .contentColumn(AppLayout.formMaxWidth)
            // ⚠️ 兜底色不能省。`Form` 自带的是 grouped 底色（浅灰 #F2F2F7），
            //    收窄到 620pt 后两侧露出的是导航栈底色（浅色模式下为白），
            //    于是出现「居中一块浅灰 + 两侧白」的缝。
            //    这里在整宽上补一层同色，iPad 上就是「整屏浅灰 + 居中表单」。
            //    iPhone 上 Form 本就铺满，这层被完全盖住，无观感影响。
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("新增纸袋")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(selectedImage == nil)
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $photoItem)
            .onChange(of: photoItem) { _, newItem in loadPhoto(from: newItem) }
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
        let bag = BagItem(imageFileName: fileName,
                          name: name.trimmingCharacters(in: .whitespaces),
                          category: category.trimmingCharacters(in: .whitespaces),
                          material: material.trimmingCharacters(in: .whitespaces),
                          tags: tags,
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
