import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../providers/app_icon_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dialog_utils.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../settings_model.dart';

/// 外观设置数据声明
List<SettingsGroup> buildAppearanceGroups(BuildContext context) {
  final l10n = context.l10n;
  return [
    // ── 语言 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_language,
      icon: Symbols.language_rounded,
      items: [
        CustomModel(
          id: 'language',
          title: l10n.appearance_language,
          builder: (context, ref) {
            final locale = ref.watch(localeProvider);
            final label = _localeLabel(context.l10n, locale);
            return ListTile(
              leading: Icon(
                Symbols.translate_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(label),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () => _showLanguagePicker(context, ref, locale),
            );
          },
        ),
      ],
    ),

    // ── 主题模式 ───────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_themeMode,
      icon: Symbols.brightness_6_rounded,
      wrapInCard: false,
      items: [
        CustomModel(
          id: 'themeMode',
          title: l10n.appearance_themeMode,
          builder: (context, ref) {
            final themeState = ref.watch(themeProvider);
            final currentMode = themeState.mode;
            final theme = Theme.of(context);
            final l10n = context.l10n;

            // 卡片预览用 v2 配色（跟随当前强调色）
            ColorScheme preview(Brightness b) =>
                appColorScheme(AppColors.resolve(b, themeState.accent), b);
            final lightScheme = preview(Brightness.light);
            final darkScheme = preview(Brightness.dark);

            final modes = [
              (
                ThemeMode.system,
                Symbols.auto_mode_rounded,
                l10n.appearance_modeAuto,
                null,
              ),
              (
                ThemeMode.light,
                Symbols.light_mode_rounded,
                l10n.appearance_modeLight,
                lightScheme,
              ),
              (
                ThemeMode.dark,
                Symbols.dark_mode_rounded,
                l10n.appearance_modeDark,
                darkScheme,
              ),
            ];

            return Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Row(
                  children: [
                    for (int i = 0; i < modes.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _ThemeModeCard(
                          mode: modes[i].$1,
                          icon: modes[i].$2,
                          label: modes[i].$3,
                          previewScheme: modes[i].$4,
                          lightScheme: lightScheme,
                          darkScheme: darkScheme,
                          isSelected: modes[i].$1 == currentMode,
                          currentTheme: theme,
                          onTap: () => ref
                              .read(themeProvider.notifier)
                              .setThemeMode(modes[i].$1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),

    // ── 强调色（四选一，只换 brand/primary 与 brand/button；完整的 v2
    // 外观页在 M8 做）────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_accent,
      icon: Symbols.color_lens_rounded,
      items: [
        CustomModel(
          id: 'accent',
          title: l10n.appearance_accent,
          builder: (context, ref) {
            final accent = ref.watch(themeProvider.select((s) => s.accent));
            final brightness = Theme.of(context).brightness;
            final l10n = context.l10n;
            final options = <(AccentPreset, String)>[
              (AccentPreset.meika, l10n.appearance_accentMeika),
              (AccentPreset.navy, l10n.appearance_accentNavy),
              (AccentPreset.graphite, l10n.appearance_accentGraphite),
              (AccentPreset.wisteria, l10n.appearance_accentWisteria),
            ];
            return RadioGroup<AccentPreset>(
              groupValue: accent,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeProvider.notifier).setAccent(value);
                }
              },
              child: Column(
                children: [
                  for (final (preset, label) in options)
                    RadioListTile<AccentPreset>(
                      value: preset,
                      title: Text(label),
                      secondary: ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              brightness,
                              preset,
                            ).brandPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(
                            dimension: AppSize.iconM,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),

    // ── 应用图标（仅 iOS/Android）────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_appIcon,
      icon: Symbols.app_shortcut_rounded,
      wrapInCard: false,
      items: [
        PlatformConditionalModel(
          condition: () => !kIsWeb && (Platform.isIOS || Platform.isAndroid),
          inner: CustomModel(
            id: 'appIcon',
            title: l10n.appearance_appIcon,
            builder: (context, ref) {
              final iconState = ref.watch(appIconProvider);
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
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

              // 与主题模式卡片同宽（400 宽放 3 张 → 2 张为 264）
              return Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 264),
                  child: Row(
                    children: [
                      for (int i = 0; i < options.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _AppIconCard(
                            label: options[i].$2,
                            assetPath: options[i].$3,
                            isSelected: iconState.currentStyle == options[i].$1,
                            isChanging: iconState.isChanging,
                            onTap: () async {
                              final success = await ref
                                  .read(appIconProvider.notifier)
                                  .setIconStyle(options[i].$1);
                              if (!success) {
                                ToastService.showError(
                                  l10n.appearance_switchIconFailed,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),

    // ── 字体 ──────────────────────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_font,
      icon: Symbols.font_download_rounded,
      items: [
        CustomModel(
          id: 'font',
          title: l10n.appearance_font,
          builder: (context, ref) {
            final fontFamily = ref.watch(
              themeProvider.select((s) => s.fontFamily),
            );
            final l10n = context.l10n;
            final options = <(String, AppFontFamily)>[
              (l10n.appearance_fontSystem, AppFontFamily.system),
              ('MiSans', AppFontFamily.miSans),
            ];

            return RadioGroup<AppFontFamily>(
              groupValue: fontFamily,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeProvider.notifier).setFontFamily(value);
                }
              },
              child: Column(
                children: [
                  for (final (label, ff) in options)
                    RadioListTile<AppFontFamily>(
                      title: Text(
                        label,
                        style: ff == AppFontFamily.miSans
                            ? const TextStyle(fontFamily: 'MiSans')
                            : null,
                      ),
                      value: ff,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),

    // ── 屏幕帧率（仅 Android）──────────────────────────────────────
    SettingsGroup(
      title: l10n.appearance_displayMode,
      icon: Symbols.monitor_rounded,
      items: [
        PlatformConditionalModel(
          condition: () => !kIsWeb && Platform.isAndroid,
          inner: ActionModel(
            id: 'displayMode',
            title: l10n.appearance_displayMode,
            icon: Symbols.monitor_heart_rounded,
            getDynamicSubtitle: (ref) {
              final rate = ref
                  .watch(preferencesProvider)
                  .displayModeRefreshRate;
              return rate == 0
                  ? context.l10n.appearance_displayModeAuto
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
                      Symbols.check_rounded,
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

// ── 应用图标选择卡片 ─────────────────────────────────────────────

/// 图标设计稿背景：细网格 + 中心十字线 + keyline 参考形状（圆 / 圆角方），
/// 模拟 icon 设计工具的规格线稿。
class _IconKeylinePainter extends CustomPainter {
  final Color backgroundColor;
  final Color gridColor;
  final Color accentColor;

  _IconKeylinePainter({
    required this.backgroundColor,
    required this.gridColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 底色
    paint.color = backgroundColor;
    canvas.drawRect(Offset.zero & size, paint);

    final center = Offset(size.width / 2, size.height / 2);

    // ── 细网格 ──
    paint
      ..color = gridColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const step = 8.0;
    // 以中心为基准向两侧铺开，保证十字线落在网格上
    for (double x = center.dx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = center.dy % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // ── 中心十字线 ──
    paint.color = accentColor.withValues(alpha: 0.25);
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);

    // ── keyline 参考形状（略大于图标，露出图标四周）──
    paint
      ..color = accentColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    // 外接圆
    canvas.drawCircle(center, 27, paint);
    // 圆角方形
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 54, height: 54),
        const Radius.circular(12),
      ),
      paint,
    );

    // ── 四角对角短线（斜向 keyline 的示意）──
    paint.color = accentColor.withValues(alpha: 0.2);
    const d = 19.0; // 45° 方向上的偏移
    const len = 6.0;
    for (final (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      final from = center + Offset(sx * d, sy * d);
      final to = center + Offset(sx * (d + len), sy * (d + len));
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IconKeylinePainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.accentColor != accentColor;
  }
}

/// 应用图标选择卡片，样式与 [_ThemeModeCard] 保持一致：
/// 顶部为迷你"设计稿"预览（keyline 网格线稿 + 悬浮应用图标），
/// 底部显示勾选 + 文字，选中态高亮边框 + 容器底色。
class _AppIconCard extends StatelessWidget {
  final String label;
  final String assetPath;
  final bool isSelected;
  final bool isChanging;
  final VoidCallback onTap;

  const _AppIconCard({
    required this.label,
    required this.assetPath,
    required this.isSelected,
    required this.isChanging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: isChanging ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? cs.secondaryContainer.withValues(alpha: 0.5)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 迷你设计稿：keyline 网格背景 + 悬浮图标
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _IconKeylinePainter(
                          backgroundColor: cs.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          gridColor: cs.outline,
                          accentColor: isSelected ? cs.primary : cs.outline,
                        ),
                      ),
                      Center(
                        child: AnimatedScale(
                          scale: isSelected ? 1.0 : 0.88,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          child: Container(
                            width: 44,
                            height: 44,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isSelected ? 0.25 : 0.15,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Image.asset(assetPath, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      if (isChanging && isSelected)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: LoadingSpinner(size: 24, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 勾选 + 文字（与主题模式卡片同款底部行）
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected) ...[
                    Icon(
                      Symbols.check_circle_rounded,
                      size: 14,
                      fill: 1,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 主题模式卡片（浅色/深色/跟随系统）
// ══════════════════════════════════════════════════════════════════

class _ThemeModeCard extends StatelessWidget {
  final ThemeMode mode;
  final IconData icon;
  final String label;

  /// 该模式对应的配色方案，system 模式为 null（需同时展示 light + dark）
  final ColorScheme? previewScheme;
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;
  final bool isSelected;
  final ThemeData currentTheme;
  final VoidCallback onTap;

  const _ThemeModeCard({
    required this.mode,
    required this.icon,
    required this.label,
    required this.previewScheme,
    required this.lightScheme,
    required this.darkScheme,
    required this.isSelected,
    required this.currentTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = currentTheme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? cs.secondaryContainer.withValues(alpha: 0.5)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // 迷你屏幕预览
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _buildPreview(),
            ),
            const SizedBox(height: 8),
            // 图标 + 文字
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: currentTheme.textTheme.labelSmall?.copyWith(
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 绘制迷你屏幕预览
  Widget _buildPreview() {
    if (mode == ThemeMode.system) {
      // 跟随系统：同一个屏幕，左半亮色右半暗色
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 64,
          child: CustomPaint(
            painter: _SplitThemePreviewPainter(
              lightScheme: lightScheme,
              darkScheme: darkScheme,
            ),
            size: Size.infinite,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(height: 64, child: _buildMiniScreen(previewScheme!)),
    );
  }

  /// 单个迷你屏幕：模拟 app bar + 内容行
  Widget _buildMiniScreen(ColorScheme scheme) {
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模拟 app bar
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                const SizedBox(width: 3),
                Container(
                  width: 16,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // 模拟内容行
          _buildContentLine(scheme, 0.7),
          const SizedBox(height: 2),
          _buildContentLine(scheme, 0.5),
          const SizedBox(height: 2),
          // 模拟按钮
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 14,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildContentLine(ColorScheme scheme, double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 跟随系统预览：同一个屏幕背景，左半亮色右半暗色，
/// UI 元素在分界线处自然切换颜色。
class _SplitThemePreviewPainter extends CustomPainter {
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;

  _SplitThemePreviewPainter({
    required this.lightScheme,
    required this.darkScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midX = size.width / 2;
    final paint = Paint();

    // ── 背景：左亮右暗 ──
    paint.color = lightScheme.surface;
    canvas.drawRect(Rect.fromLTRB(0, 0, midX, size.height), paint);
    paint.color = darkScheme.surface;
    canvas.drawRect(Rect.fromLTRB(midX, 0, size.width, size.height), paint);

    final pad = 4.0;

    // ── app bar 背景条 ──
    _drawSplitRRect(
      canvas,
      size,
      rect: Rect.fromLTWH(pad, pad, size.width - pad * 2, 10),
      radius: 3,
      lightColor: lightScheme.surfaceContainerHighest,
      darkColor: darkScheme.surfaceContainerHighest,
    );

    // ── app bar 标题 ──
    _drawSplitRRect(
      canvas,
      size,
      rect: Rect.fromLTWH(pad + 3, pad + 2.5, 16, 5),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.6),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.6),
    );

    // ── 内容行 1 ──
    final y1 = pad + 13.0;
    _drawSplitRRect(
      canvas,
      size,
      rect: Rect.fromLTWH(pad, y1, (size.width - pad * 2) * 0.7, 4),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.15),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.15),
    );

    // ── 内容行 2 ──
    final y2 = y1 + 6;
    _drawSplitRRect(
      canvas,
      size,
      rect: Rect.fromLTWH(pad, y2, (size.width - pad * 2) * 0.5, 4),
      radius: 2,
      lightColor: lightScheme.onSurface.withValues(alpha: 0.15),
      darkColor: darkScheme.onSurface.withValues(alpha: 0.15),
    );

    // ── 按钮 ──
    final btnW = 14.0;
    final btnH = 6.0;
    final btnY = y2 + 8;
    _drawSplitRRect(
      canvas,
      size,
      rect: Rect.fromLTWH(size.width - pad - btnW, btnY, btnW, btnH),
      radius: 3,
      lightColor: lightScheme.primary,
      darkColor: darkScheme.primary,
    );

    // ── 中线分隔（半透明细线，暗示分界）──
    paint
      ..color = lightScheme.outline.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
  }

  /// 绘制一个跨越亮暗分界的圆角矩形，
  /// 左半用 lightColor，右半用 darkColor。
  void _drawSplitRRect(
    Canvas canvas,
    Size size, {
    required Rect rect,
    required double radius,
    required Color lightColor,
    required Color darkColor,
  }) {
    final midX = size.width / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint();

    // 左半（亮色）
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, midX, size.height));
    paint.color = lightColor;
    canvas.drawRRect(rrect, paint);
    canvas.restore();

    // 右半（暗色）
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(midX, 0, size.width, size.height));
    paint.color = darkColor;
    canvas.drawRRect(rrect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SplitThemePreviewPainter oldDelegate) {
    return oldDelegate.lightScheme != lightScheme ||
        oldDelegate.darkScheme != darkScheme;
  }
}
