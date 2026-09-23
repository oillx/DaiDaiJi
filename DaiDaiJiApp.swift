import SwiftUI
import SwiftData

@main
struct DaiDaiJiApp: App {
    var body: some Scene {
        WindowGroup {
            ShelfView()
        }
        // 挂上 SwiftData 容器，整个 App 共享 modelContext。
        //
        // ⚠️ 用带 `migrationPlan` 的显式容器，不要退回 `.modelContainer(for:)`。
        //    复刻 H5 时给 `BagItem` 加了 `material` / `tags` / `size`，
        //    其中 `tags: [String]` 是非可选、无默认值的 transformable ——
        //    老库升上来不迁移会直接抛错、App 启动即崩。
        //    迁移细节见 `Models/BagItemSchema.swift`。
        .modelContainer(Self.container)
    }

    /// 全局容器。迁移失败时给出可诊断的崩溃信息，而不是让 `try!` 抛原始错误。
    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BagItemMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // 走到这里说明迁移也救不回来（例如磁盘上的库结构已被手工改坏）。
            // 与其让用户看到白屏，不如崩在明处、带上真实原因。
            fatalError("""
                无法打开纸袋数据库。

                原因：\(error)

                如果这是开发机且数据可丢，删掉 App 重装即可。
                如果是正式用户遇到，请保留现场并上报 —— 这属于迁移计划没覆盖到的结构变化。
                """)
        }
    }()
}
