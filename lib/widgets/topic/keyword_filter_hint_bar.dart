import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../settings/definitions/preferences_defs.dart';

/// 话题列表顶部的「本地内容过滤」提示。
///
/// 仅在有话题被隐藏时显示。整行可点击，按本次隐藏的实际来源打开对应
/// 管理入口：本次隐藏全部来自屏蔽名单时打开名单，否则打开关键词编辑。
/// 0.4.0：和新话题横幅一样是列表顶部 44 高的行内提示，用 meta 色表示次要状态。
class KeywordFilterHintBar extends ConsumerWidget {
  final int hiddenCount;

  /// [hiddenCount] 中因本地屏蔽名单隐藏的数量（其余为关键词命中）
  final int hiddenByBlocked;

  const KeywordFilterHintBar({
    super.key,
    required this.hiddenCount,
    this.hiddenByBlocked = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hiddenCount <= 0) return const SizedBox.shrink();
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    // 全部由屏蔽名单导致才跳名单管理；混合或纯关键词时管理关键词
    final onlyBlocked = hiddenByBlocked >= hiddenCount;

    // 44 高的行内提示：meta 文字，「管理」是 brand 文字按钮
    return AppPressable(
      highlight: true,
      onTap: () => onlyBlocked
          ? showBlockedUsernamesDialog(context, ref)
          : showTopicFilterKeywordsDialog(context, ref),
      child: SizedBox(
        height: AppSize.hit,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.visibilityOff,
                size: AppSize.iconS,
                color: colors.textMeta,
              ),
              const SizedBox(width: AppSpace.s),
              Text(
                l10n.topic_keywordFilter_hiddenCount(hiddenCount),
                style: style,
              ),
              Text(' · ', style: style),
              Text(
                l10n.topic_keywordFilter_manage,
                style: style.copyWith(color: colors.brandPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
