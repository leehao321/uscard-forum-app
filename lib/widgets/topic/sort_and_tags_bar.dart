import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';

import '../../providers/topic_list/filter_provider.dart';
import '../../providers/topic_list/sort_provider.dart';
import '../common/topic_badges.dart';
import 'filter_dropdown.dart';
import '../../l10n/s.dart';

/// 筛选选项定义
List<(TopicListFilter, String)> get filterOptions => [
  (TopicListFilter.latest, S.current.topic_filterLatest),
  (TopicListFilter.newTopics, S.current.topic_filterNew),
  (TopicListFilter.unread, S.current.topic_filterUnread),
  (TopicListFilter.unseen, S.current.topic_filterUnseen),
  (TopicListFilter.top, S.current.topic_filterTop),
  (TopicListFilter.hot, S.current.topic_filterHot),
];

/// 获取筛选模式的显示名称
String filterLabel(TopicListFilter filter) {
  for (final option in filterOptions) {
    if (option.$1 == filter) return option.$2;
  }
  return S.current.topic_filterLatest;
}

/// 筛选下拉 + 排序下拉 + 标签 chips（固定在 Tab 和列表之间）
///
/// 纯 callback-based，不再内部读写任何 provider。
class SortAndTagsBar extends StatelessWidget {
  final TopicListFilter currentFilter;
  final bool isLoggedIn;
  final ValueChanged<TopicListFilter> onFilterChanged;
  final NewSubset currentSubset;
  final ValueChanged<NewSubset> onSubsetChanged;
  final TopicSortOrder currentOrder;
  final bool ascending;
  final ValueChanged<TopicSortOrder> onOrderChanged;
  final VoidCallback onToggleAscending;
  final List<String> selectedTags;
  final ValueChanged<String> onTagRemoved;
  final VoidCallback? onAddTag;
  final Widget? trailing;

  const SortAndTagsBar({
    super.key,
    required this.currentFilter,
    required this.isLoggedIn,
    required this.onFilterChanged,
    required this.currentSubset,
    required this.onSubsetChanged,
    required this.currentOrder,
    required this.ascending,
    required this.onOrderChanged,
    required this.onToggleAscending,
    required this.selectedTags,
    required this.onTagRemoved,
    this.onAddTag,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // 筛选胶囊行（Figma「分类话题页 / 标签话题列表」）：左右 20，胶囊间距 8，
    // 胶囊自带上下 6 的透明热区，凑足 44 高
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
      child: Row(
        children: [
          // 筛选下拉
          FilterDropdown(
            currentFilter: currentFilter,
            isLoggedIn: isLoggedIn,
            onFilterChanged: onFilterChanged,
          ),
          // 「新话题」子过滤下拉
          if (currentFilter == TopicListFilter.newTopics) ...[
            const SizedBox(width: AppSpace.s),
            NewSubsetDropdown(
              currentSubset: currentSubset,
              onSubsetChanged: onSubsetChanged,
            ),
          ],
          const SizedBox(width: AppSpace.s),
          // 排序下拉
          OrderDropdown(
            currentOrder: currentOrder,
            ascending: ascending,
            onOrderChanged: onOrderChanged,
            onToggleAscending: onToggleAscending,
          ),
          const SizedBox(width: AppSpace.s),
          // 标签区域
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...selectedTags.map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: AppSpace.s),
                      child: RemovableTagBadge(
                        name: tag,
                        onDeleted: () => onTagRemoved(tag),
                        size: const BadgeSize(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          radius: 6,
                          iconSize: 12,
                          fontSize: AppFontSize.meta,
                        ),
                      ),
                    ),
                  ),
                  if (onAddTag != null)
                    FilterPill(
                      label: context.l10n.tag_tabTags,
                      onTap: onAddTag,
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
