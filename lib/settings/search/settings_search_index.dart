import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../l10n/s.dart';
import '../../pages/appearance_page.dart';
import '../../pages/bottom_nav_settings_page.dart';
import '../../pages/data_management_page.dart';
import '../../pages/diagnostics_page.dart';
import '../../pages/network_settings_page/network_settings_page.dart';
import '../../pages/preferences_page.dart';
import '../../pages/reading_settings_page.dart';
import '../../pages/shortcut_settings_page.dart';
import '../../utils/platform_utils.dart';
import '../definitions/appearance_defs.dart';
import '../definitions/bottom_nav_defs.dart';
import '../definitions/data_management_defs.dart';
import '../definitions/network_defs.dart';
import '../definitions/preferences_defs.dart';
import '../definitions/reading_defs.dart';
import '../definitions/shortcut_defs.dart';
import '../settings_model.dart';

/// 搜索结果项
class SettingsSearchResult {
  final SettingsModel model;
  final String categoryName;
  final IconData categoryIcon;
  final Color categoryColor;

  /// 结果行下方的路径（13 meta），如「外观 › 字体」
  final String path;

  /// 构建目标页面，支持高亮定位
  final Widget Function({String? highlightId}) pageBuilder;

  const SettingsSearchResult({
    required this.model,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.path,
    required this.pageBuilder,
  });
}

/// 构建全局搜索索引
List<SettingsSearchResult> buildSearchIndex(BuildContext context) {
  final l10n = context.l10n;

  List<SettingsSearchResult> fromGroups(
    List<SettingsGroup> groups, {
    required String categoryName,
    required IconData categoryIcon,
    required Color categoryColor,
    required Widget Function({String? highlightId}) pageBuilder,
  }) {
    return [
      for (final g in groups)
        for (final item in g.items)
          if (item is! PlatformConditionalModel || item.shouldShow)
            SettingsSearchResult(
              model: item is PlatformConditionalModel ? item.inner : item,
              categoryName: categoryName,
              categoryIcon: categoryIcon,
              categoryColor: categoryColor,
              path: g.title.isEmpty || g.title == categoryName
                  ? categoryName
                  : '$categoryName › ${g.title}',
              pageBuilder: pageBuilder,
            ),
    ];
  }

  return [
    ...fromGroups(
      buildReadingGroups(context),
      categoryName: l10n.settings_reading,
      categoryIcon: AppIcons.autoStories,
      categoryColor: Colors.deepOrange,
      pageBuilder: ({highlightId}) =>
          ReadingSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildPreferencesGroups(context),
      categoryName: l10n.settings_preferences,
      categoryIcon: AppIcons.tune,
      categoryColor: Colors.deepPurple,
      pageBuilder: ({highlightId}) =>
          PreferencesPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildBottomNavGroups(context),
      categoryName: l10n.settings_bottomNav,
      categoryIcon: AppIcons.menu,
      categoryColor: Colors.amber,
      pageBuilder: ({highlightId}) =>
          BottomNavSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildAppearanceGroups(context),
      categoryName: l10n.settings_appearance,
      categoryIcon: AppIcons.palette,
      categoryColor: Colors.teal,
      pageBuilder: ({highlightId}) =>
          AppearancePage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildNetworkGroups(context),
      categoryName: l10n.settings_network,
      categoryIcon: AppIcons.serverOff,
      categoryColor: Colors.blueGrey,
      pageBuilder: ({highlightId}) =>
          NetworkSettingsPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildNetworkCustomGroups(context),
      categoryName: l10n.settings_network,
      categoryIcon: AppIcons.serverOff,
      categoryColor: Colors.blueGrey,
      pageBuilder: ({highlightId}) =>
          NetworkCustomPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildDataManagementGroups(context),
      categoryName: l10n.settings_dataManagement,
      categoryIcon: AppIcons.folder,
      categoryColor: Colors.brown,
      pageBuilder: ({highlightId}) =>
          DataManagementPage(highlightId: highlightId),
    ),
    ...fromGroups(
      buildDiagnosticsGroups(context),
      categoryName: l10n.settings_diagnostics,
      categoryIcon: AppIcons.history,
      categoryColor: Colors.grey,
      pageBuilder: ({highlightId}) => DiagnosticsPage(highlightId: highlightId),
    ),
    // 快捷键（仅桌面端）
    if (PlatformUtils.isDesktop)
      ...fromGroups(
        buildShortcutGroups(context),
        categoryName: l10n.settings_shortcuts,
        categoryIcon: AppIcons.code,
        categoryColor: Colors.cyan,
        pageBuilder: ({highlightId}) =>
            ShortcutSettingsPage(highlightId: highlightId),
      ),
  ];
}
