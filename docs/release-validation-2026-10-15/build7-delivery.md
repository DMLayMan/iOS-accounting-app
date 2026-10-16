# 1.0（7）：重复打赏入口修正交付

2026-10-15。用户要求每次打开都直接选择最新金额，可重复主动支持，不管理历史待确认状态。功能、设计和本地验证见 [修正记录](repeat-support.md)。

## 分发结果

- 本人解锁Mac后，Xcode Organizer完成上传。ASC已处理，build ID为b5f0cb37-6c5c-4ece-869f-450e47828447。
- 仅加入原「首发验收」内部群组，仍1位测试员，独立测试员0；未扩大权限或公开测试。
- 说明在testflight-build7-notes.txt，已保存并刷新回读正文完全相同，群组和人数亦回读。初次含咖啡符号的说明被Apple拒绝为无效字符，改为纯文字后保存成功；App入口文案没有因此改变。
- 用户已确认App内1.0（7）；devicectl实际安装清单也回读bundleVersion7。不能根据其builtByDeveloper标记推断Debug安装：本轮只上传TestFlight，真机测试runner没有AUT安装路径或Yuji.app依赖。独立真机用例已从帮助页核对7并验证进入/选择/关闭重开，1条通过；这不等于真实付款通过。
- 未提交App Review，商店版本草稿未改，备案继续等待。

## 源码与分发包

canonical构建号7，SDK远端固定4f573f2fee49e30626ef702af0db72eb6e71ebac（原PR#4未合并）。111个构建源码/资源/测试/验证脚本的完整快照与逐项哈希保存于私有evidence，tar解包验证通过；归档后源码无漂移。App工作树仍保留既有修改，不能只凭旧HEAD复现候选。

真实App Store导出IPA为4,030,676字节，严格codesign、资源、团队/Bundle/Production容器和get-task-allow=false通过。SHA256：4274f9e0f87420662bf398878bde33c980092f328e8f3880d7dff2ab36a6be82。构建前后source锁与实际SDK解析一致，无源码复制进宿主。

## 验证边界

SDK43条Swift＋7条原生harness、宿主22条专项及根161条测试已通过；不能把本地StoreKit当成新TestFlight真人购买。新版真机先检查打开、选择不付款、关闭重开，历史锁不再影响入口。真实再次付款没有代用户执行；收据仍按环境和transactionID去重、验签持久化后finish。

上传前正常Application Support已只读备份至私有build7-device-before；真机原生UI使用独立runner13，只activate，不调用launch中断支付、不覆盖安装App。独立真机用例1条通过。进入/重开后support.json与邀请文件字节相同；业务实体均相同，ledger仅cloudLinks[1]的lastSync/version变化。用户随后亲自点击「请一杯」报告卡住；不激活/重启/点击的runner14已观察到.purchasing等待和系统未呈现确认页。此诊断用例不计入功能回归通过数。详见 [构建7付款卡住](build7-iap-hang.md)。


后续本人完成账号登录后确认整体支付正常。两笔新增18/CNY/Sandbox收据已回收、原收据保留；但登录后新的进入/重开仍展示USD，价格一致性未通过。独立观察和重复进入用例只按同一场景记录，不叠加为多个覆盖点。最新结论见 [故障及回收](build7-iap-hang.md)。
