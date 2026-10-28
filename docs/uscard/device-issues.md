# 真机问题记录

测试环境：SideStore 安装未签名 IPA（Actions 运行 40636868595），iOS 26.x。时间均为 UTC。

| 编号 | 日期 | 现象 | 状态 | 修复 commit |
| --- | --- | --- | --- | --- |
| D-001 | 2026-10-27 | 登录页选“浏览器授权登录”，授权后跳转到 Discourse 官方客户端而不是本 App | 已修复，待真机验证 | 02c26718 |
| D-002 | 2026-10-27 | 首次打开 App 加载首页时，Cloudflare“正在验证”页面一直转圈 | 搁置（用户决定暂不处理；后续日志里 cf_clearance 正常、请求全 200，未能复现） | - |
| D-004 | 2026-10-28 | App 内大量 linux.do / LINUX.DO 字样未改（登录页大标题、登录按钮、WebView 登录标题、分享图、关于页、设置说明、邀请、代理测试、AI 审核提示词等） | 已修复，待真机验证 | 3f2a4003 |
| D-005 | 2026-10-28 | 用户要求重新设计 logo | 已完成，待真机验证（用户提供的罗盘气泡图） | 6e0e8ac0 |
| D-006 | 2026-10-28 | 日志显示登录后反复请求 `/chat/api/me/channels`，美卡未开聊天，返回 404 并产生错误日志 | 已修复，待真机验证 | d12d08af |
| D-007 | 2026-10-28 | 开屏（欢迎页）的浮动 logo 动画沿用 linux.do 条纹圆标，没有美卡特色 | 已完成，待真机验证：启动页加载动画改为指针转动 | 6e0e8ac0 |
| D-003 | 2026-10-27 | 扫码登录尚未测试 | 未测试 | - |

## D-001 分析

- 回调用的是 `discourse://auth_redirect`（站点默认白名单 scheme），而手机上若装了 Discourse 官方客户端，同一 scheme 会被它抢走；iOS 对同 scheme 多 App 注册没有确定的归属。
- 美卡的 `allowed_user_api_auth_redirects` 白名单是服务端设置，未知，不能直接改用 `uscardforum://`。

### 修复

iOS 上改用 `flutter_web_auth_2`（ASWebAuthenticationSession）发起授权，回调 scheme `discourse` 由系统在会话内拦截，不再被 Discourse 官方客户端抢走。其他平台不变。

## D-002 线索

- 验证页地址是 `${baseUrl}/challenge`（上游为 linux.do 设计）。
- 需要真机截图和应用日志页“CF 验证”日志，才能判断是 iOS 26 WebView 未放行，还是流程判定问题。

## D-004 修复范围

- 多语言文案（简中/繁中/英）里的 Linux.do、LINUX.DO 改为“美卡论坛 / USCard Forum”，代理测试文案改为 uscardforum.com。
- 登录页大标题、分享图标题、AI 发帖审核提示词改名。
- 剪贴板话题链接检测原先硬编码匹配 linux.do，改为 uscardforum.com（相应测试一并更新）。
- 未改：CDK / LDC / 打赏相关文案和域名（`enableLinuxdoServices=false`，入口已隐藏）；`auth_*` 里的 CDK/LDC 确认文案；内部常量与代码注释。
- `test/services` 另有约 32 个失败用例（CF 验证、cookie、网络恢复等），是切换站点后上游测试仍按 linux.do 写，非本次引入，未处理。

## 日志分析（2026-10-28 app_log_share.jsonl，v0.2.29，iPhone17,2 / iOS 26.6.1）

- 日志内没有任何“CF 验证”条目，**没有记录到 D-002 的转圈**；日志里 201 次请求几乎全是 200，cf_clearance 存在（长度 426），登录成功、浏览正常。需要转圈那次的日志（可能在更早的会话，或需开启开发者模式才会写 CF 日志）。
- 其他发现：`/chat/api/me/channels` 404（D-006，已修）；`/n/topic/<id>.json` 404；`/tags/filter/search` 400；一次首页预加载 5 秒无状态码（网络失败）。后三项暂未处理。
- 扫码登录：日志有“生成扫码登录二维码”，是本机生成给别的设备扫，不是扫码登录本机。

## D-005 / D-007：新 logo 与启动动画

- logo 采用用户提供的罗盘气泡图（`docs/uscard/logo-source.webp`）。`tool/gen_logo_assets.py` 把它矢量化为 `assets/logo.svg`、`logo_base.svg`、`logo_needle.svg`，并生成 iOS / macOS / Android 旧版位图 / Windows 图标与设置页图标预览（奶油底 + 居中 logo）。
- 新增 `lib/widgets/common/compass_logo.dart`：底图静止，指针绕中心转动。启动页（`PreheatLogo`）指针 2.4 秒一圈并去掉原来的菊花加载圈；欢迎页和登录页（`FloatingLogo`）指针 6 秒一圈。
- 未处理：Android 自适应图标的矢量前景、macOS 外的桌面端 flatpak / altstore 图标、`logo_modern*.svg`（不再被引用的旧文件）。
