# 外部共享邀请弹层崩溃复审

2026-10-15 用户反馈：共享后打开 App 闪退。这是送审阻塞；当前手机 TestFlight 1.0（4）还没有修复。原始报告仅存私有 evidence，不上传用户机器信息。

## 证据与归因

Mac 两份报告发生在 12:01:22、12:15:48，均 EXC_BREAKPOINT / SIGTRAP，主线程依次为 EnvironmentObject.error → EnvironmentObject.wrappedValue → PresentationTheme.body，原 Design.swift 第 161 行。经过脱敏的栈见 [记录](sharing-presentation-crash.json)。iPhone 的 systemCrashLogs 按 Yuji 过滤返回 0 文件，仅表示本次接口没有返回对应文件，不能据此证明手机从未闪退。

之前隔空投送后看到普通首页，是后续工具重新启动 App 后的状态；缺少邀请页不能单独归因为网络或 Development/Production 路由。两套环境仍需核对，但实际崩溃有独立证据。

原实现：yujiSheet 将 PresentationTheme 附加在系统创建的弹层中；主题在新呈现边界读取隐式 AppState，外部分享回调触发全局 sheet 时可能缺失，导致 fatal assertion。普通设置/记账 sheet 通过不覆盖这个入口。

## 修复

布尔和 Identifiable 两种 yujiSheet 共用 ThemedPresentationRoot。呈现侧 ViewModifier 在 body 中先读取并捕获 AppState；系统创建弹层时传入同一个实例，由根观察状态、重新注入业务对象并解析主题与中文 locale。主题组件不再依赖呈现边界里恰好存在的隐式对象。不吞异常、不创建新的空 AppState、不关闭共享来避开问题，也不增加新的用户弹窗或操作。

## 验证与剩余

- Mac 原生 3 条通过：无任何外部环境注入的根、布尔 cold sheet、item cold sheet；核对同一对象身份与中文 locale。
- 完整模拟器回归实际退出 0：135 通过、24 项显式专项跳过、0 失败，覆盖修改后的共同呈现通道；冻结构建的旧 SDK 与后续构建 5 的 21 条专项分别记录，不相加冒充同一构建全测。
- 真正外部邀请复验已通过：解锁后先发现仍运行 12:15 旧进程（文件已在 12:29 更新），完整退出并核对 12:53 新进程后重发同一个邀请，实际显示指定 QA 账本并接受成功。B 为不同真实 Production 账号，下载 1 笔 1234 分，version/lastSync 非空、cached/base 相同；后续独立远端读取也通过。未创建重复邀请或重置正常库。
- 候选 1.0（5）固定新 SDK 5a15573，21 条支持/邀请/弹层宿主测试通过；归档及其资源、签名与 Production entitlement 检查通过。CLI 导出报 No Accounts / 无本地 Distribution 证书，保留失败，Organizer 上传后 ASC 处理完成，已进入既有内部群组。最后确认的手机 TestFlight 4 和商店草稿所选 4 仍不包含修复，新候选不能算已安装。

## 防复发

外部 URL、CloudKit callback、通知和冷启动呈现单列为入口矩阵；不是导航内任意打开一次同页就算覆盖。环境依赖在呈现侧捕获并显式传给 portal 根，禁止在缺少依赖时悄悄创建空业务状态。收到闪退反馈先回收 ips，再重新启动；不得因重启后首页正常就把崩溃解释成账号或路由问题。

更新磁盘上的 App 不会替换已在内存中的进程。重验前检查窗口是否有未保存内容，安全退出仅用于 QA 的接收端，再按精确路径启动；核对进程路径、启动时间晚于二进制更新时间和签名环境，然后才让用户重发。保留旧进程导致的无效重发记录，不把它算成新代码失败，也不反复向用户索要同一链接。
