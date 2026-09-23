import SwiftUI
import SwiftData

/// 纸袋详情：大图 + 基础信息（可编辑）+ 补充信息 + 删除（二次确认）
struct BagDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var bag: BagItem

    @State private var showDelete = false
    @State private var editing = false

    /// 标签在编辑态的双向绑定：读时拼成「、」分隔，写时拆回数组。
    /// 这样不用为 `[String]` 单独做一套增删 UI，编辑体验与 H5 的输入框一致。
    private var tagsText: Binding<String> {
        Binding(
            get: { bag.tags.joined(separator: "、") },
            set: { newValue in
                bag.tags = newValue
                    .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部大图（透明背景铺白底，避免锯齿）
                // 用 `BagImageResolver` 兼容「磁盘真实图」与「Assets 演示图」
                if let image = BagImageResolver.load(bag.imageFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemBackground))
                }

                if editing {
                    VStack(spacing: 12) {
                        TextField("名称", text: $bag.name)
                        TextField("分类", text: $bag.category)
                        TextField("材质", text: $bag.material)
                        // 标签在编辑态用逗号串表示：比做一套增删 UI 轻，
                        // 且与 H5 底层存的就是数组、展示成逗号串一致。
                        TextField("标签（逗号分隔）", text: tagsText)
                        TextField("详情", text: $bag.note, axis: .vertical)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("名称", value: bag.displayName)
                        if !bag.category.isEmpty {
                            LabeledContent("分类", value: bag.category)
                        }
                        // 材质用 displayMaterial：空值渲染成「—」，与 H5 一致
                        LabeledContent("材质", value: bag.displayMaterial)
                        if !bag.tags.isEmpty {
                            LabeledContent("标签", value: bag.tags.joined(separator: "、"))
                        }
                        if !bag.note.isEmpty {
                            LabeledContent("详情", value: bag.note)
                        }
                        LabeledContent("上传", value: bag.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            // 宽屏（iPad）收进阅读列居中：不限制的话顶部大图会被拉到一千多点宽，
            // 键值对两端相隔太远。iPhone 上 393 < 620，恒等变换。
            .contentColumn(AppLayout.formMaxWidth)
        }
        .navigationTitle("纸袋详情")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "完成" : "编辑") { editing.toggle() }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("删除", role: .destructive) { showDelete = true }
            }
        }
        .confirmationDialog("确认删除这个纸袋？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                ImageStore.delete(bag.imageFileName)
                context.delete(bag)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 预览

// 用 `sampleManagedBag()`（已插入容器）而不是 `sampleBag()` ——
// 详情页会写入并可能删除，游离对象在这两条路径上都会出问题。
#Preview {
    NavigationStack {
        BagDetailView(bag: PreviewData.sampleManagedBag())
    }
    .modelContainer(PreviewData.container)
}
