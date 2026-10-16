import SwiftUI

/// The same Markdown is bundled offline and maintained as the public-policy source.
struct PrivacyPolicyView: View {
    private var blocks: [String] {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["隐私说明暂时无法读取，请在帮助与反馈中联系我们。"]
        }
        return text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    if block.hasPrefix("# ") {
                        Text(String(block.dropFirst(2))).font(.title2.bold())
                    } else if block.hasPrefix("## ") {
                        Text(String(block.dropFirst(3))).font(.headline).padding(.top, 6)
                    } else { Text(block).font(.body).textSelection(.enabled) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }.navigationTitle("隐私说明").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("about.privacy")
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("数据在这里") {
                Text("账本保存在本机，无需登录。换机或删除 App 前，请生成备份，并在系统分享面板中保存到文件。")
                NavigationLink("备份、恢复与导出") { DataManagementView() }
            }
            Section("记账与核对") {
                Text("新建记录关闭或退后台时保留草稿；点击保存后才计入流水和统计。编辑原记录时，取消不会改动已保存内容。")
                Text("当前余额与统计截至今天。未来日期的记录可在流水中查看，并在发生日期计入余额。转账不计入收支，退款冲减支出。")
            }
            Section("iCloud 与共同记账") {
                Text("在账本名称旁打开同步与成员，可逐账本开启 iCloud，并用系统私有邀请共同记账。未配置 iCloud 的安装包仍可纯本地使用。")
                Text("草稿、主题和其他账本不共享。离线修改先保存本机；遇到冲突会保留两个版本。暂停自动同步不等于退出共享；退出前先保存独立本地副本。备份恢复为本地数据，不自动恢复云绑定。")
                NavigationLink("iCloud 与共享") { CloudOverviewView() }
            }
            Section("分类与预算") {
                Text("每笔收入或支出选择一个二级分类，一级用于组织和汇总。分类可编辑或归档；备注仅保留说明，不参与搜索。")
                Text("月预算与年预算独立，留空表示不设置，0 表示零支出计划。退款返还发生期间的额度，超预算仍可记账。修改预算保留历史周期。")
            }
            Section("反馈问题") {
                Text("请说明操作步骤、预期结果、设备和系统版本。公开反馈前请隐藏个人信息，无需上传真实账本。")
                Link("打开项目反馈页", destination: URL(string: "https://github.com/DMLayMan/iOS-accounting-app/issues")!)
                    .accessibilityIdentifier("about.support")
            }
            Section("版本") {
                Text("余记 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")（\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")）")
            }
        }.navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
    }
}
