import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/deep_link_service.dart';
import '../widgets/common/app_mark.dart';
import 'login_page.dart';
import 'network_settings_page/network_settings_page.dart';

/// 引导页（v2，设计说明 §5.4「引导页」）：App 图标 96、名称、四字口号、
/// 三条说明、主按钮「登录」、透明按钮「先逛逛」、右上网络设置。无极光背景。
class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  /// 初始化邮箱链接登录的 Deep Link 监听（测试里关掉，不碰平台通道）
  final bool initializeDeepLink;

  const OnboardingPage({
    super.key,
    required this.onComplete,
    this.initializeDeepLink = true,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  @override
  void initState() {
    super.initState();
    // 初始化 Deep Link 服务以处理邮箱链接登录
    if (!widget.initializeDeepLink) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.onEmailLoginSuccess = () {
        if (mounted) widget.onComplete();
      };
      DeepLinkService.instance.initialize(context);
    });
  }

  @override
  void dispose() {
    if (widget.initializeDeepLink) {
      DeepLinkService.instance.onEmailLoginSuccess = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final large = AppButtonStyles.large.merge(
      FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, AppSize.replyButton),
      ),
    );

    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              automaticallyImplyLeading: false,
              trailing: [
                AppIconButton(
                  icon: AppIcons.globe,
                  semanticLabel: context.l10n.onboarding_networkSettings,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NetworkSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.pageMargin,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpace.xxl),
                        const AppMark(size: 96),
                        const SizedBox(height: AppSpace.xl),
                        Semantics(
                          header: true,
                          child: Text(
                            '美卡论坛',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall
                                ?.merge(tokens.text.title)
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: AppSpace.s),
                        Text(
                          context.l10n.onboarding_slogan,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.merge(tokens.text.meta)
                              .copyWith(color: colors.textMeta),
                        ),
                        const SizedBox(height: AppSpace.x32),
                        const _Point(
                          icon: AppIcons.visibility,
                          title: '不登录也能浏览',
                          body: '公开话题可直接阅读，登录后才能回复和收藏。',
                        ),
                        const _Point(
                          icon: AppIcons.globe,
                          title: '连不上就先设置网络',
                          body: '右上角可以配置代理或 DNS。',
                        ),
                        const _Point(
                          icon: AppIcons.lock,
                          title: '笔记和统计只在本机',
                          body: '不会上传到论坛。',
                        ),
                        const SizedBox(height: AppSpace.l),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                AppSpace.s,
                AppSpace.pageMargin,
                AppSpace.l,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () => _navigateToLogin(context),
                      style: large,
                      child: Text(context.l10n.common_login),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    TextButton(
                      onPressed: () => _continueAsGuest(context),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          double.infinity,
                          AppSize.replyButton,
                        ),
                      ),
                      child: Text(context.l10n.onboarding_guestAccess),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToLogin(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );

    if (result == true && context.mounted) {
      widget.onComplete();
    }
  }

  void _continueAsGuest(BuildContext context) {
    widget.onComplete();
  }
}

/// 一条说明：图标 20 brand + 标题 17 + 说明 13
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: AppSize.iconM, color: colors.brandPrimary),
          ),
          const SizedBox(width: AppSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge
                      ?.merge(tokens.text.control)
                      .copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall
                      ?.merge(tokens.text.meta)
                      .copyWith(color: colors.textMeta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
