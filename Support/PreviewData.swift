import SwiftData
import SwiftUI

/// SwiftUI 预览专用的内存数据容器与示例数据。
/// 只用于 Xcode Canvas，不影响正式运行的 App。
///
/// ⚠️ 数据集与 H5 原型 `app.js` 顶部 `items[]` **完全一致**（16 只袋子）。
/// 日期是写死的 2026 年 8~9 月，因此时间口径要配合 `FeedBase.demo` 使用
/// —— 用数据集里最新的那一天当「今天」，否则「最近 15 天」会全部失效。
@MainActor
enum PreviewData {

    /// 内存中的 SwiftData 容器（预览用，不落盘）。
    ///
    /// ⚠️ 这里**不用 `try!`**：`try!` 一旦失败会让 Xcode Canvas 直接闪退，
    ///    而且崩在 `static let` 的首次访问处，报错信息指不到真正的 schema 问题。
    ///    改成带原因的 `fatalError`，至少能在日志里看到为什么建不起来。
    ///
    /// schema 与正式容器保持一致（都走 `SchemaV4`），避免「预览能跑、真机不能跑」。
    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            for bag in samples() {
                container.mainContext.insert(bag)
            }
            return container
        } catch {
            fatalError("预览容器创建失败（schema 与 SchemaV4 不一致？）：\(error)")
        }
    }()

    /// 单张示例纸袋（用于详情/卡片预览）
    ///
    /// ⚠️ 这是**游离对象**（没有插进任何 context）。`BagCell` / `HeroCardView`
    /// 这类只读视图用它没问题；但 `BagDetailView` 会 `@Bindable` 写入、
    /// 还会 `context.delete` —— 那种场景必须用 `sampleManagedBag()`。
    static func sampleBag() -> BagItem {
        samples()[0]
    }

    /// 真正挂在预览容器里的示例对象。
    ///
    /// 给需要写入 / 删除的预览用（详情页、编辑态）。
    /// 直接拿 `sampleBag()` 塞给这类视图，会在保存或删除时因为对象
    /// 不属于任何 context 而崩溃或静默失效。
    ///
    /// 取「第一条已插入的记录」而不是重新 insert，避免每次预览重绘都往里塞一份。
    ///
    /// ⚠️ 参数默认值必须写 `nil`，在函数体里再回退到 `PreviewData.container`。
    ///    **不能**直接把默认值写成 `= PreviewData.container`：
    ///    默认参数表达式按 **nonisolated** 上下文求值，而 `PreviewData` 是 `@MainActor`，
    ///    于是报
    ///    "Main actor-isolated static property 'container' can not be referenced
    ///     from a nonisolated context"。
    ///    （SE-0411 允许默认值继承外层隔离，但 Swift 5.9 工具链上还没生效。）
    ///    函数体内部会继承 `@MainActor` 隔离，所以回退取值是安全的。
    static func sampleManagedBag(in container: ModelContainer? = nil) -> BagItem {
        let container = container ?? PreviewData.container
        let descriptor = FetchDescriptor<BagItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let first = try? container.mainContext.fetch(descriptor).first {
            return first
        }
        // 兜底：容器里居然是空的（不该发生），插一条再返回
        let bag = samples()[0]
        container.mainContext.insert(bag)
        return bag
    }

    /// 16 只真实袋子，顺序与 H5 `items[]` 一致（编号 NO.001~NO.016 依赖这个顺序）
    ///
    /// `location`（上传地点）逐条照抄 H5 `items[]` 的字面值 —— 首页背面与
    /// 详情卡编辑态的只读条都直接展示它，两边必须一字不差。
    static func samples() -> [BagItem] {
        let bags: [BagItem] = [
            // ── 霸王茶姬 ──
            make("chagee-scenery", "山水风景手提袋", "霸王茶姬",
                 ["茶饮", "艺术"], "2026.09.15", "中号 · 260×320mm", "深圳市南山区",
                 "袋身是层叠的蓝绿山水笔触，远处有两个人影。收进来时还留着茶的余温。"),
            make("chagee-lime", "柠檬绿叶手提袋", "霸王茶姬",
                 ["茶饮", "植物"], "2026.09.13", "中号 · 260×320mm", "深圳市福田区",
                 "青柠与白花铺满整面，颜色很亮。夏天拎出去像带了一袋降温的绿。"),
            make("chagee-blossom", "青花杏花手提袋", "霸王茶姬",
                 ["茶饮", "国风"], "2026.09.11", "中号 · 260×320mm", "广州市天河区",
                 "青底白杏花，枝干缠成一片。三只茶姬里留了这只，纹样最耐看。"),

            // ── 瑞幸咖啡 ──
            make("luckin-crocs", "CROCS 联名手提袋", "瑞幸咖啡",
                 ["咖啡", "联名"], "2026.09.14", "中号 · 250×310mm", "深圳市南山区",
                 "桃粉底上堆满蓝绿立体字，每个字母里塞了热带小插画。联名款里最花的一只。"),
            make("luckin-allin", "ALL IN 拥抱手提袋", "瑞幸咖啡",
                 ["咖啡", "插画"], "2026.09.14", "中号 · 250×310mm", "深圳市福田区",
                 "满版拥抱的人，衣服颜色拼在一起像马赛克。下面一颗大心写着 ALL IN。"),
            make("luckin-kitty", "Hello Kitty 联名手提袋", "瑞幸咖啡",
                 ["咖啡", "联名"], "2026.09.12", "中号 · 250×310mm", "深圳市罗湖区",
                 "Hello Kitty 骑着小摩托，蝴蝶结是标志性的粉。袋底压了一排 HAPPY LUCKIN。"),
            make("luckin-summer", "SUMMER 夏日手提袋", "瑞幸咖啡",
                 ["咖啡", "夏日"], "2026.09.10", "中号 · 250×310mm", "广州市越秀区",
                 "深蓝底上撒满沙滩球、墨镜、棕榈树，SUMMER 用了两个颜色分色印。"),
            make("luckin-hand", "LUCK IN HAND 手提袋", "瑞幸咖啡",
                 ["咖啡", "联名"], "2026.09.09", "中号 · 250×310mm", "深圳市南山区",
                 "和 MINISO、Yoyo 三方联名。红斗篷小人在蓝底上举着手，配色很干净。"),
            make("luckin-grid", "九宫格拼贴手提袋", "瑞幸咖啡",
                 ["咖啡", "拼贴"], "2026.09.07", "窄版 · 220×300mm", "深圳市宝安区",
                 "被划成八格漫画，每格一个场景。窄长比例让格子排得很整齐。"),

            // ── Peet's Coffee ──
            make("peets-flower", "手工之花手提袋", "Peet's Coffee",
                 ["咖啡", "艺术"], "2026.09.08", "中号 · 250×320mm", "上海市静安区",
                 "橙金色大理石纹拧成一朵花，THE FLOWER OF Handcraft 压在中间。纸面有点粗粝的手感。"),
            make("peets-autumn", "秋日私语手提袋", "Peet's Coffee",
                 ["咖啡", "植物"], "2026.09.06", "中号 · 250×320mm", "上海市徐汇区",
                 "奶油底上两朵大花，橙黄渐变像水彩刚洇开。Whispers OF AUTUMN。"),
            make("peets-kraft", "经典牛皮纸手提袋", "Peet's Coffee",
                 ["咖啡"], "2026.09.05", "中号 · 250×310mm", "北京市朝阳区",
                 "最经典的一只，只印了 Peet's 大 logo。牛皮纸的褶痕留得很好看。"),
            make("peets-slim", "窄版牛皮纸手提袋", "Peet's Coffee",
                 ["咖啡", "窄版"], "2026.09.03", "窄版 · 170×300mm", "北京市海淀区",
                 "尺寸偏窄，Peet's 是竖排的。适合装单杯，拎着不占手。"),

            // ── 城市纸袋 ──
            make("more-crocs", "CROCS 联名手提袋（复刻）", "城市纸袋",
                 ["联名", "复刻"], "2026.09.02", "中号 · 250×310mm", "深圳市南山区",
                 "同款 CROCS 联名，这张是浅色版本。两只放一起看，底色差别挺明显。"),
            make("more-allin", "ALL IN 拥抱手提袋（复刻）", "城市纸袋",
                 ["插画", "复刻"], "2026.08.31", "中号 · 250×310mm", "广州市天河区",
                 "和白底那张构图一样，这张裁切比例更方一些。"),
            make("more-summer", "SUMMER 夏日手提袋（复刻）", "城市纸袋",
                 ["夏日", "复刻"], "2026.08.26", "中号 · 250×310mm", "上海市黄浦区",
                 "深蓝底那款的重印版，图案元素和配色完全一致。"),
        ]

        // 编号与组内顺序：与正式迁移（`BagItemMigrationPlan.migrateV3toV4`）同一口径，
        // 让预览里看到的编号/排列和真机升完库完全一样：
        // · serialNumber 按 createdAt 倒序发放（新的在前 → NO.001~016，与 H5 items[] 对齐）
        // · manualOrder 按同一条倒序、每个展示架各自计数（组内顺序即迁移前的样子）
        var serial = 1
        var perShelf: [String: Int] = [:]
        for bag in bags.sorted(by: { $0.createdAt > $1.createdAt }) {
            bag.serialNumber = serial
            serial += 1
            let key = bag.displayShelf
            perShelf[key, default: 0] += 1
            bag.manualOrder = perShelf[key] ?? 1
        }
        return bags
    }

    /// 解析 `2026.09.15` 并构造 BagItem
    private static func make(_ file: String, _ name: String, _ shelf: String,
                            _ tags: [String], _ date: String, _ size: String,
                            _ location: String,
                            _ note: String) -> BagItem {
        BagItem(imageFileName: file,
                name: name,
                category: shelf,
                tags: tags,
                size: size,
                location: location,
                note: note,
                createdAt: parse(date))
    }

    /// H5 的日期字面量是 `2026.09.15`，这里转成 Date
    static func parse(_ value: String) -> Date {
        let parts = value.split(whereSeparator: { !$0.isNumber }).map(String.init)
        guard parts.count >= 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return .now
        }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c) ?? .now
    }
}
