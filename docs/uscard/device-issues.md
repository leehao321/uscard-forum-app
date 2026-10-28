# 真机问题记录

测试环境：SideStore 安装未签名 IPA（Actions 运行 40636868595），iOS 26.x。时间均为 UTC。

| 编号 | 日期 | 现象 | 状态 | 修复 commit |
| --- | --- | --- | --- | --- |
| D-001 | 2026-10-27 | 登录页选“浏览器授权登录”，授权后跳转到 Discourse 官方客户端而不是本 App | 已修复，待真机验证 | 见 git log |
| D-002 | 2026-10-27 | 首次打开 App 加载首页时，Cloudflare“正在验证”页面一直转圈 | 待日志 | - |
| D-003 | 2026-10-27 | 扫码登录尚未测试 | 未测试 | - |

## D-001 分析

- 回调用的是 `discourse://auth_redirect`（站点默认白名单 scheme），而手机上若装了 Discourse 官方客户端，同一 scheme 会被它抢走；iOS 对同 scheme 多 App 注册没有确定的归属。
- 美卡的 `allowed_user_api_auth_redirects` 白名单是服务端设置，未知，不能直接改用 `uscardforum://`。

### 修复

iOS 上改用 `flutter_web_auth_2`（ASWebAuthenticationSession）发起授权，回调 scheme `discourse` 由系统在会话内拦截，不再被 Discourse 官方客户端抢走。其他平台不变。

## D-002 线索

- 验证页地址是 `${baseUrl}/challenge`（上游为 linux.do 设计）。
- 需要真机截图和应用日志页“CF 验证”日志，才能判断是 iOS 26 WebView 未放行，还是流程判定问题。
