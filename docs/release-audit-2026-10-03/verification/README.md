# 本轮验证与复现

日期：2026-10-03。根目录指 `iOS-accounting-app`。生产实现固定为 `58aed2d526844739e13cdf2795800f83e869681d`；本轮未修改 `Sources`、`ios-app/Yuji` 和 `project.yml`。文件 SHA-256 见 [实现清单](implementation-files.json)。新建测试和系统标签兼容调整独立于生产代码。

## 结果文件

| 文件/批次 | 结果 | 解释 |
|---|---|---|
| [SE 完整结果](se26-summary.json) | 67/67 | 18 原生单元 + 49 UI；11 条布局运行警告 |
| [Pro 完整初轮](pro27-summary.json) | 66/67 | 主题色块名称定位失败；其余均通过；11 条布局警告 |
| [Pro 主题复核](pro27-theme-recheck-summary.json) / [SE 主题复核](se26-theme-recheck-summary.json) | 各 1/1 | 只兼容系统名称，保留原提交/取消/重启断言 |
| [补充 v3](supplement-v3-summary.json) | 1/3 | 金额闭环通过；系统 Cancel 英文定位失败；长名称真实产品失败 |
| [补充 v4](supplement-v4-summary.json) | 1/1 | 仅复核系统分享/文件选择取消；未重复计算已通过的金额路径 |
| [分类预算补拍](category-capture-summary.json) | 1/1 | 同一规则 CRUD/重复校验/重启，额外保留 U30 分类选择截图 |
| [独立 UI 用例总表](ui-case-coverage.json) | 51 通过 / 1 失败 / 0 未运行 | 按用例身份与后续复核合并，跨设备汇总不等于每台完整执行 52 条 |
| [未来余额数值探针](domain-probes.json) | 已复现缺陷 | 完整源码见 [DomainProbes.swift](DomainProbes.swift) |
| [原图清单](screenshots.json) | 原始 PNG SHA-256 | 全量截图本机 evidence；没有合成或图像修饰 |
| [代表截图清单](visual-review-selection.json) | 68 张 / 17 组 | 已集中查看；另有补充原图检查，见 [视觉结论](../visual-review.md) |
| [运行警告的场景](se26-runtime-warnings.json) | 11 条待定位 | 本轮 xcresult 没有源码位置，不猜测根因 |

Swift 核心日志在 `evidence/release-audit-20261003/core/core.log`：116 条（99 Core + 17 AppState）通过。Release 未签名 archive 日志在 `evidence/release-audit-20261003/release-archive.log`，归档 `release/Yuji.xcarchive`；只有未链接 AppIntents 相关元数据跳过提示。App 版本 0.1.0 (1)，约 2.6 MB；没有分发签名/上传证明。

## 可重复命令

从仓库根执行；使用自己的可用 simulator UUID。不要在正在运行的测试构建目录里重建，不复用原有个人数据路径。

```sh
YUJI_REGRESSION_OUTPUT=evidence/audit-rerun-core scripts/regress.sh core

YUJI_REGRESSION_BUILD=.build-audit-rerun \
YUJI_REGRESSION_OUTPUT=evidence/audit-rerun-build \
scripts/regress.sh build SIMULATOR_UUID

YUJI_REGRESSION_BUILD=.build-audit-rerun \
YUJI_REGRESSION_OUTPUT=evidence/audit-rerun-native \
scripts/regress.sh test SIMULATOR_UUID -collect-test-diagnostics never
```

当前完整 UI 测试会包含新增的长名称失败。**不要跳过、`XCTExpectFailure` 或放宽名称/屏幕边界来制造全绿**；修复生产布局后原样关闭此断言。隔离脚本为每次测试创建新的 session，并冻结业务日期；无需卸载 App 或清空模拟器。

未来余额探针只使用隔离账本与唯一临时目录，不接触个人文件；它同时验证保存、重新读取与备份还原：

```sh
swiftc -O -o /tmp/yuji-release-domain-probe \
  Sources/YujiCore/*.swift docs/release-audit-2026-10-03/verification/DomainProbes.swift
/tmp/yuji-release-domain-probe
```

最终汇总命令保留失败返回码 1，作为审查结果而不是工具故障：

```sh
node scripts/summarize-regression.mjs \
  evidence/release-audit-20261003/se26/native.log \
  evidence/release-audit-20261003/pro27/native.log \
  evidence/release-audit-20261003/pro27-theme-recheck/native.log \
  evidence/release-audit-20261003/supplement-v3/native.log \
  evidence/release-audit-20261003/supplement-v4/native.log \
  evidence/release-audit-20261003/category-capture/native.log
```

本轮生成图集的输入路径固定在 [build-gallery.mjs](build-gallery.mjs)，先用 `xcrun xcresulttool export attachments` 将上述指定结果导出到对应 `*-attachments` 目录，再执行该脚本。它只复制原始图片并计算摘要。页面全文索引是本机产物；[四张关键原图](portable-evidence.json)已单独随文档保留，支持离开本机仍复核主要视觉问题。

## 执行中的非产品故障

- 分享手势、Picker 动态标签、Files 英文 Cancel、iOS 27 色块改名导致的初次自动化失败均有层级证据，修正定位后复测；没有改应用行为让测试过。
- 一次补充构建在测试代码调用坐标 API 时类型不匹配，修正后构建通过，失败构建没有运行测试。
- 初次补充失败和 Pro 初轮失败触发 Xcode 全系统诊断，诊断子进程长时间不结束；仅终止本轮 `simctl diagnose` 子进程，保留 xcodebuild 正常结束及其 xcresult/失败截图。两份包的广泛系统诊断可能不完整，测试步骤与结果保留。后续定向测试关闭这项诊断采集。
- 个别截图发生在弹层动画中途；不将过渡帧空白当作产品故障。真实长名称越界有稳定的 frame 断言和原图，相互印证。

## 尚未证明

真机安装/性能/触觉/VoiceOver、最低 iOS 16、锁屏/低磁盘等系统故障、Files 真正保存并选回恢复、签名旧版覆盖升级、开发者分发资格、App Privacy 最终报告、TestFlight 与审核结果。所有这些均有明确待办，不计入“通过”。
