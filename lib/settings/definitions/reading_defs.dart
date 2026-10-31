import 'dart:io';

import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/sites/uscard.dart';
import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../services/preloaded_data_service.dart';
import '../choice_sheet.dart';
import '../settings_model.dart';

/// 阅读设置数据声明
List<SettingsGroup> buildReadingGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    SettingsGroup(
      title: l10n.appearance_reading,
      icon: AppIcons.autoStories,
      items: [
        SwitchModel(
          id: 'displayPanguSpacing',
          title: l10n.appearance_panguSpacing,
          subtitle: l10n.appearance_panguSpacingDesc,
          icon: AppIcons.autoFixHigh,
          getValue: (ref) => ref.watch(preferencesProvider).displayPanguSpacing,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setDisplayPanguSpacing(v),
        ),
        SwitchModel(
          id: 'showSuggestedTopics',
          title: l10n.reading_showSuggestedTopics,
          subtitle: l10n.reading_showSuggestedTopicsDesc,
          icon: AppIcons.forum,
          getValue: (ref) => ref.watch(preferencesProvider).showSuggestedTopics,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setShowSuggestedTopics(v),
        ),
      ],
    ),
    SettingsGroup(
      title: l10n.preferences_basic,
      icon: AppIcons.touchApp,
      items: [
        SwitchModel(
          id: 'longPressPreview',
          title: l10n.preferences_longPressPreview,
          subtitle: l10n.preferences_longPressPreviewDesc,
          icon: AppIcons.touchApp,
          getValue: (ref) => ref.watch(preferencesProvider).longPressPreview,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setLongPressPreview(v),
        ),
        SwitchModel(
          id: 'openExternalLinksInAppBrowser',
          title: l10n.preferences_openLinksInApp,
          subtitle: l10n.preferences_openLinksInAppDesc,
          icon: AppIcons.openInNew,
          getValue: (ref) =>
              ref.watch(preferencesProvider).openExternalLinksInAppBrowser,
          onChanged: (ref, v) => ref
              .read(preferencesProvider.notifier)
              .setOpenExternalLinksInAppBrowser(v),
        ),
        SwitchModel(
          id: 'expandRelatedLinks',
          title: l10n.reading_expandRelatedLinks,
          subtitle: l10n.reading_expandRelatedLinksDesc,
          icon: AppIcons.link,
          getValue: (ref) => ref.watch(preferencesProvider).expandRelatedLinks,
          onChanged: (ref, v) =>
              ref.read(preferencesProvider.notifier).setExpandRelatedLinks(v),
        ),
        // 服务端未启用签名插件时隐藏该开关
        if (PreloadedDataService().signaturesEnabled)
          SwitchModel(
            id: 'showSignatures',
            title: l10n.reading_showSignatures,
            subtitle: l10n.reading_showSignaturesDesc,
            icon: AppIcons.edit,
            getValue: (ref) => ref.watch(preferencesProvider).showSignatures,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setShowSignatures(v),
          ),
        if (PreloadedDataService().signaturesEnabled)
          SwitchModel(
            id: 'adaptiveSignatureFrameRate',
            title: l10n.reading_adaptiveSignatureFrameRate,
            subtitle: l10n.reading_adaptiveSignatureFrameRateDesc,
            icon: AppIcons.speed,
            getValue: (ref) =>
                ref.watch(preferencesProvider).adaptiveSignatureFrameRate,
            onChanged: (ref, v) => ref
                .read(preferencesProvider.notifier)
                .setAdaptiveSignatureFrameRate(v),
          ),
        ActionModel(
          id: 'bookmarksOpenMode',
          title: l10n.reading_bookmarksOpenMode,
          icon: AppIcons.menu,
          valueBuilder: (ref) => switch (ref
              .watch(preferencesProvider)
              .bookmarksOpenMode) {
            BookmarksOpenMode.defaultRoute =>
              l10n.reading_bookmarksOpenModeDefault,
            BookmarksOpenMode.tabbedWorkspace =>
              l10n.reading_bookmarksOpenModeTabbedWorkspace,
          },
          onTap: (context, ref) => _showBookmarksOpenModePicker(
            context,
            ref,
            ref.read(preferencesProvider).bookmarksOpenMode,
          ),
        ),
        PlatformConditionalModel(
          inner: SwitchModel(
            id: 'aiSwipeEntry',
            title: l10n.reading_aiSwipeEntry,
            subtitle: l10n.reading_aiSwipeEntryDesc,
            icon: AppIcons.back,
            getValue: (ref) => ref.watch(preferencesProvider).aiSwipeEntry,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setAiSwipeEntry(v),
          ),
          condition: () => Platform.isIOS || Platform.isAndroid,
        ),
      ],
    ),
    // 树形视图依赖站点的树形回复插件，美卡没有，整组设置不显示
    if (uscardCustomization.supportsNestedView)
      SettingsGroup(
        title: l10n.nested_title,
        icon: AppIcons.accountTree,
        items: [
          SwitchModel(
            id: 'defaultNestedView',
            title: l10n.nested_defaultView,
            subtitle: l10n.nested_defaultViewDesc,
            icon: AppIcons.accountTree,
            getValue: (ref) => ref.watch(preferencesProvider).defaultNestedView,
            onChanged: (ref, v) =>
                ref.read(preferencesProvider.notifier).setDefaultNestedView(v),
          ),
          ActionModel(
            id: 'nestedLineStyle',
            title: l10n.nested_lineStyle,
            icon: AppIcons.sort,
            valueBuilder: (ref) => switch (ref
                .watch(preferencesProvider)
                .nestedLineStyle) {
              NestedLineStyle.auto => l10n.nested_lineStyleAuto,
              NestedLineStyle.lLine => l10n.nested_lineStyleL,
              NestedLineStyle.straight => l10n.nested_lineStyleStraight,
            },
            onTap: (context, ref) => _showLineStylePicker(
              context,
              ref,
              ref.read(preferencesProvider).nestedLineStyle,
            ),
          ),
        ],
      ),
  ];
}

void _showLineStylePicker(
  BuildContext context,
  WidgetRef ref,
  NestedLineStyle current,
) {
  final l10n = context.l10n;
  showSettingsChoiceSheet<NestedLineStyle>(
    context,
    title: l10n.nested_lineStyle,
    options: [
      (NestedLineStyle.auto, l10n.nested_lineStyleAuto),
      (NestedLineStyle.lLine, l10n.nested_lineStyleL),
      (NestedLineStyle.straight, l10n.nested_lineStyleStraight),
    ],
    current: current,
    onSelected: (v) =>
        ref.read(preferencesProvider.notifier).setNestedLineStyle(v),
  );
}

void _showBookmarksOpenModePicker(
  BuildContext context,
  WidgetRef ref,
  BookmarksOpenMode current,
) {
  final l10n = context.l10n;
  showSettingsChoiceSheet<BookmarksOpenMode>(
    context,
    title: l10n.reading_bookmarksOpenMode,
    options: [
      (BookmarksOpenMode.defaultRoute, l10n.reading_bookmarksOpenModeDefault),
      (
        BookmarksOpenMode.tabbedWorkspace,
        l10n.reading_bookmarksOpenModeTabbedWorkspace,
      ),
    ],
    current: current,
    onSelected: (v) =>
        ref.read(preferencesProvider.notifier).setBookmarksOpenMode(v),
  );
}
