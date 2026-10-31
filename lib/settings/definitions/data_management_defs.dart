import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../pages/data_management_page.dart';
import '../settings_model.dart';

/// 数据管理设置数据声明
List<SettingsGroup> buildDataManagementGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    // Section 1 — 缓存管理
    SettingsGroup(
      title: l10n.dataManagement_cacheManagement,
      icon: AppIcons.delete,
      // 区块内部自带分段卡片
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'cacheManagement',
          title: l10n.dataManagement_cacheManagement,
          builder: (context, ref) => const CacheManagementSection(),
        ),
      ],
    ),

    // Section 2 — 自动管理
    SettingsGroup(
      title: l10n.dataManagement_autoManagement,
      icon: AppIcons.delete,
      items: [
        SwitchModel(
          id: 'clearOnExit',
          title: l10n.dataManagement_clearOnExit,
          subtitle: l10n.dataManagement_clearOnExitDesc,
          icon: AppIcons.delete,
          getValue: (ref) => ref.watch(preferencesProvider).clearCacheOnExit,
          onChanged: (ref, value) =>
              ref.read(preferencesProvider.notifier).setClearCacheOnExit(value),
        ),
      ],
    ),

    // Section 3 — 数据备份（说明收进页脚）
    SettingsGroup(
      title: l10n.dataManagement_dataBackup,
      footer:
          '${l10n.dataManagement_exportDesc}；${l10n.dataManagement_importDesc}。\n${l10n.dataManagement_backupFooter}',
      icon: AppIcons.upload,
      // 区块内部自带分段卡片
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'dataBackup',
          title: l10n.dataManagement_dataBackup,
          builder: (context, ref) => const DataBackupSection(),
        ),
      ],
    ),

    // Section 4 — 破坏性单独一组
    SettingsGroup(
      title: l10n.dataManagement_destructiveGroup,
      icon: AppIcons.delete,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'localData',
          title: l10n.dataManagement_destructiveGroup,
          builder: (context, ref) =>
              const CacheManagementSection(localOnly: true),
        ),
      ],
    ),
  ];
}
