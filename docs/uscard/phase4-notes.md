# 阶段 4 笔记：iOS 打包

## 已完成
- 新增 `.github/workflows/ios-unsigned.yaml`（手动触发 `workflow_dispatch`，`macos-latest`）：
  Flutter 3.47.4 → Rust iOS 目标 → `dart tool/flutterw.dart build ios --release --no-codesign` → 校验 `doh_proxy` 符号 → 打成 `uscard-forum-unsigned.ipa` → 作为 Actions 产物上传（保留 14 天）。
- 首次触发即成功：https://github.com/leehao321/uscard-forum-app/actions/runs/40636868595
  产物名 `uscard-forum-unsigned-ipa`，在该运行页面底部「Artifacts」下载（需登录 GitHub）。
- iOS 配置调整：
  - `Info.plist` 去掉 `UIBackgroundModes`（fetch / processing / remote-notification）和 `BGTaskSchedulerPermittedIdentifiers`，与阶段 2「不做后台自动访问」一致。
  - `Runner.entitlements` 去掉 `com.apple.developer.web-browser`（需 Apple 审批的付费能力，免费 Apple ID 侧载会签名失败）。
- 仓库默认分支改为 `uscard`（`workflow_dispatch` 只对默认分支上的工作流可用）；`main` 仍保持上游原样。

## 触发方式
```bash
"C:\Program Files\GitHub CLI\gh.exe" workflow run ios-unsigned.yaml -R leehao321/uscard-forum-app --ref uscard
```

## 真机安装（待用户操作，未验证）
IPA 是未签名的，需要用自己的 Apple ID 重签名后安装，常见做法：
- Sideloadly（Windows / macOS）：拖入 IPA，填 Apple ID，选设备安装；免费账号签名 7 天过期，需要重新安装。
- AltStore：同样 7 天续签，需要电脑上的 AltServer 在同一网络。
- 付费开发者账号可改用自动签名 + TestFlight（需要另配 Secrets，当前未做）。

## 尚未验证 / 风险
- **没有真机跑过**：构建成功只说明能编译链接，启动、登录、AI 总结、已存帖子、Cloudflare 验证页在 iOS 上的表现都未验证。
- iOS 上 Cloudflare 手动验证和 User API Key 回调（`discourse://auth_redirect`）要真机验证；美卡的 User API Key 授权回调白名单是服务端设置，目前未知。
- 免费 Apple ID 对 App ID 数量（每周 10 个）和 7 天有效期有限制。
- 仓库目前是公开的；用户计划在 iOS 包打好后转私有——转私有后 GitHub 免费账号的 macOS 构建分钟有限额（私有仓库按 10 倍计费）。
