# 构建7：「请一杯」后等待，Apple确认页未出现

2026-10-15。用户澄清已点击底部「请一杯」，并非只点击商品。按真实支付故障处理；不改变商品行的选择语义，不再让用户重复尝试付款。

## 最新回收：登录恢复，价格目录与收据仍不一致

本人随后确认卡住因登录问题，完成登录后整体链路正常。只读复制App独立支持日志回收：原1笔收据完整保留，新增2笔coffee，每笔均已验签、持久化，Sandbox、18/CNY、有当次attempt关联；邀请文件字节相同，业务数据根键仅cloudLinks变化。系统也记录15:26:30和15:28:15两次购买完成。没有代理发起新购买，不需要本人继续反复付款。

此前挂起的调用最终返回认证失败，含`ExpiredLongLivedToken`、AMSErrorDomain100及账号不支持密码复用，和本人登录恢复一致。不能声称App能绕过Apple认证或保证其同步耗时。

**价格展示仍未关闭。** 登录后重新拉取/关闭重开的独立真机检查通过，仍展示US$0.99/US$2.99/US$3.99；同一时期新交易已是18/CNY。runtime Storefront也仍USA。不能再把美元解释成“实际付款身份就是美区”，也不能以目录和Storefront相互一致宣称系统页/收据必然一致。

公开一手线索：[Apple论坛同类TestFlight目录/系统页币种不一致报告](https://developer.apple.com/forums/thread/847397)、[TestFlight返回USA的DTS回复](https://developer.apple.com/forums/thread/794932)。前者是开发者报告，后者建议提交Feedback；不是Apple对本App根因的确认。刷新无效已在本机复现，不能承诺重启或换构建号能修好。未切换StoreKit1、强改货币符号、用设备地区或旧收据价格猜当前报价。

私有新证据：build7-after-auth-payment-summary.json、build7-device-after-auth、build7-after-auth-system.logarchive及distribution-driver/build7-after-auth-fresh-catalog.xcresult。两笔实际支付回收已完成；真实系统取消仍需独立记录，人民币目录/系统金额一致仍是发布待关闭项。

## 已验证事实

1. 用户已确认1.0（7），设备清单及独立runner13从原生帮助页再次核对。进入支持页、选择不购买、关闭重开无预选及历史锁，1条真机测试通过。用户接受重开动线。
2. 用户亲自点付款后，runner14仅读取屏幕、App状态及AX树，不activate/launch/terminate/点击。15:17 App仍为原PID1614、前台，`support.purchase`为「正在等待 Apple 确认」、禁用，选中coffee，三档USD；Apple确认页没有呈现。此用例是诊断取证，不是支付验收通过。
3. 系统归档日志：15:11:46 App调用StoreKit购买；15:11:47系统storekitd发往Apple Sandbox购买端点并收到HTTP200，随后请求交互式账号认证，提示标题为「需要登录」。appstored转交AuthKit；后续未见该次调用返回。HTTP200不代表支付成功、取消或已扣款。
4. 同批系统有AuthKit账号上下文错误及认证资料缺失；只能定位认证等待阶段，不能单凭这些旁路错误确定最终根因。未证明由App呈现上下文、具体账号、网络或Apple服务端哪一项导致。
5. App运行时Storefront明确为USA/USD；ASC刷新回读现有Sandbox账号地区为中国大陆。仅凭后台配置不能断言TestFlight当前正在使用此账号，也不能将USD强制替换为人民币。
6. 本轮没有代用户购买、清交易历史/日志、退出账号、覆盖安装、重启App或删除云QA账本。原收据和频控保留。

## 已确认的客户端体验问题

购买按钮在disabled状态保留白色spinner，系统禁用背景也很浅，真机截图几乎只剩空白块。等待没有可见文字，长期认证无说明。SDK本地修正为可见阶段文字与中性spinner；15秒仍未返回时，显示可关闭、结果继续自动接收、不自动重付的内联提示。15秒仅控制提示，不取消StoreKit任务，不判定失败或未扣款，不解除真实在途调用的连点保护。

该修正本地44条Swift、Pro4/SE2原生专项与Release编译通过，截图已复看；首轮本地目录准备失败保留并复测。未包含在TestFlight7。它改善故障反馈，不能宣称修好Apple认证/币种；真实付款已由本人和两笔收据确认，真实系统取消尚未单列验收。

## TestFlight与Development账号路径不同

[Apple官方Sandbox测试说明](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)区分两条路径：Development签名App可保持正常购买账号，仅在Developer登录Sandbox；TestFlight始终使用Sandbox环境，但若要强制使用指定Sandbox账号及控制项，需退出Media & Purchases的正常账号，再在Developer登录Sandbox。正常购买账号重新登录后，TestFlight归属也会切回。

此前把“不用退出正常购买账号”的Development操作直接套到TestFlight不充分，现予纠正。退出Media & Purchases可能影响既购内容访问；当前没有授权切换日常购买账号，不执行。先只请本人回读媒体与购买项目的登录状态/地区，不索取密码或验证码。

研判：运行时USA与后台中国大陆之间的差异，需要核对TestFlight有效购买身份或地区回落，不能通过改币种字符处理。认证为什么未弹出仍待核实。SwiftUI推荐的PurchaseAction与现有Product.purchase均属Apple公开接口；没有足够证据就把替换API宣称为根因修复。

## 私有证据与下一步

`evidence/release-20261015/`保留build7-stuck-processes、live-syslog、system.logarchive.tar及解包归档、filtered/auth-context/authkit日志；包含设备/账号关联信息，不提交公开仓库。独立观察结果在distribution-driver/build7-inflight-observation.xcresult与attachments；原始截图不加工。

下一步：本人仅回读购买账号登录状态/地区 → 确认是否需要本人完成已有账号认证 → 回收同一调用结果后再决定是否重启或开启新测试。新SDK等待反馈已完成本地正常/小屏、深色大字、延迟回执、正常购买/取消专项；未推送、未升级宿主、未上传新包。价格一致性与等待UI分开处理，不因UI通过宣称币种问题已关闭。
