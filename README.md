# 袋袋集 DaiDaiJi — iOS App（v1.0 完整版）

一款轻量级**纸袋收藏管理工具**。核心链路：

> 拍照/上传 → **自动抠图 + 透视矫正 + 色彩增强** → **OCR 自动识别名称** → 货架式浏览 → 搜索定位 → 详情查看/删除

**技术栈**：SwiftUI + SwiftData + Vision + Core Image + AVFoundation
**特点**：无登录、纯本地存储、零第三方依赖、图像处理与 OCR 全部端侧完成（不联网）
**要求**：iOS 17.0+（Vision 前景分割 `VNGenerateForegroundInstanceMaskRequest` 需要 17）

---

## 一、直接打开工程

本目录已是**可打开的完整 Xcode 工程**（含 `DaiDaiJi.xcodeproj` + 共享 Scheme）。

```bash
open DaiDaiJi.xcodeproj      # 在 macOS 上
```

然后：
1. 选中 Scheme `DaiDaiJi`，选一台 **iOS 17+ 真机**（拍照/抠图建议真机，模拟器无相机）
2. Signing & Capabilities → 选择你的 Team（自动签名）
3. ⌘R 运行

> 若 Xcode 提示需要，右键 `DaiDaiJi.xcodeproj` → 或用 `xcodegen generate`（见 `project.yml`）重新生成工程。

### 权限
工程已通过 `INFOPLIST_KEY_*` 自动写入相机/相册权限描述（`GENERATE_INFOPLIST_FILE = YES`），无需手动配置 Info.plist。

---

## 二、工程结构

```
DaiDaiJi/
├── DaiDaiJiApp.swift              # 入口，挂带 migrationPlan 的 SwiftData 容器
├── Models/
│   ├── BagItemSchema.swift        # ⭐ 版本化 Schema（V1/V2）+ 迁移计划
│   └── BagItem.swift              # 展示 / 搜索 / 日期 / 15 天窗口等派生逻辑
├── Support/
│   ├── BagImagePipeline.swift     # ⭐ 核心图像流水线：矫正→增强→OCR→抠图
│   ├── CameraController.swift     # AVFoundation 相机会话（拍照/闪光灯/切换镜头）
│   ├── CategoryMatcher.swift      # 分类模糊匹配（编辑距离）
│   ├── ImageStore.swift           # 图片文件存储（PNG，保留透明通道）
│   ├── PreviewData.swift          # 预览用内存容器 + H5 的 16 只示例袋子
│   └── ThumbnailCache.swift       # 缩略图内存缓存 + 等比缩放
├── Views/
│   ├── ShelfView.swift            # 首页：陈列 / 全部收藏 双屏 + 底部导航
│   ├── HeroCardView.swift         # 主展位：玻璃卡 + 3D 翻面 + 背面详情
│   ├── RackSection.swift          # 挂袋吧台：绳索 / 孔环 / 摆动 / 主从联动
│   ├── BagCell.swift              # 网格卡片
│   ├── ThumbnailImage.swift       # 异步缩略图视图 + 图片名解析（磁盘/Assets 双源）
│   ├── AddBagView.swift           # 新增：选图→跑流水线→表单（名称/分类/材质/标签）→保存
│   ├── CameraView.swift           # 自定义相机 + 辅助取景框
│   └── BagDetailView.swift        # 详情：大图 + 编辑 + 删除二次确认
├── Assets.xcassets/               # AppIcon + AccentColor + 16 只演示袋子 + light-beam
└── DaiDaiJi.xcodeproj/            # Xcode 工程
```

> ⚠️ **改了 `BagItem` 的字段？** 别直接改 `BagItemSchema.swift` 里的 V2 ——
> 按文件顶部注释新建 `SchemaV3` + 追加一个 `MigrationStage`，再把 `typealias` 指过去。
> 直接改已发布的 schema 会让老库对不上、启动即崩。
>
> ⚠️ **图集取名**：`BagItem.imageFileName` 一个字段同时承载两种来源，
> 由 `BagImageResolver` 统一解析 —— 先查 `Documents/bags/`（用户拍的），
> 再查 Asset Catalog（内置演示）。新增读取处请走它，不要直接用 `Image(_:)`。

---

## 三、v1.0 已实现功能

| 模块 | 实现 |
|---|---|
| **新增上传** | 相册选图 / 自定义相机拍照 → 自动跑图像流水线 |
| **抠图去背景** | `VNGenerateForegroundInstanceMaskRequest`（iOS 17+ 类无关前景分割），透明 PNG |
| **透视矫正** | `VNDetectRectanglesRequest` 检测边界 + `CIPerspectiveCorrection` 拉正 |
| **色彩增强** | Core Image `autoAdjustmentFilters` 自动调色 |
| **OCR 名称识别** | `VNRecognizeTextRequest`（zh-Hans），取最优文本行作名称建议，用户可改 |
| **辅助拍照框** | 自定义相机实时预览 + 镂空取景框 + 提示文字 + 闪光灯/切换镜头 |
| **货架浏览** | `LazyVGrid` 网格 + 「最近上传(15天)/全部」分段 + 缩略图缓存 |
| **搜索定位** | 按名称/分类/详情模糊搜索 |
| **分类模糊匹配** | 输入分类时提示相似已有分类，可替换 |
| **详情/编辑/删除** | 大图 + 可编辑信息 + 删除二次确认 |
| **本地存储** | SwiftData（元数据）+ 文件系统（图片），无登录无云端 |

---

## 四、图像流水线顺序（为什么这么排）

`BagImagePipeline.process()` 内部顺序为：

1. **矫正**：先拉正，后面所有处理都在正视图上进行
2. **增强**：调色后再 OCR，文字对比度更高、识别更准
3. **OCR**：在增强后的不透明图上取字
4. **抠图**：最后去背景，输出透明 PNG

每一步都可独立失败并降级（矫正失败保留原图、抠图失败保留不透明图），不会中断流程。

---

## 五、已知边界与后续优化

**当前边界**
- 抠图依赖「有可分割背景」；纸袋占满画面时会回退为不透明原图（正常）
- 矫正依赖矩形检测；拍太斜/背景杂乱时跳过（保留原图）
- 名称用 OCR 最佳文本行；纯图形 Logo 取不到，需用户手填
- 图片存 PNG（保透明），体积偏大；量大后可合成纯色底转 JPEG
- `BagDetailView` 直接读原图，大图库建议也走缩略图缓存

**后续可选**（第一版未做）
- 分类模糊匹配接入品牌词表；Logo 型品牌用 Core ML 分类器 / 视觉大模型
- 云端同步（CloudKit）、多端、备份
- 「最近 15 天」用时间刷新定时器，避免列表不自动更新
- 单元测试与 UI 测试

---

## 六、常见问题

**Q：为什么抠图/矫正有时没生效？**
A：见「已知边界」。拍照时尽量让纸袋**完整入框、背景干净、正面朝上**，成功率最高。

**Q：能在模拟器跑吗？**
A：模拟器无相机，「拍照」不可用；「相册」选图可用，抠图/矫正/OCR 都能跑（视模拟器对 Vision 的支持）。

**Q：想一键生成工程？**
A：`brew install xcodegen && cd DaiDaiJi && xcodegen generate`，会用 `project.yml` 重建 `DaiDaiJi.xcodeproj`。
