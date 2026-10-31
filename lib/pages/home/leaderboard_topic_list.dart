import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/badge.dart';
import '../../models/topic.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/leaderboard_provider.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/paged_list_footer.dart';
import '../../widgets/desktop_refresh_indicator.dart';
import '../../widgets/topic/topic_list_skeleton.dart';
import '../../widgets/topic/topic_row.dart';
import '../login_page.dart';
import '../topic_detail_page/topic_detail_page.dart';

String leaderboardLabel(BuildContext context, LeaderboardKind kind) =>
    switch (kind) {
      LeaderboardKind.great => context.l10n.leaderboard_great,
      LeaderboardKind.funny => context.l10n.leaderboard_funny,
    };

/// 首页选中「精彩」「难绷」后的列表（0.4.0 M9.6，设计说明 §3.1 分类条 /
/// §5.7）：数据是论坛官方的徽章授予记录，按获得时间倒序，行是 v2 话题行
/// （不显示赞 / 回复数，元信息「作者 · 获得于 日期 · N 回复」）。
///
/// 只在用户操作时请求：选中这一项、下拉刷新、拖到底。不预取、不后台刷新。
class LeaderboardTopicList extends ConsumerStatefulWidget {
  const LeaderboardTopicList({super.key, required this.kind});

  final LeaderboardKind kind;

  @override
  ConsumerState<LeaderboardTopicList> createState() =>
      _LeaderboardTopicListState();
}

class _LeaderboardTopicListState extends ConsumerState<LeaderboardTopicList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // 用户拖到离底部不到 400 才请求下一页
    if (n is ScrollUpdateNotification &&
        n.metrics.extentAfter < 400 &&
        n.dragDetails != null) {
      ref.read(leaderboardProvider(widget.kind).notifier).loadMore();
    }
    return false;
  }

  void _open(BadgeTopicEntry entry) {
    final post = entry.postNumber;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: entry.topicId,
          initialTitle: entry.title,
          scrollToPostNumber: post != null && post > 1 ? post : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = leaderboardProvider(widget.kind);
    final async = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return async.when(
      // 200ms 内静默，之后出骨架，3 秒后加「正在等待论坛响应」（设计说明 §1-6）
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
      error: (error, stack) => _ErrorWithLogin(
        error: error,
        stackTrace: stack,
        onRetry: () => ref.invalidate(provider),
      ),
      data: (state) {
        if (state.entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.pageMargin),
              child: Text(
                context.l10n.leaderboard_empty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium!
                    .merge(context.tokens.text.meta)
                    .copyWith(color: context.tokens.colors.textMeta),
              ),
            ),
          );
        }
        return DesktopRefreshIndicator(
          onRefresh: notifier.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListView.builder(
              controller: _controller,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.entries.length + 1,
              itemBuilder: (context, i) {
                if (i == state.entries.length) {
                  return PagedListFooter(
                    hasMore: state.hasMore,
                    isLoadingMore: state.isLoadingMore,
                    isLoadMoreFailed: state.loadMoreFailed,
                    onRetry: notifier.loadMore,
                  );
                }
                final entry = state.entries[i];
                return ReadableColumn(
                  gutter: 0,
                  child: TopicRow(
                    topic: Topic.fromJson({
                      'id': entry.topicId,
                      'title': entry.title,
                      'slug': '',
                      'posts_count': entry.postsCount,
                    }),
                    showCounts: false,
                    metaText: leaderboardMeta(context, entry),
                    onTap: () => _open(entry),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 「作者 · 获得于 日期 · N 回复」
String leaderboardMeta(BuildContext context, BadgeTopicEntry entry) => [
  if (entry.author != null && entry.author!.isNotEmpty) entry.author!,
  context.l10n.leaderboard_grantedOn(
    TimeUtils.formatShortDate(entry.grantedAt),
  ),
  if (entry.postsCount > 0)
    context.l10n.leaderboard_repliesCount(entry.replyCount),
].join(' · ');

/// 共享错误状态 + 登录入口（榜单接口未登录是否可用还没在真机核实：
/// 没登录时出错，给一条说明和「登录」按钮）
class _ErrorWithLogin extends ConsumerWidget {
  const _ErrorWithLogin({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  final Object error;
  final StackTrace stackTrace;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(currentUserProvider).value != null;
    final tokens = context.tokens;
    return Column(
      children: [
        Expanded(
          child: ErrorView(
            error: error,
            stackTrace: stackTrace,
            onRetry: onRetry,
          ),
        ),
        if (!loggedIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.pageMargin,
              0,
              AppSpace.pageMargin,
              AppSpace.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.leaderboard_loginHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall!
                      .merge(tokens.text.meta)
                      .copyWith(color: tokens.colors.textMeta),
                ),
                const SizedBox(height: AppSpace.s),
                TextButton.icon(
                  icon: const Icon(AppIcons.login, size: AppSize.iconM),
                  label: Text(context.l10n.common_login),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const LoginPage())),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
