<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <b>FustAI Harness</b> 的 Android 客户端：登录 FustAI 账号后，在本机运行 FustAI 引擎。
</p>

> 本仓库是 [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）的修改版。修改内容、日期与依据见 [MODIFICATIONS.md](MODIFICATIONS.md)。

## 这是什么

FustAI Harness 把 FustAI 引擎装进 Android 手机：聊天、本机执行、插件、技能和定时任务都在手机上运行。桌面端与手机端登录同一个 FustAI 账号即可互通，不需要扫码绑定电脑。

目前只维护 Android。仓库里的 `app/ios/`、`docs/guide/harmony/` 是上游留下的工程与文档，不再随本分支构建或验证。

## 与上游的差异

- 品牌：DSH Go / Deepy → FustAI Harness；包名 `com.fustai.harness`，应用名、图标、启动画面与 URL scheme `fustai://` 一并替换。
- 账号：手机端改为登录 FustAI 账号（App 内 OAuth PKCE + 回环回调），凭据仍存本机 `flutter_secure_storage`。
- 远程连接：删除扫码配对入口；SSH 主机与 Remote 账号连接保留。
- 付费：删除充值 / 余额入口。
- 依赖：移除 `mobile_scanner`，随之去掉 ML Kit 条码扫描与 CameraX；本机 OCR 仍保留。
- 指南：`docs/guide` 与 App 内指南同步改为 FustAI 文案。

## 构建

需要 Flutter SDK（Dart 3.9+）、Android SDK 与 JDK 17。

```sh
cd app
flutter pub get
flutter build apk --release
```

调试包：

```sh
cd app
flutter build apk --debug --flavor x64 --target-platform android-x64
```

文案表由 `app/lib/l10n/parts/` 合并生成；改完 `python app/tool/l10n_merge.py`，再 `flutter build`。

## 许可与署名

- 代码以 [AGPL-3.0](LICENSE) 发布，衍生作品必须继续开源。
- 上游：dsh-Go（作者 ccch1mneyyy），本仓库保留其提交历史。
- 第三方组件与素材的来源、许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 上游 DSH Go 名称、标识与 Deepy / 鲸娘形象不随 AGPL 授权；App 内已全部替换为 FustAI Harness 自有素材。`docs/`、`site/` 中保留的上游营销图仅作来源存档，不可复用。