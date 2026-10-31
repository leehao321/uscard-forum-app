import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../../l10n/s.dart';
import '../../../services/network/adapters/cronet_fallback_service.dart';
import '../../../services/network/adapters/platform_adapter.dart';
import '../../../services/network/doh/network_settings_service.dart';
import '../../../services/network/doh/webview_mitm_policy.dart';
import '../../../services/network/proxy/proxy_settings_service.dart';
import '../../../services/network/rhttp/rhttp_settings_service.dart';
import '../../../services/network/webview/webview_adapter_settings_service.dart';
import '../../../services/toast_service.dart';
import '../../../utils/dialog_utils.dart';
import 'doh_settings_card.dart' show ensureWindowsCertTrusted;

/// 网络引擎卡片（预设单选 + 自定义展开）
///
/// 顶部用预设 chips（标准 / 高性能 / 兼容 / 自定义）单选，常用场景一键切换；
/// 复杂开关（rhttp 模式、WebView、Android 降级）收进「自定义」展开区。
/// 「当前生效引擎」压成一行，降级等异常即时可见。
class EngineCard extends StatefulWidget {
  const EngineCard({super.key});

  @override
  State<EngineCard> createState() => _EngineCardState();
}

enum _EnginePreset { standard, performance, compat, custom }

class _EngineCardState extends State<EngineCard> {
  bool _customExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rhttp = RhttpSettingsService.instance;
    final webview = WebViewAdapterSettingsService.instance;
    final fallbackService = CronetFallbackService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        rhttp.notifier,
        NetworkSettingsService.instance.notifier,
        NetworkSettingsService.instance.isApplying,
        ProxySettingsService.instance.notifier,
        webview.notifier,
        webview.effectiveNotifier,
        fallbackService,
      ]),
      builder: (context, _) {
        final rhttpSettings = rhttp.current;
        final rhttpEnabled = rhttpSettings.enabled;
        final webviewEnabled = webview.enabled;

        final autoPreset = _presetOf(
          rhttpEnabled,
          rhttpSettings.mode,
          webviewEnabled,
        );
        final isCustom = _customExpanded || autoPreset == _EnginePreset.custom;
        final shownPreset = isCustom ? _EnginePreset.custom : autoPreset;

        // v2：引擎单选（标准 ✓ / 高性能 / 兼容 / 自定义 ›），页脚写当前生效引擎，
        // 自定义展开后下面多一组开关
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPresetSelector(theme, shownPreset, rhttp, webview),
            _buildCurrentEngineRow(theme, fallbackService),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: isCustom
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: AppSpace.m),
                child: SegmentedCardGroup(
                  children: [
                    _buildCustomSection(
                      theme,
                      rhttp,
                      rhttpSettings,
                      webview,
                      webviewEnabled,
                      fallbackService,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---- 预设 ----

  Widget _buildPresetSelector(
    ThemeData theme,
    _EnginePreset shown,
    RhttpSettingsService rhttp,
    WebViewAdapterSettingsService webview,
  ) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final items = <(_EnginePreset, String)>[
      (_EnginePreset.standard, l10n.enginePreset_standard),
      (_EnginePreset.performance, l10n.enginePreset_performance),
      (_EnginePreset.compat, l10n.enginePreset_compat),
      (_EnginePreset.custom, l10n.enginePreset_custom),
    ];
    return SegmentedCardGroup(
      children: [
        for (final item in items)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: item.$1 == shown,
            child: ListTile(
              title: Text(item.$2),
              subtitle: item.$1 == shown
                  ? Text(
                      _presetDesc(shown),
                      style: theme.textTheme.bodySmall!
                          .merge(tokens.text.meta)
                          .copyWith(color: colors.textMeta),
                    )
                  : null,
              trailing: item.$1 == _EnginePreset.custom
                  ? Icon(
                      shown == _EnginePreset.custom
                          ? AppIcons.check
                          : AppIcons.chevronRight,
                      size: shown == _EnginePreset.custom
                          ? AppSize.iconM
                          : AppSize.iconS,
                      color: shown == _EnginePreset.custom
                          ? colors.brandPrimary
                          : colors.textMeta,
                    )
                  : (item.$1 == shown
                        ? Icon(
                            AppIcons.check,
                            size: AppSize.iconM,
                            color: colors.brandPrimary,
                          )
                        : null),
              onTap: () => _applyPreset(item.$1, rhttp, webview),
            ),
          ),
      ],
    );
  }

  Future<void> _applyPreset(
    _EnginePreset preset,
    RhttpSettingsService rhttp,
    WebViewAdapterSettingsService webview,
  ) async {
    switch (preset) {
      case _EnginePreset.standard:
        setState(() => _customExpanded = false);
        webview.disableSessionFallback();
        await rhttp.setEnabled(false);
        await webview.setEnabled(false);
      case _EnginePreset.performance:
        setState(() => _customExpanded = false);
        webview.disableSessionFallback();
        await rhttp.setMode(RhttpMode.always);
        await rhttp.setEnabled(true);
        await webview.setEnabled(false);
      case _EnginePreset.compat:
        if (!await _ensureWebViewCanBeEnabled()) return;
        if (!mounted) return;
        setState(() => _customExpanded = false);
        webview.disableSessionFallback();
        await rhttp.setEnabled(false);
        await webview.setEnabled(true);
      case _EnginePreset.custom:
        setState(() => _customExpanded = true);
    }
  }

  Future<bool> _ensureWebViewCanBeEnabled() async {
    final requiresCa = WebViewMitmPolicy.requiresTrustedCa(
      isWindows: Platform.isWindows,
      dohEnabled: NetworkSettingsService.instance.current.dohEnabled,
      webViewAdapterEnabled: true,
    );
    if (!requiresCa) return true;
    return ensureWindowsCertTrusted(context);
  }

  Future<void> _setWebViewEnabled(
    bool value,
    WebViewAdapterSettingsService webview,
  ) async {
    if (value && !await _ensureWebViewCanBeEnabled()) return;
    await webview.setEnabled(value);
  }

  _EnginePreset _presetOf(bool rhttpOn, RhttpMode mode, bool webviewOn) {
    if (!rhttpOn && !webviewOn) return _EnginePreset.standard;
    if (rhttpOn && mode == RhttpMode.always && !webviewOn) {
      return _EnginePreset.performance;
    }
    if (!rhttpOn && webviewOn) return _EnginePreset.compat;
    return _EnginePreset.custom;
  }

  String _presetDesc(_EnginePreset preset) {
    final l10n = context.l10n;
    return switch (preset) {
      _EnginePreset.standard => l10n.enginePreset_standardDesc,
      _EnginePreset.performance => l10n.enginePreset_performanceDesc,
      _EnginePreset.compat => l10n.enginePreset_compatDesc,
      _EnginePreset.custom => l10n.enginePreset_customDesc,
    };
  }

  // ---- 当前生效引擎（一行）----

  Widget _buildCurrentEngineRow(
    ThemeData theme,
    CronetFallbackService fallbackService,
  ) {
    final effective = resolveEffectiveAdapter();
    final engineName = getAdapterDisplayName(effective.type);
    final isFallback = effective.reason == AdapterReason.fallback;
    final webviewSettings = WebViewAdapterSettingsService.instance;
    final webviewEnabled = webviewSettings.effectiveEnabled;
    final sessionFallback = webviewSettings.sessionFallbackEnabled;
    final showReset = isFallback && Platform.isAndroid && !sessionFallback;

    // WebView 在最外层分流：主站 API 走 WebView，其余走推算出的引擎。
    // 它不参与 resolveEffectiveAdapter()，所以开启时要单独显示分流，
    // 否则「兼容」预设会错误地只显示 native/Cronet。
    final tokens = context.tokens;
    final colors = tokens.colors;
    final meta = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final InlineSpan span;
    if (webviewEnabled) {
      span = TextSpan(
        text: context.l10n.engineStatus_webviewSplit(engineName),
        style: meta,
      );
    } else {
      span = TextSpan(
        children: [
          TextSpan(
            text: '${context.l10n.engineStatus_currentEngine}: ',
            style: meta,
          ),
          TextSpan(
            text: engineName,
            style: meta.copyWith(
              color: isFallback ? colors.textDestructive : colors.textPrimary,
            ),
          ),
          TextSpan(text: '  ·  ${_reasonText(effective.reason)}', style: meta),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.m, AppSpace.s, AppSpace.m, 0),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              span,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showReset)
            AppIconButton(
              icon: AppIcons.refresh,
              semanticLabel: context.l10n.networkAdapter_resetFallback,
              onPressed: () => _resetFallbackState(fallbackService),
            ),
          if (sessionFallback)
            AppIconButton(
              icon: AppIcons.close,
              semanticLabel: S.current.cf_sessionCompatDisable,
              onPressed: webviewSettings.disableSessionFallback,
            ),
        ],
      ),
    );
  }

  // ---- 自定义展开区 ----

  Widget _buildCustomSection(
    ThemeData theme,
    RhttpSettingsService rhttp,
    RhttpSettings rhttpSettings,
    WebViewAdapterSettingsService webview,
    bool webviewEnabled,
    CronetFallbackService fallbackService,
  ) {
    final l10n = context.l10n;
    final rhttpEnabled = rhttpSettings.enabled;
    final ns = NetworkSettingsService.instance.current;
    final echFallback =
        rhttpEnabled && ns.dohEnabled && ns.echServerUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _divider(theme),
        // rhttp 引擎
        SwitchListTile.adaptive(
          dense: true,
          secondary: Icon(
            AppIcons.rocket,
            fill: rhttpEnabled ? 1 : 0,
            color: rhttpEnabled ? theme.colorScheme.primary : null,
          ),
          title: Text(l10n.rhttpEngine_title),
          subtitle: Text(l10n.rhttpEngine_enabledDesc),
          value: rhttpEnabled,
          onChanged: (value) => rhttp.setEnabled(value),
        ),
        if (rhttpEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: M3eButtonGroup<RhttpMode>(
                    items: [
                      M3eButtonGroupItem(
                        value: RhttpMode.always,
                        label: Text(l10n.rhttpEngine_alwaysUse),
                      ),
                      M3eButtonGroupItem(
                        value: RhttpMode.proxyOnly,
                        label: Text(l10n.rhttpEngine_proxyDohOnly),
                      ),
                    ],
                    selected: rhttpSettings.mode,
                    onSelected: (mode) => rhttp.setMode(mode),
                  ),
                ),
                if (echFallback)
                  _miniHint(theme, l10n.rhttpEngine_echFallbackHint),
                if (rhttpSettings.forceDisabled)
                  _miniHint(
                    theme,
                    l10n.rhttpEngine_initFailedHint,
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
          ),
        _divider(theme),
        // WebView 适配器
        SwitchListTile.adaptive(
          dense: true,
          secondary: Icon(
            AppIcons.language,
            fill: webviewEnabled ? 1 : 0,
            color: webviewEnabled ? theme.colorScheme.primary : null,
          ),
          title: Text(l10n.webviewAdapter_title),
          subtitle: Text(l10n.webviewAdapter_enabledDesc),
          value: webviewEnabled,
          onChanged: (value) => _setWebViewEnabled(value, webview),
        ),
        // Android：Cronet 降级控制
        if (Platform.isAndroid)
          ..._buildFallbackControls(theme, fallbackService),
      ],
    );
  }

  /// Android Cronet 降级控制
  List<Widget> _buildFallbackControls(
    ThemeData theme,
    CronetFallbackService fallbackService,
  ) {
    final l10n = context.l10n;
    final hasFallenBack = fallbackService.hasFallenBack;
    final forceFallback = fallbackService.forceFallback;
    final failureReason = fallbackService.fallbackReason;
    final autoFellBack = hasFallenBack && !forceFallback;

    return [
      _divider(theme),
      SwitchListTile.adaptive(
        secondary: const Icon(AppIcons.sync),
        title: Text(l10n.networkAdapter_forceFallback),
        subtitle: Text(l10n.networkAdapter_forceFallbackDesc),
        value: forceFallback,
        onChanged: (value) async {
          await fallbackService.setForceFallback(value);
          ToastService.showSuccess(S.current.networkAdapter_settingSaved);
        },
      ),
      if (autoFellBack) ...[
        ListTile(
          leading: Icon(AppIcons.info, color: theme.colorScheme.error),
          title: Text(l10n.networkAdapter_autoFallback),
          subtitle: Text(l10n.networkAdapter_autoFallbackDesc),
          dense: true,
        ),
        if (failureReason != null)
          ListTile(
            leading: const Icon(AppIcons.code),
            title: Text(l10n.networkAdapter_viewReason),
            trailing: const Icon(AppIcons.chevronRight, size: 20),
            dense: true,
            onTap: () => _showFailureReasonDialog(failureReason),
          ),
        ListTile(
          leading: const Icon(AppIcons.refresh),
          title: Text(l10n.networkAdapter_resetFallback),
          subtitle: Text(l10n.networkAdapter_resetFallbackDesc),
          trailing: const Icon(AppIcons.chevronRight, size: 20),
          dense: true,
          onTap: () => _resetFallbackState(fallbackService),
        ),
      ],
      if (kDebugMode && !hasFallenBack)
        ListTile(
          leading: Icon(
            AppIcons.autoAwesome,
            color: theme.colorScheme.tertiary,
          ),
          title: Text(l10n.networkAdapter_simulateError),
          subtitle: Text(l10n.networkAdapter_simulateErrorDesc),
          trailing: const Icon(AppIcons.chevronRight, size: 20),
          dense: true,
          onTap: () => _simulateCronetError(fallbackService),
        ),
    ];
  }

  // ---- 小组件 / 映射 ----

  Widget _miniHint(ThemeData theme, String text, {Color? color}) {
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            color != null ? AppIcons.warning : AppIcons.info,
            size: 13,
            color: c,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c,
                fontSize: AppFontSize.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) => Divider(
    height: 1,
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
  );

  // ---- 降级对话框 ----

  Future<void> _showFailureReasonDialog(String reason) async {
    await showAppDialog(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(dialogContext.l10n.networkAdapter_degradeReason),
        content: SingleChildScrollView(
          child: SelectableText(
            reason,
            // 技术原因是多行等宽文字，左对齐才好读（说明文字默认居中）
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: AppFontSize.meta,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_close),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: reason));
              ToastService.showSuccess(S.current.common_copiedToClipboard);
            },
            child: Text(dialogContext.l10n.common_copy),
          ),
        ],
      ),
    );
  }

  String _reasonText(AdapterReason reason) {
    final l10n = context.l10n;
    return switch (reason) {
      AdapterReason.rhttp => l10n.engineStatus_reasonRhttp,
      AdapterReason.gateway => l10n.engineStatus_reasonGateway,
      AdapterReason.proxy => l10n.engineStatus_reasonProxy,
      AdapterReason.fallback => l10n.engineStatus_reasonFallback,
      AdapterReason.native => l10n.engineStatus_reasonNative,
    };
  }

  Future<void> _resetFallbackState(
    CronetFallbackService fallbackService,
  ) async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(dialogContext.l10n.networkAdapter_resetFallback),
        content: Text(dialogContext.l10n.networkAdapter_resetFallbackDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.common_reset),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await fallbackService.reset();
      ToastService.showSuccess(S.current.networkAdapter_resetSuccess);
    }
  }

  Future<void> _simulateCronetError(
    CronetFallbackService fallbackService,
  ) async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(dialogContext.l10n.networkAdapter_simulateError),
        content: Text(dialogContext.l10n.networkAdapter_simulateErrorDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.tertiary,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.common_confirm),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await fallbackService.simulateCronetError();
      ToastService.showInfo(S.current.networkAdapter_simulateSuccess);
    }
  }
}
