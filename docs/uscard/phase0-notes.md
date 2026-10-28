# 阶段 0 笔记：克隆、编译、改名

## 上游版本
- 上游仓库：https://github.com/Lingyan000/fluxdo.git
- 克隆到的提交：`bc5a04b0fc09bde915415e2ab345bc24c8c8146c`（v0.2.29 changelog 提交，`main` 分支）
- 子模块：`core/doh_proxy` @ `660a19b3`，`packages/fluxdo_render` @ `5bfd16be`

## 工具版本
- Flutter 3.47.4（`C:\src\flutter`，`git clone -b 3.47.4 --depth 1`），Dart 3.13.3
- Visual Studio 2022 Community 17.14（C++ 桌面开发，Windows 10 SDK 10.0.26100）
- Rust 1.99.1 stable（rustup）、just 1.59.0、melos 8.10.0、NuGet（winget `Microsoft.NuGet`）
- `flutter doctor`：Windows、Visual Studio 项为绿；Android 工具链未装（本阶段不需要）。

## 遇到的问题与修法
1. **克隆**：先 `git config --global core.longpaths true`，否则 Windows 长路径会丢文件。本次克隆无缺失。
2. **GitHub 偶发 TLS 握手失败**（clone flutter）：直接重试即可。
3. **Visual Studio 装不全**：winget 带 `--override` 装到一半被中断，之后 `vswhere` 显示 `isComplete:false`；
   用 `setup.exe repair` 再 `setup.exe modify --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart`（不能加 `--wait`，会报 87）修复。
4. **`melos bootstrap` / 构建报 "Building with plugins requires symlink support"**：需在 Windows「设置→开发者选项」开启开发人员模式（系统设置，需用户手动开）。
5. **`just` 找不到 `pwsh.exe`**：justfile 指定了 PowerShell 7。未安装 pwsh，改用文档里的备用入口：
   `dart run tool/project_prep.dart app`（等价 `just sync`）、`dart run tool/flutterw.dart build windows --debug`。
6. **`flutter_inappwebview_windows` 报 NuGet 找不到（MSB3073 / 9009）**：`winget install Microsoft.NuGet`，并保证 `nuget` 在 PATH（`%LOCALAPPDATA%\Microsoft\WinGet\Links`）。
7. 不要让两个构建同时写同一个日志文件，否则后一个会因文件被占用而根本没跑。
8. 构建会重写 `windows/flutter/generated_plugin_registrant.*` 等已跟踪的生成文件，提交前用 `git checkout --` 还原，避免噪声。

## 原版启动验证
- `build\windows\x64\runner\Debug\fluxdo.exe` 可启动，显示欢迎页（登录 / 游客访问）。
- 未点击任何按钮，未登录，未触发对 linux.do 的访问（欢迎页之后才会联网）。

## 改名（USCard Forum）
- 显示名：`USCard Forum`（AndroidManifest、iOS Info.plist、Windows main.cpp/Runner.rc/setup.iss）
- 包名：`com.github.lingyan000.fluxdo` → `com.hao.uscardforum`
  （Android `namespace`/`applicationId`、Kotlin 目录与 package、iOS/macOS bundle id、Linux APPLICATION_ID、所有 `MethodChannel` 名）
- URL scheme：`fluxdo://` → `uscardforum://`（Android intent-filter、iOS Info.plist、Windows 协议注册、Dart 深链解析、扫码登录）；`discourse://` 保留。
- 更新检查与关于页：指向 `leehao321/uscard-forum-app`（GitHub 用户名 `leehao321`）。
- README 顶部加中文说明；LICENSE 与原作者版权声明未动。
- **未改**（后续再处理）：`android/app/google-services.json` 的 package_name、`flatpak/`、`altstore/`、`.github/` 工作流、Dart 包名 `fluxdo`、可执行文件名 `fluxdo.exe`、图标、各处 l10n 文案里的 “FluxDO”。

## 阶段 1 入口文件清单
- `lib/constants.dart`：`AppConstants.baseUrl` 改为 `https://www.uscardforum.com`
- 新建 `lib/config/sites/uscard.dart`（参照 `lib/config/sites/linuxdo.dart` 的 `SiteCustomization`）
- `lib/services/discourse/`（21 个 part 文件）：核对站点专属接口
- 登录：`lib/pages/login_page.dart`、`lib/pages/webview_login_page.dart`；去掉 hCaptcha 登录步骤
- AndroidManifest 里 `linux.do` 的 App Link intent-filter（`android/app/src/main/AndroidManifest.xml`）
- 阶段 2 预留：追觅、`lib/services/background/`（后台通知轮询）、预加载服务

## 仓库
- 远端：https://github.com/leehao321/uscard-forum-app （公开；iOS 包打好后转私有）
- `main`：上游 bc5a04b0 原样；`uscard`：改名及后续所有改动。
- GitHub CLI 登录用设备码网页授权；内置浏览器输入代码时遇到过代码过期，重新生成即可。
