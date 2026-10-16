# 非发布依赖功能自测 · 2026-10-08

本批次使用当前源代码与已定稿图标，重新构建原生测试宿主，运行领域/应用状态及 Pro、SE 两套原生测试。只使用隔离 UUID 合成数据；不卸载、不重置模拟器，不读取个人 `ledger.json`，不发送 CloudKit 请求。

结论：本批次已完成，覆盖内未发现新的测试失败；没有因此修改功能代码。以下通过只适用于隔离本地数据与模拟云协作，不代表真实云端或发布验收已经完成。

| 本轮实际执行 | 结果 |
| --- | --- |
| Portable：YujiCore 113 + YujiAppState 36 | 149 / 149，0 失败 |
| iPhone 18 Pro · iOS 27.0 模拟器 | 103 / 103，0 失败、0 跳过 |
| iPhone SE 3 · iOS 26.5 模拟器 | 103 / 103，0 失败、0 跳过 |
| 两套原生结果包 | runtimeWarnings 均为空 |

每台原生设备包含 37 个 hosted 状态用例与 66 个 UI 用例；与 portable 状态测试有重叠，不能把运行次数相加当成独立场景数量。按当前源码声明逐一核对身份，没有缺失、额外用例或重复身份。详见 [verification.json](verification.json)、[Pro 原始摘要](verification/pro.json)、[SE 原始摘要](verification/se.json)与 [预期用例及源码位置](expected-native-cases.json)。

## 覆盖任务

| 范围 | 核对的用户任务/异常 |
| --- | --- |
| 记账与账户 | 收入、支出、退款、转账、账户期初、保存与重启、未来日期、非法金额 |
| 分类与录入 | 一级/二级、行内新增、图标、长按排序、搜索定位、键盘互斥、取消与编辑保护 |
| 统计与流水 | 五年 500 笔独立金额核对、饼图/排行/同页明细、同环比、空期/负基期/闰月、时间栏共享、账户与金额筛选 |
| 预算 | 账本月/年、父/子分类规则、历史额度、超额折叠、保存前预览、退款与账本隔离 |
| 本地耐久 | 草稿关闭/后台/重启、撤回空表单、删除撤销/回收站、备份编解码/文件恢复、系统分享打开与取消、恢复点管理、磁盘失败回滚 |
| 模拟云协作 | 双客户端、账号隔离、重试防重复、并发退款、冲突保留副本、只读、暂停、撤权状态、恢复后的独立副本、成员退出 |
| 页面环境 | Pro / SE、iOS 27 / 26.5、深色、最大字号、长名称、隐私与帮助入口 |

真实共享邀请、CloudKit 请求、签名升级、TestFlight、App Review 与真实用户长期体验不在此次通过范围。最低 iOS 16 与 VoiceOver/触觉实机验收仍待完成；云端彻底删除功能尚未实现，不能把模拟成员退出算作拥有者删除通过。

真实 CloudKit 联调本身无需先上架，但当前仍缺真实团队/容器配置与双账号设备验收。工程按 iOS 16 部署目标构建通过，当前可运行的两套测试环境是 iOS 26.5 / 27，不能代替最低系统运行验证。系统分享面板打开不等于文件已存到外部提供器；实际文件提供器往返仍待实机核对。

## 命令与证据

```sh
YUJI_REGRESSION_OUTPUT=evidence/selftest-20261008/portable scripts/regress.sh core
YUJI_REGRESSION_BUILD=.build-selftest-20261008 YUJI_REGRESSION_OUTPUT=evidence/selftest-20261008/build scripts/regress.sh build C456E5DC-1377-43E9-871E-394439D7DAF0
YUJI_REGRESSION_BUILD=.build-selftest-20261008 YUJI_REGRESSION_OUTPUT=evidence/selftest-20261008/pro scripts/regress.sh test C456E5DC-1377-43E9-871E-394439D7DAF0
YUJI_REGRESSION_BUILD=.build-selftest-20261008 YUJI_REGRESSION_OUTPUT=evidence/selftest-20261008/se scripts/regress.sh test E6119632-E5BB-48F2-93C5-ECA03C60092F
swiftc -O -o /tmp/yuji-benchmark-selftest-20261008 Sources/YujiCore/*.swift scripts/benchmark-history.swift
/tmp/yuji-benchmark-selftest-20261008 > evidence/selftest-20261008/performance-after-native.json
```

上述原生 test 命令不传筛选，即运行全部目标；test 脚本为 hosted tests 生成新 UUID，UI 用例自行生成隔离 UUID。两设备使用不同临时 manifest 与结果包。结果包完成后再顺序读 summary/export，避免 xcresult 数据库首次迁移竞争；不在测试中重建 derivedData。

[source-fingerprints.json](source-fingerprints.json)冻结本批次 92 个源/资源文件，[fixture-fingerprints.json](fixture-fingerprints.json)记录 500 笔夹具与独立 oracle；结束时校验均未变化。测试业务日期固定为 2026-09-10，统计 oracle 覆盖 57 个月、5 个年份；实际执行日期为 2026-10-08。旧 iCloud / review 批次不改写，旧截图与测试数量不冒充本轮结果。

原始日志：[Portable](../../evidence/selftest-20261008/portable/core.log)、[构建](../../evidence/selftest-20261008/build/build.log)、[Pro](../../evidence/selftest-20261008/pro/native.log)、[SE](../../evidence/selftest-20261008/se/native.log)。Xcode 日志保留了 `IDELaunchParametersSnapshot` 的 debugger version lookup / noURL 信息；结果摘要没有对应测试失败或运行时警告，不能据此推导 App 崩溃。

## 原生页面抽查

[本轮原图集](gallery/index.html)保留 Pro / SE 共 24 个代表状态，[manifest](gallery/manifest.json)可追溯用例、时间、原始文件与 SHA-256。抽查了 Pro 的备注焦点、饼图选中、最大字号长账户，以及 SE 的预算预览、新增分类 sheet 与统一流水时间栏，共 6 张原图；未重绘，未将抽查冒充每个视觉状态的人工验收。

备注焦点状态下自定义金额键盘隐藏；饼图选择有高亮；最大字号长账户保留日期入口；分类 sheet 有图标与名称入口，空名称不能创建。SE 同时显示月/年预算提示时，固定金额键盘压缩分类可视区，需要滚动查看完整分类和备注；自动测试已验证滚动后的操作可达，仍列为小屏屏效的后续打磨点。系统中文输入法、真实软件键盘与触觉手感仍需实机体验。

## 大数据压力边界

`scripts/benchmark-history.swift` 以五年 500 笔夹具扩展为 5k / 50k，带退款、归档/删除与 19 条分类预算，`swiftc -O` 三次取中位数。使用随机临时库，不修改个人数据。

首次 [并发测量](../../evidence/selftest-20261008/performance.json)保留；两套原生回归结束后又测一次，见 [结束后测量](../../evidence/selftest-20261008/performance-after-native.json)。后者不再与本批次 UI 测试并发，其他主机负载未控制；下表只作量级参考，不是物理 iPhone、不是云资产上传量测，也不是性能回归结论。

| 合成记录数 | 保存全库 | 读回全库 | 全部流水排序 | 年度分类查询 | 19 条分类预算 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5,000 | 45.5 ms | 41.6 ms | 7.0 ms | 0.5 ms | 1.3 ms |
| 50,000 | 440.0 ms | 440.6 ms | 97.6 ms | 4.7 ms | 13.3 ms |

大数据仍是主线程全量 JSON 保存；查询索引的热查询速度不能代替落盘成本。5 万笔落盘成本保留为后续性能问题，需要先在真实设备测输入响应、保存、读回和内存，再决定异步持久化或分块方案。前台突然中断时最新未提交草稿的耐久边界也仍未关闭；本轮通过的是关闭/后台检查点路径，具体见 [功能就绪核对](../functional-readiness-2026-10-08/README.md)。

上线数据入口另见 [运营数据与诊断方案](../analytics-plan-2026-10-08.md)。
