import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/site_customization.dart';
import '../constants.dart';
import '../models/badge.dart';
import 'core_providers.dart';

/// 榜单种类：数据是论坛官方的徽章授予记录。
enum LeaderboardKind { great, funny }

extension LeaderboardKindX on LeaderboardKind {
  /// 站点配置里这个榜单用的徽章；站点没有对应徽章时为 null（入口隐藏）
  int? get badgeId => switch (this) {
    LeaderboardKind.great => AppConstants.siteCustomization.greatTopicBadgeId,
    LeaderboardKind.funny => AppConstants.siteCustomization.funnyTopicBadgeId,
  };
}

/// [site] 可用的榜单（没配徽章的不在里面）
List<LeaderboardKind> leaderboardsFor(SiteCustomization site) => [
  if (site.greatTopicBadgeId != null) LeaderboardKind.great,
  if (site.funnyTopicBadgeId != null) LeaderboardKind.funny,
];

/// 当前站点可用的榜单
List<LeaderboardKind> availableLeaderboards() =>
    leaderboardsFor(AppConstants.siteCustomization);

class LeaderboardState {
  const LeaderboardState({
    this.entries = const [],
    this.offset = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<BadgeTopicEntry> entries;

  /// 下一页的 offset（按服务端返回的授予记录条数推进）
  final int offset;
  final bool hasMore;
  final bool isLoadingMore;
  final bool loadMoreFailed;

  LeaderboardState copyWith({
    List<BadgeTopicEntry>? entries,
    int? offset,
    bool? hasMore,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => LeaderboardState(
    entries: entries ?? this.entries,
    offset: offset ?? this.offset,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// 榜单列表：第一页在页面被打开时才请求；下一页由滑到底触发；刷新由下拉触发。
/// 不预取、不后台刷新。
class LeaderboardNotifier extends AsyncNotifier<LeaderboardState> {
  LeaderboardNotifier(this.kind);

  final LeaderboardKind kind;

  /// 按 topic_id 去重（同一话题的多个帖子都可能拿到徽章，保留最先出现的）
  static List<BadgeTopicEntry> mergeUnique(
    List<BadgeTopicEntry> current,
    List<BadgeTopicEntry> incoming,
  ) {
    final seen = {for (final e in current) e.topicId};
    return [
      ...current,
      for (final e in incoming)
        if (seen.add(e.topicId)) e,
    ];
  }

  @override
  Future<LeaderboardState> build() async {
    final badgeId = kind.badgeId;
    if (badgeId == null) return const LeaderboardState(hasMore: false);
    final page = await ref
        .read(discourseServiceProvider)
        .getBadgeTopicsPage(badgeId: badgeId);
    return LeaderboardState(
      entries: mergeUnique(const [], page.entries),
      offset: page.fetchedCount,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    final badgeId = kind.badgeId;
    if (current == null ||
        badgeId == null ||
        !current.hasMore ||
        current.isLoadingMore) {
      return;
    }
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .getBadgeTopicsPage(badgeId: badgeId, offset: current.offset);
      state = AsyncData(
        current.copyWith(
          entries: mergeUnique(current.entries, page.entries),
          offset: current.offset + page.fetchedCount,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// 下拉刷新：从第一页重来
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
  }
}

final leaderboardProvider = AsyncNotifierProvider.autoDispose
    .family<LeaderboardNotifier, LeaderboardState, LeaderboardKind>(
      LeaderboardNotifier.new,
    );
