# 私有依赖的 CI 读取配置

2026-10-16：App PR #3 的远端 Core 测试通过；macOS 任务 run 38847596313 在拉取 `DMLayMan/ios-base` 时以 `Permission denied (publickey)` 失败。SDK 仓库为 Private，App 仓库当前没有 Actions Secret。这与 SDK 自身 PR #4 的计费限制是两个独立问题。

用户已于 2026-10-16 明确授权，并已完成配置：为 `ios-base` 创建独立、只读 Deploy Key（名称 `Yuji Actions read-only 2026-10-16`）；私钥仅存入 App 仓库的 Actions Secret `IOS_BASE_READONLY_DEPLOY_KEY`。回读确认 `read_only: true`、Secret 存在；本机临时私钥、公钥已删除。未使用个人密钥，未授予写权限，未改变仓库可见性。原有其他 Deploy Key 保留。

`.github/workflows/ci.yml` 和 `scripts/build-ci.sh` 已接入上述配置。提交 `909c1b7` 的 [远端 run 38848436338](https://github.com/DMLayMan/iOS-accounting-app/actions/runs/38848436338) 已完成：Linux Core、macOS 域与状态测试、iOS App 和原生测试目标编译全部通过。后续产品源码提交仍需检查对应的新 run。

工作流只在构建步骤暴露凭据，使用临时 0700 目录，结束后清理；通过 HTTPS 取得 GitHub 官方 host key，SSH 严格校验，系统 Git 拉取固定提交。Fork PR 不接收 Secret、原生构建明确失败，不能把未执行写成成功；不使用 `pull_request_target`。

该权限允许受信任的 App 仓库工作流读取整个 `ios-base` 仓库，因此启用需要明确许可。仓库写权限持有人可能修改工作流使用凭据，应只让可信维护者提交/运行。Deploy Key 无自动到期时间；不再需要时同时撤销 SDK Deploy Key 和 App Actions Secret。

依据：[GitHub 官方 Deploy Key 文档](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)。
