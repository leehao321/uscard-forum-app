# 阶段 1 笔记：换站点与登录

## 已做
- `lib/constants.dart`：`AppConstants.baseUrl` → `https://www.uscardforum.com`，`siteCustomization` → `uscardCustomization`。
- 新建 `lib/config/sites/uscard.dart`：不挂 linux.do 专属插件（reply_cost / warden / character_counts），头像光晕和头衔特效规则为空；链接安全配置的内部域名为 `uscardforum.com` / `*.uscardforum.com`。
- 去 hCaptcha：`SiteCustomization` 新增 `requiresHcaptcha`（默认 true，美卡为 false）。
  `lib/widgets/auth/webview_login_dialog.dart` 在 false 时不加载 hCaptcha 脚本与组件，页面就绪后直接调用 JS 登录（token 为空时 JS 自动跳过 `/hcaptcha/create.json`）。
- 硬编码的 linux.do 改为跟随 `baseUrl`：`login_page`（找回密码）、`profile_page`（账号设置）、`deep_link_service`、`clipboard_topic_link_service`、`ai_post_review_service`（版规链接）、`cookie_devtools_extension`、登录对话框的 bootstrap 地址。

## 验证
- `flutter analyze`（相关文件）无 error / warning；Windows debug 编译通过。
- **未做登录联调**：按约定不向论坛发脚本化请求。登录对话框仍依赖 Cloudflare 手动验证（`LoginPage._ensureCfClearance`），论坛在 CF 后面，所以保留。

## 留给阶段 2 / 3 的 linux.do 残留（刻意没动）
- `connect.linux.do` 请求：`trust_level_requirements_page`、`directory_providers`、`app_cookie_manager` 的 connect 分支
- `ech_dns_policy.builtinDomains`、`network_settings_service` 里的 linux.do 子域列表
- LDC / CDK：`lib/modules/ldc_reward`、`ldc_oauth_service`、`cdk_oauth_service`、`ldc_balance_card`、`cdk_balance_card`
- `AndroidManifest.xml` 里 linux.do 的 App Link intent-filter；`google-services.json`；界面文案里的 “FluxDO” / “Linux.do”
- 后台通知轮询、预加载、追觅（阶段 2，涉及论坛条款）
