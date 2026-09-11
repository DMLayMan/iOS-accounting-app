> 历史迭代记录：本文保留当时方案与验收结果，旧界面不代表当前实现。当前基线见 [PRD](PRD.md)、[UI 复刻清单](UI-SPEC.md) 与 [设计规范](../DESIGN.md)。`evidence/` 链接指本机历史材料，不随 Git 分发。

# 设计技能安装记录 · 2026-09-10

用户授权：查找开源 PM/UI 美感 Skills，自行挂载并应用到全页面 review + 优化。

| 技能 | 主仓库 / 路径 | 固定版本 | 本机位置 |
|---|---|---|---|
| Impeccable 4.3.1 | https://github.com/pbakaus/impeccable · plugin/skills/impeccable | 67d018fe052853c104a96d441ce175dd5ec4c39d | ~/.codex/skills/impeccable |
| Opportunity Solution Tree | https://github.com/phuryn/pm-skills · pm-product-discovery/skills/opportunity-solution-tree | 18468a95b427e70e258b51389796367c6f684e7d | ~/.codex/skills/opportunity-solution-tree |

先查看 skills.sh 目录与主仓库，识别旧 frontend-design 别名已弃用；只安装目标技能，没有批量引入全部 PM 插件。通过系统 skill-installer 的 git 方法安装，安装结果已读回；Impeccable launcher 经源代码检查后运行 context，下载使用其固定版校验机制。未修改全局 hooks。技能可在下个对话回合被发现，本轮已经直接读取并应用。

已读取 Impeccable 的主技能、craft-floor、critique、operate、ios、audit.native。原生技术审查遵循 audit.native：浏览器/CSS detector 不适用于 SwiftUI；以源码审查、XCUITest 和 Simulator 截图取证。Assessment A 与 B 独立完成，见同目录评审文件。

## 本次产品推导

目标：用户能在连续上下文内迅速完成记录和追查支出。

| 用户问题 | 比较过的方案 | 本次选择与验证 |
|---|---|---|
| 新增分类时不知道图标和名称最终长什么样 | 全屏表单 / sheet 再套图标选择 / 一个 sheet 内图标与名称 | 一个 70% sheet；预览、填名、选图标、保存；验证读回与立即选中 |
| 从图表追查支出却不断丢上下文 | push 多层 / 明细 sheet / 同页联动 | 同页联动；点击一级后二级与流水同时响应，单笔返回保留筛选 |
| 根入口与详情动作争抢注意力 | 全局悬浮 + / 将动作伪装为 Tab / 根内容安全区记账按钮 | 保留系统四 Tab，记账动作只出现根内容；验证详情没有覆盖按钮 |

这是根据用户反馈做的定性优先级判断，没有虚构机会评分、访谈人数或效率提升百分比。长期满意度仍需实际使用验证。
