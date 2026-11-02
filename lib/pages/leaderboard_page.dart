import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/badge.dart';
import '../providers/core_providers.dart';
import '../providers/leaderboard_provider.dart';
import '../utils/time_utils.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/paged_list_footer.dart';
import '../widgets/desktop_refresh_indicator.dart';
import 'login_page.dart';
import 'topic_detail_page/topic_detail_page.dart';

String leaderboardLabel(BuildContext context, LeaderboardKind kind) =>
    switch (kind) {
      LeaderboardKind.great => context.l10n.leaderboard_great,
      LeaderboardKind.funny => context.l10n.leaderboard_funny,
    };

/// 精彩 / 难绷榜单：从首页的筛选菜单进入。数据是论坛官方的徽章授予记录，按获得时间
/// 倒序，元信息是「作者 · 获得于 日期 · N 回复」。
///
/// 只在用户操作时请求：打开这一页、下拉刷新、拖到底。不预取。
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, required this.kind});

  final LeaderboardKind kind;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(leaderboardLabel(context, widget.kind))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorWithLogin(
          error: error,
          stackTrace: stack,
          onRetry: () => ref.invalidate(provider),
        ),
        data: (state) {
          if (state.entries.isEmpty) {
            return Center(
              child: Text(
                context.l10n.leaderboard_empty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return DesktopRefreshIndicator(
            onRefresh: notifier.refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: state.entries.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
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
                  return ListTile(
                    title: Text(entry.title),
                    subtitle: Text(leaderboardMeta(context, entry)),
                    onTap: () => _open(entry),
                  );
                },
              ),
            ),
          );
        },
      ),
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
    context.l10n.leaderboard_repliesCount('${entry.replyCount}'),
].join(' · ');

/// 错误状态 + 登录入口（榜单接口未登录是否可用因站而异，没登录时出错给一条说明）
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
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.leaderboard_loginHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const LoginPage())),
                  child: Text(context.l10n.common_login),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
