import Foundation
import SwiftData

/// 纸袋数据模型（SwiftData 持久化）
/// 图片本身存文件系统，数据库只存文件名，避免把大图塞进数据库拖慢查询。
///
/// 字段与 H5 原型 `app.js` 顶部 `items[]` 对齐：
/// `id / name / shelf / tags / date / size / material / note`。
/// 其中 `shelf`（展示架 / 品牌·店铺）→ `category`，`date` → `createdAt`。
///
/// ⚠️ 模型的**定义**在 `Models/BagItemSchema.swift`（版本化 `SchemaV2`），
///    本文件只放**展示 / 搜索 / 时间口径**等派生逻辑。
///    `BagItem` 这个名字由 `BagItemSchema.swift` 的 typealias 指向当前版本。

// MARK: - 便捷展示属性
extension BagItem {
    var displayName: String { name.isEmpty ? "未命名" : name }

    /// 品牌 / 店铺的展示兜底
    var displayShelf: String { category.isEmpty ? "未分类" : category }

    /// 材质展示兜底（H5 侧空值渲染成「—」）
    var displayMaterial: String { material.isEmpty ? "—" : material }

    /// 用于搜索匹配：名称 + 分类 + 标签 + 材质 + 详情
    func matches(_ keyword: String) -> Bool {
        let k = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return true }
        return name.lowercased().contains(k)
            || category.lowercased().contains(k)
            || material.lowercased().contains(k)
            || note.lowercased().contains(k)
            || tags.contains { $0.lowercased().contains(k) }
    }
}

// MARK: - 编号（三处必须一致）
extension BagItem {
    /// 编号文案：在给定全集中的序号（从 0 起），补零 3 位。
    /// H5 里 `NO.xxx` 出现在三处——背面眉标、正面空状态、详情——全部走同一条规则。
    /// ⚠️ 编号是「在数据集里的位置」，不是收藏时间；删掉中间某一只后，后面所有编号都会前移。
    static func numberText(index: Int) -> String {
        "NO." + String(format: "%03d", index + 1)
    }

    /// 空状态编号（H5：`NO.000`）
    static let emptyNumberText = "NO.000"
}

// MARK: - 日期格式
enum DateFormat {
    /// 2026.09.15 → 2026/09/15（月日补零两位）
    /// 用于正面文字信息里的收藏日期。
    static func slash(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 2026.09.15 → 2026-09-15（连字符）
    /// 用于背面「收藏日期」字段。
    static func dash(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 09.15 → 用于挂袋区下方的「品牌 · 09.15」
    static func monthDayDot(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - 相对天数
enum RelativeDay {
    /// 0 → 今天；1 → 昨天；其余 → N 天前
    /// 用于背面「入库时长」字段。
    static func text(_ date: Date, base: Date = .now) -> String {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: date)
        let d1 = cal.startOfDay(for: base)
        let days = cal.dateComponents([.day], from: d0, to: d1).day ?? 0

        switch days {
        case ..<0: return "今天"
        case 0:    return "今天"
        case 1:    return "昨天"
        default:   return "\(days) 天前"
        }
    }
}

// MARK: - 时间口径
enum Feed {
    /// 「最近收集」窗口：15 天。
    /// **三处共用同一口径**：①最近收集区 ②卡片「最新」角标 ③头部统计的「N 件最近」。
    static let recentWindowDays = 15

    /// 货架区最多展示几张（H5 `recentItems(limit = 6)`）
    static let rackLimit = 6

    /// 距基准日的天数
    static func daysAgo(_ date: Date, base: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: base)).day ?? 9999
    }

    /// 15 天窗口内
    static func isRecent(_ item: BagItem, base: Date) -> Bool {
        daysAgo(item.createdAt, base: base) <= recentWindowDays
    }

    /// 最近 15 天内的藏品，由新到旧，最多 `limit` 张
    static func recent(_ items: [BagItem], base: Date, limit: Int = rackLimit) -> [BagItem] {
        items
            .filter { isRecent($0, base: base) }
            .sorted { daysAgo($0.createdAt, base: base) < daysAgo($1.createdAt, base: base) }
            .prefix(limit)
            .map { $0 }
    }

    /// 15 天内的总件数（不加 limit，供统计 chip 使用）
    static func recentCount(_ items: [BagItem], base: Date) -> Int {
        items.filter { isRecent($0, base: base) }.count
    }

    /// 全部标签去重后的个数
    static func tagCount(_ items: [BagItem]) -> Int {
        Set(items.flatMap(\.tags)).count
    }

    /// 演示数据取「数据集里最新的那一天」当今天。
    ///
    /// 原型数据写死在 2026 年 9 月，若拿真实 `Date.now` 去比，
    /// 所有藏品都会变成「几百天前」，整个「最近 15 天」就失效了。
    /// 真实用户数据（相机/相册录入）请用 `FeedBase.real`。
    static func demoBase(_ items: [BagItem]) -> Date {
        items.map(\.createdAt).max() ?? .now
    }
}

/// 「今天」的基准。
enum FeedBase {
    /// 演示 / 预览数据：取数据集里最新的那一天当「今天」（照抄 H5 `latestItemDate()`）
    case demo([BagItem])
    /// 真实用户数据：用当前时间
    case real
    /// 显式指定
    case fixed(Date)

    var date: Date {
        switch self {
        case .demo(let items): return Feed.demoBase(items)
        case .real:            return .now
        case .fixed(let date): return date
        }
    }
}
