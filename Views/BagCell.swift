import SwiftUI

/// 网格卡片：缩略图 + 名称 + 展示架 + 日期
///
/// ⚠️ 缩略图高度显式写死，不要复用主卡的 248 —— 主卡的尺寸修饰符
///    一旦被复用，会把这里的小图撑破（H5 踩过 `.bag-photo { max-height: 85% }`
///    把主卡袋子压成 210.8px 的坑，iOS 侧的对应风险是反向的撑破）。
struct BagCell: View {
    let bag: BagItem
    /// 时间基准（用于「最近」角标）
    var base: Date = .now

    private var isRecent: Bool { Feed.isRecent(bag, base: base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // 走缩略图缓存（后台解码 + 内存缓存），网格滚动不掉帧；
                // 同时它兼容「磁盘真实图」与「Assets 演示图」两种来源。
                //
                // ⚠️ 顺序是「先给图片一个装得下的盒子，再让盒子定高」：
                //    `ThumbnailImage` 自己没有固有尺寸，若直接 `.frame(height:)`
                //    会把它的外框压扁、等于给图片设了固定高宽比，袋子会被拉长。
                //    先 `.frame(maxWidth:height:)` 定位可用区、靠 `.fit` 等比缩，
                //    最后才用外层 `.frame(height:)` 锁定卡片高度。
                ThumbnailImage(fileName: bag.imageFileName, size: 300,
                               contentMode: .fit, interpolation: .high)
                    .frame(maxWidth: .infinity, maxHeight: 110 - 8)   // 扣掉上下 4pt padding
                    .padding(4)
                    .frame(height: 110)
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.7), .white.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    }

                // 「最新」角标（15 天窗口，与「最近收集」同一口径）
                if isRecent {
                    Text("最新")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color(red: 150/255, green: 112/255, blue: 58/255))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.72), in: .capsule)
                        .padding(6)
                }
            }

            Text(bag.displayName)
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Text(bag.displayShelf)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(DateFormat.monthDayDot(bag.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }
}

// MARK: - 预览
#Preview {
    let bag = PreviewData.sampleBag()
    return BagCell(bag: bag, base: bag.createdAt)
        .frame(width: 140)
        .padding()
}
