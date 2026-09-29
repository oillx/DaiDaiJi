import SwiftUI

// ═══════════════════════════════════════════════════════════════
//  匹配下拉（品牌 / 标签共用一套）
//
//  H5 对应：`app.js` 的 `allKnownTags()` / `allKnownShelves()` /
//           `refreshTagSuggest()` / `refreshShelfSuggest()` / `highlightMatch()`
//
//  两侧行为必须一致，否则「已有 3 件」这类数字会对不上：
//   · 数据源是**现有藏品里去重统计**的结果，不是一张硬编码词表；
//   · 匹配用「包含」（大小写不敏感），按件数降序、同数按本地化顺序；
//   · 高亮只标命中的那一段子串，不是整个候选词。
// ═══════════════════════════════════════════════════════════════

/// 匹配下拉里的一个候选项（H5 `.ef-suggest__item`）
struct Suggestion: Identifiable, Hashable {
    /// 显示文本（品牌名 / 标签名）
    let text: String
    /// 已有多少件藏品用过它 —— 对应 H5 右侧那行「已有 3 件」
    let count: Int

    var id: String { text }
}

enum SuggestionMatcher {

    // MARK: - 数据源

    /// 全部藏品里出现过的品牌（去重 + 记件数）
    static func shelves(in bags: [BagItem]) -> [Suggestion] {
        pool(bags.map(\.category))
    }

    /// 全部藏品里出现过的标签（去重 + 记件数）
    static func tags(in bags: [BagItem]) -> [Suggestion] {
        pool(bags.flatMap(\.tags))
    }

    /// 去重统计 + 排序。空串直接丢掉 —— 未填品牌的藏品不该在候选里
    /// 冒出一个空条目（H5 `allKnownShelves` 同样是先 trim 再判空）。
    private static func pool(_ values: [String]) -> [Suggestion] {
        var counter: [String: Int] = [:]
        for value in values {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            counter[key, default: 0] += 1
        }
        return counter
            .map { Suggestion(text: $0.key, count: $0.value) }
            .sorted {
                // 件数多的在前；同数时按本地化顺序，保证每次弹出次序稳定
                // （否则字典遍历顺序会让面板里的行随机换位）
                $0.count != $1.count
                    ? $0.count > $1.count
                    : $0.text.localizedStandardCompare($1.text) == .orderedAscending
            }
    }

    // MARK: - 匹配

    /// 含关键字的候选项，最多 `limit` 条。
    ///
    /// - Parameter excluding: 需要排除的值（标签面板要排掉已经加过的那些）
    static func matches(_ keyword: String,
                        in pool: [Suggestion],
                        excluding excluded: Set<String> = [],
                        limit: Int) -> [Suggestion] {
        let key = normalize(keyword)
        guard !key.isEmpty else { return [] }
        return pool
            .filter { $0.text.lowercased().contains(key) && !excluded.contains($0.text) }
            .prefix(limit)
            .map { $0 }
    }

    /// 池子里是否已有与关键字**完全相同**的项（大小写不敏感）。
    ///
    /// 命中时不再给「＋ 新建」入口 —— 否则会造出「霸王茶姬」和
    /// 「霸王茶姬 」两条只差一个空格的品牌，首页陈列会多出一个空分组。
    static func hasExact(_ keyword: String, in pool: [Suggestion]) -> Bool {
        let key = normalize(keyword)
        guard !key.isEmpty else { return false }
        return pool.contains { normalize($0.text) == key }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - 搜索无结果时的「出路」（H5 `rankEmptyStateOptions`）

    /// 一条出路候选（品牌 / 标签各算一类）
    private struct ExitStat {
        /// 原始值就是排序优先级：品牌排在标签前面
        enum Kind: Int { case shelf = 0, tag = 1 }
        var kind: Kind
        var text: String
        /// 总出现次数
        var countAll = 0
        /// **只搜第一个关键词**时的命中件数 —— 见下面的排序说明
        var countBefore = 0
    }

    /// 搜索无结果时，给出「换成搜什么就一定搜得到」的候选词。
    ///
    /// 排序规则照抄 H5（越靠前越可能是用户要找的）：
    ///  1. `countBefore` —— 只搜**第一个**关键词时能命中多少件。这是「恢复能力」：
    ///     搜「咖啡 星巴克」搜不到时，「咖啡」本身有 10 件，点它立刻从空恢复到 10 件。
    ///  2. `countAll` —— 总出现次数，也就是「这个选项有多大众」。
    ///  3. `kind` —— 前三项打平时品牌优先于标签（品牌名更具体、指向更明确）。
    ///  4. 文本长度 —— 再打平就取短的，窄屏上更好点。
    ///
    /// - Note: H5 还排了 `countNow`（当前搜索结果里的频次）。这里不排：
    ///   本方法只在**结果为空**时被调用，`countNow` 恒为 0，排了也没有区分度。
    static func emptyStateOptions(keyword: String,
                                  in bags: [BagItem],
                                  limit: Int = 4) -> [String] {
        let keywords = keyword
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !keywords.isEmpty else { return [] }

        // key 用「类型:文本」—— 品牌与标签可能重名，不加类型会互相覆盖频次
        var stats: [String: ExitStat] = [:]

        func bump(_ kind: ExitStat.Kind, _ text: String, alone: Bool) {
            let key = "\(kind):\(text)"
            var stat = stats[key] ?? ExitStat(kind: kind, text: text)
            stat.countAll += 1
            if alone { stat.countBefore += 1 }
            stats[key] = stat
        }

        for bag in bags {
            // 「只搜第一个关键词」这一条能不能被找到 —— 与 H5 的
            // `matchQuery(searchableText(item), [keywords[0]])` 同义，
            // 只是判断交给 iOS 自己的 `matches`（它的命中范围还要宽一些：
            // 含材质与备注）。用同一个函数才能保证「点了标签一定有结果」。
            let alone = bag.matches(keywords[0])
            if !bag.category.isEmpty { bump(.shelf, bag.category, alone: alone) }
            for tag in bag.tags where !tag.isEmpty { bump(.tag, tag, alone: alone) }
        }

        return stats.values
            .sorted {
                if $0.countBefore != $1.countBefore { return $0.countBefore > $1.countBefore }
                if $0.countAll != $1.countAll { return $0.countAll > $1.countAll }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                if $0.text.count != $1.text.count { return $0.text.count < $1.text.count }
                // 全字段打平时按文本定序：字典遍历顺序是不确定的，
                // 不补这一条，两个候选会在每次重绘时随机换位。
                return $0.text.localizedStandardCompare($1.text) == .orderedAscending
            }
            .prefix(limit)
            .map(\.text)
    }

    // MARK: - 高亮

    /// 把 `text` 里命中 `keyword` 的那一段染成品牌红并加粗，其余原样。
    ///
    /// ⚠️ 与 H5 `highlightMatch` 逐条对齐：
    ///   · 大小写不敏感匹配，但**保留原文大小写**（打 `peets` 显示 `Peets`）；
    ///   · 没命中就整段原样返回，不要硬塞高亮；
    ///   · 只标第一处命中（H5 用的是 `indexOf`，不是全局替换）。
    ///
    /// 返回的是 `AttributedString`，只给命中段上色 —— 未命中的部分不带
    /// 任何颜色属性，仍然继承调用方设的字色。
    static func highlight(_ text: String, keyword: String) -> AttributedString {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              let range = text.range(of: key, options: [.caseInsensitive]) else {
            return AttributedString(text)
        }

        var result = AttributedString(String(text[text.startIndex..<range.lowerBound]))
        var hit = AttributedString(String(text[range]))
        hit.foregroundColor = HeroPalette.focus
        // 用「强调」而不是写死 font：面板的字号由调用方给，
        // 这里再写一遍字号就会和宿主行不一致（改字号要改两处）。
        hit.inlinePresentationIntent = .stronglyEmphasized
        result.append(hit)
        result.append(AttributedString(String(text[range.upperBound...])))
        return result
    }
}
