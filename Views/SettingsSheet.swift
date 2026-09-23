import SwiftUI

// ═══════════════════════════════════════════════════════════════
//  设置面板
//
//  H5 对应：`袋袋集原型/index.html` 的 `<aside id="settingsSheet">`
//           与 `styles.css` 的 `.settings-sheet` / `.settings-card` / `.ios-switch`
//
//  📌 入口在「最近收集」标题栏右侧的齿轮。首页右上角原本也是这个入口，
//     后来那个位置改成了「最近收藏 N」胶囊（见 ShelfView.ShowcaseHeader）。
// ═══════════════════════════════════════════════════════════════

struct SettingsSheet: View {
    /// 收藏总数，对应 H5 的 `#settingsCount`
    let totalCount: Int

    @Environment(\.dismiss) private var dismiss
    /// 摇一摇互动开关，对应 H5 的 `#motionToggle`。
    /// ⚠️ 键名抽在 `ShakeDetector` 里，挂袋区读的是同一个 —— 两边都别写字面量。
    @AppStorage(ShakeDetector.storageKey) private var motionEnabled = false

    /// 本机能不能摇一摇（iPad 模拟器 / 无陀螺仪设备上为 false）。
    /// 不支持时把开关置灰并给出说明 —— 否则就是一个点了没反应的开关。
    private var motionSupported: Bool { ShakeDetector.isSupported }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("SETTINGS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                Text("我的陈列柜")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.bottom, 18)

                VStack(spacing: 0) {
                    row("收藏统计") {
                        HStack(spacing: 3) {
                            Text("\(totalCount)")
                                .font(.system(size: 14, weight: .bold))
                            Text("件")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.leading, 16)
                    row("本地存储") {
                        Text("已启用")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Divider().padding(.leading, 16)
                    row("iCloud 同步") {
                        Text("尚未配置")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 16)
                    row("摇一摇互动") {
                        Toggle("", isOn: $motionEnabled)
                            .labelsHidden()
                            .tint(Color(red: 20/255, green: 20/255, blue: 20/255))
                            .disabled(!motionSupported)
                    }
                }
                .background(.white.opacity(0.62), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 1)
                }

                // H5 `#motionHint`。文案与原型逐字对应，包括「不支持」那一档。
                Text(motionHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)

                Text("照片处理和收藏数据默认保存在此设备。不会上传或持久保存图片。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 10)
                    .padding(.horizontal, 2)

                Button { dismiss() } label: {
                    Text("完成")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 20/255, green: 20/255, blue: 20/255),
                                    in: .rect(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Color(red: 242/255, green: 243/255, blue: 247/255))
    }

    /// 摇一摇的说明文案。三档，与 H5 `#motionHint` 的三种状态逐字对应
    /// （`enableMotion()` / `disableMotion()` / `typeof DeviceMotionEvent === 'undefined'`）。
    private var motionHint: String {
        guard motionSupported else {
            return "当前设备不支持摇一摇互动。"
        }
        return motionEnabled
            ? "已开启。轻轻晃动手机会让「最近收集」的挂袋跟着摆动。仅在本机读取设备运动数据，不会上传。"
            : "开启后，轻轻晃动手机会让「最近收集」的挂袋跟着摆动。仅在本机读取设备运动数据，不会上传。"
    }

    /// 一行设置项：左标题右值，与 H5 `.settings-card` 同构
    private func row<Content: View>(_ title: String,
                                    @ViewBuilder value: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

#Preview {
    SettingsSheet(totalCount: 16)
}
