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

阶段 1、2 已于 2026-11-02 审查通过。

## S1 可填域名：阶段 3（存储隔离）与 1.0.0 数据迁移

### 怎么隔离

`SiteProfile.storageId` 是所有隔离的根，形如 `www_uscardforum_com_be583a3a`（可读部分加地址的 FNV-1a 哈希）。已落盘的数据靠它定位，算法不能改，单测钉死了具体值。

| 存储 | 做法 |
|---|---|
| Cookie | `.cookies/<storageId>/`，每站一个 jar。主域收敛规则本来就读动态的 baseUrl，自动跟随当前站 |
| 安全存储 | 新增 `SiteScopedSecureStorage`，加前缀 `site.<storageId>.`。用户名、CSRF、User API Key 全套、保存的账密都走它 |
| Hive | 盒名改成 `<storageId>__<原名>`，在 `AppDatabase` 一处改，书签、导出历史、聊天缓存、本地草稿都覆盖 |
| SharedPreferences | 同样的前缀，用 `SiteContext.scopedKey`；按站的 key 列在 `SiteScopedPrefKeys` |
| 文件 | 表情快照移到 `ApplicationSupport/sites/<storageId>/` |
| AI 会话 | `AiChatStorageService.keyScope`：会话按话题存，话题 ID 只在一个站内唯一 |

**SharedPreferences 盘点结果**

- **按站**：当前用户和摘要缓存、固定分类、稍后阅读、屏蔽用户、hCaptcha 端点、最近表情、邀请链接、聊天表情、书签同步时间、Notion 配置、嵌套阅读、关注（seeking）、后台通知状态、被动登出记录、社区准则缓存、AI 会话。
- **全局**：外观、阅读和编辑偏好、网络（DoH、代理、rhttp）、窗口、更新、引导标记、迁移标记、贴纸市场、下载列表、网页收藏和历史、播放进度（按 URL）、AI 供应商和模型设置。
- **没动**：`cdk_*`、`ldc_*` 只有 linux.do 会用，阶段 6 做入口门禁。
- **数据备份**：排除规则先去掉站点前缀再判断。新备份导回原站；按站隔离之前的老备份，站点数据归到当前站。

**盘点后不用改的**：下载文件（`reserveAvailableDownload` 用独占创建，不会覆盖同名文件）；图片缓存（`blob_image_cache` 按完整 URL 取键，不同站不会撞）；WebView cookie 的读写（系统按域名隔离，但登出时的清理见下面第 5 条）。

### 1.0.0 迁移（`SiteDataMigration`）

`main()` 在 Cookie、Hive 初始化之前调用，把旧数据归到美卡预置站。

- **触发条件**：没选过站，且发现旧数据（`onboarding_completed`、按站偏好 key、`.cookies/cookies.v1.json`、旧用户名或 API Key 任一项）。用新包名并存时检测不到旧数据，所以什么也不做；切回原包名后自动生效，不需要改代码。
- **搬什么**：安全存储 9 个 key、偏好（含 1.0.0 的 `topic_notes_v1/v2`、`reading_stats_v1`）、Cookie 文件、Hive 盒文件、表情快照、`saved_topics` 目录。全局设置和迁移标记不动。
- **可重入**：状态存在 `site_registry_legacy_migration`（pending/done）。中途失败保持 pending，下次启动继续；当前站先定下来，不会弹选站页把旧数据晾在一边。
- **冲突时**：凭证和偏好以新位置为准，再删旧的（说明已迁过或重新登录过）；文件两份都留，不覆盖不删除。

**测试抓到一个真问题**：平时用的 `ResilientSecureStorage` 写失败时只存进内存、不报错。迁移如果走它，接着删旧 key，重启后凭证就没了；读失败也会被当成「没有凭证」跳过。所以迁移改用 `SecretFallbackPolicy.deny` 的严格模式，写完回读确认才删旧 key，读写失败都留在 pending。早期版本遗留的 `__secure_fallback__` 明文键也一起迁走清掉。

### 关卡

| 项 | 结果 |
|---|---|
| 新增单测 | 28 个全部通过：两站同名用户不串号、迁移各分支（全新、已选站、完整升级、只有 Cookie 或凭证、安全存储不可用、写入没落盘、读不出、删不掉、明文兜底、目标已有值、不重复）、备份规则，以及「只有白名单文件可以用全局安全存储」的约定测试 |
| 全量 `flutter test` | 245 个失败，和 `bc5a04b0` **完全同一批**；通过数 1959 → 2037 |
| `flutter analyze` | error、warning 与上游基线逐条相同，新增文件无 info |
| Windows 调试版编译 | 通过（之后只改了测试） |
| 代码里残留的裸 key | 搜过，除迁移表和备份规则外没有 |
| 私有词 | 同 S0 的词表扫 `bc5a04b0..HEAD`，无命中 |
| **真实 1.0.0 数据覆盖安装** | **未做**：迁移只用构造的数据测过，关卡 S1 要求的这一项必须等切回原包名、真机覆盖安装 |

### 改了 8 个已有测试的种子

这些测试把旧 key 或旧路径写死了，只改种子，断言不变：`create_topic_discard`、`create_topic_draft_sync`（用户名）、`nested_reading_provider`、`ai_post_review_service`、`bookmarks_page`、`bookmark_edit_sheet_launcher`、`bookmarks_notifier_pagination`（同步时间）；`oauth_session_client` 改了 Cookie 路径。

其中书签同步时间值得一提：种子失效后测试走进全量对账，空页把本地书签清空，一开始表现为测试失败。这说明 `bookmark_last_full_sync_` 确实已经按站生效。

### 与清单、计划的偏差

1. **前缀用 `site.<storageId>.`**，不是清单写的 `site_<host哈希>_`：带可读部分方便排查，点号让备份规则能可靠地去掉前缀。
2. **Hive 没改 `accountId`，改的是盒名**：效果相同，只动一个文件。bookmark 同步时间等其他带用户名的 key 已经按站。
3. **下载和图片缓存没有分子目录**：盘点后发现不会撞名，见上。
4. **`keyScope` 是静态字段**：`ai_model_manager` 包不依赖 App 的 `SiteContext`，由 `main()` 写入。

### 请审查时留意

1. **S2 搬 1.0.0 功能时必须遵守**：笔记、阅读统计用 `SiteContext.scopedKey` 读 `topic_notes_v2`、`reading_stats_v1`；看过就存放在 `siteSupportDirectory()/saved_topics`。迁移已经把旧数据搬到这些位置，存到别处就读不到。
2. **S3 的私有数据**：只在美卡站出现，可以继续用全局位置，不需要迁移。如果放到按站位置，要把迁移步骤加在私有分支里，公开代码里不能出现这些词。
3. **SideStore 重签可能影响钥匙串**：覆盖安装要包名和签名团队都一致才读得到 1.0.0 的 Keychain。读不到时 API Key 拿不回来，但 Cookie 在，登录态通常还在。S4 真机验证时要看这一点。
4. **换站入口仍未开放**：存储隔离已经就位，入口按计划在阶段 8 做。
5. **登出时 WebView Cookie 没有按站隔离（未修）**：`CookieJarService.clearAll` 只清当前站的 jar，但 `clearWebViewCookies` 调的是 `deleteAllCookies`，会清掉所有站的 WebView Cookie。不会串号，别的站的 jar 还在，登录态也还在；但那些站的 `cf_clearance` 可能要重新验证，WebView 里的登录态要等下次同步。这是平台实现（Android 上还有防 ANR 的逻辑），我没有动。现在没有换站入口，碰不到这种情况；建议在阶段 8 做换站时一起评估。

阶段 3 已于 2026-11-02 审查通过。

## S1 可填域名：阶段 4～9

清单阶段全部做完。**关卡 S1 的站点矩阵还没有实测**，见下面「关卡 S1」。

### 做了什么

| 阶段 | 提交 | 内容 |
|---|---|---|
| 4 登录 | `d64e1085` | hCaptcha 从站点设置读 sitekey，linux.do 留写死的兜底，都没有就跳过；仅 SSO 或用其他人机验证的站隐藏密码表单；浏览器授权失败降级 WebView；找回密码和标题跟随当前站；没有 fingerprint 插件的站不跑会话 bootstrap；scopes 按站配置 |
| 5 网络 | `169cdb3a` | ECH 内置域名按站；DNS 预解析的固定子域只给 linux.do；根域图片改写成主站（`2498d8a5` 通用化）；根域 cookie 算主域；站内链接判断改认根域 |
| 6 能力 | `42a952c2` | LDC、CDK、connect、元宇宙、打赏只给 linux.do；聊天、Boost、树形回复、已解决、投票看站点设置；没装回应插件时点赞走自带接口；音视频 `.xz` 只给 linux.do；不允许后台访问的站（美卡）切后台停轮询，没有后台通知、关注和列表自动拉首帖 |
| 7 深链 | `7e69fa67` | 深链认已注册站点，别的站的链接交给内置浏览器；路由解析去掉子路径前缀；剪贴板只认当前站；Android 声明美卡链接 |
| 8 换站 | `77c475b3` | 设置里的论坛管理；切换持久化后退出 App；`SiteSwitchService.runNoRestartSteps` 写好无重启切换的顺序 |
| 9 文案 | 见下 | App 名统一 USCard Flux；论坛名改成站点标题或中性说法；分享图和引导页读站点标题 |

计划 §3 第 2 条的「当年删掉 → 按站开关」对应关系：

| 当年做法 | 现在 |
|---|---|
| 去掉 hCaptcha | 站点设置决定（阶段 4） |
| 删除聊天 | `chat_enabled`，关闭时不显示入口、不请求 `/chat` |
| 隐藏 Boost | `discourse_boosts_enabled` |
| 删除 LDC、CDK、connect、元宇宙 | `SiteProfile.hasLinuxdoServices` |
| 停掉自动访问 | `SiteProfile.allowBackgroundAccess`，美卡为 false |
| 根域图片改写 | 主站带 www 的站都生效 |

站点设置名不是猜的：用 `meta.discourse.org` 首页的预载数据核对过（`chat_enabled`、`solved_enabled`、`topic_voting_enabled`、`discourse_reactions_enabled`、`discourse_boosts_enabled`、`nested_replies_enabled`、`enable_local_logins`、`hcaptcha_site_key`、`discourse_captcha_enabled`、`discourse_captcha_provider`）。**没有核对美卡和 linux.do**：美卡要守「只在用户操作时请求」，linux.do 对脚本返回 403。

linux.do 站点设置没加载时，这些开关按开启处理，沿用上游行为。

### 中途发现并修掉的

- **子路径站的前缀重复**：服务端下发的翻页地址已带 `/forum`，Dio 再拼 baseUrl 会变成 `/forum/forum/...`。现在在 `RequestHeaderInterceptor` 统一去掉，用 Dio 真实拼地址测过。
- **ECH 不能照清单做**：清单说内置域名用「当前站 host + CDN」，但查询名会换成 Cloudflare 的入口，不在 Cloudflare 后面的站会直接连不上。所以自加的站内置为空，需要时手动加到自定义域名。
- **自加的站不预先弹 Cloudflare 验证页**：上游和 1.0.0 登录前都会弹，对不在 Cloudflare 后面的站没有意义；真被拦下时登录对话框会在 CSRF 403 时再验证。

### 关卡 S1

| 项 | 结果 |
|---|---|
| 单测 | 新增 131 个全部通过；全量 245 个失败，和 `bc5a04b0` **完全同一批**；通过数 1959 → 2090 |
| `flutter analyze` | error、warning 与上游基线逐条相同 |
| Windows 调试版编译 | 通过 |
| 私有词 | 同 S0 的词表，无命中 |

下面这些**都没有实测**，需要真机或启动 App：

| 关卡项 | 现状 |
|---|---|
| linux.do 回归（专属功能全开） | 单测覆盖开关逻辑，没有真实登录 |
| 美卡（对照 1.0.0 行为） | 同上 |
| `meta.discourse.org` | 只核对过接口和设置名 |
| 子路径站、仅 SSO 站、有 Cloudflare 的站 | 只有单测，没找到可登录的测试站 |
| 两站同名用户不串号 | 存储层有单测，真实登录没测 |
| User API Key 被关时降级 | 见下面第 2 条 |
| 1.0.0 覆盖安装迁移 | 只用构造数据测过，要切回原包名上真机 |
| 美卡站抓包确认无后台请求 | 没做 |
| 首启选站后切到主界面 | 第二次 `runApp` 这一步只有启动 App 才能验证 |

Android 改了清单和 Kotlin 包名，没有编译过；S0 的 `google-services.json` 问题还在。

### 与清单、计划的偏差

1. **scopes 不能探测**：`allow_user_api_key_scopes` 不下发给客户端，游客读不到，所以默认只申请 `one_time_password`，要 `write` 得在站点配置里写明。
2. **`uscardforum` scheme 没进 iOS plist**：Dart 已经接受，等切回原包名时加一行，和 1.0.0 并存时系统不保证打开哪一个（S0 已提过）。
3. **切换用 `exit(0)`**：iOS 不能自己重启，只能退出后由用户重新打开。上架版本不合适，侧载没问题。
4. **没有区分「关停注册、仅邀请」**：清单阶段 2 提到，但这些设置要进站后才读得到，加站时只有 `login_required`。
5. **树形回复不用站点配置字段**：核心已有 `nested_replies_enabled`，直接读。
6. **没有单独的美卡配置文件**：1.0.0 的美卡配置和通用默认值一致，差别只在 `allowBackgroundAccess` 和 ECH。
7. **站点 logo 仍未显示**：`logoUrl` 只存不用。分享图和引导页显示站点标题，图标保持 App 自己的。

### 请审查时留意

1. **这一版第一次能换站了，阶段 3 的第 5 条要重新看**：登出时清掉所有站的 WebView Cookie，影响的是别的站的 `cf_clearance`，不串号也不掉登录。我没有改。
2. **User API Key 被关时只能部分自动降级**：授权页打不开或回调失败会自动转 WebView 登录。但 iOS 上站方关闭时，系统授权页里显示的是错误页，用户关掉就算取消，App 分不出来；这时登录页上的 WebView 按钮还在。
3. **移除论坛不删数据**：登录状态和本机数据都留着，重新添加后还能用。如果想要「移除即清除」，需要另外做。
4. **有两处行为对所有站都变了，包括 linux.do**：在线心跳和扫码轮询只在 App 处于前台时进行。这是 1.0.0 的修复，通用，不影响功能。
5. **`seeking`（关注）对美卡隐藏**：它是定时拉取用户动态，按条款不能用。

S1 已于 2026-11-02 审查通过；站点矩阵和真机项仍未实测，见上面的关卡 S1。

## S2 搬 1.0.0 公开功能

### 做了什么

| 功能 | 提交 | 怎么搬的 |
|---|---|---|
| AI 工具调用 | `2a9d5a44` | 直接挑选 `42d326ea` 和 5 个修复 |
| 通用 MCP | `c5356a90` | 逻辑取 `claude/0-5-0` 最新状态；列表页、编辑页、工具行用 Material 重写，行为和 key 不变，不含 `ea4ec64e` 的 v2 外观 |
| 安静模式 | `f9d59027` | 直接挑选 `7ce97de1` |
| 已读同步 | `6947620b` | 只取 `0a8eb058` 的逻辑：退出帖子时最后一批阅读时间发完并回写未读点、详情加载完才订阅话题频道、Client Hints 只在 Android 发、列表筛空时不自动翻页 |
| 替代内容扩展点 | `6947620b` | `f0b3eaec` 原样 |
| 表情包、快捷词 | `6947620b` | 确认上游也有这两个 bug（缓存前缀误伤数据源地址、导出的快捷词缺 id 导不回），`feb1c371` 原样 |
| 笔记、阅读统计、应用锁、AI 总结、看过就存 | `8d7cffe9` | 存储和服务取最新版（含 v2 笔记格式），界面用 0.3.x 的 FluxDO 风格页面 |
| 隐藏回复收起 | `2cd6c5a8` | 逻辑原样（`3ce751d8`），提示行用 Material 组件重写 |
| 精彩、难绷榜单 | `2cd6c5a8` | 数据层来自 `e9a2bb2d`；入口在首页筛选菜单，点了进单独的列表页；徽章 id 进站点配置，只有美卡有 |

这些功能的数据都按站存放，和阶段 3 迁移的目标位置一致：笔记 `topic_notes_v2`、统计 `reading_stats_v1`、已存帖子 `siteSupportDirectory()/saved_topics`。

### 关卡 S2

| 项 | 结果 |
|---|---|
| `flutter analyze` | error、warning 与上游基线逐条相同（中途多出的 2 个 warning 在搬来的测试文件里，已清掉） |
| 全量 `flutter test` | 245 个失败，和 `bc5a04b0` **完全同一批**；通过数 2150（基线 1959） |
| `ai_model_manager` 包测试 | 286 个通过，2 个失败（`ai_provider_edit_page`、`swipe_action_cell`）；这两个在干净的 `bc5a04b0` 上同样失败 |
| AI、MCP、安静模式用例 | 全部通过，其中 MCP 用的是假服务 |
| Windows 调试版编译 | 通过 |
| 私有词 | 逐提交扫描，无命中 |
| 外观 | 新页面没有用 v2 token、`AppIcons`、Lucide；`pubspec.yaml` 没有 Lucide |

**没有实测**：真实的 MCP 服务、真实 AI 接口、Face ID 解锁、真机上的笔记和统计。

### 与计划的偏差

1. **多了一个依赖 `local_auth ^3.0.2`**：计划 §7 说除 ASWebAuthenticationSession 用到的依赖外不加新依赖，但 §4 要搬的应用锁离不开它。1.0.0 用的也是这个版本，所以我加了。**这一条和计划字面上冲突，请确认。**
2. **「自定义日期范围」没有搬**：上游本来就有，点「自定义」弹原生日期范围选择。`21af9ef0` 主要是把它改成 v2 半屏，计划要的正是 FluxDO 原生日期选择，所以不用动。
3. **榜单是单独一页**：1.0.0 是在首页列表里切换，要改列表状态；单独一页不碰原有列表，行为符合「只在用户操作时请求」。
4. **笔记页不能编辑楼层笔记**：界面用 0.3.x 的，那时还没有楼层笔记。但 1.0.0 的楼层笔记会显示，保存时原样保留，有测试。楼层笔记的编辑入口在 v2 的阅读工具栏里，没搬。
5. **不搬 `0a8eb058` 的 v2 首页部分**：左滑标已读是 `home_topic_list`（v2）的功能，FluxDO 首页没有这个入口。
6. **`test/ui` 的 v2 用例没有全搬**：依赖 v2 界面的不搬；逻辑相关的改到普通测试目录，共用新增的 `test/support/app_harness.dart`。

### 请审查时留意

1. **Android 上没有应用锁**：`AppLockService.isSupportedPlatform` 只认 iOS、macOS、Windows，设置里不显示入口，和 1.0.0 一样。
2. **笔记、统计等页面文案只有中文**：和 1.0.0 一样，写死在页面里，MCP 页也是。切到英文时这几页还是中文。
3. **AI 重试顺带变了**：`ai_chat_providers` 取的是最新版，「重试」现在也能用在已完成的回答上（等于重新生成），来自 `3b5ba07c`。这是逻辑增强，没有界面改动。
4. **S1 的站点矩阵还没测**：这一阶段的功能要等出包后一起在真机上看。

### 下一步

审查通过后进入 S3，在这个分支上切 `fluxdo-shell-private`。
