import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════
//  中文字体口径：宋体（衬线标题）
//
//  ⚠️ 这里踩的是**两个会静默生效**的坑，叠在一起才出现「稿面写着衬线、真机是黑体」：
//
//   1. `design: .serif` 换掉的只是**拉丁字形**（New York）。中文字符在它里面
//      没有对应字面，会回落到苹方（黑体）—— 不报错、不警告。
//
//   2. **iOS 不预装宋体**。实测当前 iOS 26 运行时的字体库里只有 86 个族，没有 Songti：
//      `UIFont.fontNames(forFamilyName: "Songti SC")` 返回空数组，
//      而 `/System/Library/Fonts/Supplemental/Songti.ttc` 只是躺在系统里、**没有注册**
//      （宋体在 iOS 上属于「用户自行下载」的字体，切系统语言也不会激活）。
//      名字解析不到时 UIKit 同样是静默回落。
//
//  所以宋体是**随包自带**的：`Fonts/SourceHanSerifCN-*.otf`（思源宋体 CN，
//  SIL OFL 许可），在 Info.plist 的 `UIAppFonts` 里注册。
//  取字仍然写成链，末两档是兜底（万一字体没打进包，也不至于变成黑体）：
//
//      Source Han Serif CN → 系统 Songti SC → Hiragino Mincho ProN → 系统字体
//
//  目前只随包了 Bold(700) 与 Heavy(900) 两档 —— 恰好覆盖现有标题所需的字重。
//  要加字重（Regular 400 / SemiBold 600）：把 otf 放进 `Fonts/`、
//  补进 `UIAppFonts`，再加一个 `SerifWeight` case 即可。
//
//  ⚠️ 随包的是**子集化**过的版本，别直接换成下载的原始 otf。
//     原始思源宋体每档 11.3~11.8MB，两档会把包体推高 23MB；
//     子集后每档约 2.5MB（30995 → 7602 个字形），两档合计约 5MB。
//
//  子集字符集 = GB2312 的全部汉字与符号 + 项目源码里出现的所有非 ASCII 用字
//  （源码用字 100% 覆盖，界面自带文案不会缺字；字体名、族名与原始文件一致）。
//  **超出子集**的字（生僻字、扩展区汉字）由 CoreText 逐字回落到苹方 ——
//  这是刻意取舍：省 17MB 包体，代价是极少数用户自填的生僻字可能不是宋体。
//
//  重做子集（放宽字符集 / 加字重时）：
//      pip install fonttools
//      pyftsubset <原始>.otf --text-file=<字符集文件> --output-file=Fonts/<同名>.otf \
//        --layout-features='kern,ccmp,locl,mark,mkmk,liga' --drop-tables+=DSIG \
//        --name-IDs='*' --name-languages='*' --recalc-bounds
//  （末尾别加 `--no-hinting`：还能再省 0.4MB/档，但小字号笔画会发虚。）
// ═══════════════════════════════════════════════════════════════

enum AppFont {

    /// 衬线标题的字重档位。
    enum SerifWeight {
        /// 700
        case bold
        /// 900 —— H5 里 `font-weight: 900` 那几处大标题
        case heavy

        /// 随包的思源宋体（PostScript 名）
        var bundled: String {
            switch self {
            case .bold:  return "SourceHanSerifCN-Bold"
            case .heavy: return "SourceHanSerifCN-Heavy"
            }
        }

        /// 用户设备上装过宋体时的系统宋体（PostScript 名，从 `Songti.ttc` 的 name 表读出）
        var systemSongti: String {
            switch self {
            case .bold:  return "STSongti-SC-Bold"
            case .heavy: return "STSongti-SC-Black"
            }
        }

        /// 再兜一档：系统自带的明朝体（中日韩衬线，只有 W3 细 / W6 粗）
        var mincho: String { "HiraMinProN-W6" }

        /// 最后兜到系统字体时的字重
        var systemWeight: Font.Weight {
            switch self {
            case .bold:  return .bold
            case .heavy: return .bold
            }
        }
    }

    /// 中文衬线标题字体。取字顺序见文件头。
    ///
    /// - Parameters:
    ///   - size: 字号（pt）
    ///   - weight: 字重档位，默认 `.bold`
    static func songti(_ size: CGFloat, _ weight: SerifWeight = .bold) -> Font {
        for name in [weight.bundled, weight.systemSongti, weight.mincho] where hasFont(name) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight.systemWeight, design: .serif)
    }

    /// `UIFont(name:)` 每次渲染都要查一遍字体库，结果缓存住。
    ///
    /// 字体表在 App 生命周期内不会变，缓存是安全的；标题在滚动中会反复求值。
    private static var probeCache: [String: Bool] = [:]

    private static func hasFont(_ name: String) -> Bool {
        if let cached = probeCache[name] { return cached }
        let exists = UIFont(name: name, size: 12) != nil
        probeCache[name] = exists
        return exists
    }
}
