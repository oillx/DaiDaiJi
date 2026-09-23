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
//  这个文件显式声明 V1 → V2 的迁移，让老库能平滑升上来：
//  · `material` / `size`：新增文本，默认空串
//  · `tags`：新增字符串数组，默认空数组
//
//  ⚠️ 以后任何对 `BagItem` 的字段增删，都要：
//     ① 新建一个 `SchemaV3`（把 V2 原样抄过去再改）
//     ② 在 `BagItemMigrationPlan.stages` 里追加一个 `MigrationStage`
//     ③ 把 `BagItem` 的 typealias 指到新的版本
//     **不要**直接改 V1/V2 的字段定义 —— 那会让已发布的 schema 与旧库对不上。
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

// MARK: - 类型别名：全 App 用的 `BagItem` 始终指向「当前版本」

/// 全工程只认这一个名字。切换版本时只改这里。
typealias BagItem = SchemaV2.BagItem

// MARK: - 迁移计划

/// V1 → V2 的迁移。
///
/// 用 `custom` 而不是 `lightweight`，因为要显式给 `tags` 一个默认值 ——
/// `[String]` 是非可选 transformable，光靠 lightweight 推断可能拿不到
/// 合理的初值（部分系统版本上会迁移失败）。
enum BagItemMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
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
}
