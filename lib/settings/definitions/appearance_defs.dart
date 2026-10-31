import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:m3e_ui/m3e_ui.dart' show LoadingSpinner;

import '../../l10n/s.dart';
import '../../pages/font_settings_page.dart';
import '../../providers/app_icon_provider.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/font_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../../widgets/settings/appearance_widgets.dart';
import '../settings_model.dart';

/// 外观设置数据声明（0.4.0 v2）
///
/// 顺序：预设 → 外观模式 → 强调色 → 字体 → 微调 → 语言 → 应用图标 → 屏幕帧率。
/// 顶部固定的实时预览卡不在这里，见 AppearancePage。
List<SettingsGroup> buildAppearanceGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    // ── 预设 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_presets,
      icon: AppIcons.tune,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'presets',
          title: l10n.appearance_presets,
          builder: (context, ref) => const AppearancePresetGrid(),
        ),
      ],
    ),

    // ── 外观模式 ───────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_themeMode,
      icon: AppIcons.visibility,
      items: [
        CustomModel(
          id: 'themeMode',
          title: l10n.appearance_themeMode,
          builder: (context, ref) => const AppearanceModeRows(),
        ),
      ],
    ),

    // ── 强调色（四选一，只换 brand/primary 与 brand/button）──────────
    SettingsGroup(
      title: l10n.appearance_accent,
      icon: AppIcons.palette,
      items: [
        CustomModel(
          id: 'accent',
          title: l10n.appearance_accent,
          builder: (context, ref) => const AppearanceAccentRow(),
        ),
      ],
    ),

    // ── 字体 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_font,
      icon: AppIcons.description,
      items: [
        ActionModel(
          id: 'font',
          title: l10n.appearance_font,
          icon: AppIcons.description,
          valueBuilder: (ref) {
            final theme = ref.watch(themeProvider);
            if (theme.importedUiFamily != null) {
              final font = ref
                  .watch(importedFontsProvider)
                  .where((f) => f.family == theme.importedUiFamily)
                  .firstOrNull;
              return font?.displayName ?? l10n.appearance_fontSystem;
            }
            return theme.fontFamily == AppFontFamily.miSans
                ? 'MiSans'
                : l10n.appearance_fontSystem;
          },
          onTap: (context, ref) => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FontSettingsPage()),
          ),
        ),
      ],
    ),

    // ── 微调（「恢复默认」在组页眉右侧）─────────────────────────────
    SettingsGroup(
      title: l10n.appearance_tuning,
      icon: AppIcons.tune,
      footer: l10n.appearance_tuneFooter,
      headerAction: Consumer(
        builder: (context, ref, _) => TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(AppSize.hit, AppSize.hit),
            padding: EdgeInsets.zero,
            textStyle: Theme.of(context).textTheme.bodySmall!
                .merge(context.tokens.text.meta),
          ),
          onPressed: () => ref
              .read(appearanceProvider.notifier)
              .setTiers(const AppearanceTiers()),
          child: Text(l10n.appearance_tuneReset),
        ),
      ),
      items: [
        CustomModel(
          id: 'tuneFont',
          title: l10n.appearance_tuneFont,
          builder: (context, ref) {
            final tiers = ref.watch(appearanceProvider);
            return AppearanceTierRow(
              title: l10n.appearance_tuneFont,
              labels: [
                l10n.appearance_tierSmall,
                l10n.appearance_tierStandard,
                l10n.appearance_tierLarge,
                l10n.appearance_tierExtraLarge,
              ],
              value: tiers.font.index,
              showTextSizeEnds: true,
              onChanged: (i) => ref
                  .read(appearanceProvider.notifier)
                  .setTiers(tiers.copyWith(font: FontTier.values[i])),
            );
          },
        ),
        CustomModel(
          id: 'tuneLineHeight',
          title: l10n.appearance_tuneLineHeight,
          builder: (context, ref) {
            final tiers = ref.watch(appearanceProvider);
            return AppearanceTierRow(
              title: l10n.appearance_tuneLineHeight,
              labels: [
                l10n.appearance_tierCompact,
                l10n.appearance_tierStandard,
                l10n.appearance_tierRelaxed,
              ],
              value: tiers.lineHeight.index,
              onChanged: (i) => ref
                  .read(appearanceProvider.notifier)
                  .setTiers(tiers.copyWith(lineHeight: LineHeightTier.values[i])),
            );
          },
        ),
        CustomModel(
          id: 'tuneDensity',
          title: l10n.appearance_tuneDensity,
          builder: (context, ref) {
            final tiers = ref.watch(appearanceProvider);
            return AppearanceTierRow(
              title: l10n.appearance_tuneDensity,
              labels: [
                l10n.appearance_tierCompact,
                l10n.appearance_tierStandard,
                l10n.appearance_tierComfortable,
              ],
              value: tiers.density.index,
              onChanged: (i) => ref
                  .read(appearanceProvider.notifier)
                  .setTiers(tiers.copyWith(density: DensityTier.values[i])),
            );
          },
        ),
        CustomModel(
          id: 'tuneRadius',
          title: l10n.appearance_tuneRadius,
          builder: (context, ref) {
            final tiers = ref.watch(appearanceProvider);
            return AppearanceTierRow(
              title: l10n.appearance_tuneRadius,
              labels: [
                l10n.appearance_tierSmall,
                l10n.appearance_tierStandard,
                l10n.appearance_tierLarge,
              ],
              value: tiers.radius.index,
              onChanged: (i) => ref
                  .read(appearanceProvider.notifier)
                  .setTiers(tiers.copyWith(radius: RadiusTier.values[i])),
            );
          },
        ),
        CustomModel(
          id: 'tuneTranslucency',
          title: l10n.appearance_tuneTranslucency,
          builder: (context, ref) {
            final tiers = ref.watch(appearanceProvider);
            return AppearanceTierRow(
              title: l10n.appearance_tuneTranslucency,
              labels: [
                l10n.appearance_tierOff,
                l10n.appearance_tierStandard,
                l10n.appearance_tierStrong,
              ],
              value: tiers.translucency.index,
              onChanged: (i) => ref
                  .read(appearanceProvider.notifier)
                  .setTiers(
                    tiers.copyWith(translucency: TranslucencyTier.values[i]),
                  ),
            );
          },
        ),
      ],
    ),

    // ── 语言 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_language,
      icon: AppIcons.language,
      items: [
        ActionModel(
          id: 'language',
          title: l10n.appearance_language,
          icon: AppIcons.language,
          valueBuilder: (ref) =>
              _localeLabel(l10n, ref.watch(localeProvider)),
          onTap: (context, ref) =>
              _showLanguagePicker(context, ref, ref.read(localeProvider)),
        ),
      ],
    ),

    // ── 应用图标（仅 iOS/Android）────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_appIcon,
      icon: AppIcons.category,
      wrapInCard: false,
      items: [
        PlatformConditionalModel(
          condition: () => !kIsWeb && (Platform.isIOS || Platform.isAndroid),
          inner: CustomModel(
            id: 'appIcon',
            title: l10n.appearance_appIcon,
            builder: (context, ref) {
              final iconState = ref.watch(appIconProvider);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final l10n = context.l10n;
              final options = [
                (
                  AppIconStyle.classic,
                  l10n.appearance_iconClassic,
                  isDark
                      ? 'assets/images/icon_default_dark_preview.png'
                      : 'assets/images/icon_default_preview.png',
                ),
                (
                  AppIconStyle.modern,
                  l10n.appearance_iconModern,
                  isDark
                      ? 'assets/images/icon_modern_preview.png'
                      : 'assets/images/icon_modern_light_preview.png',
                ),
              ];
              return Row(
                children: [
                  for (final (style, label, asset) in options)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.l),
                      child: _AppIconChoice(
                        label: label,
                        assetPath: asset,
                        isSelected: iconState.currentStyle == style,
                        isChanging: iconState.isChanging,
                        onTap: () async {
                          final success = await ref
                              .read(appIconProvider.notifier)
                              .setIconStyle(style);
                          if (!success) {
                            ToastService.showError(
                              l10n.appearance_switchIconFailed,
                            );
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),

    // ── 屏幕帧率（仅 Android）──────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_displayMode,
      icon: AppIcons.speed,
      items: [
        PlatformConditionalModel(
          condition: () => !kIsWeb && Platform.isAndroid,
          inner: ActionModel(
            id: 'displayMode',
            title: l10n.appearance_displayMode,
            icon: AppIcons.speed,
            valueBuilder: (ref) {
              final rate = ref
                  .watch(preferencesProvider)
                  .displayModeRefreshRate;
              return rate == 0
                  ? l10n.appearance_displayModeAuto
                  : '${rate}Hz';
            },
            onTap: (context, ref) => _showDisplayModeSheet(context, ref),
          ),
        ),
      ],
    ),
  ];
}

// ── 语言选择器辅助函数 ───────────────────────────────────────────

void _showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  Locale? currentLocale,
) {
  final l10n = context.l10n;
  final options = <(String, Locale?)>[
    (l10n.appearance_languageSystem, null),
    (l10n.appearance_languageZhCN, const Locale('zh', 'CN')),
    (l10n.appearance_languageZhTW, const Locale('zh', 'TW')),
    (l10n.appearance_languageZhHK, const Locale('zh', 'HK')),
    (l10n.appearance_languageEn, const Locale('en', 'US')),
  ];

  AppBottomSheet.show<void>(
    context: context,
    contentPadding: EdgeInsets.zero,
    builder: (sheetContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, locale) in options)
            ListTile(
              title: Text(label),
              trailing: _localeKey(locale) == _localeKey(currentLocale)
                  ? Icon(
                      AppIcons.check,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(locale);
                final effectiveLocale =
                    locale ?? WidgetsBinding.instance.platformDispatcher.locale;
                AiL10n.configureLocale(effectiveLocale);
                Navigator.pop(sheetContext);
              },
            ),
        ],
      );
    },
  );
}

// ── 屏幕帧率选择器（仅 Android）────────────────────────────────

Future<void> _showDisplayModeSheet(BuildContext context, WidgetRef ref) async {
  await showAppBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _DisplayModeSheetBody(),
  );
}

class _DisplayModeSheetBody extends ConsumerStatefulWidget {
  const _DisplayModeSheetBody();

  @override
  ConsumerState<_DisplayModeSheetBody> createState() =>
      _DisplayModeSheetBodyState();
}

class _DisplayModeSheetBodyState extends ConsumerState<_DisplayModeSheetBody> {
  late Future<_DisplayModeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DisplayModeData> _load() async {
    final modes = await FlutterDisplayMode.supported;
    final active = await FlutterDisplayMode.active;
    return _DisplayModeData(modes: modes, active: active);
  }

  Future<void> _apply(
    int rate,
    List<DisplayMode> modes,
    DisplayMode active,
  ) async {
    await ref
        .read(preferencesProvider.notifier)
        .setDisplayModeRefreshRate(rate);
    try {
      if (rate == 0) {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
      } else {
        final matches = modes
            .where((m) => m.refreshRate.round() == rate)
            .toList();
        if (matches.isNotEmpty) {
          final picked = matches.firstWhere(
            (m) => m.width == active.width && m.height == active.height,
            orElse: () => matches.first,
          );
          await FlutterDisplayMode.setPreferredMode(picked);
        }
      }
    } catch (e) {
      debugPrint('[DisplayMode] 切换刷新率失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SafeArea(
      child: FutureBuilder<_DisplayModeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 200,
              child: Center(child: LoadingSpinner()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error?.toString() ?? 'unknown error',
                style: theme.textTheme.bodyMedium,
              ),
            );
          }

          final data = snapshot.data!;
          final currentRate = ref
              .watch(preferencesProvider)
              .displayModeRefreshRate;

          // 去重 + 高到低排序
          final uniqueRates = <int>{};
          for (final m in data.modes) {
            uniqueRates.add(m.refreshRate.round());
          }
          final sortedRates = uniqueRates.toList()
            ..sort((a, b) => b.compareTo(a));

          final activeRate = data.active.refreshRate.round();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  l10n.appearance_displayMode,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: RadioGroup<int>(
                    groupValue: currentRate,
                    onChanged: (value) async {
                      if (value == null) return;
                      await _apply(value, data.modes, data.active);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<int>(
                          value: 0,
                          title: Text(l10n.appearance_displayModeAuto),
                        ),
                        for (final rate in sortedRates)
                          RadioListTile<int>(
                            value: rate,
                            title: Text(
                              rate == activeRate
                                  ? '${rate}Hz  ·  [${l10n.appearance_languageSystem}]'
                                  : '${rate}Hz',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  l10n.appearance_displayModeRestartHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DisplayModeData {
  final List<DisplayMode> modes;
  final DisplayMode active;

  _DisplayModeData({required this.modes, required this.active});
}

String _localeLabel(AppLocalizations l10n, Locale? locale) {
  if (locale == null) return l10n.appearance_languageSystem;
  switch ('${locale.languageCode}_${locale.countryCode}') {
    case 'zh_CN':
      return l10n.appearance_languageZhCN;
    case 'zh_TW':
      return l10n.appearance_languageZhTW;
    case 'zh_HK':
      return l10n.appearance_languageZhHK;
    case 'en_US':
      return l10n.appearance_languageEn;
    default:
      return l10n.appearance_languageSystem;
  }
}

String _localeKey(Locale? locale) {
  if (locale == null) return 'system';
  return locale.countryCode != null
      ? '${locale.languageCode}_${locale.countryCode}'
      : locale.languageCode;
}

// ── 应用图标选择 ──────────────────────────────────────────────────

/// 64 方块（r16）预览 + 名称；选中外圈 2pt brand 环
class _AppIconChoice extends StatelessWidget {
  final String label;
  final String assetPath;
  final bool isSelected;
  final bool isChanging;
  final VoidCallback onTap;

  const _AppIconChoice({
    required this.label,
    required this.assetPath,
    required this.isSelected,
    required this.isChanging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      onTap: isChanging ? null : onTap,
      child: AppPressable(
        onTap: isChanging ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppSize.hit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? colors.brandPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      assetPath,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => SizedBox.square(
                        dimension: 64,
                        child: ColoredBox(color: colors.avatarFill),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(
                      color: isSelected
                          ? colors.brandPrimary
                          : colors.textMeta,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
