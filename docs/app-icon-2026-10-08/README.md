# 余记 App 图标交付 · 2026-10-08

用户最终选择“还是回归到第一版吧”：采用米白底、深绿账本、金色 ¥ 钱币，直观表达记账与钱。后续账袋、折页账单两个方向仅归档对比，未替换工程图标。本批次仅调整 App 图标；没有新增系统设计 token 或更改页面交互，图标不随应用内主题切换。

## 资产与复刻

| 文件 | 用途与实测规格 |
| --- | --- |
| [source.png](source.png) | 内置 imagegen 第一版原始作品；1254×1254、RGB、无 alpha。 |
| [AppIcon.png](../../ios-app/Yuji/Assets.xcassets/AppIcon.appiconset/AppIcon.png) | 当前工程资源；1024×1024、RGB、无 alpha、sRGB IEC61966-2.1。 |
| [Contents.json](../../ios-app/Yuji/Assets.xcassets/AppIcon.appiconset/Contents.json) | 单一 1024×1024 iOS universal 资源。 |
| [prompt.md](prompt.md) | 第一版完整精确提示词与生成方式。 |
| [candidates-prompts.md](candidates-prompts.md) | 两个未采用候选的完整精确提示词。 |

[generate-app-icon.swift](../../scripts/generate-app-icon.swift) 使用 CoreGraphics 将保存的方形源图等比缩放并打包为 sRGB PNG，不重绘图案。在项目根目录运行 `swift scripts/generate-app-icon.swift` 可复刻当前发布资源。内置 imagegen 生成具有随机性，精确复刻必须保留 `source.png`，仅重发提示词无法保证同图。资源保持完整方形，外轮廓由操作系统处理。

旧版备份：[previous.png](previous.png)、[previous-generator.swift](previous-generator.swift)。未采用候选：[candidate-bag.png](candidate-bag.png)、[candidate-sheet.png](candidate-sheet.png)，对照页为 [candidates.html](candidates.html)。

## 本批次验证

| 检查 | 已取得证据 |
| --- | --- |
| Debug 模拟器构建 | [build.log](../../evidence/app-icon-20261008/build.log)：`BUILD SUCCEEDED`。 |
| 未签名 Release 归档 | [archive.log](../../evidence/app-icon-20261008/archive.log)：`ARCHIVE SUCCEEDED`，`CODE_SIGNING_ALLOWED=NO`；产物 [Yuji.xcarchive](../../evidence/app-icon-20261008/Yuji.xcarchive)。 |
| iPhone 18 Pro / iOS 27 模拟器 | 主线程已安装 Debug 并查看 [home-pro.png](home-pro.png)，确认新图标；设备 ID `C456E5DC-1377-43E9-871E-394439D7DAF0`。 |
| iPhone SE 3 / iOS 26.5 模拟器 | 主线程已安装 Debug 并查看 [home-se.png](home-se.png)，确认新图标；设备 ID `E6119632-E5BB-48F2-93C5-ECA03C60092F`。 |
| 浏览器尺寸与背景 | [preview.html](preview.html) 展示 60/40 px 浅深背景；截图 [preview-light.png](preview-light.png)、[preview-dark.png](preview-dark.png)，用户定稿后实际截图 [preview-selected.png](preview-selected.png)。 |

[home-pro-before-refresh.png](home-pro-before-refresh.png) 是安装刷新前的旧图标截图，不能作为新图标验收证据。浏览器预览用于小尺寸识别检查，原生安装证据见两张主屏截图。

当前未提供专用 `impeccable_reviewer` / `impeccable_documenter` 角色，适配为 default 角色的独立 fresh reviewer / documenter。评审只覆盖图标，正式结论 [review.md](review.md) 为 `ship`，无需要返工的实质问题；不代表全 App 视觉批准。

未验证真实设备签名、App Store 提交或审核。本次图标变更没有重跑账本功能测试。历史 iCloud 验收的 `frozenSource`、归档和 hash 属于图标替换前的批次，应保留原记录；本目录对应新一批图标构建，不能据此声称历史归档包含新图标。
