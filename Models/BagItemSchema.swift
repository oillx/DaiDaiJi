import Foundation
import SwiftData

// ═══════════════════════════════════════════════════════════════
//  BagItem 的版本化 Schema 与迁移计划
//
//  为什么需要这个文件：
//  `@Model` 的「轻量迁移」只对【新增可选属性】或【带默认值的属性】自动生效。
//  复刻 H5 时给 `BagItem` 新增了 `material` / `tags` / `size` 三个属性，其中
//  `tags: [String]` 在 Core Data 层是 **非可选、无默认值的 transformable**。
//  装过旧版本的设备升级后，旧库里的每一条记录都没有这三个字段，
//  SwiftData 会直接抛迁移错误 → **App 启动即崩**。
//
//  这个文件显式声明每一版的迁移，让老库能平滑升上来：
//  · V1 → V2：新增 `material` / `size`（文本，默认空串）、`tags`（数组，默认空）
//  · V2 → V3：新增 `location`
//  · V3 → V4：新增 `serialNumber` / `manualOrder`，并按旧口径补算真值
//  · V4 → V5：**删除 `material`**（该字段整体退役 —— 界面上那行文案已全部去掉，
//             数据列一并删掉；老库里已录入的材质文本会随之丢弃，这是有意为之）
//
//  ⚠️ 以后任何对 `BagItem` 的字段增删，都要：
//     ① 新建一个 `SchemaV6`（把 V5 原样抄过去再改）
//     ② 在 `BagItemMigrationPlan.stages` 里追加一个 `MigrationStage`
//     ③ 把 `BagItem` 的 typealias 指到新的版本
//     **不要**直接改已发布版本的字段定义 —— 那会让已发布的 schema 与旧库对不上。
// ═══════════════════════════════════════════════════════════════

// MARK: - V1：复刻前的原始模型

/// 第一版模型（复刻 H5 之前的样子）。
///
/// 只含最初的 5 个业务字段。**这个定义不要改** —— 它必须与已经发布出去的
/// 磁盘结构保持一致，否则迁移会找不到起点。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    // ⚠️ 必须写全 `SchemaV1.BagItem.self`，不要省成 `BagItem.self`。
    //
    // 本文件底部有 `typealias BagItem = SchemaV2.BagItem`，而这里又定义了
    // 同名的嵌套类。Swift 的内层作用域优先规则**当前**会正确解析到
    // `SchemaV1.BagItem`（已实测确认），但这是个隐式依赖 ——
    // 一旦有人把 typealias 挪到别的文件或调整声明顺序，就可能静默指向 V2，
    // 结果是「迁移的起点变成了终点」，轻则迁移不生效、重则 schema 冲突崩溃。
    // 写全限定名，让意图不依赖作用域规则。
    static var models: [any PersistentModel.Type] { [SchemaV1.BagItem.self] }

    @Model
    final class BagItem {
        var id: UUID
        var imageFileName: String
        var name: String
        var category: String
        var note: String
        var createdAt: Date

        init(imageFileName: String,
             name: String = "",
             category: String = "",
             note: String = "",
             createdAt: Date = .now) {
            self.id = UUID()
            self.imageFileName = imageFileName
            self.name = name
            self.category = category
            self.note = note
            self.createdAt = createdAt
        }
    }
}

// MARK: - V2：复刻 H5 后的模型（新增 material / tags / size）

/// 第二版模型：与 H5 原型 `items[]` 的字段一一对齐。
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    /// 与 V1 同理，写全限定名，不依赖作用域规则。
    static var models: [any PersistentModel.Type] { [SchemaV2.BagItem.self] }

    @Model
    final class BagItem {
        var id: UUID
        /// Documents/bags 下的文件名；演示数据为 Assets 里的素材名
        var imageFileName: String
        var name: String
        /// 展示架 / 品牌·店铺。H5 里叫 `shelf`。
        var category: String
        /// 材质。背面「材质」字段。
        var material: String
        /// 标签。背面标签区 + 搜索匹配。
        var tags: [String]
        /// 尺寸（如「中号 · 260×320mm」）。
        /// ⚠️ H5 背面的「尺寸」字段已按需求移除，这个字段只为数据完整性保留，背面不再展示。
        var size: String
        var note: String
        var createdAt: Date

        init(imageFileName: String,
             name: String = "",
             category: String = "",
             material: String = "",
             tags: [String] = [],
             size: String = "",
             note: String = "",
             createdAt: Date = .now) {
            self.id = UUID()
            self.imageFileName = imageFileName
            self.name = name
            self.category = category
            self.material = material
            self.tags = tags
            self.size = size
            self.note = note
            self.createdAt = createdAt
        }
    }
}

// MARK: - V3：新增 location（上传地点）

/// 第三版模型：补上 H5 一直有、iOS 侧缺失的 `location`。
///
/// 为什么要单独开一版而不是改 V2：
/// V2 已经发布过（用户机上的库是按 V2 建的），直接改它的字段定义会让
/// 磁盘结构与迁移起点对不上 —— 轻则迁移不生效，重则启动即崩。
///
/// 字段用途（对齐 H5 `item.location`）：
///  · 首页卡片背面「上传地点」一行
///  · 详情卡编辑态顶部只读条的中间那块
/// 新增上传流程目前拿不到地点，落库为空串 —— 与 H5 的
/// 「『添加收藏』流程产生的 item 没有 location」完全一致。
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }

    /// 与 V1/V2 同理，写全限定名，不依赖作用域规则。
    static var models: [any PersistentModel.Type] { [SchemaV3.BagItem.self] }

    @Model
    final class BagItem {
        var id: UUID
        /// Documents/bags 下的文件名；演示数据为 Assets 里的素材名
        var imageFileName: String
        var name: String
        /// 展示架 / 品牌·店铺。H5 里叫 `shelf`。
        var category: String
        /// 材质。背面「材质」字段。
        var material: String
        /// 标签。背面标签区 + 搜索匹配。
        var tags: [String]
        /// 尺寸（如「中号 · 260×320mm」）。
        /// ⚠️ H5 背面的「尺寸」字段已按需求移除，这个字段只为数据完整性保留，背面不再展示。
        var size: String
        /// 上传地点（如「深圳市南山区」）。
        ///
        /// ⚠️ 这里**故意带上字面量默认值 `= ""`**，与 V1/V2 的写法不同。
        ///    String 是非可选、无默认值的属性，老库升上来时那一列全是 NULL；
        ///    带着 NULL 去读 `bag.location` 会直接崩 —— 光靠 didMigrate 里
        ///    的空操作救不回来（读的那一刻就已经踩上去了）。
        ///    声明了默认值，Core Data 才会在加列时给存量行填上 ""。
        var location: String = ""
        var note: String
        var createdAt: Date

        init(imageFileName: String,
             name: String = "",
             category: String = "",
             material: String = "",
             tags: [String] = [],
             size: String = "",
             location: String = "",
             note: String = "",
             createdAt: Date = .now) {
            self.id = UUID()
            self.imageFileName = imageFileName
            self.name = name
            self.category = category
            self.material = material
            self.tags = tags
            self.size = size
            self.location = location
            self.note = note
            self.createdAt = createdAt
        }
    }
}

// MARK: - V4：新增 serialNumber（固定编号）+ manualOrder（展架内手工序）

/// 第四版模型：`NO.xxx` 编号改为**上传时发放、终身不变**，并支持展架内长按拖动排序。
///
/// 两个字段都是「存量数据必须被补算」的类型，所以这一版迁移**不能只靠默认值**：
///
/// · `serialNumber` —— 编号口径变更。
///   原来是「在数据集里的位置」（`allBags` 按 createdAt 倒序的第几个），
///   删掉中间某一只，后面所有编号会前移。现在建卡时发放一次、之后永不改。
///   存量的补算口径：**按 createdAt 倒序发号**，这样迁移前后屏幕上显示的编号
///   完全一致（最新的仍是 NO.001），用户不会看到编号突然跳。
///   ⚠️ 代价：删号会留空（如 NO.003 空缺），这是「固定编号」的必然结果。
///
/// · `manualOrder` —— 展架组内手工排序用的序号（小的在前）。
///   存量按「迁移前的组内顺序」补算（同一条 createdAt 倒序），
///   保证升完库视觉上一动没动，用户第一次看到的就是原来的排列。
///
/// 两个字段都带字面量默认值 `= 0`（V3 加 `location` 时立的规矩）：
/// String/Int 是非可选属性，老库升上来那一列全是 NULL，读一下就崩。
/// 声明默认值 Core Data 才会给存量行填 0，随后 `didMigrate` 再纠正成真值。
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(4, 0, 0) }

    /// 与 V1/V2/V3 同理，写全限定名，不依赖作用域规则。
    static var models: [any PersistentModel.Type] { [SchemaV4.BagItem.self] }

    @Model
    final class BagItem {
        var id: UUID
        /// Documents/bags 下的文件名；演示数据为 Assets 里的素材名
        var imageFileName: String
        var name: String
        /// 展示架 / 品牌·店铺。H5 里叫 `shelf`。
        var category: String
        /// 材质。背面「材质」字段。
        var material: String
        /// 标签。背面标签区 + 搜索匹配。
        var tags: [String]
        /// 尺寸（如「中号 · 260×320mm」）。
        /// ⚠️ H5 背面的「尺寸」字段已按需求移除，这个字段只为数据完整性保留，背面不再展示。
        var size: String
        /// 上传地点（如「深圳市南山区」）。
        var location: String = ""
        /// `NO.xxx` 的固定编号（1 起，上传时发放后终身不变）。
        /// 0 表示「还没发号」（迁移未跑到的兜底状态）。
        var serialNumber: Int = 0
        /// 展架内手工排序序号（**只在同一展示架内比较**，小的在前）。
        /// 仅影响「全部收藏 → 展架排列」的组内先后；首页主卡与「最近收集」仍按时间。
        var manualOrder: Int = 0
        var note: String
        var createdAt: Date

        init(imageFileName: String,
             name: String = "",
             category: String = "",
             material: String = "",
             tags: [String] = [],
             size: String = "",
             location: String = "",
             serialNumber: Int = 0,
             manualOrder: Int = 0,
             note: String = "",
             createdAt: Date = .now) {
            self.id = UUID()
            self.imageFileName = imageFileName
            self.name = name
            self.category = category
            self.material = material
            self.tags = tags
            self.size = size
            self.location = location
            self.serialNumber = serialNumber
            self.manualOrder = manualOrder
            self.note = note
            self.createdAt = createdAt
        }
    }
}

// MARK: - V5：材质字段退役

/// 第五版模型：在 V4 基础上去掉 `material`。
///
/// 为什么删：按需求「材质」整条文案退役 —— 详情卡、主卡背面、详情页、
/// 「更多 · 删除」页与新增表单里的入口都已去掉（演示数据每条都是同一句
/// 「白卡纸覆哑膜」，卡面上纯属噪音）。只留一个没人读的列没有意义，
/// 所以连列一起删，而不是留着占位。
///
/// ⚠️ 代价（有意）：老库里已录入的材质文本随列一起丢失。
///    V1…V4 的定义**原样保留**，它们是迁移的起点，一个字都不能改。
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(5, 0, 0) }

    /// 与 V1…V4 同理，写全限定名，不依赖作用域规则。
    static var models: [any PersistentModel.Type] { [SchemaV5.BagItem.self] }

    @Model
    final class BagItem {
        var id: UUID
        /// Documents/bags 下的文件名；演示数据为 Assets 里的素材名
        var imageFileName: String
        var name: String
        /// 展示架 / 品牌·店铺。H5 里叫 `shelf`。
        var category: String
        /// 标签。背面标签区 + 搜索匹配。
        var tags: [String]
        /// 尺寸（如「中号 · 260×320mm」）。
        /// ⚠️ H5 背面的「尺寸」字段已按需求移除，这个字段只为数据完整性保留，背面不再展示。
        var size: String
        /// 上传地点（如「深圳市南山区」）。
        var location: String = ""
        /// `NO.xxx` 的固定编号（1 起，上传时发放后终身不变）。
        /// 0 表示「还没发号」（迁移未跑到的兜底状态）。
        var serialNumber: Int = 0
        /// 展架内手工排序序号（**只在同一展示架内比较**，小的在前）。
        var manualOrder: Int = 0
        var note: String
        var createdAt: Date

        init(imageFileName: String,
             name: String = "",
             category: String = "",
             tags: [String] = [],
             size: String = "",
             location: String = "",
             serialNumber: Int = 0,
             manualOrder: Int = 0,
             note: String = "",
             createdAt: Date = .now) {
            self.id = UUID()
            self.imageFileName = imageFileName
            self.name = name
            self.category = category
            self.tags = tags
            self.size = size
            self.location = location
            self.serialNumber = serialNumber
            self.manualOrder = manualOrder
            self.note = note
            self.createdAt = createdAt
        }
    }
}

// MARK: - 类型别名：全 App 用的 `BagItem` 始终指向「当前版本」

/// 全工程只认这一个名字。切换版本时只改这里。
typealias BagItem = SchemaV5.BagItem

// MARK: - 迁移计划

/// 版本迁移链：V1 → V2 → V3 → V4 → V5。
///
/// 两段都用 `custom` 而不是 `lightweight`：
/// · V1→V2 是因为要显式给 `tags` 一个默认值 —— `[String]` 是非可选
///   transformable，光靠 lightweight 推断可能拿不到合理的初值。
/// · V2→V3 的字段（`location: String = ""`）本身带字面量默认值，
///   lightweight 就够；这里仍然写 `custom`，是为了留一个「升完库之后
///   做一次数据归一化」的挂点，与上一段的写法保持一致。
enum BagItemMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        // 迁移前没什么要准备的（不需要从 V1 读数据来做换算）
        willMigrate: nil,
        didMigrate: { context in
            // 走到这里时，库结构已经是 V2 了，老记录的新字段是空值。
            //
            // 这里**不写** `bag.material = ""` 这种「赋原值」的空操作 ——
            // 那是自欺欺人：`tags: [String]` 由 Core Data 以 transformable
            // 存储，非可选但允许 nil 落库，赋值成 `[]` 才是真正有意义的归一化。
            //
            // 真正要防的边界：老记录反序列化出来可能拿到 nil，
            // 而界面是按非可选读的（`bag.tags.contains`）。统一刷成空集合，
            // 保证后面所有读取路径都不用再判空。
            let bags = try context.fetch(FetchDescriptor<SchemaV2.BagItem>())
            for bag in bags {
                if bag.tags.isEmpty { bag.tags = [] }
            }
            try context.save()
        }
    )

    /// V2 → V3：新增 `location`。
    ///
    /// 加列这一步由 Core Data 自己完成（`location` 声明了字面量默认值 `""`，
    /// 存量行会被填成空串）。`didMigrate` 里的循环是一道兜底：
    /// 万一某个系统版本忽略了默认值、把列留成 NULL，这里把它刷成空串，
    /// 后面所有读取路径（`bag.location.isEmpty` / `displayLocation`）
    /// 就都不用再判空。
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            let bags = try context.fetch(FetchDescriptor<SchemaV3.BagItem>())
            for bag in bags where bag.location.isEmpty {
                bag.location = ""
            }
            try context.save()
        }
    )

    /// V3 → V4：补算 `serialNumber`（固定编号）与 `manualOrder`（展架组内序）。
    ///
    /// 加列本身由 Core Data 完成（两个字段都带字面量默认值 `0`），这里负责把
    /// 它们纠正成「与迁移前屏幕上一模一样」的真值 —— 升完库用户不该看出任何变化：
    ///
    /// · 编号：按 createdAt **倒序**发号 → 最新的仍是 `NO.001`（旧口径就是这个）
    /// · 组内序：同一条倒序遍历、按展示架各自计数 → 组内先后也与旧口径一致
    ///
    /// ⚠️ 两件事必须在**同一次排序遍历**里算完。两次 fetch 有概率拿到不同的
    ///    顺序（同一毫秒创建的两条记录次序不定），编号与排列就会错位。
    ///
    /// ⚠️ 这里对**所有**记录重新赋值（不判「是否已发过号」）：V3 里根本没有
    ///    这两个字段，走到这里时它们必然是 0。全量重算让这段迁移幂等，
    ///    中途崩了重跑也不会发出重复编号。
    static let migrateV3toV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self,
        willMigrate: nil,
        didMigrate: { context in
            let descriptor = FetchDescriptor<SchemaV4.BagItem>(
                sortBy: [SortDescriptor(\SchemaV4.BagItem.createdAt, order: .reverse)]
            )
            let bags = try context.fetch(descriptor)

            var serial = 1
            var perShelf: [String: Int] = [:]

            for bag in bags {
                bag.serialNumber = serial
                serial += 1

                // 分组键必须与界面口径一致（`BagItem.displayShelf`）
                let key = bag.category.isEmpty ? "未分类" : bag.category
                perShelf[key, default: 0] += 1
                bag.manualOrder = perShelf[key] ?? 1
            }
            try context.save()
        }
    )
    /// V4 → V5：**删除 `material` 字段**（见 `SchemaV5`）。
    ///
    /// 删列是 Core Data 的轻量迁移能直接处理的形状变化 —— 不需要读旧值做换算，
    /// 也没有新列要填初值，所以这一段用 `lightweight`；前三段写 `custom`
    /// 是因为它们各自都要在 `didMigrate` 里做归一化 / 补算。
    ///
    /// ⚠️ 老库里已录入的材质文本会随列一起丢掉（这正是本次的目的）。
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self
    )

}
