import Foundation
import SwiftData

/// 纸袋数据模型（SwiftData 持久化）
/// 图片本身存文件系统，数据库只存文件名，避免把大图塞进数据库拖慢查询。
///
/// 字段与 H5 原型 `app.js` 顶部 `items[]` 对齐：
/// `id / name / shelf / tags / date / size / note`。
/// 其中 `shelf`（展示架 / 品牌·店铺）→ `category`，`date` → `createdAt`。
///
/// 📌 H5 里还有个 `material`（材质）字段，**已按需求整体退役** ——
///    界面上的「材质」文案全部去掉，持久化列也随 `SchemaV5` 删除，见 `BagItemSchema.swift`。
///
/// ⚠️ 模型的**定义**在 `Models/BagItemSchema.swift`（版本化 `SchemaV2`），
///    本文件只放**展示 / 搜索 / 时间口径**等派生逻辑。
///    `BagItem` 这个名字由 `BagItemSchema.swift` 的 typealias 指向当前版本。

// MARK: - 便捷展示属性
extension BagItem {
    var displayName: String { name.isEmpty ? "未命名" : name }

    /// 品牌 / 店铺的展示兜底
    var displayShelf: String { category.isEmpty ? "未分类" : category }

    /// 上传地点的展示兜底。
    ///
    /// ⚠️ 两处的空值口径**不一样**，别合并成一个：
    ///  · 首页背面 / 详情只读态：照 H5 `heroFactsHTML`，值为空时**整行不出现**；
    ///  · 详情卡编辑态的只读条：照 H5 `enterDetailEdit`，空值渲染成「—」。
    ///    新上传的藏品没有地点，只读条必须留出这一格，否则三块布局会塌。
    var displayLocation: String { location.isEmpty ? "—" : location }

    /// 一条收藏「可被搜到的文本」—— H5 `searchableText(item)`。
    ///
    /// 只覆盖**名称 / 品牌（分类）/ 标签**三类，拼成一个串、一次小写化。
    /// ⚠️ 不含材质与备注：搜索框占位符写的就是「名称 / 品牌 / 标签」，
    ///    H5 也只认这三类（iOS 原来多匹配了材质与备注，已收回）。
    var searchableText: String {
        ([name, category] + tags).joined(separator: " ").lowercased()
    }

    /// H5 `matchQuery(haystack, keywords)` 的单个关键词版本。
    ///
    /// ⚠️ 多关键词是 **AND**：调用方要按空格拆开后逐个调用（见 `ShelfView.filteredBags`），
    ///    不是把整串当一个子串去匹配 —— 否则搜「瑞幸 联名」永远搜不到。
    func matches(_ keyword: String) -> Bool {
        let k = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return true }
        return searchableText.contains(k)
    }
}

// MARK: - 编号（三处必须一致）
extension BagItem {
    /// 编号文案：`NO.xxx`，补零 3 位。
    /// H5 里 `NO.xxx` 出现在三处——背面眉标、正面空状态、详情——全部走同一条规则。
    ///
    /// ⚠️ 口径已变更（不再是 H5 的「在数据集里的位置」）：
    ///    旧口径下删掉中间某一只，之后所有编号都会前移 —— 同一只袋子昨天叫 NO.007、
    ///    今天删了别人就变成 NO.006，印在卡面上很别扭。
    ///    现在编号在**上传时发放**（存在 `serialNumber`），删除与拖动排序都不再影响它。
    ///    代价：删号会留空（NO.003 可能空缺），这是编号固定的必然结果。
    var numberText: String {
        "NO." + String(format: "%03d", serialNumber)
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

    /// 「2026-09-15」→ `Date`（详情卡编辑态的「收藏日期」输入框用）。
    ///
    /// 口径照 H5 `normalizeDateText`：`/(\d{4})\D+(\d{1,2})\D+(\d{1,2})/`
    /// —— 年份必须 4 位，年月日之间可以是任意非数字字符，所以
    /// `2026/9/5`、`2026年9月5日` 都能解析出来（用户手打时容错更好）。
    ///
    /// ⚠️ 解析不出来一律返回 `nil`，**不要**回退成 `.now`：
    ///    调用方（保存）靠这个 nil 决定「保持原值」，回退成今天会把用户
    ///    随手敲错的一个字符变成「收藏日期被改成今天」这种静默数据损坏。
    static func parseDash(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { !$0.isNumber }).map(String.init)
        guard parts.count >= 3, parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)
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

    /// 货架区**一屏基准张数**（H5 `recentItems(limit = 6)`）。
    ///
    /// ⚠️ 它现在的含义是「**版式按几张算**」而不是「最多显示几张」：
    ///    卡片宽 / 重叠 / 舞台高都由它推出来 —— 张数超过它时**卡片不再继续变小**，
    ///    而是让这一排宽于容器、交给横向滚动（见 `rackMaxItems` 与 `RackStage`）。
    ///    ⚠️ 改这个数会同时改变卡宽：调小 ⇒ 卡片变大、能滚的更快到；调大 ⇒ 卡片变小。
    static let rackLimit = 6

    /// 货架区一次最多**取出**几张（超出一屏基准张数的部分靠横向滚动看）。
    ///
    /// 📌 按需求「超过 6 张卡片要能横向滚动」：取数上限从 6 放开到 **24**。
    ///    15 天窗口内一般远小于它，也就是说实际上「15 天内有多少就挂多少」；
    ///    真要完全不截断，把这个数调大即可（只影响一排多长，不影响卡宽）。
    static let rackMaxItems = 24

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
