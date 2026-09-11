> 历史迭代记录：本文保留当时方案与验收结果，旧界面不代表当前实现。当前基线见 [PRD](PRD.md)、[UI 复刻清单](UI-SPEC.md) 与 [设计规范](../DESIGN.md)。`evidence/` 链接指本机历史材料，不随 Git 分发。

# 真机安装进度

2026-09-10。用户已确认目标为当前连接的 iPhone 12。

- 真机已配对、有线连接，iOS 26.6.1，开发者模式 enabled。
- 本次开发安装使用独立 Bundle ID `com.dmwangkai.yuji.dev`，不改变仓库默认 `com.yuji.app`。
- 真机 arm64 构建（关闭签名）成功：`evidence/device-install/build-unsigned.log`。
- 自动签名构建失败：Xcode `No Accounts`，并且找不到该 Bundle ID 的开发描述文件。日志：`evidence/device-install/build.log`。
- 当前 Apple Accounts 界面为空，已为用户打开登录入口。未读取或代填密码/验证码。
- 尚未安装或启动到手机。未签名的 `.build-device/Build/Products/Debug-iphoneos/Yuji.app` 不能视为可安装交付。

用户在 Xcode 登录 Apple 账号后，确认实际可用的个人签名团队，重新执行自动签名构建，然后使用 `xcrun devicectl device install app` 安装、`device process launch` 启动，并检查安装回执。
