# CloudKit 签名与容器配置

默认 `YUJI_CLOUDKIT_ENABLED=NO`。未签名模拟器包及本地领域测试不会构造 CKContainer，也不会上传账本。真实开启需要由用户提供/登录开发团队；无需在余记注册账号，也不要把 Apple 密码放入仓库或脚本。

`ios-app/project.yml` 是工程唯一声明，`Yuji/Cloud/Yuji.entitlements` 为能力模板。配置项：

| 项 | 默认值 | 要求 |
| --- | --- | --- |
| DEVELOPMENT_TEAM | 7S626H9YL4 | 2026-10-13 从指定账号的 Xcode 团队核对 |
| PRODUCT_BUNDLE_IDENTIFIER | com.dmlayman.yuji | 旧值被 Apple 拒绝；用户确认、Portal explicit ID 与分发 profile 已回读 |
| YUJI_ICLOUD_CONTAINER | iCloud.com.dmlayman.yuji | 已登记并关联新 App ID，Development 与 Production 云 profile/实际 entitlements 核对通过 |
| YUJI_CLOUDKIT_ENABLED | NO | 当前签名候选通过明确构建参数覆盖为 YES；默认交付配置待 schema 与真实云验收后冻结 |
| CODE_SIGN_ENTITLEMENTS | 空 | 云构建指定 Yuji/Cloud/Yuji.entitlements；纯本地构建不申请 iCloud 能力 |
| YUJI_CLOUDKIT_ENVIRONMENT | Debug: Development / Release: Production | 开发、生产数据隔离，不能混用 |

先 `xcodegen generate --spec ios-app/project.yml`，在 Xcode 中选择团队、检查 iCloud/CloudKit 能力及容器，使用签名构建覆盖以上设置。启用云时必须同时指定 `YUJI_CLOUDKIT_ENABLED=YES` 和 `CODE_SIGN_ENTITLEMENTS=Yuji/Cloud/Yuji.entitlements`，并匹配团队、应用 ID、容器和环境。默认空 entitlements 使纯本地版本仍可按原路径签名，不因云模板要求免费个人团队具备 iCloud 能力。可以通过未提交的本地 xcconfig 或 xcodebuild 参数覆盖，不需要修改同步领域代码。不要在运行中的测试批次重建同一 derivedData。

容器初次在 Development 保存会建立 `YujiLedger` record type：`name` String、`formatVersion` Int64、`payload` Asset。系统共享是 `CKShare`；不是另建公开 Team 表。仅访问 private/shared 数据库，默认私有邀请，未设置 publicPermission 为可读/可写。

上架前从 CloudKit Console 部署 schema 到 Production，并重新验收生产构建。团队绑定和 Release archive 只证明对应配置/产物，不证明生产共享可用。2026-10-13 已核对真实容器与关联，生成 1.0 (1) Production 云签名 IPA；Development 已保存并刷新回读 YujiLedger 的 name STRING、formatVersion INT64、payload ASSET，保留 [Console 导出](../app-store-2026-10-13/cloudkit-development.ckdb)与[回读记录](../app-store-2026-10-13/cloud-schema-check.json)。未上传账本、未安装云候选包、未部署 Production。10 月 8 日原始验收 JSON 保留旧标识，新的签名证据见 [发布准备](../app-store-2026-10-13/README.md)。
