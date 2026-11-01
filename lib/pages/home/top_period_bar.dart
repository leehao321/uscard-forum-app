import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/topic_list/filter_provider.dart';

/// 首页「排行榜」的时间段分段控件（Figma「首页 · 排行榜」）：分类条下面一行，
/// 外框左右 20、上下 8；40 高的 surface/grouped 圆角底，6 等分：日 / 周 / 月 / 季 / 年 / 全部。
/// 选中的一段是 surface/page 底的圆角块 + 13 号 medium 主色字，其余 13 号 meta 色。
///
/// 选哪一段写进 [topPeriodProvider]，列表按新的时间段重新请求。
class TopPeriodBar extends ConsumerWidget {
  const TopPeriodBar({super.key});

  /// 控件本体高度
  static const double height = 40;

  /// 选中块与底的间隙
  static const double inset = 2;

  static String labelOf(BuildContext context, TopPeriod period) {
    final l10n = context.l10n;
    return switch (period) {
      TopPeriod.daily => l10n.topic_periodDaily,
      TopPeriod.weekly => l10n.topic_periodWeekly,
      TopPeriod.monthly => l10n.topic_periodMonthly,
      TopPeriod.quarterly => l10n.topic_periodQuarterly,
      TopPeriod.yearly => l10n.topic_periodYearly,
      TopPeriod.all => l10n.topic_periodAll,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(topPeriodProvider);
    return TopPeriodSegments(
      selected: selected,
      onSelected: ref.read(topPeriodProvider.notifier).setPeriod,
    );
  }
}

/// [TopPeriodBar] 的纯展示部分
class TopPeriodSegments extends StatelessWidget {
  const TopPeriodSegments({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TopPeriod selected;
  final ValueChanged<TopPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final insets = readableInsets(context, gutter: 0);
    // 视觉上 40 高，点按区撑到 44（上下的外框留白也算）
    return Padding(
      padding: EdgeInsets.fromLTRB(
        insets.left + AppSpace.pageMargin,
        0,
        insets.right + AppSpace.pageMargin,
        0,
      ),
      child: SizedBox(
        height: TopPeriodBar.height + 2 * AppSpace.s,
        child: Stack(
          children: [
            Positioned.fill(
              top: AppSpace.s,
              bottom: AppSpace.s,
              child: DecoratedBox(
                key: const ValueKey('top-period-track'),
                decoration: BoxDecoration(
                  color: colors.surfaceGrouped,
                  borderRadius: BorderRadius.circular(tokens.radius.field),
                ),
              ),
            ),
            Row(
              children: [
                for (final period in TopPeriod.values)
                  Expanded(
                    child: _Segment(
                      period: period,
                      selected: period == selected,
                      onTap: () => onSelected(period),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.period,
    required this.selected,
    required this.onTap,
  });

  final TopPeriod period;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final label = TopPeriodBar.labelOf(context, period);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: AppPressable(
        onTap: onTap,
        // 点按反馈只在已选块上看得出来，其余段不变淡
        pressedOpacity: 0.6,
        button: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpace.s + TopPeriodBar.inset,
            horizontal: TopPeriodBar.inset,
          ),
          child: DecoratedBox(
            key: ValueKey('top-period-${period.name}'),
            decoration: BoxDecoration(
              color: selected ? colors.surfacePage : Colors.transparent,
              borderRadius: BorderRadius.circular(tokens.radius.table),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(
                      color: selected ? colors.textPrimary : colors.textMeta,
                      fontWeight: selected ? FontWeight.w500 : null,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
