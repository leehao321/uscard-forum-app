import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart' show M3eRefreshIndicatorState;
import 'package:share_plus/share_plus.dart';

import '../../constants.dart';
import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/topic.dart';
import '../../navigation/nav_action_bus.dart';
import '../../providers/bookmark_sync_controller.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/selected_topic_provider.dart';
import '../../providers/shortcut_provider.dart';
import '../../models/shortcut_binding.dart';
import '../../services/toast_service.dart';
import '../../utils/frame_jank_monitor.dart';
import '../../utils/load_more_coordinator.dart';
import '../../utils/platform_utils.dart';
import '../../utils/topic_keyword_filter.dart';
import '../../widgets/common/anchor_guard_sliver.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/paged_list_footer.dart';
import '../../widgets/desktop_refresh_indicator.dart';
import '../../widgets/layout/master_detail_layout.dart';
import '../../widgets/topic/keyword_filter_hint_bar.dart';
import '../../widgets/topic/topic_list_skeleton.dart';
import '../../widgets/topic/topic_list_update_banner.dart';
import '../../widgets/topic/topic_list_updates_mixin.dart';
import '../../widgets/topic/topic_row.dart';
import '../topic_detail_page/topic_detail_page.dart';
import 'home_signals.dart';

/// 首页的话题列表（0.4.0 v2，计划 §5 M3 `home_topic_list.dart`）。
///
/// 只显示一个分类（[categoryId]，null = 全部）。行是 [TopicRow]，置顶话题
/// 折成单行 [PinnedTopicRow]；左滑露出「书签」「标为已读」，长按浮起上下文
/// 菜单。加载：200ms 内静默，之后出骨架，3 秒后加「正在等待论坛响应」；
/// 出错原地显示；新话题横幅和关键词过滤提示是列表顶部 44 高的行内提示。
class HomeTopicList extends ConsumerStatefulWidget {
  const HomeTopicList({
    super.key,
    required this.categoryId,
    required this.categoryMap,
    required this.parentActive,
  });

  final int? categoryId;
  final Map<int, Category> categoryMap;

  /// 宿主底栏 Tab 是否活跃（桌面快捷键注册的失活谓词用）
  final bool parentActive;

  @override
  ConsumerState<HomeTopicList> createState() => _HomeTopicListState();
}

class _HomeTopicListState extends ConsumerState<HomeTopicList>
    with TopicListUpdatesMixin<HomeTopicList> {
  final _scrollController = ScrollController();
  final _refreshIndicatorKey = GlobalKey<M3eRefreshIndicatorState>();
  late final ShortcutScopeBinding _listShortcutBinding = ShortcutScopeBinding(
    ref: ref,
    scope: ShortcutScope.master,
    enabled: () => widget.parentActive,
  );

  /// 需要高亮的话题 IDs（loadBefore 插入后设置，渐变消失后清除）
  final Set<int> _highlightedTopicIds = {};

  /// keyed reconcile 的固定行 key
  static const _pillKeyValue = 'topics-pill';
  static const _filterHintKeyValue = 'topics-filter-hint';
  static const _footerKeyValue = 'topics-footer';

  /// topic.id → 可见列表 index，供 findChildIndexCallback O(1) 反查
  List<Topic>? _visibleIndexSource;
  Map<int, int> _topicIdToVisibleIndex = const {};
  int? _lastHeaderOffset;

  /// 键盘焦点索引（J/K 导航用）
  int _keyboardFocusIndex = -1;
  DateTime _lastKeyNavTime = DateTime(0);

  final TopicLoadMoreCoordinator _loadMoreCoordinator =
      TopicLoadMoreCoordinator();
  List<String> _lastAutoLoadKeywords = const [];
  Set<String> _lastAutoLoadBlockedUsernames = const <String>{};
  bool? _lastAutoLoadWholeWord;

  Map<int, int> _visibleIndexMapFor(List<Topic> topics) {
    if (!identical(_visibleIndexSource, topics)) {
      final hadPrevious = _visibleIndexSource != null;
      _visibleIndexSource = topics;
      _topicIdToVisibleIndex = <int, int>{
        for (var i = 0; i < topics.length; i++) topics[i].id: i,
      };
      // 列表数据换代（顶部插入 / 全量替换 / 单行刷新）：武装锚定哨兵
      if (hadPrevious) AnchorGuardSliver.arm();
    }
    return _topicIdToVisibleIndex;
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _clearIncomingState() {
    _highlightedTopicIds.clear();
    topicUpdates.reset();
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) _listShortcutBinding.disposeDeferred();
    _scrollController.dispose();
    super.dispose();
  }

  // —— 键盘导航（桌面 J/K/Enter）——

  int _resolveKeyboardAnchorIndex(List<Topic> topics) {
    final selectedTopicId = ref.read(selectedTopicProvider).topicId;
    final selectedIndex = selectedTopicId == null
        ? -1
        : topics.indexWhere((topic) => topic.id == selectedTopicId);
    if (_keyboardFocusIndex >= 0 && _keyboardFocusIndex < topics.length) {
      if (selectedIndex != -1 &&
          topics[_keyboardFocusIndex].id != selectedTopicId) {
        return selectedIndex;
      }
      return _keyboardFocusIndex;
    }
    return selectedIndex;
  }

  void _moveKeyboardFocus(int delta, AsyncValue<List<Topic>> topicsAsync) {
    final now = DateTime.now();
    if (now.difference(_lastKeyNavTime).inMilliseconds < 150) return;
    _lastKeyNavTime = now;
    final topics = topicsAsync.asData?.value;
    if (topics == null || topics.isEmpty) return;
    final anchorIndex = _resolveKeyboardAnchorIndex(topics);
    final newIndex = (anchorIndex + delta).clamp(0, topics.length - 1);
    if (newIndex == _keyboardFocusIndex) return;
    setState(() => _keyboardFocusIndex = newIndex);
    _openTopic(topics[newIndex]);
    if (_scrollController.hasClients) {
      final estimated = newIndex * 80.0;
      final viewport = _scrollController.position.viewportDimension;
      final current = _scrollController.position.pixels;
      if (estimated < current || estimated > current + viewport - 80) {
        _scrollController.animateTo(
          estimated.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _openFocusedTopic(AsyncValue<List<Topic>> topicsAsync) {
    final topics = topicsAsync.asData?.value;
    if (topics == null || topics.isEmpty) return;
    final i = _resolveKeyboardAnchorIndex(topics);
    if (i < 0 || i >= topics.length) return;
    final topic = topics[i];
    final scrollTo = ref.read(preferencesProvider).defaultNestedView
        ? null
        : topic.lastReadPostNumber;
    // 强制用 Navigator push 打开（而非 Master-Detail 内选中）
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          initialTitle: topic.title,
          scrollToPostNumber: scrollTo,
        ),
      ),
    );
  }

  void _syncKeyboardFocusToTopicId(int topicId) {
    final index = _topicIdToVisibleIndex[topicId];
    if (index != null && _keyboardFocusIndex != index) {
      setState(() => _keyboardFocusIndex = index);
    }
  }

  // —— 加载更多 ——

  /// 触发 loadMore，并在关键词命中率高、可见增量不足时自动续加载
  Future<void> _triggerLoadMore(int? providerKey) async {
    final notifier = ref.read(topicListProvider(providerKey).notifier);
    final prefs = ref.read(preferencesProvider);
    final keywords = prefs.normalizedFilterKeywords;
    final wholeWord = prefs.topicFilterWholeWord;
    final blockedUsernames = prefs.normalizedBlockedUsernames;

    int itemCount() =>
        ref.read(topicListProvider(providerKey)).value?.length ?? 0;
    int visibleItemCount() {
      final raw =
          ref.read(topicListProvider(providerKey)).value ?? const <Topic>[];
      final (visible, _, _) = TopicKeywordFilter.apply(
        raw,
        normalizedKeywords: keywords,
        wholeWord: wholeWord,
        blockedUsernames: blockedUsernames,
      );
      return visible.length;
    }

    await _loadMoreCoordinator.loadTopicPage(
      loadMore: notifier.loadMore,
      hasMore: () => notifier.hasMore,
      isActive: () => mounted,
      itemCount: itemCount,
      visibleItemCount: visibleItemCount,
      hasKeywordFilter: keywords.isNotEmpty || blockedUsernames.isNotEmpty,
    );
  }

  void _syncAutoLoadFilter(
    List<String> keywords,
    bool wholeWord,
    Set<String> blockedUsernames,
  ) {
    if (listEquals(_lastAutoLoadKeywords, keywords) &&
        _lastAutoLoadWholeWord == wholeWord &&
        setEquals(_lastAutoLoadBlockedUsernames, blockedUsernames)) {
      return;
    }
    _lastAutoLoadKeywords = List.unmodifiable(keywords);
    _lastAutoLoadWholeWord = wholeWord;
    _lastAutoLoadBlockedUsernames = Set.unmodifiable(blockedUsernames);
    _loadMoreCoordinator.resetCooldown();
  }

  // —— 行动作 ——

  void _openTopic(Topic topic) {
    // 树形视图从完整话题开始，续读楼层只用于平铺视图
    final scrollTo = ref.read(preferencesProvider).defaultNestedView
        ? null
        : topic.lastReadPostNumber;
    if (MasterDetailLayout.canShowBothPanesFor(context)) {
      ref
          .read(selectedTopicProvider.notifier)
          .select(
            topicId: topic.id,
            initialTitle: topic.title,
            scrollToPostNumber: scrollTo,
          );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          initialTitle: topic.title,
          scrollToPostNumber: scrollTo,
          autoSwitchToMasterDetail: true,
        ),
      ),
    );
  }

  /// 把滚动距离告诉侧栏：宽屏的「首页」图标往下滚后变成回顶箭头（L-2）
  void _publishScrollProgress(double pixels) {
    final progress = pixels < 0 ? 0.0 : pixels;
    final current = ref.read(navScrollProgressProvider(NavEntryIds.home));
    final atZero = progress == 0 && current != 0;
    final crossed =
        (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4.0) return;
    ref.read(navScrollProgressProvider(NavEntryIds.home).notifier).state =
        progress;
  }

  Future<void> _bookmark(Topic topic) async {
    try {
      await ref.read(discourseServiceProvider).bookmarkTopic(topic.id);
      // 写穿透：静默拉书签列表第一页，「我的 → 书签」里立刻能看到（M-7）
      unawaited(
        ref.read(bookmarkSyncControllerProvider.notifier).pullFirstPage(),
      );
      ToastService.showSuccess(S.current.common_bookmarkAdded);
    } catch (e) {
      ToastService.showError(S.current.common_operationFailed(e.toString()));
    }
  }

  /// 能不能「标为已读」：已登录、非置顶、有未读或新帖子。左滑和长按菜单共用
  bool _canMarkRead(Topic topic, bool isLoggedIn) =>
      isLoggedIn && !topic.pinned && (topic.unread > 0 || topic.newPosts > 0);

  /// 标为已读（0.4.0 计划 P8）：只发这一条的 dismiss 请求，成功后只改这一条的
  /// 本地已读状态（列表项 + 它自己的追踪状态）。不按分类清零，也不再重取整帖详情。
  /// 失败只提示，不重试。
  Future<void> _markRead(Topic topic, int? providerKey) async {
    try {
      await ref.read(discourseServiceProvider).dismissTopicPosts([topic.id]);
      ref
          .read(topicListProvider(providerKey).notifier)
          .updateSeen(topic.id, topic.highestPostNumber);
    } catch (e) {
      ToastService.showError(S.current.common_operationFailed(e.toString()));
    }
  }

  void _share(Topic topic) {
    final url = '${AppConstants.baseUrl}/t/${topic.slug}/${topic.id}';
    SharePlus.instance.share(ShareParams(text: url));
  }

  Widget _row(
    BuildContext context,
    Topic topic, {
    required int? providerKey,
    required bool isLoggedIn,
    required bool isSelected,
    required bool enableLongPress,
    Color? highlightColor,
  }) {
    final tokens = context.tokens;
    final category = widget.categoryMap[int.tryParse(topic.categoryId)];
    void open() {
      _syncKeyboardFocusToTopicId(topic.id);
      _openTopic(topic);
    }

    List<List<AppMenuItem<int>>> menu() => [
      [
        AppMenuItem(
          label: S.current.topic_rowOpen,
          icon: AppIcons.article,
          value: 0,
        ),
        if (isLoggedIn)
          AppMenuItem(
            label: S.current.topic_rowBookmark,
            icon: AppIcons.bookmark,
            value: 1,
          ),
        AppMenuItem(
          label: S.current.common_share,
          icon: AppIcons.share,
          value: 2,
        ),
        if (_canMarkRead(topic, isLoggedIn))
          AppMenuItem(
            label: S.current.topic_rowMarkRead,
            icon: AppIcons.checkAll,
            value: 3,
          ),
      ],
    ];

    Widget item = topic.pinned
        ? PinnedTopicRow(topic: topic, onTap: open, isSelected: isSelected)
        : TopicRow(
            topic: topic,
            category: category,
            isSelected: isSelected,
            highlightColor: highlightColor,
            onTap: open,
          );

    if (enableLongPress) {
      item = LiftedContextMenu<int>(
        sectionsBuilder: (_) => menu(),
        liftedBuilder: (_) => topic.pinned
            ? PinnedTopicRow(topic: topic, onTap: () {})
            : TopicRow(topic: topic, category: category, onTap: () {}),
        onSelected: (v) {
          switch (v) {
            case 0:
              open();
            case 1:
              _bookmark(topic);
            case 2:
              _share(topic);
            case 3:
              _markRead(topic, providerKey);
          }
        },
        child: item,
      );
    }

    if (isLoggedIn && !topic.pinned) {
      item = SwipeActions(
        actions: [
          SwipeActionItem(
            label: S.current.topic_rowBookmark,
            icon: AppIcons.bookmark,
            onTap: () => _bookmark(topic),
          ),
          if (_canMarkRead(topic, isLoggedIn))
            SwipeActionItem(
              label: S.current.topic_rowMarkRead,
              icon: AppIcons.checkAll,
              background: tokens.colors.avatarFill,
              foreground: tokens.colors.textPrimary,
              onTap: () => _markRead(topic, providerKey),
            ),
        ],
        child: ColoredBox(color: tokens.colors.surfacePage, child: item),
      );
    }
    return item;
  }

  @override
  Widget build(BuildContext context) {
    final providerKey = widget.categoryId;
    final tokens = context.tokens;
    final isLoggedIn = ref.watch(currentUserProvider).value != null;
    final topicsAsync = ref.watch(topicListProvider(providerKey));

    ref.listen(scrollToTopProvider, (_, _) => _scrollToTop());
    ref.listen(homeRefreshSignalProvider, (_, _) {
      _refreshIndicatorKey.currentState?.show();
    });
    ref.listen(tabTagsProvider(widget.categoryId), (prev, next) {
      if (prev != next) {
        _loadMoreCoordinator.resetCooldown();
        ref.read(topicListProvider(widget.categoryId).notifier).refresh();
        _clearIncomingState();
      }
    });
    ref.listen(topicListGlobalParamsSignal, (_, _) {
      _loadMoreCoordinator.resetCooldown();
      _clearIncomingState();
    });

    final keywords = ref.watch(
      preferencesProvider.select((p) => p.normalizedFilterKeywords),
    );
    final wholeWord = ref.watch(
      preferencesProvider.select((p) => p.topicFilterWholeWord),
    );
    final blockedUsernames = ref.watch(
      preferencesProvider.select((p) => p.normalizedBlockedUsernames),
    );
    final showFilterHint = ref.watch(
      preferencesProvider.select((p) => p.showFilterHint),
    );
    _syncAutoLoadFilter(keywords, wholeWord, blockedUsernames);
    var hiddenCount = 0;
    var hiddenByBlocked = 0;
    final visibleTopicsAsync = topicsAsync.whenData((topics) {
      final (visible, hidden, byBlocked) = TopicKeywordFilter.apply(
        topics,
        normalizedKeywords: keywords,
        wholeWord: wholeWord,
        blockedUsernames: blockedUsernames,
      );
      hiddenCount = hidden;
      hiddenByBlocked = byBlocked;
      return visible;
    });
    final selectedTopicId = ref.watch(selectedTopicProvider).topicId;
    final enableLongPress = ref.watch(
      preferencesProvider.select((p) => p.longPressPreview),
    );

    // 桌面端：注册 J/K/Enter 导航到主面板快捷键
    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _listShortcutBinding.register(context, {
          ShortcutAction.nextItem: () =>
              _moveKeyboardFocus(1, visibleTopicsAsync),
          ShortcutAction.previousItem: () =>
              _moveKeyboardFocus(-1, visibleTopicsAsync),
          ShortcutAction.openItem: () => _openFocusedTopic(visibleTopicsAsync),
        });
      });
    }

    final updateQuery = TopicListUpdateQuery(
      filter: ref.read(topicFilterProvider),
      subset: ref.read(topicNewSubsetProvider),
      categoryId: widget.categoryId,
      tags: ref.read(tabTagsProvider(widget.categoryId)),
      order: ref.read(topicSortOrderProvider).apiValue,
      ascending: ref.read(topicSortAscendingProvider),
      newNewView: newNewViewEnabled,
    );
    watchTopicUpdates(
      updateQuery,
      tags: ref.read(topicListProvider(providerKey).notifier).knownTags,
    );

    final bottomPad = MediaQuery.paddingOf(context).bottom + AppSpace.m;
    return visibleTopicsAsync.when(
      data: (topics) {
        final newTopicCount = topicUpdateSnapshot.length;
        final hasNewTopics = newTopicCount > 0 || isLoadingTopicUpdates;
        final newTopicOffset = hasNewTopics ? 1 : 0;
        final hintOffset = (showFilterHint && hiddenCount > 0) ? 1 : 0;
        final headerOffset = newTopicOffset + hintOffset;
        final idToIndex = _visibleIndexMapFor(topics);
        if (_lastHeaderOffset != null && _lastHeaderOffset != headerOffset) {
          AnchorGuardSliver.arm();
        }
        _lastHeaderOffset = headerOffset;

        return DesktopRefreshIndicator(
          refreshIndicatorKey: _refreshIndicatorKey,
          refreshNotifier: masterRefreshNotifier,
          shouldRefresh: () =>
              ref.read(currentTabCategoryIdProvider) == widget.categoryId,
          onRefresh: () async {
            _loadMoreCoordinator.resetCooldown();
            final ticket = beginTopicUpdatesRefresh(updateQuery);
            try {
              // ignore: unused_result
              await ref.refresh(topicListProvider(providerKey).future);
              if (isCurrentTopicUpdatesRefresh(ticket.generation)) {
                setState(() => topicUpdates.acknowledge(ticket.snapshot));
              }
            } catch (_) {}
          },
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) {
                _publishScrollProgress(notification.metrics.pixels);
                final distance =
                    notification.metrics.maxScrollExtent -
                    notification.metrics.pixels;
                if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
                  _triggerLoadMore(providerKey);
                }
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverReadable(
                  gutter: 0,
                  sliver: SliverPadding(
                    padding: EdgeInsets.only(bottom: bottomPad),
                    sliver: SliverList.builder(
                      itemCount: topics.length + headerOffset + 1,
                      addAutomaticKeepAlives: false,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final value = key.value;
                        if (value == _pillKeyValue) {
                          return hasNewTopics ? 0 : null;
                        }
                        if (value == _filterHintKeyValue) {
                          return hintOffset > 0 ? newTopicOffset : null;
                        }
                        if (value == _footerKeyValue) {
                          return topics.length + headerOffset;
                        }
                        if (value.startsWith('topic-')) {
                          final id = int.tryParse(value.substring(6));
                          final topicIndex = id == null ? null : idToIndex[id];
                          if (topicIndex != null) {
                            return topicIndex + headerOffset;
                          }
                        }
                        return null;
                      },
                      itemBuilder: (context, index) {
                        if (hasNewTopics && index == 0) {
                          FrameJankMonitor.noteBuild('home:pill');
                          return KeyedSubtree(
                            key: const ValueKey(_pillKeyValue),
                            child: _newTopicIndicator(
                              newTopicCount,
                              providerKey,
                            ),
                          );
                        }
                        if (hintOffset > 0 && index == newTopicOffset) {
                          return KeyedSubtree(
                            key: const ValueKey(_filterHintKeyValue),
                            child: KeywordFilterHintBar(
                              hiddenCount: hiddenCount,
                              hiddenByBlocked: hiddenByBlocked,
                            ),
                          );
                        }
                        final topicIndex = index - headerOffset;
                        if (topicIndex >= topics.length) {
                          final notifier = ref.watch(
                            topicListProvider(providerKey).notifier,
                          );
                          return KeyedSubtree(
                            key: const ValueKey(_footerKeyValue),
                            child: PagedListFooter(
                              hasMore: notifier.hasMore,
                              isLoadingMore: notifier.isLoadingMore,
                              isLoadMoreFailed: notifier.isLoadMoreFailed,
                              onRetry: notifier.retryLoadMore,
                            ),
                          );
                        }

                        final topic = topics[topicIndex];
                        final highlighted = _highlightedTopicIds.contains(
                          topic.id,
                        );
                        Widget row(Color? highlight) => _row(
                          context,
                          topic,
                          providerKey: providerKey,
                          isLoggedIn: isLoggedIn,
                          isSelected: topic.id == selectedTopicId,
                          enableLongPress: enableLongPress,
                          highlightColor: highlight,
                        );
                        final Widget content = highlighted
                            ? TweenAnimationBuilder<Color?>(
                                tween: ColorTween(
                                  begin: tokens.colors.brandPrimary.withValues(
                                    alpha: 0.12,
                                  ),
                                  end: tokens.colors.surfacePage,
                                ),
                                duration: const Duration(milliseconds: 2000),
                                curve: const Interval(
                                  0.2,
                                  1.0,
                                  curve: Curves.easeOut,
                                ),
                                onEnd: () =>
                                    _highlightedTopicIds.remove(topic.id),
                                builder: (context, color, _) => row(color),
                              )
                            : row(null);
                        return KeyedSubtree(
                          key: ValueKey('topic-${topic.id}'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              content,
                              const AppHairline(indent: AppSpace.pageMargin),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // 滚动锚定哨兵：keyed 迁移产生的位移在这里同帧修正
                const AnchorGuardSliver(),
              ],
            ),
          ),
        );
      },
      // 200ms 内静默，之后出骨架，3 秒后加等待提示（设计说明 §1-6）
      loading: () => DelayedLoading.builder(
        builder: (context, phase) => switch (phase) {
          LoadingPhase.quiet => const SizedBox.expand(),
          LoadingPhase.skeleton => const TopicListSkeleton(),
          LoadingPhase.waiting => Column(
            children: [
              WaitingHint(label: context.l10n.common_waitingForForum),
              const Expanded(child: TopicListSkeleton()),
            ],
          ),
        },
      ),
      error: (error, stack) => ErrorView(
        error: error,
        stackTrace: stack,
        onRetry: () => ref.refresh(topicListProvider(providerKey)),
      ),
    );
  }

  Widget _newTopicIndicator(int count, int? providerKey) {
    return TopicListUpdateBanner(
      count: count,
      filter: topicUpdates.query!.filter,
      newNewView: newNewViewEnabled,
      loading: isLoadingTopicUpdates,
      onTap: () async {
        final insertedIds = await loadTopicUpdates(
          (ids) =>
              ref.read(topicListProvider(providerKey).notifier).loadBefore(ids),
        );
        if (!mounted || insertedIds.isEmpty) return;
        setState(() => _highlightedTopicIds.addAll(insertedIds));
        final idsToRemove = insertedIds.toSet();
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (!mounted) return;
          setState(() => _highlightedTopicIds.removeAll(idsToRemove));
        });
        _scrollToTop();
      },
    );
  }
}
