# 真机问题记录

测试环境：SideStore 安装未签名 IPA（Actions 运行 40636868595），iOS 26.x。时间均为 UTC。

| 编号 | 日期 | 现象 | 状态 | 修复 commit |
| --- | --- | --- | --- | --- |
| D-001 | 2026-10-27 | 登录页选“浏览器授权登录”，授权后跳转到 Discourse 官方客户端而不是本 App | 已修复，待真机验证 | 02c26718 |
| D-002 | 2026-10-27 | 首次打开 App 加载首页时，Cloudflare“正在验证”页面一直转圈 | 待日志 | - |
| D-004 | 2026-10-28 | App 内大量 linux.do / LINUX.DO 字样未改（登录页大标题、登录按钮、WebView 登录标题、分享图、关于页、设置说明、邀请、代理测试、AI 审核提示词等） | 已修复，待真机验证 | 见 git log |
| D-005 | 2026-10-28 | 用户要求重新设计 logo | 待确认设计方向 | - |
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
