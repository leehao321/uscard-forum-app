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

S0 已于 2026-11-01 审查通过。

## S1 可填域名：阶段 1、2

阶段 3（存储隔离）和 1.0.0 数据迁移尚未开始，在此停下等审查和切模型。

### 做了什么

**阶段 1 域名动态化**

- `lib/models/site_profile.dart`：`SiteProfile`、`SitePresets`（美卡、linux.do）、`normalizeSiteBaseUrl`。功能包只由地址决定，不持久化，别的站拿不到专属功能。
- `lib/services/site_context.dart`：本次运行连接的站点。`AppConstants.baseUrl` 改成读它的 getter，未选站时回落 linux.do（只有选站之前和测试会走到）。
- `lib/config/sites/current.dart`、`generic.dart`：按当前站取配置。其他站没有光晕、头衔特效和社区插件，外链确认保持开启。`PluginRegistry` 也改走这里。
- 新增 `AppConstants.siteOrigin`：Origin 头、Windows WebView 的 origin 校验、富文本编辑器的恢复范围原先都用 baseUrl，子路径站会出错。
- `DioHttpClient._mainHost`、`DiscourseService.baseUrl` 改为 getter。

**阶段 2 站点注册与加站**

- `lib/services/site_registry_service.dart`：站点列表和当前站存 SharedPreferences。`setCurrent` 只改持久化，重启生效。这两个 key 不进数据备份。
- `lib/services/site_probe_service.dart`：`/site.json` + `/site/basic-info.json` + `/about.json`。用独立 Dio，不带 cookie 和 API Key，避免把登录态发给刚输入的陌生地址。分清不是 Discourse、连不上、证书错误、Cloudflare 验证；需要登录的站靠 `basic-info` 确认；跟随重定向用真实地址，重定向到 http 不接受。
- `lib/pages/add_site_page.dart`、`first_run_site_picker.dart`：美卡、linux.do 卡片加自由输入，默认选中美卡（计划 §8 Q3）。选预置站或手输预置站域名都不发请求。
- `main()` 在其余服务初始化之前选站，所以 Cookie、Dio、预加载一启动就读到确定的站点。
- iOS 后台任务的独立 isolate 启动时先读当前站点。

### 关卡（S1 整体关卡要到阶段 9 之后，这里是阶段 1、2 的部分）

| 项 | 结果 |
|---|---|
| 新增单测 | 50 个全部通过（模型、注册、探测、加站页、首启选站） |
| 全量 `flutter test` | 245 个失败，和干净的 `bc5a04b0` **完全同一批**，无新增、无消失；通过数 1959 → 2008。全量跑在首启选站测试加入之前，这个测试单独跑过 |
| `flutter analyze` | error、warning 与上游基线逐条相同，新增文件无 info |
| Windows 调试版编译 | 通过 |
| 真实 API 形状 | 用 `meta.discourse.org` 核对过 `/site.json`、`/site/basic-info.json`、`/about.json`，字段与解析逻辑一致；`example.com/site.json` 返回 404。没有向美卡发请求 |
| 私有词 | 同 S0 的词表扫 `bc5a04b0..HEAD`，无命中 |
| **真实运行 App** | **未做**：没有启动 `fluxdo.exe`（原因见 S0）。首启选站之后第二次 `runApp` 切到主界面这一步只有真机或手动启动才能验证 |

那 245 个失败集中在编辑器语义测试和发帖页，都是上游本来就有的，没有查原因。

### 与清单、计划的偏差

1. **`DiscourseService.baseUrl` 用静态 getter**，不是实例 getter：只有一个调用方，效果相同。
2. **还没有站内换站入口**：只有首次启动能选站。见下一节第 1 条，这是有意的。
3. **探测不走 App 的 DoH 和代理**：首启时这些服务还没初始化，要靠它们才连得上的网络会提示连不上。预置站不探测，不受影响。
4. **只支持 https**：输入 http 也升级成 https，host 不带点的（如 `localhost`）不接受。
5. **多加了 `/site/basic-info.json`**：清单只写了 `site.json` 和 `about.json`，但需要登录的站只有这个接口对游客开放。

### 请审查时留意

1. **阶段 3 之前绝不能开放换站**。现在 `linux_do_username`、User API Key 等都是全局 key，换站会把 A 站的 API Key 发给 B 站。首次启动只选一次，没有旧数据，所以是安全的；这也是第 2 条偏差的原因。
2. **这一版不能当通用客户端用**：阶段 4～7 还没做，别的站上 hCaptcha、`login_page` 的写死链接、ECH 域名、LDC 和 connect 入口、深链都还是 linux.do 的行为。阶段 9 前不要出包给人用。
3. **S0 关卡里「默认仍连 linux.do」已被计划 §8 Q3 取代**：现在首次启动显示加站页，默认选中美卡。
4. **`SiteProfile` 的 `logoUrl`、`faviconUrl` 只存不显示**，界面在阶段 9 才用上。

### 下一步

审查通过并切模型后做阶段 3 和 1.0.0 数据迁移。
