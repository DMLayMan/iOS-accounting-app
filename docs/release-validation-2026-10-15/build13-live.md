# 构建 13 真机与真实昵称异常验收

2026-10-16，实际 iPhone 12 TestFlight 1.0（13），Production；B 为另一真实 iCloud 账号的 Mac Catalyst 原生服务验收端。不是第二台 TestFlight iPhone，不把本轮结果扩展为同账号多物理设备已验证。

## 已通过

- 设备清单与帮助页核对版本 13。独立 UI runner 没有 AUT 安装路径或 App 构建依赖，未覆盖安装 Debug 包。
- 升级后业务实体与昵称资料保持；QA 仍 8 笔、¥666.99；支付文件、打赏触发文件字节相同，云绑定仅更新最后同步时间。
- 支持页实际三档报价可见，选择后按钮金额一致，刷新可用，关闭重开清空选择、不出现历史购买拦截。没有触发购买。
- 本人开启手机飞行模式并关闭 Wi-Fi 后，工具保存临时昵称。页面保留并显示“已保存在本机，待同步到 iCloud”；关闭 App 再打开后，输入值和待同步状态仍在，磁盘回读相符。
- 本人恢复网络后，手机昵称 pending 清除，共享成员发布版本与本机版本一致；B 通过真实 Production 获取共享资料并确认新昵称。
- 通过手机界面恢复本轮开始时的原昵称，B 再次读取确认恢复。没有恢复昨天的旧偏好，也没有修改 B 的昵称。
- 最后 9 项保护检查全部通过：所有业务实体、创建人/最后编辑人、草稿不变；原昵称与账号/云姓名恢复、pending 清除；支付和邀请文件字节相同、其他云绑定保持、B 昵称保持。B 每阶段均确认普通 Mac 数据文件未变。

手机支持页初次与本人取消后重开共 2 次执行、昵称离线/重连/恢复 3 次执行，均通过且无跳过；B 基线/新昵称回读/恢复回读 3 次执行均通过。重复测试及参数化多阶段执行不累计成 8 个不同测试用例。

## 未关闭的价格问题

刷新后的真实目录仍为 US$0.99、US$2.99、US$3.99。本人已确认媒体与购买项目地区中国大陆；在构建 13 选择「小小鼓励」后，亲见 Apple 系统确认页显示 ¥6，随后取消。系统金额来自本人反馈，未取得该确认页的工具截图，测试环境标志也未单独报告。只读回收发现没有新增验签交易，已有收据日志语义、账本与打赏邀请均未变；旧构建 7 的 CNY 收据不能冒充本轮新交易。

因此当前包的应用报价与系统确认页币种不一致已复现，价格发布门槛未通过。SDK 已监听 Storefront 更新、重新请求商品、核对请求前后 storefront、商品币种及付款前 storefront，并设置 onStorefrontChange；这些基于目录 API 的检查没有消除本次差异。不能由 USD 推断购买账号美区，也不能宣称正式 App Store 不受影响。

[Apple 技术反馈草稿](apple-storekit-feedback-draft.md)已追加构建 13 观察，已按本人授权实际提交，编号 [FB25209457](https://feedbackassistant.apple.com/feedback/25209457)，正文已回读、0 附件；Apple 处理结论待回覆。不含交易 ID、账号邮箱、token 或个人账目。

取消后的瞬时返回没有捕获：观察工具激活 App 时已经处于「我的」，支持弹层已关闭，故原断言失败；无法据此判定由用户关闭还是应用自动关闭，不记为即时取消返回通过。随后无购买的重开检查 1 次通过：三档可选择、按钮金额一致、刷新可用、再次关闭重开无历史拦截。最终财务业务、昵称、收据日志和打赏邀请语义均与原昵称恢复后的快照一致；云绑定仅最后同步时间变化，不能称整份 ledger 相同。

## 原始失败与恢复

1. 支持页第一轮驱动返回“我的”后，顶部入口因列表虚拟化暂不在 AX 树中，脚本反向滚动，未进入支付页。改为朝已知顶部寻找后通过。
2. 首次切网后输入框未取得键盘焦点，测试在输入/保存前停止；磁盘核对原昵称、账目、草稿未变，立即请本人恢复网络。工具补充联网焦点预检、人工切网后重新激活 App、键盘可见断言，再完成真实断网重试。原失败与成功日志都保留，未删失败来制造全绿。

## 证据与余项

私有证据目录 `evidence/ux13-20261016/`：

- `phone13-installed.json`、`phone13-upgrade-data-verification.json`；
- `phone13-support-r2.xcresult` 与实际报价截图；
- `phone13-nickname-offline-r2.xcresult`、`phone13-nickname-reconnect.xcresult`、`phone13-nickname-restore.xcresult`；
- `b13-{baseline,reconnect,restored}.xcresult` 及每阶段独立快照；
- `phone13-offline-data-verification.json`、`phone13-final-data-verification.json`（9 项全通过）。
- `phone13-human-price-verification.json`：本人口述系统金额与取消、5 项只读数据核对；没有新增付款。
- `phone13-human-cancel.xcresult`：未捕获即时取消返回的原始失败；`phone13-postcancel-reopen.xcresult`：重开通过；`phone13-postcancel-safety-normalized.json`：最终业务与收据不变、云绑定仅 lastSync 变化。原全文件检查 `phone13-postcancel-safety.json` 保留，未将正常同步时间更新误判为数据损坏。

本轮未改生产源码、完成购买、删除账目、切换账号或提交 App Review。当前运行时清单只有 iOS 26.5 与 27.0，因此 iOS 17 实际运行仍未验证；同账号多物理设备、人工 VoiceOver、价格异常、SDK 自身 CI 计费限制与备案继续单列。最新状态见 [validation-status.json](validation-status.json)。
