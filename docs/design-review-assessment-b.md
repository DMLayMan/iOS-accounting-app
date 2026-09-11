> 历史迭代记录：本文保留当时方案与验收结果，旧界面不代表当前实现。当前基线见 [PRD](PRD.md)、[UI 复刻清单](UI-SPEC.md) 与 [设计规范](../DESIGN.md)。`evidence/` 链接指本机历史材料，不随 Git 分发。

# Assessment B — 原生 iOS 技术审查

## 平台符合性结论

**原生身份检查：通过。发布质量检查：尚未通过。** 源码主体采用 SwiftUI `TabView`、`NavigationStack`、`List`、`Form`、系统 sheet、日期选择器及 SF Symbols，符合记账工具的原生结构。当前主要问题是失败后退出编辑、恢复覆盖缺少决策保护、深色保存按钮对比不足，以及固定字号和部分过密操作区；不需要因此重做整套视觉语言。

这是独立、只读的源码技术评估，未读取 Assessment A，未运行浏览器检测器，未操作 Simulator，未修改应用源码。评估依据为 `impeccable/reference/audit.native.md` 与 `ios.md`。下列“已确认”指源码控制流或明确样式值可确认，**不表示已在设备上复现**。运行现象单独标为“待核实”。

- 取证日期：2026-09-10，源码采样时间截至 07:55 UTC（15:55 上海）。
- 仓库：`/Users/wktt_1/Documents/Money💰/iOS-accounting-app`。
- HEAD：`f1bca776c03ff5208b1800a2307c05ab2a7738e8`。工作区有大量未提交修改；本报告针对采样时工作区，不能把 HEAD 当作受审代码的完整版本。
- 范围：`ios-app/Yuji/Views` 14 个 Swift 文件中的核心入口、录入、分类、流水、统计、详情、账户及数据管理，关联 `Design.swift`、`AppState.swift`、`YujiApp.swift` 和持久化边界。非活跃的历史标签页面仅作搜索覆盖，未逐项评级。
- 设备范围：`ios-app/project.yml` 声明 `TARGETED_DEVICE_FAMILY: "1"`、仅 iPhone 竖屏；未把缺少 iPad 布局列为缺陷。没有足够产品证据判断竖屏限定本身是否应取消。
- 未执行构建、测试、VoiceOver 遍历、触摸命中测量或性能 profile。已有测试源码仅说明覆盖意图，不构成此次通过证据。

## 健康评分

| 维度 | 分数 | 主要依据 |
|---|---:|---|
| Accessibility | 2/4 | 分类拖动有无障碍替代操作；但首页、金额、流水、录入大面积固定字号，选择状态语义不一致 |
| Performance | 2/4 | 流水使用 List、分类使用可复用 UICollectionView；保存与全量 JSON 编码在主线程，未测量延迟 |
| Appearance & Theming | 2/4 | 有深浅色 token；保存按钮前景没有随深色主色调整，多处仍直接使用浅色 sage |
| Platform Conformance | 3/4 | 系统结构占主导；表单退出与破坏性操作保护不一致，嵌套导航栈需运行复核 |
| Adaptivity | 2/4 | 统计已有无障碍字号布局分支、录入备注有焦点管理；固定分类布局和小操作区尚未完整适配 |
| **总计** | **11/20** | **Acceptable：需要显著整改；仅为源码暂定评分** |

**问题统计：P0 0 项、P1 6 项、P2 4 项、P3 0 项。** 另有 5 项未计入问题数量的运行验证点。没有证据支持“所有页面不可用”或“已经发生数据损坏”等更强结论。

研判：先修 B01–B03、B06 的数据与反馈边界，再统一 B04–B05、B07 的字号、颜色和操作区域。此前已实现的草稿保护、原子持久化和统计无障碍分支应保留并复用。

## 按优先级排列的发现

### B01 · [P1] 选择有效备份后直接替换所有本地账本，没有覆盖确认

- **位置／类别**：我的 → 数据；Conformance / destructive UX。
- **源码证据**：`ios-app/Yuji/Views/MeAndData.swift:225–227,252–260` 在文件选择成功后直接调用 `restoreBackup`；`ios-app/Yuji/AppState.swift:211–222` 校验后直接 `repository.save(newStore.data)` 并替换 `store`。当前路径没有备份内容预览、覆盖范围确认或当前库的恢复点。
- **影响**：用户选择了旧但合法的备份，当前新增账目会被替换。校验只能证明文件结构与关联有效，不能证明用户理解“替换全部账本”；现有按钮“先校验再切换”也未说明覆盖范围。
- **规则**：原生任务式 sheet 应给出清晰决策，破坏性操作需要明确后果。这里的风险是成功路径覆盖，不能用“失败原库不动”替代保护。
- **建议**：先校验并展示备份日期、账本与交易数量、将被覆盖的当前数据摘要；提供明确的“替换全部本地数据”确认；替换前保存可恢复的当前库快照。取消不得写入库。
- **验收**：含新增交易的库选择较旧合法备份，确认前与取消后库字节／交易数量均不变；确认后结果对应预览，且能恢复替换前快照。无效备份仍保持原库。
- **建议命令**：`/impeccable harden`。

### B02 · [P1] 账户保存失败仍关闭编辑页，无法就地修正或重试

- **位置／类别**：账户 → 新增／编辑；Conformance / error recovery。
- **源码证据**：`ios-app/Yuji/Views/ManageViews.swift:109–125` 丢弃 `state.perform` 的 Bool 后无条件 `dismiss()`；账户归档 `79–83` 也如此。`AppState.swift:76–100` 已可靠返回失败并回滚。`Sources/YujiCore/LedgerStore.swift:158–166` 存在可直接触发的领域拒绝：起点晚于已有流水日期。
- **影响**：修改账户名称、余额和记账起点后，若起点非法或磁盘写入失败，表单照样消失，用户输入丢失。全局错误状态仍会设置，因此不能称为“完全没有错误提示”；确定的问题是失败仍退出、表单状态不能重试。
- **规则**：失败应保持任务上下文，成功返回才结束任务。
- **建议**：仅在 `perform == true` 时关闭；失败在表单中展示错误并保留字段。归档同样遵守成功条件。复用交易录入和分类编辑已使用的成功守卫。
- **验收**：注入磁盘空间不足、非法起点两种失败，表单保持打开且字段不变；更正后重试只产生一次提交，重启读回成功结果。
- **建议命令**：`/impeccable harden`。

### B03 · [P1] 非空非法期初金额被悄悄当作零提交

- **位置／类别**：账户编辑的期初余额；Conformance / input validation。
- **源码证据**：`ios-app/Yuji/Views/ManageViews.swift:112` 使用 `Decimal(string: openingYuan) ?? 0`；`Sources/YujiCore/Money.swift:19–25` 随后直接取分值。`LedgerStore.swift:146–155,158–168` 接收数值，不可能再识别原输入解析失败。
- **影响**：粘贴非法非空字符串后保存，解析失败和有意输入零成为同一结果；编辑已有账户可能把期初余额改为零并正常报“已保存”。数字键盘不能防止粘贴或硬件键盘输入。
- **规则**：金额输入必须区分空值、合法零和解析错误，并说明实际提交值。
- **建议**：仅产品允许的空值才默认零；非空输入须完整解析并校验范围与小数精度，非法时原地提示且不得提交。采用明确的本地化解析或统一金额输入策略，避免接受部分字符串。
- **验收**：空串、`0`、负余额、有效两位小数、粘贴字母、货币符号／分组符、过大金额分别验证；错误输入不改变原账户余额。
- **建议命令**：`/impeccable harden`。

### B04 · [P1] 深色模式可用状态的保存按钮只有 1.82:1 文字对比

- **位置／类别**：记一笔／编辑的保存键、首页草稿；Appearance & Theming / Accessibility。
- **源码证据**：`Design.swift:8–11` 深色主色为 `#9DCAB0`；`Views/EntryView.swift:316–320` 可用保存键使用该背景，但前景固定白色。用源码 sRGB 值计算，`#FFFFFF / #9DCAB0 = 1.82:1`。`LedgerHomeView.swift:106–108` 草稿条深色模式仍用浅色 `#367961` 文字配 `#314A3B`，比值为 `1.87:1`。
- **影响**：主操作的“保存”及舍入确认金额在深色模式很难辨认；草稿恢复文字也会显著弱化。这里审查的是 enabled 状态，不拿 disabled 控件计入对比失败。
- **规则**：iOS 参考要求深色外观与语义色成体系。文字对比采用 WCAG 的 4.5:1 普通文字参考阈值；本次不是对整个原生 App 作 WCAG 合规认证。[W3C 对比说明](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- **建议**：为实心动作按钮建立随背景变化的 foreground token；Entry 退出决策 `EntryView.swift:435–438` 已采用深色黑字，可复用同一规则。草稿、退款、收入和 tab tint 统一检查 `Design.sage` 直用点，不只修保存键。
- **验收**：深／浅色下保存可用、不可用、舍入确认、草稿恢复、收入／退款显示逐项检查；可用普通文字至少达到 4.5:1，且真实设备仍清楚可读。
- **建议命令**：`/impeccable colorize`。

### B05 · [P1] 核心阅读与录入内容没有随 Dynamic Type 放大

- **位置／类别**：首页、流水、录入、账户及分类条；Accessibility / Adaptivity。
- **源码证据**：`Design.swift:40–46,69–78` 以固定 CGFloat 定义字体，`AmountText` 调用 `.system(size:)`；`LedgerHomeView.swift:55–65,179–187` 的金额与流水文本均固定字号；`EntryView.swift:67,84,89,160,250,256,298,317` 多处相同，其中选中分类提示和页码仅 10 pt。UIKit 分类条 `InlineCategoryStrip.swift:186–194,217–229,241–249` 固定字体、单行与 frame，未使用 `UIFontMetrics` 或 `adjustsFontForContentSizeCategory`。
- **影响**：系统大字体用户仍要读取原来 10–16 pt 的关键信息；`minimumScaleFactor` 只允许缩小，不能补足 Dynamic Type。统计页的无障碍布局不代表全流程已可访问。
- **规则**：iOS 参考要求系统文本样式、支持 Dynamic Type、11 pt 字号下限。
- **建议**：文本改用语义样式，需保持展示比例的金额使用可缩放度量；UIKit 用 preferred font／UIFontMetrics 并重算 item 高度；大字号分类从固定四列切换为更少列或列表，保证名字可读。统计页 `AnyLayout` 分支可作为实现样例。
- **验收**：默认、XXXL、AX 最大字号，在最小支持 iPhone 上完成查看余额 → 选分类 → 保存 → 看流水；分类全名和保存金额不因缩小字号而规避适配，正文实际变大。
- **建议命令**：`/impeccable adapt`。

### B06 · [P1] 备份临时文件生成失败被吞掉，“最近备份”却已更新

- **位置／类别**：我的 → 数据 → 生成备份／CSV；Conformance / error feedback。
- **源码证据**：`AppState.swift:194–206` 在返回 bytes 之前就持久化 `lastBackupAt`；`MeAndData.swift:219–222` 之后才写临时文件；`264–266` 对写入错误直接返回 nil，调用处没有失败提示。CSV 导出 `230–235` 也静默失败。`239–241` 仍显示最近备份时间。
- **影响**：临时目录不可写或空间不足时，用户既拿不到文件，也不知道如何重试，却可能看到刚更新的备份时间并误判已有可用备份。
- **规则**：成功状态应对应实际完成的用户动作；错误必须可识别、可恢复。
- **建议**：临时文件写入返回可解释错误；文件实际生成成功后再记录“文件已生成”状态。若继续使用“最近备份”，明确它代表本地生成还是已保存到用户选择的目标，避免把分享面板出现视作外部交付完成。
- **验收**：注入临时写入失败，展示错误且不更新生成成功时间；恢复后可重试。取消分享与成功保存后的状态文案能区分；CSV 同样有可见失败路径。
- **建议命令**：`/impeccable harden`。

### B07 · [P2] 录入页多组高频操作没有给出 44 pt 的可靠操作区域

- **位置／类别**：记一笔的类型、账户／日期、分类工具条；Accessibility / touch targets。
- **源码证据**：`EntryView.swift:76–84` 账户／日期整行只有 30 pt；`154–163` 类型按钮内容最小高 32 pt；`198–206` 分类编辑和全部分类行固定 36 pt。这些位置没有额外的 44 pt label frame 或明确 hit shape。相反数字键、增分类按钮已经给出 44–60 pt 尺寸。
- **影响**：相邻小操作需要更精确点击，对手部活动受限和单手操作用户不友好。源码能确认空间不足；系统最终命中矩形需 Accessibility Inspector／设备测量，未声称已测得触摸区域等于文本 frame。
- **规则**：iOS 参考要求至少 44×44 pt 且操作间留有间隔。
- **建议**：在各 Button 的 label 内提供至少 44 pt frame 和 content shape，再调整行高；不要仅给父 HStack 外加 padding 假设子按钮会自动扩展。
- **验收**：读取实际命中矩形，账户、日期、类型、分类工具操作均至少 44×44 pt，相邻区域无冲突；小屏仍能触达保存。
- **建议命令**：`/impeccable layout`。

### B08 · [P2] 次级编辑表单滑动关闭会丢弃未提交字段

- **位置／类别**：退款、转账、账户和分类编辑；Conformance / draft handling。
- **源码证据**：`DetailAndRefund.swift:169–173,188–223`、`MeAndData.swift:349–354,359–402`、`ManageViews.swift:53–55,57–106`、`CategoryLibraryView.swift:210–216,217–272` 将输入保存在本地 `@State`，取消直接 dismiss，没有 changed 检测、草稿或交互式关闭保护。`EntryView.swift:130,421–458` 已有相应保护，可证明同一 App 的处理不一致。
- **影响**：用户填完长备注或调整账户字段后误向下滑动，重新打开会恢复初始值，输入工作丢失。这里说的是未提交输入损失，并非已保存交易丢失。
- **规则**：任务式 sheet 默认可关闭；发生数据输入损失时应保护修改，未修改的表单仍保持原生关闭自由。
- **建议**：复用 Entry 的初始快照与变更检测；按任务成本决定确认放弃或保留草稿。不要无条件禁止所有 sheet 的下拉。
- **验收**：无修改时可正常滑动关闭；修改名称、金额或备注后关闭按已定义策略保留／确认；取消确认可返回原输入，保存后可正常退出。
- **建议命令**：`/impeccable harden`。

### B09 · [P2] 外观与反馈中的两个偏好只保存，未接入实际反馈

- **位置／类别**：设置、分类拖动与翻页；Accessibility / platform settings。
- **源码证据**：`MeAndData.swift:275–279` 提供 `hapticsEnabled` 与 `reduceMotion` 开关；当前应用源码搜索未发现它们在效果执行处被读取。`InlineCategoryStrip.swift:106,127` 无条件触发触觉；`64` 翻页动画只检查系统 `UIAccessibility.isReduceMotionEnabled`。
- **影响**：用户关闭触觉或开启 App 的减弱动态后，分类控件继续按原方式反馈，偏好承诺无法兑现。系统减弱动态在分类翻页已被检查，应保留这条有效路径。
- **规则**：可见偏好应影响对应行为；无障碍系统设置与应用偏好应有一致的合成规则。
- **建议**：统一反馈服务读取设置；减弱动态取系统或 App 任一开启即生效。若暂不支持某偏好，应去除可操作但无效果的入口。
- **验收**：两开关分别开／关后拖动分类与翻页，触觉和动画变化符合文案；系统 Reduce Motion 开启时 App 设置不能重新启用大移动。
- **建议命令**：`/impeccable animate`。

### B10 · [P2] 自定义选择控件与当前账本缺少完整的读屏状态

- **位置／类别**：记一笔类型切换、账本切换；Accessibility / semantics。
- **源码证据**：`EntryView.swift:154–163` 支出／收入只通过字体和颜色区分选择，未设置 selected trait／value；`LedgerHomeView.swift:24–33` 把账本名按钮的 label 替换成“切换账本”，没有 accessibilityValue 保留当前账本名；`MeAndData.swift:75–83` 当前账本只展示 checkmark。
- **影响**：VoiceOver 使用者知道有支出／收入按钮或切换入口，却缺少直接读取“当前选中哪一类／哪一本账”的稳定语义。未运行读屏，因此不声称系统一定读出某个具体错误文本。
- **规则**：自定义可交互控件应暴露角色、名称和当前状态；测试用 `accessibilityIdentifier` 不能替代读屏标签。
- **建议**：类型改为原生 segmented picker 或补 `.isSelected`；账本入口保留当前名称作为 value，列表行提供“当前账本”的 selected trait；避免图标和文案重复播报。
- **验收**：仅用 VoiceOver 能识别当前账本、当前类型，切换后状态更新，选中态无须靠颜色理解。
- **建议命令**：`/impeccable harden`。

## 待核实的运行风险，不计入已确认问题数量

1. **嵌套导航栈**：首页 `LedgerHomeView.swift:83–85` 通过 NavigationLink 打开内部自带 NavigationStack 的 `StatsView.swift:25`，而首页已有 `RootView.swift:14` 的栈。源码确认栈嵌套，但返回按钮、边缘滑动或重复导航栏是否异常未运行。验收“首页看统计 → 下钻 → 返回首页”和直接统计 Tab 两条路径；通常应让共享统计内容由宿主拥有导航容器。
2. **全局 ＋ 的覆盖范围**：`RootView.swift:32–48` 使用 ZStack 固定叠加，只有底部 14 pt padding，没有与 tab bar frame 建立关系。不能据源码声称已挡住 Tab 或 Home Indicator；需小屏、不同 safe area 测量四个 Tab 与 ＋ 的实际命中范围。
3. **主线程工作规模**：`AppState.swift:5,76–84` 在 MainActor 内调用全量保存，`Persistence.swift:42–51` 同步编码和写盘；统计 `StatsView.swift:27–29` 在月视图也计算 yearSummary，下钻 `StatsDrilldownSheet.swift:47–51,68,83,123–125` 多次访问会重新筛选／排序的计算属性。结构成本已确认，是否明显卡顿待核实。用 500／5,000／50,000 笔数据测启动、筛选、排序及保存的主线程耗时，再决定缓存／后台工作，不以肉眼或测试通过替代 profile。
4. **键盘与错误呈现**：Entry 已显式切换备注焦点并隐藏自定义键盘，CategoryLibrary 已使用 `.scrollDismissesKeyboard(.interactively)`。账户期初用 `.decimalPad`，没有显式负号或完成辅助键；其他 Form 依赖系统避让。需实机确认负期初余额的普通键盘输入、最小屏幕备注／保存可达性。全局 alert 仅挂在 `YujiApp.swift:25–30`，sheet 内保存失败时是否能在最上层可靠展示也需运行；不能由没有局部 alert 推导必然静默。
5. **已删除详情的永久删除分支**：`DetailAndRefund.swift:123–128` 直接调用 purge 而无确认，但当前 Trash 列表没有进入该详情的 NavigationLink，未证实常规入口可到达此分支，因此不列作已复现的破坏性 UX 缺陷。若未来增加入口，必须复用 Trash 当前已有的二次确认。

## 系统性问题与值得保留的实现

**系统性问题**：新统计页和旧首页／流水使用两套字号策略；同一色彩 token 有些调用随 scheme 有些直接用浅色值；异步／失败语义虽已在 AppState 集中，却未在所有 UI 调用点贯彻成功后关闭；原生表单保护也只在主录入完整实现。

**有效实现**：

- `AppState.perform` 在保存失败后回滚并返回 Bool，避免把内存变更当持久化成功；现有 AppState 测试源码覆盖写盘失败、部分操作失败、重试和真实文件替换。此次未重新执行。
- 主录入保存、草稿保存／清空只在成功后退出；编辑取消有保留修改上下文的决策，未改动的 sheet 不被一律锁死。
- 分类列表具有明确的归档／删除确认和引用检查，管理操作有有意义的无障碍标签；UIKit 拖动提供 VoiceOver 向前／向后移动替代动作。
- 流水使用 List、最近记录限制为 8 条且使用 LazyVStack；没有把完整交易列表全部堆在普通 VStack 中。
- 统计有明确口径文字、年度柱图文字替代入口、范围无障碍分支；下钻在大字号或进入单条详情时扩展到 large，汇总有组合读屏标签。
- 系统 SF Symbols、原生 DatePicker 和 sheet 是现成的可维护基础；没有发现用 WebView 替代核心原生页面。

## 建议执行顺序

1. **[P1] `/impeccable harden`**：B01、B02、B03、B06，完成恢复覆盖、账户输入与失败反馈的最小闭环。
2. **[P1] `/impeccable colorize`**：B04，统一可用按钮前景与深色文字 token，测实际对比。
3. **[P1] `/impeccable adapt`**：B05，统一 Dynamic Type，首先覆盖首页 → 录入 → 流水这一核心链路。
4. **[P2] `/impeccable layout`**：B07，以实际命中区域验收高频操作，联动验证小屏键盘与导航风险。
5. **[P2] `/impeccable harden`**：B08、B10，统一 sheet 修改保护和选择状态语义。
6. **[P2] `/impeccable animate`**：B09，接通用户反馈偏好，保留系统减弱动态优先权。
7. **验证后按需 `/impeccable optimize`**：只有性能 profile 证实成本值得处理时再做缓存或任务隔离，避免盲目重构。
8. **最后 `/impeccable polish`**：修复后做一次合并的 iPhone 默认／大字号／深色原生验收；再运行 `/impeccable audit` 更新评分。

这些动作可按项、合并或调整顺序执行；本报告只提供可审阅的整改建议，未执行修复或扩大当前交付范围。

## 证据复核说明

原生尺度、Dynamic Type、modality 等按本机 [iOS 参考](/Users/wktt_1/.codex/skills/impeccable/reference/ios.md) 评定；报告结构按 [native audit](/Users/wktt_1/.codex/skills/impeccable/reference/audit.native.md)。Apple HIG Accessibility 官方网页本次文本抓取只返回 JavaScript 提示，因此没有把未读到的页面内容写成已核实引文。对比公式及阈值读取了上文所链 W3C 原始说明；颜色数值来自当前源码，用 sRGB 线性化后 `(Lmax + 0.05)/(Lmin + 0.05)` 计算，不来自截图取色。

核心源码采样 SHA-256（用于识别父任务后续修改造成的漂移）：

```text
Design.swift       0f76f01d27ec43e78e990c5ed77d3c38b44c0b32cfc80432206d740ff3c17897
EntryView.swift    2ddb4b1fe02bdca7a204fcee950727cf8456071ded1ab21a7bd28ce7e2ba615d
ManageViews.swift  024bba91f462ed449c32b4a25390f1d09ef311929402afa2bf4c6322a02f4491
MeAndData.swift    a08c3145645a333916834c3bf8e6278ef330f9716dc8ab576d9b93a69e9de6b2
RootView.swift     75bf4c3acaa34555c65e9aeab30671b8081aaa628f082e9b4043bdea97c013cd
StatsView.swift    34d0f3955c8076aa18032cdd583237601e5aae1f0cc6818ceadfb3bbd29fce69
```

源码行号属于此次采样。应用后续修改后，先按函数名和上述指纹确认报告是否仍适用；此文件不是当前 UI 运行通过凭证。
