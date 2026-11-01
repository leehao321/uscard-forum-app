import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart' show SegmentedCardGroup;

import '../../l10n/s.dart';
import '../../providers/preferences_provider.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';

/// 并发与限流的三个数（同时请求数 / 限流阈值 / 时间窗口秒数）
class RateLimitValues {
  const RateLimitValues(this.maxConcurrent, this.maxPerWindow, this.windowSeconds);

  final int maxConcurrent;
  final int maxPerWindow;
  final int windowSeconds;

  @override
  bool operator ==(Object other) =>
      other is RateLimitValues &&
      other.maxConcurrent == maxConcurrent &&
      other.maxPerWindow == maxPerWindow &&
      other.windowSeconds == windowSeconds;

  @override
  int get hashCode => Object.hash(maxConcurrent, maxPerWindow, windowSeconds);

  @override
  String toString() => 'RateLimitValues($maxConcurrent, $maxPerWindow, $windowSeconds)';
}

/// 预设档位：省心 / 均衡 / 极速；自定义没有固定数值
enum RateLimitPreset { gentle, balanced, turbo, custom }

/// 与 preferences_provider.dart 的默认值保持一致（3 / 6 / 3）
const rateLimitDefaults = RateLimitValues(3, 6, 3);

const rateLimitPresetValues = <RateLimitPreset, RateLimitValues>{
  RateLimitPreset.gentle: RateLimitValues(2, 6, 5),
  RateLimitPreset.balanced: rateLimitDefaults,
  RateLimitPreset.turbo: RateLimitValues(6, 15, 3),
};

/// 三个数正好等于某个预设就返回它，否则是自定义
RateLimitPreset rateLimitPresetOf(RateLimitValues values) {
  for (final entry in rateLimitPresetValues.entries) {
    if (entry.value == values) return entry.key;
  }
  return RateLimitPreset.custom;
}

/// 三条滑杆的取值范围（现版）
const rateLimitConcurrentRange = (min: 1, max: 10);
const rateLimitPerWindowRange = (min: 2, max: 30);
const rateLimitWindowRange = (min: 1, max: 10);

/// 并发与限流设置（设置 › 高级 › 诊断 底部「高级」区，补充稿 33）：
/// 预设分段「省心 / 均衡 / 极速 / 自定义」，选自定义时在下面展开三条滑杆。
///
/// 选预设立即写入三个数；选「自定义」只展开滑杆、不改数值（所以数值恰好等于
/// 某个预设时也能停在自定义里继续调）。
class RateLimitSettings extends ConsumerStatefulWidget {
  const RateLimitSettings({super.key});

  @override
  ConsumerState<RateLimitSettings> createState() => _RateLimitSettingsState();
}

class _RateLimitSettingsState extends ConsumerState<RateLimitSettings> {
  /// 用户点了「自定义」：数值和某个预设重合时也保持展开
  bool _customPicked = false;

  static const _order = [
    RateLimitPreset.gentle,
    RateLimitPreset.balanced,
    RateLimitPreset.turbo,
    RateLimitPreset.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final prefs = ref.watch(preferencesProvider);
    final notifier = ref.read(preferencesProvider.notifier);
    final values = RateLimitValues(
      prefs.maxConcurrent,
      prefs.maxPerWindow,
      prefs.windowSeconds,
    );
    final matched = rateLimitPresetOf(values);
    final isCustom = _customPicked || matched == RateLimitPreset.custom;
    final selected = isCustom ? RateLimitPreset.custom : matched;
    final meta = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);

    final labels = [
      l10n.networkSettings_rateLimitPresetGentle,
      l10n.networkSettings_rateLimitPresetBalanced,
      l10n.networkSettings_rateLimitPresetTurbo,
      l10n.networkSettings_rateLimitPresetCustom,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmented(
          labels: labels,
          selectedIndex: _order.indexOf(selected),
          onChanged: (i) async {
            final picked = _order[i];
            if (picked == RateLimitPreset.custom) {
              setState(() => _customPicked = true);
              return;
            }
            setState(() => _customPicked = false);
            final v = rateLimitPresetValues[picked]!;
            await notifier.setMaxConcurrent(v.maxConcurrent);
            await notifier.setMaxPerWindow(v.maxPerWindow);
            await notifier.setWindowSeconds(v.windowSeconds);
          },
        ),
        const SizedBox(height: AppSpace.m),
        if (isCustom)
          SegmentedCardGroup(
            separatorIndent: AppSpace.m + AppSize.iconM + AppSpace.m,
            children: [
              _SliderRow(
                rowKey: const ValueKey('rateLimit-maxConcurrent'),
                icon: AppIcons.activity,
                title: l10n.networkSettings_maxConcurrent,
                subtitle: l10n.networkSettings_maxConcurrentDesc,
                value: prefs.maxConcurrent,
                min: rateLimitConcurrentRange.min,
                max: rateLimitConcurrentRange.max,
                onChanged: notifier.setMaxConcurrent,
              ),
              _SliderRow(
                rowKey: const ValueKey('rateLimit-maxPerWindow'),
                icon: AppIcons.speed,
                title: l10n.networkSettings_maxPerWindow,
                subtitle: l10n.networkSettings_maxPerWindowDesc,
                value: prefs.maxPerWindow,
                min: rateLimitPerWindowRange.min,
                max: rateLimitPerWindowRange.max,
                onChanged: notifier.setMaxPerWindow,
              ),
              _SliderRow(
                rowKey: const ValueKey('rateLimit-windowSeconds'),
                icon: AppIcons.timer,
                title: l10n.networkSettings_windowSeconds,
                subtitle: l10n.networkSettings_windowSecondsDesc,
                value: prefs.windowSeconds,
                min: rateLimitWindowRange.min,
                max: rateLimitWindowRange.max,
                suffix: l10n.networkSettings_windowSecondsSuffix,
                onChanged: notifier.setWindowSeconds,
              ),
            ],
          )
        else
          // 预设档：不展开滑杆，只用一行说明这一档的实际数值
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
            child: Text(
              l10n.networkSettings_rateLimitSummary(
                prefs.windowSeconds,
                prefs.maxPerWindow,
                prefs.maxConcurrent,
              ),
              style: meta,
            ),
          ),
        // 三个数不是默认值时才出现：先确认，确认后回到默认并给一条 Toast
        if (values != rateLimitDefaults)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppPressable(
              onTap: () => _confirmReset(context, notifier),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.hit),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                    child: Text(
                      l10n.networkSettings_rateLimitReset,
                      style: meta.copyWith(color: tokens.colors.brandPrimary),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    PreferencesNotifier notifier,
  ) async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.networkSettings_rateLimitReset),
        content: Text(
          l10n.networkSettings_rateLimitSummary(
            rateLimitDefaults.windowSeconds,
            rateLimitDefaults.maxPerWindow,
            rateLimitDefaults.maxConcurrent,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.common_confirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await notifier.setMaxConcurrent(rateLimitDefaults.maxConcurrent);
    await notifier.setMaxPerWindow(rateLimitDefaults.maxPerWindow);
    await notifier.setWindowSeconds(rateLimitDefaults.windowSeconds);
    if (mounted) setState(() => _customPicked = false);
    ToastService.showSuccess(l10n.networkSettings_rateLimitResetDone);
  }
}

/// 一条滑杆：前导图标 20 + 标题 17 + 说明 13 meta，右侧当前值 17 meta，
/// 下面是 44 高的档位滑杆（轨 4、拇指 24）。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final Future<void> Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final valueText = suffix == null ? '$value' : '$value $suffix';
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.m,
        AppSpace.m,
        AppSpace.m,
        AppSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Icon(
                  icon,
                  size: AppSize.iconM,
                  color: tokens.colors.brandPrimary,
                ),
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: base
                          .merge(tokens.text.control)
                          .copyWith(color: tokens.colors.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: base
                          .merge(tokens.text.meta)
                          .copyWith(color: tokens.colors.textMeta),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s),
              Text(
                valueText,
                style: base
                    .merge(tokens.text.control)
                    .copyWith(
                      color: tokens.colors.textMeta,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          StepSlider(
            value: (value - min).clamp(0, max - min),
            count: max - min + 1,
            semanticLabel: title,
            labels: null,
            onChanged: (i) => onChanged(min + i),
          ),
        ],
      ),
    );
  }
}
