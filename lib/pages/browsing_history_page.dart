import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_filter.dart';
import '../models/topic.dart';
import '../navigation/nav_action_bus.dart';
import '../providers/discourse_providers.dart';
import '../providers/selected_topic_provider.dart';
import '../providers/user_content_search_provider.dart';
import '../utils/load_more_coordinator.dart';
import '../utils/blocked_user_filter.dart';
import '../utils/time_utils.dart';
import '../widgets/common/paged_list_footer.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/layout/master_detail_pane_host.dart';
import '../widgets/search/searchable_app_bar.dart';
import '../widgets/search/user_content_search_view.dart';
import '../widgets/topic/topic_item_builder.dart';
import '../widgets/topic/topic_list_skeleton.dart';
import '../providers/preferences_provider.dart';
import '../widgets/common/error_view.dart';
import '../l10n/s.dart';
import '../widgets/desktop_refresh_indicator.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// 浏览历史页面
class BrowsingHistoryPage extends ConsumerStatefulWidget {
  const BrowsingHistoryPage({super.key, this.isActive = true});

  /// 是否为当前活跃的 tab（嵌入底栏时用于决定是否响应 NavActionBus）
  final bool isActive;

  @override
  ConsumerState<BrowsingHistoryPage> createState() =>
      _BrowsingHistoryPageState();
}

class _BrowsingHistoryPageState extends ConsumerState<BrowsingHistoryPage> {
  final ScrollController _scrollController = ScrollController();
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  late final UserContentSearchNotifier _searchNotifier;

  /// 在 build 里取（不能在点击回调里读 MediaQuery）
  bool _canShowBothPanes = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchNotifier = ref.read(
      userContentSearchProvider(SearchInType.seen).notifier,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    Future(() {
      // 整个 ProviderScope 一起卸载时 notifier 已销毁，退出搜索模式没有意义
      try {
        _searchNotifier.exitSearchMode();
      } on StateError {
        // ignore
      }
    });
    super.dispose();
  }

  void _onScroll() {
    _publishScrollProgress();
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final notifier = ref.read(browsingHistoryProvider.notifier);
    await _loadMoreCoordinator.loadMore(
      loadMore: notifier.loadMore,
      hasMore: () => notifier.hasMore,
      isActive: () => mounted,
      progressCount: () => ref.read(browsingHistoryProvider).value?.length ?? 0,
    );
  }

  void _publishScrollProgress() {
    if (!_scrollController.hasClients) return;
    final raw = _scrollController.offset;
    final progress = raw < 0 ? 0.0 : raw;
    final current = ref.read(navScrollProgressProvider(NavEntryIds.history));
    final atZero = progress == 0 && current != 0;
    final crossed =
        (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4.0) return;
    ref.read(navScrollProgressProvider(NavEntryIds.history).notifier).state =
        progress;
  }

  Future<void> _onRefresh() async {
    _loadMoreCoordinator.resetCooldown();
    await ref.read(browsingHistoryProvider.notifier).refresh();
  }

  void _onItemTap(Topic topic) {
    // 树形视图从完整话题开始，续读楼层只用于平铺视图。
    final scrollToPostNumber = ref.read(preferencesProvider).defaultNestedView
        ? null
        : topic.lastReadPostNumber;
    // 宽屏进右栏,窄屏全屏 push——与草稿页同一套形态
    if (_canShowBothPanes) {
      ref
          .read(selectedHistoryPaneProvider.notifier)
          .select(
            topicId: topic.id,
            initialTitle: topic.title,
            scrollToPostNumber: scrollToPostNumber,
          );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          scrollToPostNumber: scrollToPostNumber,
        ),
      ),
    );
  }

  /// 把话题按「最后活动」的自然日切开，每一天前面插一个页眉
  List<_HistoryEntry> _groupByDay(List<Topic> topics) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final l10n = context.l10n;
    final entries = <_HistoryEntry>[];
    DateTime? lastDay;
    for (final topic in topics) {
      final time = topic.lastPostedAt ?? topic.createdAt ?? now;
      final day = DateTime(time.year, time.month, time.day);
      if (lastDay != day) {
        lastDay = day;
        final diff = today.difference(day).inDays;
        final label = diff == 0
            ? l10n.browsingHistory_groupToday
            : diff == 1
            ? l10n.browsingHistory_groupYesterday
            : l10n.browsingHistory_groupDate(TimeUtils.formatFullDate(time));
        entries.add(_HistoryEntry.header(label));
      }
      entries.add(_HistoryEntry.topic(topic));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(browsingHistoryProvider);
    final searchState = ref.watch(userContentSearchProvider(SearchInType.seen));
    _canShowBothPanes = MasterDetailLayout.canShowBothPanesFor(context);

    // 嵌入底栏时响应快捷动作（仅活跃 tab 响应）
    ref.listen(navActionBusProvider, (_, event) {
      if (event == null || event.targetId != NavEntryIds.history) return;
      if (!widget.isActive) return;
      switch (event.action) {
        case NavAction.scrollToTop:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          break;
        case NavAction.refresh:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          _onRefresh();
          ref.resetNavScrollProgress(NavEntryIds.history);
          break;
      }
    });

    final list = PopScope(
      canPop: !searchState.isSearchMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          // 搜索模式下按返回键，退出搜索而不是退出页面
          ref
              .read(userContentSearchProvider(SearchInType.seen).notifier)
              .exitSearchMode();
        }
      },
      child: Scaffold(
        appBar: SearchableAppBar(
          title: context.l10n.browsingHistory_title,
          isSearchMode: searchState.isSearchMode,
          onSearchPressed: () => ref
              .read(userContentSearchProvider(SearchInType.seen).notifier)
              .enterSearchMode(),
          onCloseSearch: () => ref
              .read(userContentSearchProvider(SearchInType.seen).notifier)
              .exitSearchMode(),
          onSearch: (query) => ref
              .read(userContentSearchProvider(SearchInType.seen).notifier)
              .search(query),
          showFilterButton: searchState.isSearchMode,
          filterActive: searchState.filter.isNotEmpty,
          onFilterPressed: () =>
              showSearchFilterPanel(context, ref, SearchInType.seen),
          searchHint: context.l10n.browsingHistory_searchHint,
        ),
        body: ReadableBody(
          child: Stack(
            children: [
              // 使用 Offstage 保持列表存在但在搜索模式下隐藏，保留滚动位置
              Offstage(
                offstage: searchState.isSearchMode,
                child: _buildTopicList(historyAsync),
              ),
              if (searchState.isSearchMode)
                UserContentSearchView(
                  inType: SearchInType.seen,
                  emptySearchHint: context.l10n.browsingHistory_emptySearchHint,
                ),
            ],
          ),
        ),
      ),
    );

    return MasterDetailPaneHost(
      stackProvider: selectedHistoryPaneProvider,
      isActive: widget.isActive,
      master: list,
    );
  }

  Widget _buildTopicList(AsyncValue<List<Topic>> historyAsync) {
    final selectedTopicId = ref.watch(
      selectedHistoryPaneProvider.select((s) => s.topicId),
    );
    return DesktopRefreshIndicator(
      onRefresh: _onRefresh,
      child: historyAsync.when(
        data: (topics) {
          final blockedUsernames = ref.watch(
            preferencesProvider.select((p) => p.normalizedBlockedUsernames),
          );
          final visibleTopics = BlockedUserFilter.visibleTopics(
            topics,
            blockedUsernames,
          );
          final notifier = ref.read(browsingHistoryProvider.notifier);
          // 已加载页全部被本地屏蔽时列表不可滚，滚动触发的翻页发生不了。
          // 不自动补载（会一页接一页地翻下去），空状态里给用户手动点的按钮
          if (visibleTopics.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.history,
                    size: 64,
                    color: context.tokens.colors.textMeta,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.browsingHistory_empty,
                    style: TextStyle(color: context.tokens.colors.textMeta),
                  ),
                  if (topics.isNotEmpty && notifier.hasMore) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const ValueKey('history-load-earlier'),
                      onPressed: notifier.isLoadingMore ? null : _loadMore,
                      child: Text(context.l10n.browsingHistory_loadEarlier),
                    ),
                  ],
                ],
              ),
            );
          }

          // v2：按天分组的页眉。话题接口没有「浏览时间」，只能按话题的最后活动
          // 日期（last_posted_at，缺省取创建时间）分组，页眉明说「最后活动」。
          final entries = _groupByDay(visibleTopics);
          final enableLongPress = ref
              .watch(preferencesProvider)
              .longPressPreview;
          return ListView.builder(
            controller: _scrollController,
            // 底部让出 extendBody 注入的底栏高度
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: entries.length + 1,
            itemBuilder: (context, index) {
              if (index == entries.length) {
                final notifier = ref.watch(browsingHistoryProvider.notifier);
                final footer = PagedListFooter(
                  hasMore: notifier.hasMore,
                  isLoadingMore: notifier.isLoadingMore,
                  isLoadMoreFailed: notifier.isLoadMoreFailed,
                  onRetry: notifier.retryLoadMore,
                );
                // 屏蔽后只剩一两条、列表不满一屏时滚动翻不了页：手动按钮
                if (visibleTopics.length < topics.length &&
                    notifier.hasMore &&
                    !notifier.isLoadingMore &&
                    !notifier.isLoadMoreFailed) {
                  return Column(
                    children: [
                      TextButton(
                        key: const ValueKey('history-load-earlier-footer'),
                        onPressed: _loadMore,
                        child: Text(context.l10n.browsingHistory_loadEarlier),
                      ),
                      footer,
                    ],
                  );
                }
                return footer;
              }
              final entry = entries[index];
              final header = entry.header;
              if (header != null) {
                return _DayHeader(label: header);
              }
              final topic = entry.topic!;
              return buildTopicItem(
                context: context,
                topic: topic,
                isSelected: _canShowBothPanes && topic.id == selectedTopicId,
                onTap: () => _onItemTap(topic),
                enableLongPress: enableLongPress,
              );
            },
          );
        },
        loading: () => const TopicListSkeleton(),
        error: (error, stack) =>
            ErrorView(error: error, stackTrace: stack, onRetry: _onRefresh),
      ),
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry.header(String this.header) : topic = null;
  const _HistoryEntry.topic(Topic this.topic) : header = null;

  final String? header;
  final Topic? topic;
}

/// 日期页眉：13 meta，上 12 下 4，左边距 20
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pageMargin,
          AppSpace.m,
          AppSpace.pageMargin,
          AppSpace.xs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.merge(tokens.text.meta)
              .copyWith(color: tokens.colors.textMeta),
        ),
      ),
    );
  }
}
