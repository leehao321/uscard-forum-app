import '../constants.dart';

import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/s.dart';
import '../services/auth_session.dart';
import '../services/cf_challenge_service.dart';
import '../services/credential_store_service.dart';
import '../services/discourse/discourse_service.dart';
import '../services/network/cookie/boundary_sync_service.dart';
import '../services/network/cookie/cookie_jar_service.dart';
import '../services/toast_service.dart';
import '../services/user_api_key_login_flow.dart';
import '../widgets/auth/webview_login_dialog.dart';
import '../widgets/auth/login_form.dart';
import '../widgets/common/app_mark.dart';
import 'network_settings_page/network_settings_page.dart';
import '../widgets/auth/two_factor_dialog.dart';
import 'qr_login_scan_page.dart';
import 'webview_login_page.dart';

/// 原生登录页。
///
/// 主路径走 [DiscourseService.loginWithPassword] (在 `_LoginMixin` 里),
/// 不加载 Discourse Ember bundle, 绕开 iOS 15 的 ES2022 `static{}` 兼容问题。
///
/// 流程对齐网页登录（第 1、2 步只在站点启用 hCaptcha 时执行，
/// 见 [SiteCustomization.requiresHcaptcha]，美卡未启用）:
/// 1. 弹 hcaptcha 人机验证 (mini WebView, 只加载几 KB hcaptcha widget)
/// 2. POST /hcaptcha/create.json 用 token 换 h_captcha_temp_id cookie
/// 3. POST /session.json 真正登录
/// 4. 2FA 用户弹 TOTP dialog 再次提交
///
/// 失败 / 高级场景 (OAuth / 注册 / 找回密码 / 2FA 走 backup code 等) 兜底跳
/// [WebViewLoginPage]。
///
/// 上游 linux.do 的 hcaptcha sitekey 写死, 只在启用 hCaptcha 的站点配置下使用;
/// 后续可从 PreloadedDataService 动态拿。
const String _kLinuxDoHcaptchaSiteKey = 'a776b4ac-8c4c-441e-986a-c6ee9ed8cf08';

/// 登录页依赖的外部服务。生产环境全部用默认实现；测试里注入假的，
/// 这样不碰钥匙串、WebView 和论坛。
class LoginPageServices {
  const LoginPageServices({
    this.loadCredentials,
    this.clearCredentials,
    this.submit,
  });

  /// 读已保存的账号密码
  final Future<({String? username, String? password})> Function()?
  loadCredentials;

  /// 清除已保存的账号密码
  final Future<void> Function()? clearCredentials;

  /// 表单提交（默认走 WebView 登录对话框全流程）
  final Future<bool> Function({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  })?
  submit;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.services});

  final LoginPageServices? services;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String? _savedUsername;
  String? _savedPassword;
  bool _credentialsLoaded = false;
  bool _browserAuthLaunching = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    if (identical(
      UserApiKeyLoginFlow.instance.onFlowFinished,
      _onBrowserAuthFinished,
    )) {
      UserApiKeyLoginFlow.instance.onFlowFinished = null;
    }
    super.dispose();
  }

  /// 浏览器授权登录:拉起系统浏览器打开 /user-api-key/new,授权后
  /// 深链 uscardforum://auth_redirect 回 App,由 UserApiKeyLoginFlow 完成
  /// OTP 兑换与登录收口,这里只负责发起和成功后 pop。
  Future<void> _loginWithBrowserAuth() async {
    if (_browserAuthLaunching) return;
    setState(() => _browserAuthLaunching = true);
    UserApiKeyLoginFlow.instance.onFlowFinished = _onBrowserAuthFinished;
    try {
      // 首次会懒生成 RSA 密钥对(isolate),可能耗时数秒
      final launched = await UserApiKeyLoginFlow.instance.start();
      if (!launched && mounted) {
        ToastService.showError('无法打开浏览器,请重试');
      }
    } finally {
      if (mounted) setState(() => _browserAuthLaunching = false);
    }
  }

  void _onBrowserAuthFinished(bool success) {
    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved =
          await (widget.services?.loadCredentials ??
              CredentialStoreService().load)();
      if (!mounted) return;
      setState(() {
        _savedUsername = saved.username;
        _savedPassword = saved.password;
        _credentialsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _credentialsLoaded = true);
    }
  }

  /// 确保 jar 里有 cf_clearance。没有 → 弹 fluxdo 现有的 CF 手动验证页让用户
  /// 人机交互拿 cookie, 然后**显式 sync** 从 WebView cookie store 到 dart jar
  /// (这步 [CfChallengeService.showManualVerify] 本身不做, sync 一般是
  /// [CfChallengeInterceptor._syncCookiesOnce] 触发, 我们直接调 showManualVerify
  /// 不经过 interceptor, 所以要手动 sync, 不然 jar 还是空)。
  Future<bool> _ensureCfClearance() async {
    final jar = CookieJarService();
    var clearance = await jar.getCfClearance();
    if (clearance != null && clearance.isNotEmpty) return true;
    if (!mounted) return false;

    final requestGeneration = AuthSession().generation;
    final ok = await CfChallengeService().showManualVerify(context, true);
    if (ok != true) return false;

    // 等 1.5s 让 WV 网络栈把 Set-Cookie 写完, 然后同步 CF/验证码相关 cookie。
    // 这里明确排除 Discourse session cookie，登录成功收口流程会单独同步它们。
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var i = 0; i < 3; i++) {
      await BoundarySyncService.instance.syncFromWebView(
        cookieNames: null,
        excludeCookieNames: CookieJarService.authCookieNames,
        requestGeneration: requestGeneration,
      );
      clearance = await jar.getCfClearance();
      if (clearance != null && clearance.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // 验证页已判通过但没拿到 cf_clearance：站点对这个用户/IP 没出挑战时本来就
    // 不发这个 cookie。照样放行，真被 CF 拦下时登录对话框会在 CSRF 403 时再验一次，
    // 不能因为缺 cookie 就永远登不上。
    return true;
  }

  /// 表单提交回调。返 true 表示走完成功路径并已 pop, false 留在表单。
  Future<bool> _handleSubmit({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  }) async {
    final service = DiscourseService();

    // Step 0: jar 必须有 cf_clearance, 否则 native dio 任何请求都被 CF 当 bot
    // 直接 403 (TLS 指纹不对). 没有就弹 CF 手动验证页让用户人机过一次。
    if (!await _ensureCfClearance()) {
      if (mounted) {
        ToastService.showError('Cloudflare 验证未完成,请重试');
      }
      return false;
    }
    if (!mounted) return false;

    // hcaptcha endpoint: 从 SharedPreferences 拿 (站长改 mount 时填到设置里);
    // 没配就让 dialog 用内置 fallback 列表 (/captcha/hcaptcha/create.json →
    // /hcaptcha/create.json)。读 prefs 直接走 SharedPreferences (不依赖
    // riverpod, LoginPage 是普通 StatefulWidget)。
    final prefs = await SharedPreferences.getInstance();
    final hcaptchaEndpoint = prefs.getString('pref_hcaptcha_create_endpoint');
    if (!mounted) return false;

    // Step 1-3: WebView 内 JS 全流程登录 (csrf → hcaptcha/create → session)。
    // 三个请求都由 WebView 内核发出, TLS/JA3 指纹与 CF 签发 cf_clearance 时一致,
    // 避开 dio (IO/rhttp 适配器) 指纹不匹配导致的 403 (BAD CSRF)。
    // 2FA 通过 onNeedSecondFactor 回调弹 TOTP, 由 dialog 内同一 WebView 重试。
    final result = await showWebViewLoginDialog(
      context,
      siteKey: _kLinuxDoHcaptchaSiteKey,
      identifier: identifier,
      password: password,
      hcaptchaCreateEndpoint: hcaptchaEndpoint,
      onNeedSecondFactor: (need) => showTwoFactorDialog(
        context,
        hint: need.totpEnabled ? '请输入身份验证器 App 显示的 6 位验证码' : '此账号需要二步验证',
        onUseBackupCode: () => _loginWithWebView(),
      ),
    );
    if (!mounted) return false;
    if (result == null || result.status == WebViewLoginStatus.canceled) {
      return false;
    }

    if (result.status == WebViewLoginStatus.success) {
      // dialog 已把会话 cookie (_t/_forum_session) 同步落 jar,
      // 这里复用收尾: AuthSession.advance → setToken → 预加载数据 → 登录广播。
      await service.finalizeNativeLoginSuccess(identifier);
      // 保存账号密码 (可选)
      if (rememberCredentials) {
        try {
          await CredentialStoreService().save(identifier, password);
        } catch (e) {
          debugPrint('[LoginPage] 保存账号失败,不影响登录: $e');
        }
      }
      if (!mounted) return true;
      ToastService.showSuccess(S.current.webviewLogin_loginSuccess);
      Navigator.of(context).pop(true);
      return true;
    }

    // 失败 — toast 出来
    _showFailureToast(
      LoginFailure(
        result.loginErrorKind ?? LoginErrorKind.unknown,
        message: result.errorMessage,
      ),
    );
    return false;
  }

  void _showFailureToast(LoginFailure f) {
    final msg = switch (f.kind) {
      LoginErrorKind.invalidCredentials => '用户名或密码错误',
      LoginErrorKind.secondFactorRequired => f.message ?? '二步验证失败',
      LoginErrorKind.notActivated => '账号未激活,请到邮箱 ${f.sentToEmail ?? ''} 完成激活',
      LoginErrorKind.notApproved => '账号尚未通过审核',
      LoginErrorKind.passwordExpired => '密码已过期,请用浏览器登录重设密码',
      LoginErrorKind.network => f.message ?? '网络异常',
      LoginErrorKind.unknown => f.message ?? '登录失败',
    };
    ToastService.showError(msg);
  }

  Future<void> _loginWithWebView([String? initialUrl]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebViewLoginPage(initialUrl: initialUrl),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clearSavedCredentials() async {
    await (widget.services?.clearCredentials ??
        CredentialStoreService().clear)();
    if (!mounted) return;
    setState(() {
      _savedUsername = null;
      _savedPassword = null;
    });
    ToastService.showSuccess('已清除保存的账号密码');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);

    // v2 登录（设计说明 §5.4）：导航左返回 / 右网络设置；App 图标 64；
    // 分组输入；主按钮 48；「或」分隔；次按钮 48；文字按钮；页脚说明。无极光背景。
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              slotWidth: 100,
              trailing: [
                if (_credentialsLoaded && _savedUsername != null)
                  AppIconButton(
                    icon: AppIcons.delete,
                    semanticLabel: '清除保存的账号',
                    onPressed: _clearSavedCredentials,
                  ),
                AppIconButton(
                  icon: AppIcons.globe,
                  semanticLabel: '网络设置',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NetworkSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageMargin,
                  AppSpace.xxl,
                  AppSpace.pageMargin,
                  AppSpace.x32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppMark(size: 64)),
                        const SizedBox(height: AppSpace.l),
                        Semantics(
                          header: true,
                          child: Text(
                            '登录美卡论坛',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge
                                ?.merge(tokens.text.title)
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          context.l10n.login_slogan,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.merge(tokens.text.meta)
                              .copyWith(color: colors.textMeta),
                        ),
                        const SizedBox(height: AppSpace.xxl),
                        if (!_credentialsLoaded)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: CircularProgressIndicator.adaptive(),
                            ),
                          )
                        else
                          LoginForm(
                            onSubmit: widget.services?.submit ?? _handleSubmit,
                            onForgotPassword: () => _loginWithWebView(
                              '${AppConstants.baseUrl}/password-reset',
                            ),
                            savedUsername: _savedUsername,
                            savedPassword: _savedPassword,
                          ),
                        const SizedBox(height: AppSpace.l),
                        _buildAltLogin(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「或」分隔 + 次按钮（浏览器授权 / 扫码）+ 文字按钮 + 页脚说明
  Widget _buildAltLogin(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final secondary = AppButtonStyles.secondary(context).merge(
      FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, AppSize.replyButton),
        iconColor: colors.textPrimary,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DividerWithLabel(label: '或'),
        const SizedBox(height: AppSpace.l),
        FilledButton.icon(
          onPressed: _browserAuthLaunching ? null : _loginWithBrowserAuth,
          icon: _browserAuthLaunching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(AppIcons.openInNew, size: AppSize.iconM),
          label: const Text('用浏览器授权登录'),
          style: secondary,
        ),
        const SizedBox(height: AppSpace.s),
        FilledButton.icon(
          onPressed: _loginWithQrScan,
          icon: const Icon(AppIcons.qrCode, size: AppSize.iconM),
          label: Text(context.l10n.login_scanToLogin),
          style: secondary,
        ),
        const SizedBox(height: AppSpace.s),
        TextButton(
          onPressed: () => _loginWithWebView(),
          child: const Text('其他方式（OAuth / Passkey / 注册）'),
        ),
        const SizedBox(height: AppSpace.s),
        Text(
          context.l10n.login_browserHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.merge(tokens.text.meta)
              .copyWith(color: colors.textMeta),
        ),
      ],
    );
  }

  /// 扫码登录:跳转扫码页,成功后 pop 登录页
  Future<void> _loginWithQrScan() async {
    final result = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const QrLoginScanPage()));
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: AppHairline()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.merge(context.tokens.text.meta)
                .copyWith(color: context.tokens.colors.textMeta),
          ),
        ),
        const Expanded(child: AppHairline()),
      ],
    );
  }
}
