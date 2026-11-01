import 'package:app_icons/app_icons.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/s.dart';
import '../services/eruda_settings_service.dart';
import '../services/log/logger_utils.dart';
import '../services/toast_service.dart';
import '../settings/settings_model.dart';
import '../utils/share_utils.dart';
import '../widgets/settings/rate_limit_settings.dart';
import '../widgets/settings/settings_group_page.dart';
import 'app_logs_page.dart';
import 'perf_diagnostics_page.dart';

/// 诊断（设置 › 高级 › 诊断，0.4.0 计划 §M8）
///
/// 日志 / 调试工具 / 发给开发者三组。HTTP 状态码、请求头和原始错误只在这里出现，
/// 其他页面的报错保持一句人话（[ErrorView] 的「查看详情」也从这里进）。
class DiagnosticsPage extends StatelessWidget {
  final String? highlightId;

  const DiagnosticsPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.settings_diagnostics,
      groupsBuilder: buildDiagnosticsGroups,
      highlightId: highlightId,
    );
  }
}

/// 诊断页的数据声明
List<SettingsGroup> buildDiagnosticsGroups(BuildContext context) {
  final l10n = context.l10n;

  ActionModel logRow(String id, String title, IconData icon, LogTypeFilter t) =>
      ActionModel(
        id: id,
        title: title,
        icon: icon,
        onTap: (context, ref) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AppLogsPage(initialType: t)),
        ),
      );

  return [
    SettingsGroup(
      title: l10n.diagnostics_logs,
      icon: AppIcons.history,
      items: [
        logRow(
          'appLogs',
          l10n.appLogs_title,
          AppIcons.article,
          LogTypeFilter.all,
        ),
        logRow(
          'networkLogs',
          l10n.debugTools_networkLogs,
          AppIcons.serverOff,
          LogTypeFilter.network,
        ),
        logRow(
          'cfLogs',
          l10n.debugTools_cfLogs,
          AppIcons.shield,
          LogTypeFilter.cfChallenge,
        ),
        ActionModel(
          id: 'perfDiagnostics',
          title: l10n.diagnostics_perf,
          icon: AppIcons.speed,
          onTap: (context, ref) => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PerfDiagnosticsPage()),
          ),
        ),
      ],
    ),
    SettingsGroup(
      title: l10n.diagnostics_tools,
      icon: AppIcons.code,
      footer: l10n.diagnostics_erudaHint,
      items: [
        CustomModel(
          id: 'erudaConsole',
          title: l10n.diagnostics_eruda,
          builder: (context, ref) => ValueListenableBuilder<bool>(
            valueListenable: ErudaSettingsService.instance.notifier,
            builder: (context, enabled, _) => SwitchListTile.adaptive(
              title: Text(l10n.diagnostics_eruda),
              secondary: const Icon(AppIcons.code),
              value: enabled,
              onChanged: ErudaSettingsService.instance.setEnabled,
            ),
          ),
        ),
      ],
    ),
    SettingsGroup(
      title: l10n.diagnostics_send,
      icon: AppIcons.send,
      footer: l10n.diagnostics_footer,
      items: [
        ActionModel(
          id: 'copyDeviceInfo',
          title: l10n.appLogs_copyDeviceInfo,
          icon: AppIcons.copy,
          onTap: (context, ref) async {
            final text = await LoggerUtils.getDeviceInfoText();
            await Clipboard.setData(ClipboardData(text: text));
            ToastService.showSuccess(S.current.common_copiedToClipboard);
          },
        ),
        ActionModel(
          id: 'exportPackage',
          title: l10n.diagnostics_exportPackage,
          icon: AppIcons.upload,
          onTap: (context, ref) async {
            final path = await LoggerUtils.getShareFilePath();
            await ShareUtils.shareFile(
              XFile(path),
              subject: S.current.appLogs_shareSubject,
            );
          },
        ),
      ],
    ),
    // 并发与限流从网络设置移到这里（补充稿 33）：预设分段 + 自定义时三条滑杆
    SettingsGroup(
      title: l10n.diagnostics_advanced,
      icon: AppIcons.speed,
      wrapInCard: false,
      footer: l10n.diagnostics_rateLimitFooter,
      items: [
        CustomModel(
          id: 'rateLimit',
          title: l10n.networkSettings_rateLimitTitle,
          subtitle: l10n.diagnostics_advanced,
          builder: (context, ref) => const RateLimitSettings(),
        ),
      ],
    ),
  ];
}
