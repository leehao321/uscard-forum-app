import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../models/shortcut_binding.dart';
import '../providers/discourse_providers.dart';
import '../models/search_filter.dart';
import '../models/search_result.dart';
import '../services/preloaded_data_service.dart';
import '../widgets/common/smart_avatar.dart';
import '../widgets/common/error_view.dart';
import 'package:m3e_ui/m3e_ui.dart';
import '../widgets/common/paged_list_footer.dart';
import '../widgets/search/search_filter_panel.dart';
import '../widgets/search/search_list_skeleton.dart';
import '../widgets/search/search_post_card.dart';
import '../providers/preferences_provider.dart';
import '../providers/selected_topic_provider.dart';
import '../providers/shortcut_provider.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../utils/responsive.dart';
import 'topic_detail_page/topic_detail_page.dart';
import 'package:dio/dio.dart';
import '../services/app_error_handler.dart';
import '../l10n/s.dart';
import 'user_profile_page.dart';
import '../utils/dialog_utils.dart';
import '../utils/load_more_coordinator.dart';
import '../utils/blocked_user_filter.dart';
import '../utils/discourse_url_parser.dart';
import '../utils/link_launcher.dart';
import 'settings_page.dart';

/// 搜索框中的站内直达链接标准化。支持完整 URL、不带协议的
/// `uscardforum.com/...`（含 www）和相对路径；
/// 普通关键词原样返回，后续由 [isInternalUrlString] 判定后继续普通搜索。
@visibleForTesting
String normalizeDirectSearchLink(String rawValue) {
  final value = rawValue.trim();
  if (value.startsWith('/')) return value;
  if (_bareSiteLinkPattern.hasMatch(value)) {
    return 'https://$value';
  }
  return value;
}

/// 不带协议的站内链接：主域去掉 `www.` 后，可带或不带 `www.` 前缀。
final RegExp _bareSiteLinkPattern = () {
  final host = Uri.parse(AppConstants.baseUrl).host.replaceFirst(
    RegExp(r'^www\.'),
    '',
  );
  return RegExp(
    '^(?:www\\.)?${RegExp.escape(host)}(?::\\d+)?/',
    caseSensitive: false,
  );
}();

/// 搜索页面
class SearchPage extends ConsumerStatefulWidget {
  static const double parallelMasterWidth = PaneBreakpoints.wideMasterWidth;
  static const double parallelMinDetailWidth =
      PaneBreakpoints.wideMinDetailWidth;

  final String? initialQuery;
  final SearchFilter? initialFilter;

  /// 首页搜索胶囊入口：搜索框包同 tag Hero 做跨页 morph（一镜到底），
  /// 键盘等 Hero 飞行结束再弹（飞行中弹出会顶起布局撕裂动画）
  final bool heroCapsule;

  const SearchPage({
    super.key,
    this.initialQuery,
    this.initialFilter,
    this.embeddedMaster = false,
    this.stackProvider,
    this.onClose,
    this.heroCapsule = false,
    this.parentActive = true,
  });

  final bool embeddedMaster;
  final SelectedTopicProvider? stackProvider;
  final VoidCallback? onClose;

  /// 宿主 tab 是否活跃(嵌入首页左栏时传入:IndexedStack 常驻页共享
  /// 根路由,非活跃 tab 的 surface 注册会截胡活跃 tab 的按键)。
  final bool parentActive;

  @visibleForTesting
  static bool canShowParallelFor(BuildContext context) {
    return MasterDetailLayout.canShowBothPanesFor(
      context,
      masterWidth: parallelMasterWidth,
      minDetailWidth: parallelMinDetailWidth,
    );
  }

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  SelectedTopicProvider get _stackProvider =>
      widget.stackProvider ?? selectedSearchProvider;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  late final ShortcutSurfaceBinding _shortcutSurfaceBinding =
      ShortcutSurfaceBinding(
        ref: ref,
        id: ShortcutSurfaceIds.search,
        triggerAction: ShortcutAction.openSearch,
        kind: ShortcutSurfaceKind.route,
        repeatBehavior: ShortcutSurfaceRepeatBehavior.reveal,
        passthroughActions: ShortcutSurfaceActionSets.globalRoutePassthrough,
        // 嵌入首页左栏(embeddedMaster)时挂在 IndexedStack 常驻 tab 里,
        // 宿主不活跃则不参与分发,否则拦掉其他 tab 的按键。
        enabled: () => !widget.embeddedMaster || widget.parentActive,
      );
  ModalRoute<dynamic>? _route;

  String _currentQuery = '';
  int _currentPage = 1;
  bool _isLoadingMore = false;
  List<SearchPost> _standardPosts = []; // 标准搜索结果（原始）
  List<SearchPost> _allPosts = []; // 最终展示列表（融合后）
  List<SearchUser> _allUsers = [];
  bool _hasMorePosts = false;
  bool _hasMoreUsers = false;
  bool _hasError = false;

  /// 独立搜索页自己的平行视界栈（嵌入时为 null）
  SelectedTopicNotifier? _ownedStackNotifier;

  /// 首页（第 1 页）请求在途；区分「还在加载」和「真的没有结果」
  bool _initialLoading = false;
  Object? _searchError;
  StackTrace? _searchErrorStack;
  bool _isLoadMoreFailed = false;

  // 最近搜索记录
  List<String> _recentSearches = [];
  bool _isLoadingRecentSearches = true;
  bool _isClearingRecentSearches = false;

  // 高级过滤器
  late SearchFilter _filter;

  // AI 语义搜索
  bool _siteAiSearchAvailable = false;
  List<SearchPost> _aiPosts = []; // AI 搜索结果（原始）
  bool _isSearchingAi = false;

  @override
  void initState() {
    super.initState();
    if (widget.stackProvider == null) {
      _ownedStackNotifier = ref.read(selectedSearchProvider.notifier);
    }
    _filter = widget.initialFilter ?? const SearchFilter();
    PreloadedDataService().isAiSemanticSearchEnabled().then((enabled) {
      if (mounted) setState(() => _siteAiSearchAvailable = enabled);
    });
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      _currentQuery = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performInitialSearchAfterTransition();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestFocusAfterTransition();
        _loadRecentSearches();
      });
    }
    _scrollController.addListener(_onScroll);
  }

  /// 个人资料页等入口会携带初始查询打开搜索页。等待路由转场结束后再启动
  /// 普通搜索与站内 AI 搜索，避免两路结果状态更新和页面入场动画争抢帧预算。
  void _performInitialSearchAfterTransition() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _performSearch();
      return;
    }

    void listener(AnimationStatus status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      animation.removeStatusListener(listener);
      if (mounted && status == AnimationStatus.completed) {
        _performSearch();
      }
    }

    animation.addStatusListener(listener);
  }

  /// Hero 入场时等转场（含 Hero 飞行）结束再聚焦弹键盘；普通入场立即聚焦
  void _requestFocusAfterTransition() {
    final route = ModalRoute.of(context);
    if (!widget.heroCapsule ||
        route == null ||
        route.animation == null ||
        route.animation!.isCompleted) {
      _focusNode.requestFocus();
      return;
    }
    final animation = route.animation!;
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        if (mounted) _focusNode.requestFocus();
      }
    }

    animation.addStatusListener(listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _route = route;
    _shortcutSurfaceBinding.registerDeferred(
      context,
      onClose: widget.onClose ?? () => Navigator.of(context).maybePop(),
      onFocus: _revealSelf,
    );
  }

  void _revealSelf() {
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null || route.isCurrent) return;
    navigator.popUntil((candidate) => identical(candidate, route));
  }

  /// 加载最近搜索记录
  Future<void> _loadRecentSearches() async {
    try {
      final service = ref.read(discourseServiceProvider);
      final searches = await service.getRecentSearches();
      if (mounted) {
        setState(() {
          _recentSearches = searches;
          _isLoadingRecentSearches = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRecentSearches = false;
        });
      }
    }
  }

  /// 清空最近搜索记录
  Future<void> _clearRecentSearches() async {
    if (_isClearingRecentSearches) return;
    setState(() => _isClearingRecentSearches = true);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.clearRecentSearches();
      if (mounted) {
        setState(() {
          _recentSearches = [];
          _isClearingRecentSearches = false;
        });
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
      if (mounted) {
        setState(() => _isClearingRecentSearches = false);
      }
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) {
        setState(() => _isClearingRecentSearches = false);
      }
    }
  }

  @override
  void dispose() {
    _shortcutSurfaceBinding.disposeDeferred();
    // 独立搜索页拥有自己的平行视界栈，退出时应清理；嵌入首页左栏时复用
    // selectedTopicProvider，搜索页被信息流/分类替换不代表右栏详情也应消失。
    // dispose 里不能再用 ref：栈 notifier 在 initState 里先存下来
    _ownedStackNotifier?.clear();
    _searchController.dispose();
    _focusNode.dispose();
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

  void _onSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    if (_tryOpenInternalLink(trimmed)) return;
    if (trimmed != _currentQuery || _allPosts.isEmpty) {
      setState(() {
        _currentQuery = trimmed;
        _currentPage = 1;
        _standardPosts = [];
        _allPosts = [];
        _aiPosts = [];
        _allUsers = [];
        _hasMorePosts = false;
        _hasMoreUsers = false;
        _hasError = false;
        _isLoadMoreFailed = false;
      });
      _performSearch();
    }
  }

  bool _tryOpenInternalLink(String rawValue) {
    final normalized = normalizeDirectSearchLink(rawValue);
    if (!isInternalUrlString(normalized)) return false;

    final topic = DiscourseUrlParser.parseTopic(normalized);
    if (topic != null) {
      if (widget.embeddedMaster || SearchPage.canShowParallelFor(context)) {
        ref
            .read(_stackProvider.notifier)
            .select(
              topicId: topic.topicId,
              initialTitle: topic.slug,
              scrollToPostNumber: topic.postNumber,
            );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: topic.topicId,
              initialTitle: topic.slug,
              scrollToPostNumber: topic.postNumber,
            ),
          ),
        );
      }
      _focusNode.unfocus();
      return true;
    }

    final user = DiscourseUrlParser.parseUser(normalized);
    if (user == null) return false;
    if (widget.embeddedMaster || SearchPage.canShowParallelFor(context)) {
      ref.read(_stackProvider.notifier).selectProfile(user.username);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfilePage(username: user.username),
        ),
      );
    }
    _focusNode.unfocus();
    return true;
  }

  void _onSortChanged(SearchSortOrder? order) {
    final currentOrder = ref.read(searchSettingsProvider).sortOrder;
    if (order != null && order != currentOrder) {
      ref.read(searchSettingsProvider.notifier).setSortOrder(order);
      setState(() {
        _currentPage = 1;
        _standardPosts = [];
        _allPosts = [];
        _allUsers = [];
        // 切换排序时清空 AI 结果
        _aiPosts = [];
        _isSearchingAi = false;
      });
      _performSearch();
    }
  }

  void _onFilterChanged(SearchFilter newFilter) {
    setState(() {
      _filter = newFilter;
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _openFilterPanel([SearchFilterSection? section]) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SearchFilterPanel(
          filter: _filter,
          onFilterChanged: _onFilterChanged,
          hideInType: true,
          initialSection: section,
        ),
      ),
    );
  }

  /// 从查询字符串中移除 order:xxx 部分，返回纯净的查询
  String _stripOrderFromQuery(String query) {
    return query
        .replaceAll(
          RegExp(r'\s*order:(relevance|latest|likes|views|latest_topic)\s*'),
          ' ',
        )
        .trim();
  }

  /// 从查询字符串中提取排序方式
  SearchSortOrder? _extractOrderFromQuery(String query) {
    final match = RegExp(
      r'order:(relevance|latest|likes|views|latest_topic)',
    ).firstMatch(query);
    if (match == null) return null;
    final orderValue = match.group(1);
    return SearchSortOrder.values.firstWhere(
      (e) => e.value == orderValue,
      orElse: () => SearchSortOrder.relevance,
    );
  }

  /// RRF（Reciprocal Rank Fusion）算法，与 Discourse 前端一致
  /// 将标准搜索结果和 AI 搜索结果按倒数排名融合
  List<SearchPost> _mergeWithRRF(
    List<SearchPost> standard,
    List<SearchPost> ai,
  ) {
    if (ai.isEmpty) return standard;
    if (standard.isEmpty) return ai;

    const k = 5; // RRF 常数，与 Discourse 一致

    // 为每个结果计算 RRF 分数，key 为 topic_id
    final scoreMap = <int, double>{};
    final postMap = <int, SearchPost>{};

    for (var i = 0; i < standard.length; i++) {
      final topicId = standard[i].topic?.id;
      if (topicId == null) continue;
      scoreMap[topicId] = 1.0 / (i + k);
      postMap[topicId] = standard[i];
    }

    for (var i = 0; i < ai.length; i++) {
      final topicId = ai[i].topic?.id;
      if (topicId == null) continue;
      if (scoreMap.containsKey(topicId)) {
        // 两个列表都有的结果，分数累加（排名更靠前）
        scoreMap[topicId] = scoreMap[topicId]! + 1.0 / (i + k);
      } else {
        scoreMap[topicId] = 1.0 / (i + k);
        postMap[topicId] = ai[i];
      }
    }

    // 按 RRF 分数降序排列
    final sortedIds = scoreMap.keys.toList()
      ..sort((a, b) => scoreMap[b]!.compareTo(scoreMap[a]!));

    return sortedIds.map((id) => postMap[id]!).toList();
  }

  /// 根据当前 AI 开关状态重新构建展示列表
  void _rebuildDisplayPosts() {
    final settings = ref.read(searchSettingsProvider);
    final showAi =
        _siteAiSearchAvailable &&
        settings.aiSearchEnabled &&
        settings.sortOrder == SearchSortOrder.relevance &&
        _aiPosts.isNotEmpty;

    if (showAi) {
      _allPosts = _mergeWithRRF(_standardPosts, _aiPosts);
    } else {
      _allPosts = List.of(_standardPosts);
    }
  }

  bool _shouldTriggerAiSearch() {
    final sortOrder = ref.read(searchSettingsProvider).sortOrder;
    final aiEnabled = ref.read(searchSettingsProvider).aiSearchEnabled;
    return _siteAiSearchAvailable &&
        aiEnabled &&
        sortOrder == SearchSortOrder.relevance;
  }

  void _triggerAiSearch(String query) async {
    setState(() => _isSearchingAi = true);
    try {
      final service = ref.read(discourseServiceProvider);
      final aiResult = await service.semanticSearch(query: query);
      if (!mounted) return;

      // 标记为 AI 生成
      _aiPosts = aiResult.posts
          .map((p) => p.copyWith(isAiGenerated: true))
          .toList();

      setState(() {
        _isSearchingAi = false;
        _rebuildDisplayPosts();
      });
    } catch (e) {
      // 静默失败，404/403/429 都不影响标准搜索
      if (mounted) setState(() => _isSearchingAi = false);
    }
  }

  Future<void> _performSearch() async {
    if (_currentQuery.isEmpty) return;

    final isLoadMore = _currentPage > 1;
    if (!isLoadMore) {
      _loadMoreCoordinator.resetCooldown();
    }

    setState(() {
      _hasError = false;
      _isLoadMoreFailed = false;
      if (!isLoadMore) {
        _isLoadingMore = false;
        _initialLoading = true;
      }
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final sortOrder = ref.read(searchSettingsProvider).sortOrder;

      // 构建查询字符串
      final cleanQuery = _stripOrderFromQuery(_currentQuery);
      String searchQuery = cleanQuery;

      // 添加过滤条件
      final filterQuery = _filter.toQueryString();
      if (filterQuery.isNotEmpty) {
        searchQuery = '$searchQuery $filterQuery';
      }

      // 添加排序
      if (sortOrder.value != null) {
        searchQuery = '$searchQuery order:${sortOrder.value}';
      }

      // 首页搜索时并行触发 AI 语义搜索
      if (_currentPage == 1 && _shouldTriggerAiSearch()) {
        _triggerAiSearch(cleanQuery);
      }

      final result = await service.search(
        query: searchQuery,
        page: _currentPage,
        typeFilter: 'topic',
      );

      setState(() {
        if (_currentPage == 1) {
          _standardPosts = result.posts;
          _allUsers = result.users;
        } else {
          _standardPosts.addAll(result.posts);
        }
        _hasMorePosts = result.hasMorePosts && result.posts.isNotEmpty;
        _hasMoreUsers = result.hasMoreUsers;
        _isLoadingMore = false;
        _initialLoading = false;
        _rebuildDisplayPosts();
      });
    } catch (e, s) {
      setState(() {
        _isLoadingMore = false;
        _initialLoading = false;
        if (isLoadMore) {
          // 加载更多失败：回退页码，显示重试
          _currentPage--;
          _isLoadMoreFailed = true;
        } else {
          // 首次搜索失败：显示全局错误
          _hasError = true;
          _searchError = e;
          _searchErrorStack = s;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadMoreFailed) return;
    await _loadMoreCoordinator.loadMore(
      loadMore: _loadMorePage,
      hasMore: () => _hasMorePosts,
      isActive: () => mounted,
      progressCount: () => _allPosts.length,
    );
  }

  Future<void> _loadMorePage() async {
    if (_isLoadingMore || !_hasMorePosts || _isLoadMoreFailed) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _performSearch();
  }

  void _clearSearch() {
    _searchController.clear();
    _loadMoreCoordinator.resetCooldown();
    setState(() {
      _currentQuery = '';
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
      _isSearchingAi = false;
      _hasMorePosts = false;
      _hasMoreUsers = false;
      _currentPage = 1;
    });
    _focusNode.requestFocus();
  }

  void _clearCategory() {
    setState(() {
      _filter = _filter.copyWith(clearCategory: true);
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _filter = _filter.copyWith(
        tags: _filter.tags.where((t) => t != tag).toList(),
      );
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _clearStatus() {
    setState(() {
      _filter = _filter.copyWith(clearStatus: true);
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _clearDateRange() {
    setState(() {
      _filter = _filter.copyWith(clearDateRange: true);
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _clearAllFilters() {
    setState(() {
      _filter = _filter.clear();
      _currentPage = 1;
      _standardPosts = [];
      _allPosts = [];
      _aiPosts = [];
      _allUsers = [];
    });
    if (_currentQuery.isNotEmpty) {
      _performSearch();
    }
  }

  void _openTopicResult(SearchPost searchPost) {
    final topic = searchPost.topic;
    if (topic == null) return;
    if (widget.embeddedMaster || SearchPage.canShowParallelFor(context)) {
      ref
          .read(_stackProvider.notifier)
          .select(
            topicId: topic.id,
            initialTitle: topic.title,
            scrollToPostNumber: searchPost.postNumber,
          );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          scrollToPostNumber: searchPost.postNumber,
        ),
      ),
    );
  }

  void _openUserResult(SearchUser user) {
    if (widget.embeddedMaster || SearchPage.canShowParallelFor(context)) {
      ref.read(_stackProvider.notifier).selectProfile(user.username);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: user.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = ref.watch(_stackProvider);
    final canShowParallel =
        widget.embeddedMaster || SearchPage.canShowParallelFor(context);

    final master = _buildSearchScaffold(theme);
    if (widget.embeddedMaster) return master;
    if (!canShowParallel) return master;

    return MasterDetailLayout(
      masterWidth: SearchPage.parallelMasterWidth,
      minDetailWidth: SearchPage.parallelMinDetailWidth,
      // 列表态与其他双栏页同语义:初始=masterWidth(440,结果卡片比首页
      // 话题卡宽一点),比例只在超大窗口放宽。旧参数(min 0.32/preferred
      // 0.4)让搜索初始就占四成屏宽,明显宽于其他页。
      maxMasterRatio: selected.isStacked ? 0.8 : 0.52,
      preferredMasterRatio: selected.isStacked ? 0.5 : null,
      // 胶片带:搜索列表也在带上,压栈被顶出左侧,倒二层格作预览。
      pinMaster: false,
      master: master,
      panes: [
        for (var i = 0; i < selected.stack.length; i++)
          KeyedSubtree(
            key: _cellKey(selected.stack[i]),
            child: _buildParallelPane(
              selected.stack[i],
              truncateOnPush: i < selected.stack.length - 1,
              // 回调内重读 provider:嵌入面板在注册 ESC 时会捕获这个闭包
              // 且不随宿主 rebuild 刷新,捕获 build 快照的 selected 会让
              // 后续按键用过期的 isStacked 判断 pop/clear。
              onBack: () {
                final notifier = ref.read(_stackProvider.notifier);
                if (ref.read(_stackProvider).isStacked) {
                  notifier.pop();
                } else {
                  notifier.clear();
                }
              },
            ),
          ),
      ],
      emptyDetail: MasterDetailEmptyState(
        icon: Symbols.preview_rounded,
        iconSize: 56,
        message: context.l10n.search_selectResultHint,
      ),
    );
  }

  Key _cellKey(PaneEntry entry) => ValueKey(
    'search_cell_${entry.kind}_'
    '${entry.instanceId ?? entry.username ?? entry.topicId}',
  );

  Widget _buildSearchScaffold(ThemeData theme) {
    final tokens = context.tokens;
    final hasText = _searchController.text.isNotEmpty;

    // 搜索框保持 Safari 式：贴在键盘上方；有内容时右侧 58 圆形关闭钮 = 清除
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.s,
        AppSpace.pageMargin,
        AppSpace.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: SearchCapsule(
              placeholder: context.l10n.search_hintText,
              controller: _searchController,
              focusNode: _focusNode,
              onSubmitted: _onSearch,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (hasText) ...[
            const SizedBox(width: AppSpace.s),
            SearchCloseButton(onPressed: _clearSearch),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppNavBar(
        title: context.l10n.common_search,
        // 嵌入首页左栏时用关闭钮，否则是系统返回
        leading: widget.onClose == null
            ? null
            : AppIconButton(
                icon: AppIcons.close,
                semanticLabel: context.l10n.common_close,
                onPressed: widget.onClose,
              ),
        automaticallyImplyLeading: widget.onClose == null,
        trailing: [
          // 高级筛选：有筛选时右上角出现未读点
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppIconButton(
                icon: AppIcons.tune,
                semanticLabel: context.l10n.search_advancedSearch,
                onPressed: _openFilterPanel,
              ),
              if (_filter.isNotEmpty)
                const Positioned(right: 8, top: 8, child: UnreadDot()),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 已激活的过滤条件（始终显示，便于查看和取消）
          if (_filter.isNotEmpty)
            ActiveSearchFiltersBar(
              filter: _filter,
              onClearCategory: _clearCategory,
              onRemoveTag: _removeTag,
              onClearStatus: _clearStatus,
              onClearDateRange: _clearDateRange,
              onClearAll: _clearAllFilters,
            ),
          Expanded(
            child: _currentQuery.isEmpty
                ? _buildEmptyState(theme)
                : _buildSearchResults(theme),
          ),
          ColoredBox(color: tokens.colors.surfacePage, child: SafeArea(top: false, child: searchBar)),
        ],
      ),
    );
  }

  Widget _buildParallelPane(
    PaneEntry entry, {
    VoidCallback? onBack,
    bool truncateOnPush = false,
  }) {
    switch (entry.kind) {
      case PaneKind.topic:
        return TopicDetailPage(
          key: ValueKey('search_topic_${entry.instanceId}'),
          topicId: entry.topicId!,
          instanceId: entry.instanceId,
          initialTitle: entry.initialTitle,
          scrollToPostNumber: entry.scrollToPostNumber,
          embeddedMode: true,
          truncateOnPush: truncateOnPush,
          onEmbeddedBack: onBack,
          parentActive: true,
          stackProvider: _stackProvider,
        );
      case PaneKind.profile:
        return EmbeddedStackScope(
          stackProvider: _stackProvider,
          truncateOnPush: truncateOnPush,
          child: UserProfilePage(
            key: ValueKey('search_profile_${entry.username}'),
            username: entry.username!,
            embeddedMode: true,
            onEmbeddedBack: onBack,
            parentActive: widget.parentActive,
          ),
        );
      case PaneKind.settings:
        return EmbeddedStackScope(
          stackProvider: _stackProvider,
          truncateOnPush: truncateOnPush,
          child: SettingsPage(
            embeddedMode: true,
            onEmbeddedBack: onBack,
            parentActive: widget.parentActive,
          ),
        );
    }
  }

  /// 搜索语法快捷胶囊：点按把语法插到输入框（不搜索）
  static const List<String> _syntaxChips = [
    '@',
    '#',
    'tags:',
    'status:solved',
    'in:bookmarks',
    'after:',
  ];

  void _insertSyntax(String token) {
    final text = _searchController.text;
    final next = text.isEmpty || text.endsWith(' ') ? '$text$token' : '$text $token';
    _searchController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  Widget _buildEmptyState(ThemeData theme) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final metaStyle = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    // 正在加载最近搜索记录
    if (_isLoadingRecentSearches) {
      return const Center(child: LoadingSpinner());
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.m,
            AppSpace.pageMargin,
            AppSpace.s,
          ),
          child: Text(context.l10n.search_syntaxTitle, style: metaStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
          child: Wrap(
            spacing: AppSpace.s,
            runSpacing: AppSpace.s,
            children: [
              for (final token in _syntaxChips)
                FilterPill(
                  label: token,
                  showChevron: false,
                  onTap: () => _insertSyntax(token),
                ),
            ],
          ),
        ),
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.pageMargin,
              AppSpace.xl,
              AppSpace.pageMargin,
              AppSpace.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.search_recentSearches, style: metaStyle),
                // 「清除」文字按钮，无确认
                AppPressable(
                  onTap: _isClearingRecentSearches ? null : _clearRecentSearches,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSize.hit,
                      minWidth: AppSize.hit,
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: _isClearingRecentSearches
                          ? const LoadingSpinner(size: 14)
                          : Text(
                              context.l10n.common_clear,
                              style: metaStyle?.copyWith(
                                color: colors.brandPrimary,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _recentSearches.length; i++) ...[
            if (i > 0) const AppHairline(indent: 52),
            _buildRecentSearchItem(_recentSearches[i], theme),
          ],
        ] else
          Padding(
            padding: const EdgeInsets.all(AppSpace.xxl),
            child: Center(
              child: Text(context.l10n.search_emptyHint, style: metaStyle),
            ),
          ),
      ],
    );
  }

  /// 最近搜索行：高 48，history 20 meta + 查询词 17 + arrow-up-left 16（填入不搜索）
  Widget _buildRecentSearchItem(String query, ThemeData theme) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    // 提取纯净查询
    final cleanQuery = _stripOrderFromQuery(query);

    return AppPressable(
      highlight: true,
      onTap: () {
        // 如果历史记录中有排序设置，恢复它
        final extractedOrder = _extractOrderFromQuery(query);
        if (extractedOrder != null) {
          ref
              .read(searchSettingsProvider.notifier)
              .setSortOrder(extractedOrder);
        }
        _searchController.text = cleanQuery;
        _onSearch(cleanQuery);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpace.pageMargin),
          child: Row(
            children: [
              Icon(AppIcons.history, size: AppSize.iconM, color: colors.textMeta),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Text(
                  query,
                  style: theme.textTheme.bodyMedium
                      ?.merge(tokens.text.control)
                      .copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppIconButton(
                icon: AppIcons.northWest,
                semanticLabel: query,
                size: AppSize.iconS,
                onPressed: () {
                  _searchController.value = TextEditingValue(
                    text: cleanQuery,
                    selection: TextSelection.collapsed(
                      offset: cleanQuery.length,
                    ),
                  );
                  _focusNode.requestFocus();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    final blockedUsernames = ref.watch(
      preferencesProvider.select((p) => p.normalizedBlockedUsernames),
    );
    final posts = _allPosts
        .where(
          (post) => !BlockedUserFilter.isBlockedUsername(
            post.username,
            blockedUsernames,
          ),
        )
        .toList(growable: false);
    final users = _allUsers
        .where(
          (user) => !BlockedUserFilter.isBlockedUsername(
            user.username,
            blockedUsernames,
          ),
        )
        .toList(growable: false);

    if (_hasError && posts.isEmpty) {
      return ErrorView(
        error: _searchError ?? Exception(context.l10n.search_error),
        stackTrace: _searchErrorStack,
        onRetry: _performSearch,
      );
    }

    if (posts.isEmpty && users.isEmpty && !_isLoadingMore) {
      // 只有原始结果也为空才可能是首页请求仍在途；
      // 原始结果非空但过滤后为空 = 全部被本地屏蔽，必须显示空态而非转圈
      if (_initialLoading) {
        return const SearchListSkeleton();
      }
      return _buildNoResults();
    }

    return Column(
      children: [
        // 筛选胶囊行（44 高可横滑）：排序 · 时间 · 分类 · 状态 · 标签；已生效的变 brand
        if (posts.isNotEmpty || users.isNotEmpty) ...[
          _buildPillRow(),
          _buildResultHeader(theme, posts.length),
        ],
        Expanded(
          child: SearchPostPrewarmScope(
            posts: posts,
            child: ListView.builder(
              controller: _scrollController,
              addAutomaticKeepAlives: false,
              padding: EdgeInsets.zero,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount:
                  posts.length + (users.isNotEmpty ? users.length + 1 : 0) + 1,
              itemBuilder: (context, index) {
                // 帖子结果（标准 + AI 混合）
                if (index < posts.length) {
                  final searchPost = posts[index];
                  final enableLongPress = ref
                      .watch(preferencesProvider)
                      .longPressPreview;

                  return SearchPostCard(
                    post: searchPost,
                    onTap: () => _openTopicResult(searchPost),
                    enableLongPress: enableLongPress,
                  );
                }

                // 用户标题
                final userStartIndex = posts.length;
                if (users.isNotEmpty && index == userStartIndex) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.pageMargin,
                      AppSpace.l,
                      AppSpace.pageMargin,
                      AppSpace.xs,
                    ),
                    child: _buildSectionHeader(
                      context.l10n.search_users,
                      users.length,
                      _hasMoreUsers,
                    ),
                  );
                }

                // 用户结果
                if (users.isNotEmpty && index > userStartIndex) {
                  final userIndex = index - userStartIndex - 1;
                  if (userIndex < users.length) {
                    return _SearchUserCard(
                      user: users[userIndex],
                      onTap: () => _openUserResult(users[userIndex]),
                    );
                  }
                }

                return PagedListFooter(
                  hasMore: _hasMorePosts,
                  isLoadingMore:
                      _loadMoreCoordinator.isRunning && _isLoadingMore,
                  isLoadMoreFailed: _isLoadMoreFailed,
                  onRetry: () {
                    _loadMoreCoordinator.resetCooldown();
                    setState(() => _isLoadMoreFailed = false);
                    _loadMore();
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoResults() {
    return AppStateView(
      icon: AppIcons.searchOff,
      title: context.l10n.search_noResults,
      message: context.l10n.search_tryOtherKeywords,
    );
  }

  /// 用户分区页眉「用户 · N」13 meta
  Widget _buildSectionHeader(String title, int count, bool hasMore) {
    final tokens = context.tokens;
    return Text(
      '$title · ${hasMore ? '$count+' : '$count'}',
      style: Theme.of(context).textTheme.bodySmall
          ?.merge(tokens.text.meta)
          .copyWith(color: tokens.colors.textMeta),
    );
  }

  Widget _buildPillRow() {
    final settings = ref.watch(searchSettingsProvider);
    final order = settings.sortOrder;
    return SizedBox(
      height: AppSize.hit,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
        children: [
          Builder(
            builder: (ctx) => FilterPill(
              label: order.label,
              selected: order != SearchSortOrder.relevance,
              onTap: () async {
                final picked = await showAppMenu<SearchSortOrder>(
                  context: ctx,
                  anchor: globalRectOf(ctx),
                  sections: [
                    [
                      for (final o in SearchSortOrder.values)
                        AppMenuItem(
                          label: o.label,
                          value: o,
                          checked: o == order,
                        ),
                    ],
                  ],
                );
                if (picked != null) _onSortChanged(picked);
              },
            ),
          ),
          const SizedBox(width: AppSpace.s),
          FilterPill(
            label: context.l10n.search_pillTime,
            selected: _filter.beforeDate != null || _filter.afterDate != null,
            onTap: () => _openFilterPanel(SearchFilterSection.date),
          ),
          const SizedBox(width: AppSpace.s),
          FilterPill(
            label: _filter.categoryName ?? context.l10n.search_pillCategory,
            selected: _filter.categoryId != null,
            onTap: () => _openFilterPanel(SearchFilterSection.category),
          ),
          const SizedBox(width: AppSpace.s),
          FilterPill(
            label: context.l10n.search_pillStatus,
            selected: _filter.status != null,
            onTap: () => _openFilterPanel(SearchFilterSection.status),
          ),
          const SizedBox(width: AppSpace.s),
          FilterPill(
            label: context.l10n.search_pillTags,
            selected: _filter.tags.isNotEmpty,
            onTap: () => _openFilterPanel(SearchFilterSection.tags),
          ),
        ],
      ),
    );
  }

  /// 结果头行 44：「20+ 条结果」13 meta；右侧「AI 语义搜索」+ 开关
  /// （仅站点开启 AI 时出现，排序不是相关度时开关不可用）
  Widget _buildResultHeader(ThemeData theme, int postCount) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final settings = ref.watch(searchSettingsProvider);
    final isRelevance = settings.sortOrder == SearchSortOrder.relevance;
    final metaStyle = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    return SizedBox(
      height: AppSize.hit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.search_resultCount(
                  postCount,
                  _hasMorePosts ? '+' : '',
                ),
                style: metaStyle,
              ),
            ),
            if (_siteAiSearchAvailable) ...[
              if (_isSearchingAi)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpace.s),
                  child: LoadingSpinner(size: 14),
                ),
              Text(context.l10n.search_aiSemanticSearch, style: metaStyle),
              const SizedBox(width: AppSpace.s),
              Switch.adaptive(
                value: settings.aiSearchEnabled && isRelevance,
                onChanged: isRelevance
                    ? (value) {
                        ref
                            .read(searchSettingsProvider.notifier)
                            .setAiSearchEnabled(value);
                        setState(() {
                          _rebuildDisplayPosts();
                          // 开启时若还没有 AI 结果，触发搜索
                          if (value &&
                              _aiPosts.isEmpty &&
                              _currentQuery.isNotEmpty) {
                            _triggerAiSearch(
                              _stripOrderFromQuery(_currentQuery),
                            );
                          }
                        });
                      }
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 搜索结果用户行：头像行单行（名字 17 + @handle 11 + chevron）
class _SearchUserCard extends StatelessWidget {
  final SearchUser user;
  final VoidCallback? onTap;

  const _SearchUserCard({required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final display = (user.name != null && user.name!.isNotEmpty)
        ? user.name!
        : user.username;
    return Column(
      children: [
        AvatarRow(
          avatar: SmartAvatar(
            imageUrl: user.getAvatarUrl().isNotEmpty
                ? user.getAvatarUrl(size: 80)
                : null,
            radius: AppSize.avatarS / 2,
            fallbackText: user.username,
            backgroundColor: tokens.colors.avatarFill,
          ),
          title: Text(display),
          titleMaxLines: 1,
          meta: Text(
            '@${user.username}',
            style: base.merge(tokens.text.caption),
          ),
          trailing: Icon(
            AppIcons.chevronRight,
            size: AppSize.iconS,
            color: tokens.colors.textMeta,
          ),
          onTap: onTap,
        ),
        const AppHairline(indent: AvatarRow.separatorIndent),
      ],
    );
  }
}
