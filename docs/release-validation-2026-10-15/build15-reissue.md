# 2026-10-16：TestFlight 构建 15 重发

用户反馈构建 14 下载／安装卡住，明确要求重发。15:07 设备清单仍为 1.0（13）。本次保留构建 14，不卸载 App、不切换账号、不清缓存、不改账目；重新备份当前 AppSupport 的 3 个文件，JSON 均可解析并冻结 SHA-256，且与此前升级前备份逐字节一致。

## 源码范围

构建 15 的提交为 `3c7dc657392a45f1593700eb64aea4023a46ffa9`。仅将 `ios-app/project.yml` 的 `CURRENT_PROJECT_VERSION` 从 14 改为 15，营销版本仍为 1.0。对比构建 14 的干净源码快照，70 个生产源码／资源／配置文件逐项相同，唯一例外为该构建号。SDK 仍固定 `97f38bb1b9aa31cae0f469a58a37e1641aa8870f`。

复用[构建 14 的 iOS 17 与无障碍验证](ios17-accessibility-2026-10-16.md)：181 条 portable、实际 iOS 17.5 模拟器 33 个不同原生/UI 用例及 SE 小屏专项。它们不是本次重新执行的测试；完整 AX 审计告警、真机 VoiceOver 及精确 iOS 17.0 的限制继续保留。新包独立进行签名归档、资源检查、IPA 导出、上传及分发验证。

## 安装卡住的取证

针对 TestFlight、appstored、installd、installcoordinationd、storedownloadd 进行了 25 秒有界日志读取。捕获到 TestFlight/appstored 的网络端点清理信息及一条 appstored 内存限额告警，未发现能对应到余记构建 14 的下载或安装失败码。该告警没有证据链证明是根因，不能据此判断网络、手机内存或 App 包有问题。日志保存于本地私有 evidence，不提交到仓库。

重发用于重新提供可安装构建，不代表根因已经修复。后续若再卡住，应在重试发生时采集对应任务的失败记录，而不是反复增加版本并声称问题已解决。

## 分发状态

构建 15 签名归档与 App Store IPA 导出通过；归档和 IPA 的 14 项资源检查、严格签名、指定团队、Production 容器与无调试权限通过，dSYM UUID 匹配。IPA 为 4,330,575 字节，SHA-256：`ccd8f2b9ae478a73077a87f39c4b87067baf4c0159f0e6e17c5f6fa3568ea5d7`。当前提交的 [Core 与 iOS build CI](https://github.com/DMLayMan/iOS-accounting-app/actions/runs/38865389545) 均成功。15:12 Xcode 回报上传成功；Apple 已处理完成，构建 ID `f34ffa3b-4ae6-41e8-89a2-2ee3fd55d22a`；已加入原「首发验收」内部组（1 位测试员），测试说明和群组均经刷新回读。当前手机确认仍为 13，App Review 草稿最近确认仍为 13，未提交审核。

## 安装后继续

覆盖安装 15 后，先核对设备版本、帮助页及业务／支付数据保留，再做真机 VoiceOver 听读和焦点顺序。不得使用会覆盖安装 Debug App 的普通 UI 测试清单。Apple 报价反馈与备案按用户要求等待，不重复提交或催办。

私有证据目录：`evidence/reissue15-20261016/`。
