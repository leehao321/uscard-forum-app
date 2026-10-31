import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/message_bus/topic_tracking_providers.dart';
import '../../providers/topic_list/filter_provider.dart';
import '../../providers/topic_list/sort_provider.dart';
import '../../providers/topic_list/tab_state_provider.dart';
import '../../widgets/topic/sort_and_tags_bar.dart'
    show filterOptions, filterLabel;

/// 菜单值哨兵（与筛选 / 排序 / 子过滤的枚举值区分）
const _dismissAllValue = #homeTitleMenuDismissAll;
const _selectTagsValue = #homeTitleMenuSelectTags;

/// 首页导航栏的标题菜单（设计说明 §3.1 导航 · 收起单行）：
/// 「最新 ▾」17 Regular + chevron-down 14，热区 52×44。
///
/// 菜单：筛选方式（带计数）/「新」的子过滤 / 排序二级（再选已选项切升降序）
/// / 添加标签 / 全部标为已读（仅新 / 未读完，需确认）。取代 TopicFilterMenuButton。
class HomeTitleMenu extends ConsumerWidget {
  const HomeTitleMenu({
    super.key,
    required this.isLoggedIn,
    required this.categoryId,
    required this.onSelectTags,
    required this.onDismissAll,
  });

  final bool isLoggedIn;
  final int? categoryId;
  final VoidCallback onSelectTags;

  /// 点「全部标为已读」后由页面弹确认
  final void Function(TopicListFilter filter) onDismissAll;

  static int _countFor(TopicListFilter filter, int newCount, int unreadCount) =>
      switch (filter) {
        TopicListFilter.newTopics => newCount + unreadCount,
        TopicListFilter.unread => unreadCount,
        _ => 0,
      };

  static String _subsetLabel(NewSubset subset) => switch (subset) {
    NewSubset.all => S.current.topic_filterNewAllShort,
    NewSubset.topics => S.current.topic_filterNewTopicsShort,
    NewSubset.replies => S.current.topic_filterNewRepliesShort,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filter = ref.watch(topicFilterProvider);
    final order = ref.watch(topicSortOrderProvider);
    final ascending = ref.watch(topicSortAscendingProvider);
    final subset = ref.watch(topicNewSubsetProvider);
    final tagCount = ref.watch(tabTagsProvider(categoryId)).length;
    final tracking = ref.watch(topicTrackingStateProvider.notifier);
    ref.watch(topicTrackingStateProvider);
    final newCount = isLoggedIn ? tracking.countNew(categoryId: categoryId) : 0;
    final unreadCount = isLoggedIn
        ? tracking.countUnread(categoryId: categoryId)
        : 0;

    String withCount(TopicListFilter f, String base) {
      final n = _countFor(f, newCount, unreadCount);
      return n > 0 ? '$base ($n)' : base;
    }

    final label = withCount(filter, filterLabel(filter));
    final orderActive = order != TopicSortOrder.defaultOrder;

    List<List<AppMenuItem<Object>>> sections() {
      final visibleFilters = filterOptions.where(
        (o) =>
            isLoggedIn ||
            (o.$1 != TopicListFilter.newTopics &&
                o.$1 != TopicListFilter.unread &&
                o.$1 != TopicListFilter.unseen),
      );
      return [
        [
          for (final o in visibleFilters)
            AppMenuItem<Object>(
              label: withCount(o.$1, o.$2),
              value: o.$1,
              checked: o.$1 == filter,
            ),
        ],
        if (filter == TopicListFilter.newTopics)
          [
            for (final s in NewSubset.values)
              AppMenuItem<Object>(
                label: _subsetLabel(s),
                value: s,
                checked: s == subset,
              ),
          ],
        [
          AppMenuItem<Object>(
            label: S.current.topic_sortTooltip(order.label),
            icon: AppIcons.sort,
            submenu: [
              [
                for (final o in TopicSortOrder.values)
                  AppMenuItem<Object>(
                    label: o == order && o != TopicSortOrder.defaultOrder
                        ? '${o.label} ${ascending ? '↑' : '↓'}'
                        : o.label,
                    value: o,
                    checked: o == order,
                  ),
              ],
            ],
          ),
          AppMenuItem<Object>(
            label: tagCount > 0
                ? '${S.current.topic_addTags} ($tagCount)'
                : S.current.topic_addTags,
            icon: AppIcons.tag,
            value: _selectTagsValue,
          ),
        ],
        if (isLoggedIn &&
            (filter == TopicListFilter.newTopics ||
                filter == TopicListFilter.unread))
          [
            AppMenuItem<Object>(
              label: S.current.topics_dismiss,
              icon: AppIcons.checkAll,
              value: _dismissAllValue,
            ),
          ],
      ];
    }

    return Builder(
      builder: (buttonContext) => AppPressable(
        semanticLabel: S.current.topic_filterTooltip(filterLabel(filter)),
        excludeChildSemantics: true,
        onTap: () async {
          final value = await showAppMenu<Object>(
            context: buttonContext,
            anchor: globalRectOf(buttonContext),
            sections: sections(),
          );
          if (value == null) return;
          if (value is TopicListFilter) {
            ref.read(topicFilterProvider.notifier).setFilter(value);
          } else if (value is NewSubset) {
            ref.read(topicNewSubsetProvider.notifier).setSubset(value);
          } else if (value is TopicSortOrder) {
            // 再选已选中的非默认排序 = 切换升降序
            if (value == order && value != TopicSortOrder.defaultOrder) {
              ref.read(topicSortAscendingProvider.notifier).toggle();
            } else {
              ref.read(topicSortOrderProvider.notifier).setOrder(value);
            }
          } else if (value == _selectTagsValue) {
            onSelectTags();
          } else if (value == _dismissAllValue) {
            onDismissAll(filter);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSize.hit,
            minWidth: 52,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge!
                      .merge(tokens.text.control)
                      .copyWith(color: tokens.colors.textPrimary),
                ),
              ),
              if (orderActive)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpace.xs),
                  child: UnreadDot(size: 5),
                ),
              const SizedBox(width: AppSpace.xs),
              Icon(
                AppIcons.chevronDown,
                size: 14,
                color: tokens.colors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
