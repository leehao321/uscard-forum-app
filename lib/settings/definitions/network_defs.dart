import 'package:flutter/material.dart';
import '../../services/network/proxy/proxy_settings_service.dart';
import '../../services/network/doh/network_settings_service.dart';
import '../../utils/dialog_utils.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';

import '../../l10n/s.dart';
import '../../pages/network_settings_page/widgets/cf_verify_card.dart';
import '../../pages/network_settings_page/widgets/doh_settings_card.dart';
import '../../pages/network_settings_page/widgets/engine_card.dart';
import '../../pages/network_settings_page/widgets/http_proxy_card.dart';
import '../../pages/network_settings_page/widgets/vpn_auto_toggle_card.dart';
import '../../widgets/settings/settings_group_page.dart';
import '../settings_model.dart';
import '../../providers/preferences_provider.dart';

/// 网络设置数据声明
List<SettingsGroup> buildNetworkGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    // 网络引擎
    SettingsGroup(
      title: l10n.networkSettings_engine,
      icon: AppIcons.speed,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'engine',
          title: l10n.networkSettings_engine,
          subtitle: 'rhttp · WebView',
          builder: (context, ref) => const EngineCard(),
        ),
      ],
    ),

    // 网络代理
    SettingsGroup(
      title: l10n.networkSettings_proxy,
      icon: AppIcons.serverOff,
      wrapInCard: false,
      items: [
        // DoH / 上游代理：行内只显示当前状态，点开是半屏（里面是原来的完整设置）
        CustomModel(
          id: 'dohSettings',
          title: 'DNS over HTTPS',
          subtitle: l10n.networkSettings_proxy,
          builder: (context, ref) => ListenableBuilder(
            listenable: NetworkSettingsService.instance.notifier,
            builder: (context, _) => _SheetRow(
              icon: AppIcons.hub,
              title: 'DNS over HTTPS',
              value: NetworkSettingsService.instance.current.dohEnabled
                  ? context.l10n.settings_valueOn
                  : context.l10n.settings_valueOff,
              sheetTitle: 'DNS over HTTPS',
              sheetBuilder: (_) => const DohSettingsCard(),
            ),
          ),
        ),
        CustomModel(
          id: 'httpProxy',
          title: l10n.httpProxy_title,
          subtitle: l10n.networkSettings_proxy,
          builder: (context, ref) => ListenableBuilder(
            listenable: ProxySettingsService.instance.notifier,
            builder: (context, _) {
              final proxy = ProxySettingsService.instance.notifier.value;
              return _SheetRow(
                icon: AppIcons.serverOff,
                title: context.l10n.httpProxy_title,
                value: proxy.enabled
                    ? proxy.protocol.displayName
                    : context.l10n.settings_valueOff,
                sheetTitle: context.l10n.httpProxy_title,
                sheetBuilder: (_) => const HttpProxyCard(),
              );
            },
          ),
        ),
      ],
    ),

    // 辅助功能
    SettingsGroup(
      title: l10n.networkSettings_auxiliary,
      icon: AppIcons.tune,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'vpnAutoToggle',
          title: l10n.vpnToggle_title,
          subtitle: l10n.vpnToggle_subtitle,
          builder: (context, ref) => const VpnAutoToggleCard(),
        ),
        CustomModel(
          id: 'cfVerify',
          title: l10n.cf_securityVerifyTitle,
          subtitle: l10n.networkSettings_auxiliary,
          builder: (context, ref) => const CfVerifyCard(),
        ),
      ],
    ),

    // 自定义（D25）：并发与限流、文件上传等技术项收进子页；调试项在「高级 › 诊断」
    SettingsGroup(
      title: '',
      icon: AppIcons.settings,
      footer: l10n.networkSettings_customFooter,
      items: [
        ActionModel(
          id: 'networkCustom',
          title: l10n.networkSettings_custom,
          icon: AppIcons.tune,
          onTap: (context, ref) => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NetworkCustomPage()),
          ),
        ),
      ],
    ),
  ];
}

/// 网络 › 自定义：并发与限流、文件上传
class NetworkCustomPage extends StatelessWidget {
  const NetworkCustomPage({super.key, this.highlightId});

  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.networkSettings_custom,
      groupsBuilder: buildNetworkCustomGroups,
      highlightId: highlightId,
    );
  }
}

List<SettingsGroup> buildNetworkCustomGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    SettingsGroup(
      title: l10n.networkSettings_upload,
      icon: AppIcons.upload,
      items: [
        SwitchModel(
          id: 'forceDisableMultipartUpload',
          title: l10n.networkSettings_forceDisableMultipart,
          subtitle: l10n.networkSettings_forceDisableMultipartDescription,
          icon: AppIcons.upload,
          getValue: (ref) =>
              ref.watch(preferencesProvider).forceDisableMultipartUpload,
          onChanged: (ref, value) => ref
              .read(preferencesProvider.notifier)
              .setForceDisableMultipartUpload(value),
        ),
      ],
    ),
  ];
}

/// 行 + 半屏：行内右侧写当前状态，点开半屏里放完整设置卡
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.sheetTitle,
    required this.sheetBuilder,
  });

  final IconData icon;
  final String title;
  final String value;
  final String sheetTitle;
  final WidgetBuilder sheetBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Material(
      color: colors.surfaceGrouped,
      borderRadius: BorderRadius.circular(tokens.radius.card),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: colors.brandPrimary),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: colors.textMeta),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(
              AppIcons.chevronRight,
              size: AppSize.iconS,
              color: colors.textMeta,
            ),
          ],
        ),
        onTap: () => showAppBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => AppSheetScaffold(
            title: sheetTitle,
            maxHeightFactor: 0.92,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpace.xl),
              child: sheetBuilder(sheetContext),
            ),
          ),
        ),
      ),
    );
  }
}
