import Foundation

/// 分类模糊匹配：输入时从已有分类里找相似项，供用户替换或继续输入
/// V1 用轻量编辑距离，无需第三方库。
enum CategoryMatcher {

    /// 从 existing 里找出与 input 模糊匹配的分类（按相似度降序）
    static func match(_ input: String, in existing: [String], limit: Int = 3) -> [String] {
        let key = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return [] }
        return existing
            .map { ($0, score(key, $0.lowercased())) }
            .filter { $0.1 >= 1 }                    // 至少有点相似
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// 相似度：包含关系优先，其次按编辑距离
    private static func score(_ a: String, _ b: String) -> Int {
        if a == b { return 100 }
        if b.contains(a) || a.contains(b) { return 50 + min(a.count, b.count) }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        let similarity = Double(maxLen - dist) / Double(maxLen)
        return similarity > 0.4 ? Int(similarity * 40) : 0
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i - 1] == b[j - 1] ? prev : min(prev, dp[j], dp[j - 1]) + 1
                prev = temp
            }
        }
        return dp[b.count]
    }
}
