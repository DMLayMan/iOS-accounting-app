# 1.0（6）重新打包与内部 TestFlight

## 目标与授权

2026-10-15 用户确认构建 5 点“继续”后仍无法下载，要求重新生成新 build 并发布。范围是现有“首发验收”内部 TestFlight 群组，不提交 App Review、不扩大测试员、不删除 App 或账本、不切换账号。

研判：新 build 用于排除单个分发产物/下载任务的问题，当前没有下载失败错误码，不能声称已确定根因或新 build 必定解决。

## 本地候选

- canonical `ios-app/project.yml` 的 CURRENT_PROJECT_VERSION 5 → 6，版本仍 1.0。
- 先与构建 5 的 111 个构建源文件/资源逐项哈希比较，全相同；更新后只有 project.yml 构建号变化。SDK 固定 5a15573e6cdf5175e4efc064316b1e2714af056f。
- XcodeGen 生成成功；全新 derivedData 与 archivePath 归档，实际 xcodebuild 退出 0。
- 实际 App 为 1.0（6），严格 codesign 检查通过；团队/Bundle/CloudKit 容器和 Production entitlement 均核对通过。
- 发布资源检查通过：无 fixture、测试 bundle/启动标记或模拟云客户端；隐私政策与 canonical 源相同。
- 重新保存 111 个源文件/资源的完整私有快照，tar 解包逐项哈希通过；归档完成后再检查源文件无漂移。
- 本次只改构建元数据，没有新增业务/UI 变更。沿用相同业务源码的先前专项证据，不把旧测试写成构建 6 的真实服务或支付验收。

## 上传与后续

Xcode Organizer 已明确显示“Yuji 1.0 (6) uploaded”，上传成功截图保存在私有 evidence；App Store Connect 已处理完成，实际 build ID 为 `4b51d508-77e0-4962-9e7a-24e8e1c5c54e`；已加入原“首发验收”内部群组（仍仅 1 位测试员），说明保存后刷新回读一致、截图留存。本人随后确认 App 内显示 1.0（6），设备安装清单也已实际回读构建 6；独立原生 UI 与云验收继续。上传完成、可用和实际安装是三个独立状态。

另外已通过 Xcode Organizer 导出构建 6 的真实 App Store IPA（4,035,504 字节），解包后严格签名、团队/Bundle、Production 容器、`get-task-allow=false` 与资源检查均通过；它是分发产物证明，不是手机 TestFlight 安装证明。SHA-256：`38b4e0bad9c0b87b9d329d828ce4e2d926a53a652ebab1f57677d958a3b7dd56`。

手机本轮操作前实际为 4，更新后设备安装清单已回读 6；原 B→A 云恢复结果为 2 笔 3234 分。尚未验证的新包支付取消、A→B 编辑及权限/撤销矩阵继续保留，旧待确认购买日志不自动清空。不再要求本人重复支付。

## 私有证据

`evidence/release-20261015/`：`build6-archive.log`、`build6-resource-gate.json`、`build6-entitlements.plist`、`build6-signature-check.json`、`build6-source-complete-manifest.json` 与 tar。快照 SHA-256：`f3335df3b4ff6ceab2251c5a6c78b37f7af8e643964fc5688e08aa66bfd159a1`。真实个人快照和收据均不在源文件快照内，原始 evidence 不公开。

安装后的私有快照 `build6-device-after-install`：QA 仍 2 笔 3234 分；支持与邀请日志分别和更新前逐字节相同。ledger 文件因启动同步等变化并非字节相同，不能泛化为整个库完全不变。未清空旧待确认购买。

## 构建 6 实际原生与双账号验证

- 独立 runner 已从「我的 → 帮助与反馈」读到 1.0（6）并截图；清单没有 UITargetAppPath 或 Yuji.app 依赖，没有覆盖安装调试 App。
- 同一本 QA 原流水的金额/ID 保持不变，仅新增测试备注。备注输入时金额键盘不可点击，完成后恢复；保存后修订号由 1 → 2，仍 2 笔 3234 分。
- A 真实 Production 同步成功，无 pending/issue/incoming；B 不同 iCloud 身份独立 scoped 服务回读到同一备注和 revision=2，本机缓存与远端一致，正常 Mac 文件指纹不变。此前 B→A 新增已通过，所以基础双向读写成立；离线并发、权限/撤销等完整矩阵仍不合并宣称通过。
- 支持/邀请文件在此次云修改前后分别逐字节相同，旧未决购买没有被云流程清除。
- 6 的 Apple 原生成员管理页已实际打开并显示同一 QA 名称和已加入成员，无崩溃；打开页面不是权限切换验证。

原始证据：`distribution-driver/build6-owner-edit-navigated.xcresult`、`b-receives-build6-owner-edit.xcresult`、`build6-device-after-owner-edit/readback.json`、`b-production-accepted/owner-edit-readback.json`。早先 driver9 错误假设用户仍停在帮助页，在任何写入前被 guard 拦截；原失败保留，修正为先实际导航后完成有效重验，不归因于 App 版本错误。

## 真实 Production 权限切换

A 的实际 TestFlight 6 打开系统共享管理，精确选择唯一已加入的 B。设置“仅查看”、返回并完成，A 页面回读 B 为只读。随后 B 独立服务同步读到 writable=false，并验证 AppState 拦截修改，整个隔离数据编码前后相同。

接着 A 同一路径恢复“可更改”，完成后 B 再次真实回读 writable=true。全程还是同一 QA 的 2 笔 3234 分，无 pending/issue/conflict，普通 Mac 文件指纹不变。恢复权限后的新写入尚未另外验证；撤销/重邀、双端真实离线与并发冲突也不因此算通过。

对应私有结果包：`b-production-readonly-build6.xcresult`、`b-production-restored-edit-build6.xcresult`，B 摘要分别在 `b-production-accepted/readOnly-build6-summary.json`、`restored-readWrite-build6-summary.json`。A 的 open-peer/set-readonly/back/done/restore-edit 操作每步另留结果与截图，未触及“与更多人共享”“移除”“停止共享”，未扩大接收范围或删除账本。

## 支付后续需求已变更

构建6曾进入旧购买恢复页，support.check 与 support.done 可独立定位，但旧 unresolved 仍阻断金额选择。用户明确拒绝这套历史状态管理方式，要求可重复打赏、每次打开直接选择最新金额。旧“本人核对并解锁”的请求已取消；新 SDK/宿主修改及构建7验证见 [重复支持修正](repeat-support.md)。构建6不包含这次新动线，不能宣称本版已修复。
