> 历史迭代记录：本文保留当时方案与验收结果，旧界面不代表当前实现。当前基线见 [PRD](PRD.md)、[UI 复刻清单](UI-SPEC.md) 与 [设计规范](../DESIGN.md)。`evidence/` 链接指本机历史材料，不随 Git 分发。

# 本地构建与验收记录

2026-09-09 创建，2026-09-10 更新。仓库 git@github.com:DMLayMan/iOS-accounting-app.git，初始提交 f1bca77，初始 master 工作区干净。修复在本地分支 codex/local-build-acceptance，未推送远端。

## 环境与启动

- Xcode 26.6（17F113），iOS Simulator 26.5（23F77）。
- 新建独立 iPhone 17 Pro 模拟器 Yuji-Acceptance，UDID 7D938105-A3A8-464A-A083-2195BEC29F0E，不使用已有设备数据。
- Bundle ID com.yuji.app，使用本机 Application Support/Yuji/ledger.json，无自建后端。
- `scripts/run-simulator.sh` 重新生成工程、构建并安装到该设备；其他设备传 UDID 作第一参数。
- 也可打开 `ios-app/Yuji.xcodeproj`，选择 Yuji scheme 与模拟器运行。

## 已完成的证据

| 项目 | 结果 | 证据 |
|---|---|---|
| 克隆与版本 | 拉取成功，初始版本 f1bca77 | git log / status |
| 原始领域测试 | 38/38 通过 | evidence/local-acceptance/swift-test.log |
| 初次 iOS 编译 | 失败，发现类型冲突与遗漏导入等 | xcode-build-initial.log、xcode-build-second.log |
| 修复后 iOS 构建 | BUILD SUCCEEDED | xcode-build-final.log |
| 应用安装启动 | simctl install / launch 成功，原生首页已渲染 | screens/01-home-empty.png |
| 初始录入页 | 通过模拟器实际点「记一笔」，金额、分类、账户/日期、键盘和保存区域可见 | 本轮 Computer Use 画面与交互回执 |
| 首页导航问题 | 首次运行中“看统计”被禁用且没有账本标题；加入 NavigationStack，重建后标题出现 | home-before-navigation-fix.png 与 screens/01-home-empty.png |
| 写盘失败回归 | 失败不返回成功、恢复内存快照、不显示成功提示；重试并重建 AppState 后读回正确 | AppStateTests，3 项 |
| 实际文件读写与恢复 | 临时真实 JSON 文件保存、原子替换、88.00 支出读回、备份恢复均成功 | DiskPersistenceTests，1 项 |
| 当前完整 Swift 测试 | 43/43 通过，包含原有 38 项与新增 5 项 | swift-test-final.log |
| 差异格式检查 | git diff --check 通过 | 当前命令检查 |

测试日志路径若省略前缀，均位于 evidence/local-acceptance/。金额和文件测试使用隔离合成数据，不涉及真实账目。

## 本地修复

1. SwiftUI 与领域模型均有 Transaction：UI 文件显式使用 YujiCore.Transaction。
2. Design.swift 导入 YujiCore，解决 EntityID 未找到。
3. 备份时间经完整快照更新并成功写盘后发布，避免跨模块写 private(set) data。
4. 统计图形函数参数 max 遮蔽标准函数，改用 Swift.max。
5. AccentColor 深色资源 appearance 键修正为 luminosity；XcodeGen 声明保留中文名称、版本、启动和横屏限制等信息。
6. 首页补导航容器；底部＋新增保存后切到账本，取消不切；首页暗色快捷区域改为跟随主题。
7. AppState.perform 在写盘成功后才返回成功，领域操作或写盘失败恢复之前快照；补保存失败与真实落盘回归。
8. macOS Swift Package 可直接编译同一份 AppState 源码并运行应用状态测试，不必依赖模拟器测试宿主。

## 2026-09-10 实际 UI 验证

本节均为隔离模拟器合成数据。通过原生 UI 产生，随后从 App 容器读取真实文件核对；没有向应用注入测试交易。

| 流程 | 结果与证据 |
|---|---|
| 新增与两级标签 | 输入 (28+16)×2，选择咖啡茶饮、自己、通勤，备注「模拟器验收 · 咖啡」，保存 88.00；ui-saved-88.json |
| 编辑 | 改为 90.00，交易 ID 不变、revision = 2，标签和备注保留；exports/ledger-after-ui.json |
| 部分退款 | 退款 20.00，剩余可退与净支出均为 70.00；screens/06-refund-detail.png |
| 超额退款 | 再退 71.00，明确显示「退款超出剩余可退额度」；没有额外退款交易；screens/07-refund-limit.png |
| 重启读回 | terminate → 安装修复构建 → launch 后支出 90.00 / 退款 20.00 / 净支出 70.00 保留 |
| 跨日缺陷 | 昨日启动后 today 固定为 9/9，今天新增账目未纳入当前期间统计；已修复日期刷新，新增跨日与跨月回归 |
| 日期刷新 | App 出现、回到前台、日历跨日与显著时间变更均触发 refreshToday；自动化测试覆盖原先遗漏的次日记录与月份切换。尚未再次等待真实午夜进行系统通知验收 |
| 月度与年度 | 修复后截至 9/10，净支出 70.00，分类净额 70.00，两组标签各 70.00；标签不应直接相加；screens/08、09 |
| 流水筛选 | 咖啡关键词筛选后仅有支出行，筛选后净额 -90.00；搜索页截图 screens/11 |
| 转账 | 现金 → 银行卡 100.00；余额分别 -170.00 / 100.00；净支出仍为 70.00；screens/12 |
| 管理页面 | 账户与分类标签页面已渲染；账户余额与转账结果一致；screens/14、15 |
| 多账本隔离 | 新建「旅行 · 验收」，切入后净额、账户余额均为 0；切回个人账本原 3 笔记录与余额保留；screens/16 |
| 备份生成 | 点击「生成备份文件」，系统分享预览出现 JSON；真实 tmp/yuji-backup.json 为 33,855 字节，已拷贝留档 |
| 文件独立核对 | 2 账本、4 账户、3 笔唯一交易；支出 9000 分、退款 2000 分、转账 10000 分；备份交易数组与实际库相同；ui-data-verification.json passed=true |

日期修复后重新执行 swift test（43 项，0 失败）和 iOS build（BUILD SUCCEEDED）。这些 Swift 测试在 macOS 上运行；不把它们称为 iOS UI 自动化测试。

### 可直接查看的产物

- 原生实测截图画廊：../evidence/local-acceptance/index.html（25 张过程截图，可点击放大）。
- 数据核对回执：../evidence/local-acceptance/ui-data-verification.json。
- 实际备份：../evidence/local-acceptance/exports/yuji-backup.json。
- 当前数据快照：../evidence/local-acceptance/exports/ledger-after-ui.json。

### 扩展验收与问题清单

1. 10:07 左右锁屏暂停，10:13 后继续并完成系统文件保存、CSV 导出、UI 备份恢复、删除与回收站恢复、草稿重启恢复和收入录入。短时撤销按钮未在 UI 有效时间内点击；不将其计为 UI 通过。
2. 深色主页面、录入和偏好已检查，统计快捷按钮白底白字已修复并重建、截图验证。深色草稿提示与恢复按钮的次要文字对比度仍需优化；动态字号、VoiceOver、窄屏、真机触觉尚未验收。iOS XCTest 宿主此前两次停在 dyld __open，未执行断言，已中断；相关 xcresult 不是通过证据。
3. 现有 SwiftUI 与已认可 HTML UI v2 仍不一致：分类横滚、四行补充信息、详情页仍浮动＋、顶部大标题等。此次先验证仓库实际能力，未重做整套 UI。
4. 账户期初日期仍显示「2,026/9/9」；统计年份已修正。部分日期控件沿用模拟器系统英文日期。需在体验统一时处理。
5. 筛选页重新进入时条件恢复与流水筛选状态提示尚需改善；当前搜索结果缺少明显的「筛选中」提示。
6. 仓库未实现原型全部 84 个场景；iCloud、家庭共享、预算、周期与导入等后置。模拟器运行不等于个人 iPhone 长期使用或 App Store 发布验收。

## 最终补验结果（2026-09-10 10:22）

- 系统「保存到文件」成功：File Provider Storage 中真实存在 yuji-backup.json 与 yuji-个人账本.csv；备份字节与应用生成文件完全一致，CSV 3 行交易字段、金额和关联原支出 ID 正确。留档 CSV 是早餐与收入录入前的阶段快照。
- UI 恢复成功：系统文件选择器选择相同合成数据备份，出现「恢复完成，数据已核对」，磁盘记录 lastRestoreVerifiedAt。之后重启，原 3 笔交易和余额保留。
- 草稿：12 元早餐 → 取消 → 保留草稿并退出 → 重启 → 首页草稿入口 → 恢复 12 元及早餐分类 → 保存。草稿阶段净支出保持 70；提交后为 82，最终 drafts 为空。
- 删除恢复：早餐进入回收站后净额回到 70；回收站恢复后净额回到 82。未永久删除。
- 收入：切换收入，1÷0 显示「除数不能为 0」且保存禁用；清空并输入奖金 500，保存后从我的页回到账本，收入 500、结余 418。
- 最终文件核对：5 笔唯一有效交易、2 账本，支出 10200 分、退款 2000 分、净支出 8200 分、收入 50000 分；现金 31800 分、银行卡 10000 分，合计等于结余 41800 分。见 final-verification.json 与 exports/ledger-final.json。
- 最新 iOS 构建 BUILD SUCCEEDED；git diff --check 通过。领域及状态测试维持 43 项通过；本轮最后改动为单处深色填充，已通过构建和真实界面截图验证。

本次「拉取仓库 → 本地构建 → 原生渲染 → 核心流程自测 → 效果交付」完成。上述扩展验收与体验问题仍作为后续产品化事项，不声明全 PRD、全设备或上线验收通过。代码保持本地分支，未提交或推送远端。
