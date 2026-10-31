import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../providers/topic_search_provider.dart';
import '../../utils/load_more_coordinator.dart';
import '../common/paged_list_footer.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../providers/selected_topic_provider.dart';
import 'search_list_skeleton.dart';
import 'search_post_card.dart';
import '../../providers/preferences_provider.dart';

/// 话题内搜索结果视图
class TopicSearchView extends ConsumerStatefulWidget {
  /// 话题 ID
  final int topicId;

  /// 跳转到指定帖子的回调（用于话题内跳转）
  final void Function(int postNumber)? onJumpToPost;

  const TopicSearchView({super.key, required this.topicId, this.onJumpToPost});

  @override
  ConsumerState<TopicSearchView> createState() => _TopicSearchViewState();
}

class _TopicSearchViewState extends ConsumerState<TopicSearchView> {
  final ScrollController _scrollController = ScrollController();
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();

  /// 匹配导航：当前停在第几条结果（0 起）
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final provider = topicSearchProvider(widget.topicId);
    await _loadMoreCoordinator.loadMore(
      loadMore: ref.read(provider.notifier).loadMore,
      hasMore: () => ref.read(provider).hasMore,
      isActive: () => mounted,
      progressCount: () => ref.read(provider).results.length,
    );
  }

  Future<void> _retryLoadMore() async {
    _loadMoreCoordinator.resetCooldown();
    await ref
        .read(topicSearchProvider(widget.topicId).notifier)
        .retryLoadMore();
  }

  /// 上 / 下一个匹配：循环切换并跳到那条结果所在楼层
  void _step(int delta, List<dynamic> results) {
    if (results.isEmpty) return;
    final next = (_current + delta) % results.length;
    setState(() => _current = next < 0 ? next + results.length : next);
    widget.onJumpToPost?.call(results[_current].postNumber as int);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchState = ref.watch(topicSearchProvider(widget.topicId));

    // 未搜索状态
    if (searchState.query.isEmpty && searchState.results.isEmpty) {
      return AppStateView(
        icon: AppIcons.search,
        title: context.l10n.search_topicSearchHint,
      );
    }

    // 加载中（首次搜索）
    if (searchState.isLoading && searchState.results.isEmpty) {
      return const SearchListSkeleton(padding: EdgeInsets.zero);
    }

    // 错误状态
    if (searchState.error != null && searchState.results.isEmpty) {
      return AppStateView(
        icon: AppIcons.dataError,
        title: context.l10n.search_error,
        message: searchState.error,
        announce: true,
      );
    }

    // 无结果
    if (searchState.results.isEmpty) {
      return AppStateView(
        icon: AppIcons.searchOff,
        title: context.l10n.search_noResults,
        message: context.l10n.search_tryOtherKeywords,
      );
    }

    // 搜索结果
    return Column(
      children: [
        // 结果数量 + 匹配导航（上 / 下一个匹配，当前位置 n/N）
        SizedBox(
          height: AppSize.hit,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpace.pageMargin),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.onJumpToPost != null
                        ? context.l10n.search_matchSummary(
                            searchState.results.length,
                            _current.clamp(0, searchState.results.length - 1) +
                                1,
                          )
                        : context.l10n.search_resultCount(
                            searchState.results.length,
                            searchState.hasMore ? '+' : '',
                          ),
                    style: theme.textTheme.bodySmall
                        ?.merge(context.tokens.text.meta)
                        .copyWith(color: context.tokens.colors.textMeta),
                  ),
                ),
                if (widget.onJumpToPost != null) ...[
                  AppIconButton(
                    icon: AppIcons.chevronUp,
                    semanticLabel: context.l10n.search_prevMatch,
                    onPressed: () => _step(-1, searchState.results),
                  ),
                  AppIconButton(
                    icon: AppIcons.chevronDown,
                    semanticLabel: context.l10n.search_nextMatch,
                    onPressed: () => _step(1, searchState.results),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: SearchPostPrewarmScope(
            posts: searchState.results,
            child: ListView.builder(
              controller: _scrollController,
              addAutomaticKeepAlives: false,
              padding: EdgeInsets.zero,
              itemCount: searchState.results.length + 1,
              itemBuilder: (context, index) {
                if (index == searchState.results.length) {
                  return PagedListFooter(
                    hasMore: searchState.hasMore,
                    isLoadingMore:
                        searchState.isLoading && searchState.results.isNotEmpty,
                    isLoadMoreFailed: searchState.isLoadMoreFailed,
                    onRetry: _retryLoadMore,
                  );
                }

                final post = searchState.results[index];

                final enableLongPress = ref
                    .watch(preferencesProvider)
                    .longPressPreview;
                return SearchPostCard(
                  post: post,
                  onTap: () {
                    // 优先使用话题内跳转
                    if (widget.onJumpToPost != null) {
                      widget.onJumpToPost!(post.postNumber);
                    } else {
                      // 跨话题:平行视界面板内压当前栈,全屏页照旧 push
                      final topic = post.topic;
                      if (topic != null) {
                        if (EmbeddedStackScope.maybePushTopic(
                          context,
                          topicId: topic.id,
                          scrollToPostNumber: post.postNumber,
                        )) {
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TopicDetailPage(
                              topicId: topic.id,
                              scrollToPostNumber: post.postNumber,
                            ),
                          ),
                        );
                      }
                    }
                  },
                  enableLongPress: enableLongPress,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
