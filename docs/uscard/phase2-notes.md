# 阶段 2 笔记：清理 linux.do 专属功能与自动访问

论坛条款禁止非浏览器程序自动访问论坛，所以只保留「用户操作触发」和「前台页面可见时」的请求。

## 已移除 / 停用
- **追觅（`seeking`，监控用户动态）**：删除 `lib/models/seeking.dart`、`lib/pages/seeking_page.dart`、`lib/providers/seeking_provider.dart`、`lib/l10n/modules/seeking/`、导航入口与 `selectedSeekingProvider`，对应测试 `test/models/seeking_test.dart` 同步删除；另 3 个测试里的 `selectedSeekingProvider` 改为 `selectedSearchProvider`。
- **后台通知轮询**：`BackgroundNotificationService` 改为空壳（Android 前台服务、iOS BGTaskScheduler / Workmanager 都不再启动），删除 `notification_task_handler.dart`。
  `MessageBusService.enterBackgroundMode()` 现在直接停止轮询，回前台 `exitBackgroundMode()` 才恢复，后台模式下订阅也不会重启轮询。
- **常驻 Cloudflare Turnstile WebView**：`CfClearanceRefreshService.start()` 全平台禁用（原来只禁 Windows）。`cf_clearance` 只在用户操作触发的验证页里获取。
- **linux.do 生态服务**：`SiteCustomization.enableLinuxdoServices`（美卡为 false）挡住：个人页的「元宇宙」「信任等级要求」入口、帖子菜单的 LDC 打赏、`connectStatsProvider`（`connect.linux.do` 请求）。

## 仍保留（需要用户决定）
- **前台 MessageBus 实时更新**：App 在前台时仍会长轮询 `/message-bus`（新通知、话题新回复提示）。这是否算「自动访问」取决于论坛条款的解读，**待你决定是否保留**；如要关，在 `MessageBusService` 里把订阅启动处加开关即可。
- **启动时预加载首页数据**（`BrowserTrustCoordinator.ensurePreloaded`）：相当于打开首页，保留。
- **阅读计时上报 / 在线状态心跳**（`screen_track`、`presence_service`）：等同于浏览器网页行为，保留，阶段 3「看过就存」时一并梳理。

## 暂未处理（留给阶段 3）
- 死代码未删：`lib/modules/ldc_reward`、`ldc_oauth_service`、`cdk_oauth_service`、`metaverse_page`、`trust_level_requirements_page`、余额卡片等，只是入口被站点开关挡住。
- `ech_dns_policy` / `network_settings_service` 里写死的 linux.do 子域；Android 清单里 linux.do 的 App Link；`google-services.json`；界面文案里的 “FluxDO” / “Linux.do”；聊天（美卡关闭了 chat）和 discourse-ai 相关入口。

## 验证
- `flutter analyze lib` 无 error / warning；Windows debug 编译通过。
- 改过的 `selected_topic_provider_test`、`pane_projection_test` 通过。
- `fluxdo_render_parallel_navigation_test` 里 2 个用例失败（`sharedPreferencesProvider` 未覆盖），是原有问题，与本阶段无关。
- 仓库里 `devtools_extension/`、`packages/.../example` 的分析 error 同样是原有的。
- 未联网自测。
