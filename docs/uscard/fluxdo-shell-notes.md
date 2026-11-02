# FluxDO 壳改造记录

依据：`改造计划.md`（下称「计划」）与《FluxDO-可填域名彻底改造清单》。每阶段结束在这里记结果与偏差，审查通过后才进下一阶段。

## S0 底座搬运

- 分支：`fluxdo-shell`，从上游 `main` `bc5a04b0` 切出；未推送，未触发 CI。
- worktree：`C:\Users\hao\uscard-app\.claude\worktrees\fluxdo-shell`。
- `fluxdo-shell-private` 到 S3 再切，现在切了也只能跟着 rebase。

### 提交

| 提交 | 内容 | 来源 |
|---|---|---|
| `6df48ca4` | 构建产物、解密文件的忽略规则 | `b16e2684` |
| `f0d294f0` | `ios-unsigned.yaml`（含 `with_private`、只传加密 IPA）；去后台模式与付费 entitlement | `b3c9a1a5` + `claude/0-5-0` 最新工作流 |
| `49e6e373` | `tool/private_patch.sh` | `claude/0-5-0` |
| `d7e0bca3` | 登录页「非官方第三方客户端」 | `a0009a1e`（不含版本号） |
| `baf2d057` | iOS 授权登录改 ASWebAuthenticationSession，新增 `flutter_web_auth_2 ^5.1.0` | `02c26718` |
| `258b4475` | 显示名 USCard Flux，包名 `com.hao.uscardforum.flux`，关于页与更新检查指向本仓库 | `033fa4cd` 的意图，`c11a14dc` 的真实仓库名 |
| `6dd1ee89` | 罗盘图标与启动动画 | `6e0e8ac0`、`d8e66f2f`，`compass_logo.dart` 含 `a102ea43` 的修复 |
| `4549a3de` | 版本 `1.1.0+2026110119` | 计划 §8 Q1 |

`tool/project_prep.dart`、`tool/flutterw.dart` 在 `claude/0-5-0` 与上游 `main` 完全一致，不用改。

### 关卡 S0

| 项 | 结果 |
|---|---|
| Windows 调试版能编译 | 通过：`dart tool/flutterw.dart build windows --debug`，产出 `fluxdo.exe` |
| `flutter analyze` | 与上游基线相同：561 条，其中 error 12、warning 3，逐条比对无新增；12 个 error 都不在 `lib/`（`devtools_extension`、`flutter_inappwebview_linux/example`、`test/`） |
| 默认仍连 linux.do | 只做了静态确认：`lib/constants.dart` 无改动 |
| CI 公开 IPA 绿 | **未验证**：本阶段不推送、不触发 CI，留给 S4 或审查后单独触发 |
| 装机后界面是原版 FluxDO | **未验证**：需要真机，依赖上一项的 IPA |
| 私有词 | 用 `leak_grep.sh` 的同一组词扫 `bc5a04b0..HEAD` 的提交信息、新增行和路径：无命中；无解密产物 |
| iOS 配置 | `Info.plist`、`Runner.entitlements` 能解析；工作流 YAML 能解析；Bundle ID 无残留。iOS 无法在 Windows 上编译 |

没有跑 `flutter test`：本阶段改动没有对应单测，关卡也不要求。
没有启动 `fluxdo.exe`：启动时会把 `fluxdo://`、`discourse://` 写进本机注册表，指向这个调试版。

### 与来源提交的偏差

1. **URL scheme 不改**：仍是 `fluxdo`、`discourse`。`033fa4cd` 把 `fluxdo` 换成了 `uscardforum`，计划 §3 要求三个并存，放到 S1 做。
2. **MethodChannel 名不改**：仍是 `com.github.lingyan000.fluxdo/*`。这只是 App 内部通信，与包名无关；不改可以少动 10 个文件（9 个 Dart 和 `AppDelegate.swift`），以后切回原包名也不用再改一遍。Kotlin 包目录按新包名搬了。
3. **App 内文案只改了启动页和关于页**：l10n 里其余的「FluxDO」和 `onboarding_slogan`（「真诚 · 友善 · 团结 · 专业」）属于清单阶段 9，放到 S1。
4. **不搬 `docs/uscard/phase0-notes.md`、`device-issues.md`**：它们记录的是 1.0.0 那条线。图标脚本用到的 `docs/uscard/logo-source.webp` 搬了。

### 请审查时留意

1. **iOS 后台任务**：`AppDelegate.swift:21` 仍注册 `com.fluxdo.notificationPoll`，plist 已不声明这个 ID。1.0.0 也是这个组合（同为 `workmanager_apple 0.9.6`），而 1.0.0 在真机上一直能用，所以启动这一步有依据，但这是推断，不是这个包的实测。不同的是 1.0.0 把 Dart 侧的后台通知整个停用了，这里还保留上游代码，切后台时会走 `Workmanager().registerPeriodicTask`，失败由 `lib/main.dart` 进入后台处的 try/catch 兜底。这条路径没有真机验证过，S0 装机时要切一次后台看看。按站关闭后台的 `allowBackgroundAccess` 在 S1 做。
2. **Android 预计编译不过**：`android/app/google-services.json` 里的 `package_name` 还是上游的，与新 `applicationId` 不匹配，google-services 插件应该会报错（未实测）。`uscard` 分支也是同样状态，Android 不在关卡内，所以没动；要出 Android 包时得换配置或去掉 Firebase。
3. **S1 的 `uscardforum` scheme**：和 1.0.0 并存时，两个 App 都会注册这个 scheme，iOS 不保证打开哪一个。建议 S1 写好代码，但 plist 里等切回原包名时再加。

### 下一步

审查通过后进入 S1，按清单阶段 1→2 做；到阶段 3（存储隔离）和 1.0.0 数据迁移时停下，等会话切模型。
