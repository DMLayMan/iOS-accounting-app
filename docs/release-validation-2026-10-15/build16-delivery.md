# TestFlight 1.0（16）：最终视觉与动线打磨

2026-10-16。用户要求将已完成的 UI 优化提供到 TestFlight，同时更新发布材料。本轮不提交 App Review，备案与 Apple 价格反馈继续等待。

## 源码与变更

源码提交 `af89f013529cc87f5f12fafb3b114ec52a53e5d0`；营销版本 1.0，构建号 16，SDK 仍固定 `97f38bb1b9aa31cae0f469a58a37e1641aa8870f`。代码已推送到原 [PR #3](https://github.com/DMLayMan/iOS-accounting-app/pull/3)，没有合并分支。该提交 [CI](https://github.com/DMLayMan/iOS-accounting-app/actions/runs/38880971126) 通过。

统计摘要更紧凑，默认记账人菜单并入净支出标题；流水备注与元信息分行，详情完整左对齐；我的合并分组、偏好前移并修复小屏底栏遮挡；记账金额字形与收支选中提示统一；账本辅助功能字号标题、操作纵排。保持用户确认的期间组件、两级分类、中间记账及统计同页下钻。

本轮没有修改财务计算、schema、云权限、人员身份或支付 SDK。详见 [设计复审及前后截图](../final-polish-2026-10-16/README.md)。

## 验证与数据保护

复用刚完成的相同产品代码验证：181 条 portable、69 条原生测试及 21 个不同 UI 用例，覆盖实际 iOS 17.5 模拟器、SE 小屏、深色及最大字号；原始失败及修复重验均保留。10 条 opt-in 原生用例跳过，不算通过。新增构建号不改变产品代码；不重复执行完整业务测试冒充新增覆盖。

已从连接的 iPhone 12 只读备份当前 Application Support 的 3 个文件，全部 JSON 可解析并冻结 SHA-256。未安装 Debug App、删除账本、切换账号或付款；真机新 UI 安装/体验仍待用户完成。

## 正式包

从干净 Git 快照生成工程，签名归档与 App Store IPA 导出成功。指定团队 `7S626H9YL4`，Bundle ID `com.dmlayman.yuji`，容器 `iCloud.com.dmlayman.yuji`，Production 环境。归档和导出 IPA 分别通过 14 项资源检查；导出包严格签名验证通过、`get-task-allow=false`，二进制与 dSYM UUID 一致。

IPA 大小 4,354,841 字节；SHA-256 `7ad977cad037512ef9f5ffe3623c30dc559d6c9edea2b3ad96649b6928d17184`。Xcode 于 17:35:52 回报上传成功。Apple 后台二进制状态已验证，最低 iOS 17.0、Production entitlement 和无调试权限回读一致。1.0（16）已处理完成，加入原“首发验收”内部组（1 位测试员）；测试说明保存后刷新回读一致。手机安装尚未确认，分发成功不等于真机验收通过。

私有证据目录：`evidence/build16-20261016/`。商店截图仅使用新建隔离模拟器和合成账本。最初未签名的模拟器 Release 缺少 CloudKit entitlement 导致启动失败，手工补签也未能启动；保留失败日志，改用 Xcode 正常签名构建，不据此改动产品代码或正式分发包。

## 后台材料与源码交付

- [TestFlight 构建 16](https://appstoreconnect.apple.com/teams/2c0964be-2cd0-43f8-b3f4-0484a39b53b5/apps/6822126066/testflight/ios/678b0a74-77a8-40f9-a817-a263b0cad217)：build ID 678b0a74-77a8-40f9-a817-a263b0cad217，原内部群组与[测试说明](testflight-build16-notes.txt)回读一致。
- [五张新版商店截图](build16-screenshots/README.md)：记账、统计、预算、账本、流水，1206 × 2622、无透明通道。独立模拟器上的 Release App 拍摄，两个截图用例通过（0 失败、0 跳过），不接触个人账本；原始文件 SHA-256 可追溯。
- App Store 1.0 版本关联构建 16，五张新图和顺序刷新后核对通过；旧图只解除当前版本关联，仍保留在素材库。
- [审核说明](app-review16-notes.txt)已保存并与网页字段逐字核对；联系信息保留、无需 App 登录、手动发布。
- 17:48 回读原审核草稿：App 1.0（16）与三档 IAP，共 4 项；最终“提交以供审核”未点击。未新增群组或受邀账号。
- 本地设计文档、原生对照图集及机器可读状态同步更新，继续在原 PR #3 交付；正式 IPA 来自 af89f01，后续材料提交不改变二进制。

原始后台证据：evidence/build16-20261016/testflight16-verified.png、review-draft16-verified.png。备案及 Apple 价格反馈 FB25209457 未操作；未切换购买账号、未执行购买、未代替真机 VoiceOver 听读。App Store 正式提交仍有这些独立门槛，不能由本次分发推断全部通过。

## 验收及恢复

覆盖更新，不卸载；在“我的 → 帮助与反馈”确认 1.0（16）。优先检查期间/人员筛选、流水与长备注、记账键盘和取消、我的入口与主题。实际 VoiceOver 听读由用户暂缓，不再重复请求。

若升级后出现数据或同步异常，先保留现场、回读本轮升级前备份与日志，不重置库或盲目重复操作。旧 TestFlight 构建保留；需要恢复数据时先比较并取得明确授权，不自动用旧快照覆盖新记录。
