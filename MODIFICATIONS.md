# 修改说明（AGPL-3.0 §5）

本仓库是 [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) 的修改版，改名为 **FustAI Harness**，只维护 Android 客户端。

- 上游基线：`6db08d2`（2026-11-17 时的上游 `main`）
- 修改方：FustAI
- 修改日期：2026-11-17
- 许可：代码继续以 [AGPL-3.0](LICENSE) 发布。本文件与 `LICENSE`、`THIRD_PARTY_NOTICES.md` 一并保留。

## 改动清单

### 品牌

- 用户可见文案由 DSH Go / DSH-Go / Deepy 改为 FustAI Harness，中文与英文文案表同时替换（`app/lib/l10n/parts/`，合并到 `app/lib/l10n/gen/`）。
- 应用名、包名、URL scheme 改为 FustAI Harness：`com.fustai.harness`、`fustai://`；Android 工程目录与 Kotlin 包路径同步迁移。
- 应用图标、启动画面、引导图与品牌标记替换为 FustAI Harness 自有素材；上游 Deepy / 鲸娘形象不再使用。
- 删除内置宠物包：`app/assets/pets/` 不再随 APK 打包，宠物默认**不显示**，选择器里只有已带回的宠物、**不显示**和**导入**；伙伴小屋、Android 桌面小组件和鸿蒙桌面卡片统一显示 F 字标，小组件名称改为 FustAI；伙伴小屋的默认人格、小屋背景里的鲸鱼剪影和「鲸尾／Whale tail」等界面词条一并去掉鲸鱼娘设定。
- 用户产出目录由 `Download/DSH-Go` 改为 `Download/FustAI`（Android 仍只读兼容旧目录）；Android / HarmonyOS / iOS 的 guest 工作区产出目录统一为 `<home>/workspace/FustAI`。
- 插件槽位 `dsh-go.panel` / `dsh-go.chat` 改为 `fustai.panel` / `fustai.chat`（`app/lib/plugins/seams/slot_catalog.dart`、`app/assets/islands/recipes.json` 及对应技能、测试、文档）。
- `docs/guide/{zh,en,harmony}` 与 App 内指南同步改名，并重新生成 `app/assets/skills/dsh-go-guide/`。
- 关于页保留上游作者与个人主页，标注为「上游项目原作者」；新增「本项目」分组，链接本仓库源码与本文档。标语与页脚声明改为 FustAI 自有文案（`app/lib/ui/settings/about_page.dart`、`app/lib/state/app_info.dart`）。

### 功能

- 账号：手机端改为登录 FustAI 账号，App 内完成 OAuth PKCE（S256）与回环回调；`accountApiProvider` 切换到 `FustAIAccountApi`，新增登录门 `app/lib/ui/shell/root_gate.dart`。
- 远程连接：删除扫码配对页面与入口（`app/lib/ui/remote/pairing_page.dart`、`app/lib/state/remote_pairing_state.dart` 及对应测试）；SSH 主机与 Remote 账号连接保留。
- 付费：删除充值 / 余额入口与相关文案。
- 依赖：移除 `mobile_scanner`，APK 不再包含 ML Kit 条码扫描与 CameraX；本机文字识别（OCR）保留。

### 未改动的部分

- 引擎、Remote 协议、插件运行时、技能加载、定时任务等核心逻辑沿用上游实现。
- 上游提交历史完整保留，便于追溯每一处改动。

## 上游品牌与素材

上游 DSH Go 的名称、标识、Deepy 与鲸娘形象不在 AGPL 授权范围内（见 [ASSETS.md](ASSETS.md)）。本仓库的 App 不使用这些素材；`docs/`、`site/` 内保留的上游营销图仅作来源存档，不可复用或再发布。