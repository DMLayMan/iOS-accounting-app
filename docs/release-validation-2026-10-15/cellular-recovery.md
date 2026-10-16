# Production 网络恢复与构建安装回读

2026-10-15，北京时间 13:40–13:43 回读。属于同一隔离 QA 批次，不创建新账本、不重复 B-add、不清理任何云数据。

## 已通过

此前 A 真实同步失败时保留 1 笔 1234 分及明确连接错误；用户报告切蜂窝后，独立无 AUT 的真机 UI runner 冷启动同一账本并点击立即同步，13:41:20 收到实际同步结果。回看原生截图状态栏仍有 Wi-Fi 图标，因此仅判定真实连接失败后的恢复，不判定纯蜂窝链路验收通过，也不推断 Wi-Fi 是否在期间重连。UI 显示累计净支出 ¥32.34；手机落盘为 2 笔、3234 分、cached/base 相同、无 issue/incoming。

B 随后以不同真实 iCloud 身份执行 Production scoped 同步和独立远端回读，也得到 2 笔、3234 分，无 pending/issue/conflict，正常 Mac 文件指纹不变。B→A 成员写入及 A 连接失败后的恢复已通过；A→B 编辑、无线关闭期间双端写入、冲突、权限与撤销的完整矩阵仍待完成，不合并宣称双向全验收。

个人数据安全：原 1 个 Development cloudLink（含缓存）逐项相同；原 1 笔已验证支付收据逐项相同；旧 unresolvedProduct 保留。整个 ledger/support 文件因为合法验收数据与待确认状态不同，不能称为整文件不变。

## 构建 5 尚未实际安装

用户曾报告已更新到 5，但设备安装清单两次及 App 内「我的 → 帮助与反馈」均显示 1.0（4）。TestFlight 列表和详情显示可用 1.0 Build 5，实际操作状态为「正在下载」，截图已留存。**可用版本不等于已安装版本，观察测试通过也不等于构建 5 验收通过。**

本次云恢复证据属于实际构建 4，不能给 5 的支付修复背书。本人后续反馈仍在下载或有错误；先处理下载，不卸载 App、不切换 iCloud/媒体购买账号、不再次付款。后续必须从 App 内版本及真实服务行为重新确认 5。

## 私有证据索引

所有原始文件位于忽略目录 `evidence/release-20261015/distribution-driver/`，不提交个人账本或收据：

- `a-cellular-owner-sync.xcresult` / 日志 / summary：实际 UI 同步、账本总额通过。
- `a-cellular-recovered/readback.json`：2 笔 3234 分、05:41:20Z、无问题。
- 同目录 `personal-data-readback.json`：原 Development 缓存与收据保留。
- `b-after-cellular-recovery.xcresult`：B scoped 服务回读通过；摘要拷贝在 `b-production-accepted/sync-after-cellular-summary.json`。
- `current-version-detail.xcresult` 与附件：App 内 4、TestFlight 可用 5/正在下载，同一次回读。
- `installed-build5.json` / `installed-build5-after-observe.json`：安装清单仍为 4。

测试 runner 的清单逐次检查无 UITargetAppPath、无 Yuji.app 依赖，只操作已安装包；未安装本地 App 覆盖 TestFlight。构建与运行完成后顺序读取结果包。

下载处理补充：13:45/13:47 重启 TestFlight、点击下载进度后系统显示“继续”；自动 runner 找到控件但不可点击，未假报下载或安装完成。已请求本人点“继续”，保留当前数据，不卸载、不改账号、未再次付款。该观察场景的 XCTest passed 只表示观察步骤完成，不是安装成功。
