import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/theme_provider.dart';

/// 外观页的 v2 小组件：实时预览卡、预设四格、外观模式行、强调色四圆、微调档位行。

/// 顶部实时预览卡（设计说明 §5.4 外观）：0.5 separator 描边 r12，
/// 一条列表行 + 一层楼，右上角写当前预设名。档位和字体一改，这里立刻跟着变。
class AppearancePreviewCard extends ConsumerWidget {
  const AppearancePreviewCard({super.key, this.presetLabel});

  /// 右上角文字；null 时自动取预设名或「自定义」
  final String? presetLabel;

  static String presetName(BuildContext context, AppearanceTiers tiers) {
    final l10n = context.l10n;
    return switch (AppearancePreset.match(tiers)) {
      AppearancePreset.standard => l10n.settings_presetStandard,
      AppearancePreset.compact => l10n.settings_presetCompact,
      AppearancePreset.comfortable => l10n.settings_presetComfortable,
      AppearancePreset.largeText => l10n.settings_presetLargeText,
      null => l10n.settings_valueCustom,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiers = ref.watch(appearanceProvider);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final headline = base
        .merge(tokens.text.headline)
        .copyWith(color: colors.textPrimary);
    final body = base
        .merge(tokens.text.body)
        .copyWith(color: colors.textPrimary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.xs,
        AppSpace.pageMargin,
        AppSpace.s,
      ),
      child: Semantics(
        container: true,
        label: l10n.appearance_previewTitle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfacePage,
            borderRadius: BorderRadius.circular(tokens.radius.card),
            border: Border.all(
              color: colors.separator,
              width: AppSpace.hairline,
            ),
          ),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.appearance_previewTitle, style: meta),
                      const Spacer(),
                      Text(
                        presetLabel ?? presetName(context, tiers),
                        style: meta.copyWith(color: colors.brandPrimary),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.rowPadV),
                  Text(
                    l10n.appearance_previewRowTitle,
                    style: headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(l10n.appearance_previewRowMeta, style: meta),
                  SizedBox(height: tokens.rowPadV),
                  const AppHairline(),
                  SizedBox(height: tokens.rowPadV),
                  Row(
                    children: [
                      const LetterAvatar(name: 'Chase', size: AppSize.avatarS),
                      const SizedBox(width: AppSpace.s),
                      Text(
                        'Chase',
                        style: meta
                            .merge(tokens.text.metaStrong)
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.brandPrimary),
                          borderRadius: BorderRadius.circular(
                            tokens.radius.tag,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            l10n.appearance_previewOwner,
                            style: base
                                .merge(tokens.text.caption)
                                .copyWith(color: colors.brandPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s),
                  Text(
                    l10n.appearance_previewPostBody,
                    style: body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 预设四格：等宽，surface/grouped r12，选中文字变 brand
class AppearancePresetGrid extends ConsumerWidget {
  const AppearancePresetGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiers = ref.watch(appearanceProvider);
    final current = AppearancePreset.match(tiers);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final labels = {
      AppearancePreset.standard: l10n.settings_presetStandard,
      AppearancePreset.compact: l10n.settings_presetCompact,
      AppearancePreset.comfortable: l10n.settings_presetComfortable,
      AppearancePreset.largeText: l10n.settings_presetLargeText,
    };
    final captions = {
      AppearancePreset.standard: l10n.appearance_presetCaptionStandard,
      AppearancePreset.compact: l10n.appearance_presetCaptionCompact,
      AppearancePreset.comfortable: l10n.appearance_presetCaptionComfortable,
      AppearancePreset.largeText: l10n.appearance_presetCaptionLarge,
    };
    return Row(
      children: [
        for (final preset in AppearancePreset.values) ...[
          if (preset != AppearancePreset.values.first)
            const SizedBox(width: AppSpace.s),
          Expanded(
            child: Semantics(
              button: true,
              selected: current == preset,
              label: labels[preset],
              excludeSemantics: true,
              onTap: () =>
                  ref.read(appearanceProvider.notifier).applyPreset(preset),
              child: AppPressable(
                onTap: () =>
                    ref.read(appearanceProvider.notifier).applyPreset(preset),
                child: Container(
                  constraints: const BoxConstraints(minHeight: AppSize.hit),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.xs,
                    vertical: AppSpace.s,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceGrouped,
                    borderRadius: BorderRadius.circular(tokens.radius.card),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labels[preset]!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: base
                            .merge(
                              current == preset
                                  ? tokens.text.metaStrong
                                  : tokens.text.meta,
                            )
                            .copyWith(
                              color: current == preset
                                  ? colors.brandPrimary
                                  : colors.textPrimary,
                            ),
                      ),
                      Text(
                        captions[preset]!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: base
                            .merge(tokens.text.caption)
                            .copyWith(color: colors.textMeta),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 外观模式三行：跟随系统 / 浅色 / 深色，选中打勾
class AppearanceModeRows extends ConsumerWidget {
  const AppearanceModeRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider.select((s) => s.mode));
    final l10n = context.l10n;
    final colors = context.tokens.colors;
    final options = [
      (ThemeMode.system, AppIcons.speed, l10n.appearance_modeAuto),
      (ThemeMode.light, AppIcons.visibility, l10n.appearance_modeLight),
      (ThemeMode.dark, AppIcons.visibilityOff, l10n.appearance_modeDark),
    ];
    return Column(
      children: [
        for (final (m, icon, label) in options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: m == mode,
            child: ListTile(
              leading: Icon(icon, color: colors.brandPrimary),
              title: Text(label),
              trailing: m == mode
                  ? Icon(
                      AppIcons.check,
                      size: AppSize.iconM,
                      color: colors.brandPrimary,
                    )
                  : null,
              onTap: () => ref.read(themeProvider.notifier).setThemeMode(m),
            ),
          ),
      ],
    );
  }
}

/// 强调色：四个 28 圆，选中外圈 2pt 间隙 + 2pt brand 环
class AppearanceAccentRow extends ConsumerWidget {
  const AppearanceAccentRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(themeProvider.select((s) => s.accent));
    final brightness = Theme.of(context).brightness;
    final l10n = context.l10n;
    final colors = context.tokens.colors;
    final options = [
      (AccentPreset.meika, l10n.appearance_accentMeika),
      (AccentPreset.navy, l10n.appearance_accentNavy),
      (AccentPreset.graphite, l10n.appearance_accentGraphite),
      (AccentPreset.wisteria, l10n.appearance_accentWisteria),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.l,
        vertical: AppSpace.xs,
      ),
      child: Row(
        children: [
          for (final (preset, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.xs),
              child: Semantics(
                button: true,
                selected: preset == accent,
                label: label,
                excludeSemantics: true,
                onTap: () => ref.read(themeProvider.notifier).setAccent(preset),
                child: AppPressable(
                  onTap: () =>
                      ref.read(themeProvider.notifier).setAccent(preset),
                  // 点击区 ≥ 44，圆 28，选中环外扩 4，圆下面写名称
                  child: SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: AppSize.hit,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: preset == accent
                                      ? colors.brandPrimary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.resolve(
                                      brightness,
                                      preset,
                                    ).brandPrimary,
                                  ),
                                  child: const SizedBox.square(dimension: 28),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: preset == accent
                                    ? colors.brandPrimary
                                    : colors.textMeta,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 微调的一项：名称 17 + 当前值 13 meta，下面是档位滑块
class AppearanceTierRow extends StatelessWidget {
  const AppearanceTierRow({
    super.key,
    required this.title,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.showTextSizeEnds = false,
  });

  final String title;
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  final bool showTextSizeEnds;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.l,
        AppSpace.s,
        AppSpace.l,
        AppSpace.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: base
                      .merge(tokens.text.control)
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                labels[value],
                style: base
                    .merge(tokens.text.meta)
                    .copyWith(color: colors.textMeta),
              ),
            ],
          ),
          StepSlider(
            value: value,
            count: labels.length,
            labels: labels,
            semanticLabel: title,
            showTextSizeEnds: showTextSizeEnds,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
