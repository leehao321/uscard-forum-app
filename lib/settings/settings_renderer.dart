import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import 'settings_model.dart';

/// 根据 SettingsModel 类型分派到对应的 Widget
class SettingsRenderer extends ConsumerWidget {
  final SettingsModel model;

  const SettingsRenderer({super.key, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return switch (model) {
      SwitchModel m => _buildSwitch(context, ref, theme, m),
      DoubleSliderModel m => _buildDoubleSlider(context, ref, theme, m),
      IntSliderModel m => _buildIntSlider(context, ref, theme, m),
      ActionModel m => _buildAction(context, ref, theme, m),
      CustomModel m => m.builder(context, ref),
      PlatformConditionalModel m => m.shouldShow
          ? SettingsRenderer(model: m.inner)
          : const SizedBox.shrink(),
    };
  }

  Widget _buildSwitch(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    SwitchModel m,
  ) {
    // 依赖的前置开关关闭时整行隐藏(展示无意义;前置开启当场出现)
    if (!(m.enabledWhen?.call(ref) ?? true)) return const SizedBox.shrink();
    final value = m.getValue(ref);
    final subtitle = m.subtitleBuilder?.call(ref) ?? m.subtitle;
    return SwitchListTile.adaptive(
      title: Text(m.title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      // v2 分组列表：前导图标 20 brand/primary（组内 IconTheme 给尺寸）
      secondary: Icon(m.icon, color: context.tokens.colors.brandPrimary),
      value: value,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        m.onChanged(ref, v);
      },
    );
  }

  Widget _buildDoubleSlider(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    DoubleSliderModel m,
  ) {
    final value = m.getValue(ref);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(m.icon, color: context.tokens.colors.brandPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title),
                    Text(
                      m.labelBuilder(value),
                      style: theme.textTheme.bodySmall
                          ?.merge(context.tokens.text.meta)
                          .copyWith(color: context.tokens.colors.textMeta),
                    ),
                  ],
                ),
              ),
              if (m.onReset != null)
                TextButton(
                  onPressed: value != ((m.min + m.max) / 2).roundToDouble()
                      ? () => m.onReset!(ref)
                      : null,
                  child: Text(context.l10n.common_reset),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 不再本地覆盖 SliderTheme:滑块样式统一走全局主题
          // (M3E 开 = year2023:false 新样式,关 = M3 经典)。
          Slider(
            value: value,
            min: m.min,
            max: m.max,
            divisions: m.divisions,
            label: m.labelBuilder(value),
            onChanged: (v) => m.onChanged(ref, v),
          ),
        ],
      ),
    );
  }

  Widget _buildIntSlider(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    IntSliderModel m,
  ) {
    final value = m.getValue(ref);
    final suffix = m.valueSuffix ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(m.icon, color: context.tokens.colors.brandPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title, style: theme.textTheme.bodyMedium),
                if (m.subtitle != null)
                  Text(
                    m.subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.merge(context.tokens.text.meta)
                        .copyWith(color: context.tokens.colors.textMeta),
                  ),
                Slider(
                  value: value.toDouble(),
                  min: m.min.toDouble(),
                  max: m.max.toDouble(),
                  divisions: m.max - m.min,
                  label: '$value$suffix',
                  onChanged: (v) => m.onChanged(ref, v.round()),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value$suffix',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.tokens.colors.brandPrimary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    ActionModel m,
  ) {
    final dynamicSub = m.getDynamicSubtitle?.call(ref);
    final displaySub = dynamicSub ?? m.subtitle;
    final value = m.valueBuilder?.call(ref);

    final tokens = context.tokens;
    final colors = tokens.colors;
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    return ListTile(
      leading: Icon(m.icon, color: colors.brandPrimary),
      title: Text(m.title),
      subtitle: displaySub != null
          ? Text(
              displaySub,
              maxLines: m.wrapSubtitle ? null : 1,
              overflow: m.wrapSubtitle
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            )
          : null,
      // 右侧：当前值（13 meta）+ chevron-right 16
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                value,
                style: metaStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (value != null) const SizedBox(width: AppSpace.xs),
          Icon(AppIcons.chevronRight, size: AppSize.iconS, color: colors.textMeta),
        ],
      ),
      onTap: () => m.onTap(context, ref),
    );
  }
}
