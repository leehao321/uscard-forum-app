import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pending_post.dart';
import '../models/topic.dart';
import '../providers/discourse_providers.dart';
import '../widgets/desktop_refresh_indicator.dart';
import '../widgets/common/skeleton.dart';
import '../widgets/common/error_view.dart';
import '../widgets/post/reply_sheet.dart';
import '../services/toast_service.dart';
import '../widgets/common/relative_time_text.dart';
import '../l10n/s.dart';
import '../providers/selected_topic_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/layout/master_detail_pane_host.dart';
import 'topic_detail_page/topic_detail_page.dart';
import 'create_topic_page.dart';

/// 待审核内容列表 Provider
final pendingPostsProvider = FutureProvider.autoDispose<List<PendingPost>>((
  ref,
) async {
  final service = ref.watch(discourseServiceProvider);
  return service.getMyPendingPosts();
});

/// 我的待审核内容列表页(对齐官方 /u/{me}/activity/pending)
class PendingPostsPage extends ConsumerStatefulWidget {
  const PendingPostsPage({super.key});

  @override
  ConsumerState<PendingPostsPage> createState() => _PendingPostsPageState();
}

class _PendingPostsPageState extends ConsumerState<PendingPostsPage> {
  Future<void> _onRefresh() async {
    ref.invalidate(pendingPostsProvider);
    await ref.read(pendingPostsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingPostsProvider);

    final list = Scaffold(
      appBar: AppNavBar(
        title: context.l10n.review_myPending,
        showDivider: true,
      ),
      body: ReadableBody(
        child: DesktopRefreshIndicator(
          onRefresh: _onRefresh,
          child: pendingAsync.when(
            data: (pendingPosts) {
              if (pendingPosts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        AppIcons.clock,
                        size: 64,
                        color: context.tokens.colors.textMeta,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.review_empty,
                        style: TextStyle(color: context.tokens.colors.textMeta),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: pendingPosts.length,
                itemBuilder: (context, index) {
                  final pending = pendingPosts[index];
                  return _PendingPostCard(
                    pending: pending,
                    onTap: pending.topicId != null
                        ? () => _openTopic(pending)
                        : null,
                    onWithdraw: () => _onWithdraw(pending),
                    onWithdrawAndEdit: () => _onWithdrawAndEdit(pending),
                  );
                },
              );
            },
            loading: () => const _PendingListSkeleton(),
            error: (error, stack) => ErrorView(
              error: error,
              stackTrace: stack,
              onRetry: () => ref.invalidate(pendingPostsProvider),
            ),
          ),
        ),
      ),
    );

    return MasterDetailPaneHost(
      stackProvider: selectedPendingPaneProvider,
      master: list,
      emptyDetail: MasterDetailEmptyState(
        icon: AppIcons.clock,
        message: context.l10n.layout_selectTopicHint,
      ),
    );
  }

  void _openTopic(PendingPost pending) {
    // 宽屏进右栏,窄屏全屏 push(平行视界宿主标准分流)。
    if (MasterDetailLayout.canShowBothPanesFor(context)) {
      ref
          .read(selectedPendingPaneProvider.notifier)
          .select(topicId: pending.topicId!, initialTitle: pending.title);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: pending.topicId!,
          initialTitle: pending.title,
        ),
      ),
    );
  }

  /// 撤回确认弹窗 + 删除请求;成功返回 true
  Future<bool> _confirmWithdraw(
    PendingPost pending, {
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (dialogContext, setState) => AppAlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.l10n.common_cancel),
              ),
              FilledButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setState(() => isDeleting = true);
                        try {
                          await ref
                              .read(discourseServiceProvider)
                              .deleteReviewable(pending.id);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setState(() => isDeleting = false);
                            ToastService.showError(
                              S.current.review_withdrawFailed(e.toString()),
                            );
                          }
                        }
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(confirmLabel),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      ref.invalidate(pendingPostsProvider);
      return true;
    }
    return false;
  }

  Future<void> _onWithdraw(PendingPost pending) async {
    final withdrawn = await _confirmWithdraw(
      pending,
      title: S.current.review_withdrawConfirmTitle,
      content: S.current.review_withdrawConfirmContent,
      confirmLabel: S.current.review_withdraw,
    );
    if (withdrawn && mounted) {
      PendingReplyTargetRegistry.remove(pending.id);
      ToastService.showSuccess(S.current.review_withdrawn);
    }
  }

  Future<void> _onWithdrawAndEdit(PendingPost pending) async {
    // 回复目标只在送审当下的会话里可知(服务端本人可见接口不吐,
    // 见 PendingReplyTargetRegistry);冷场景提示会退化为直接回复话题
    final isReply = !pending.isNewTopic;
    final targetKnown =
        !isReply || PendingReplyTargetRegistry.contains(pending.id);
    final replyToPostNumber = PendingReplyTargetRegistry.lookup(pending.id);
    final confirmContent = targetKnown
        ? S.current.review_withdrawAndEditConfirmContent
        : '${S.current.review_withdrawAndEditConfirmContent}\n\n'
              '${S.current.review_replyTargetUnknownHint}';

    final withdrawn = await _confirmWithdraw(
      pending,
      title: S.current.review_withdrawAndEdit,
      content: confirmContent,
      confirmLabel: S.current.review_withdrawAndEdit,
    );
    if (!withdrawn || !mounted) return;
    PendingReplyTargetRegistry.remove(pending.id);

    if (pending.isNewTopic) {
      // 待审的新主题:原文带回创建话题页
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateTopicPage(
            initialCategoryId: pending.categoryId,
            initialTitle: pending.title,
            initialContent: pending.raw,
          ),
        ),
      );
    } else {
      // 待审的回复:原文带回回复编辑器,尽量恢复送审时的回复目标
      Post? replyToPost;
      if (replyToPostNumber != null) {
        try {
          replyToPost = await ref
              .read(discourseServiceProvider)
              .getPostByNumber(pending.topicId!, replyToPostNumber);
        } catch (_) {
          // 目标楼层拉不到(已删除等):退化为直接回复话题
        }
      }
      if (!mounted) return;
      await showReplySheet(
        context: context,
        topicId: pending.topicId,
        categoryId: pending.categoryId,
        replyToPost: replyToPost,
        topicTitle: pending.title,
        initialContent: pending.raw,
      );
    }
    if (mounted) ref.invalidate(pendingPostsProvider);
  }
}

/// 待审内容卡片(布局对齐草稿卡片)
class _PendingPostCard extends StatelessWidget {
  final PendingPost pending;
  final VoidCallback? onTap;
  final VoidCallback onWithdraw;
  final VoidCallback onWithdrawAndEdit;

  const _PendingPostCard({
    required this.pending,
    this.onTap,
    required this.onWithdraw,
    required this.onWithdrawAndEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final typeLabel = pending.isNewTopic
        ? context.l10n.review_typeNewTopic
        : context.l10n.review_typeReply;
    final typeIcon = pending.isNewTopic ? AppIcons.addCircle : AppIcons.reply;

    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = theme.textTheme.bodyMedium!;
    final metaStyle = base
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    Widget action(String label, VoidCallback onTap, {bool brand = false}) =>
        AppPressable(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.hit),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpace.l),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: base
                      .merge(tokens.text.meta)
                      .copyWith(
                        color: brand ? colors.brandPrimary : colors.textMeta,
                      ),
                ),
              ),
            ),
          ),
        );

    // v2：平行，不再是卡片（与草稿行同构）；底部「撤回」「撤回并重新编辑」是
    // 44 高的文字操作
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfacePage,
        border: Border(
          bottom: BorderSide(color: colors.separator, width: AppSpace.hairline),
        ),
      ),
      child: AppPressable(
        highlight: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.m,
            AppSpace.pageMargin,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 类型头：图标 + 类型（brand）、等待审核、时间
              Row(
                children: [
                  Icon(typeIcon, size: 14, color: colors.brandPrimary),
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    typeLabel,
                    style: base
                        .merge(tokens.text.metaStrong)
                        .copyWith(color: colors.brandPrimary),
                  ),
                  const SizedBox(width: AppSpace.m),
                  Icon(AppIcons.loading, size: 14, color: colors.textMeta),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      context.l10n.review_awaitingApproval,
                      style: metaStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pending.createdAt != null)
                    RelativeTimeText(
                      dateTime: pending.createdAt,
                      style: metaStyle,
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.s),

              // 标题(新主题 = 待审标题,回复 = 所在主题标题)
              if (pending.title != null && pending.title!.isNotEmpty)
                Text(
                  pending.title!,
                  style: base
                      .merge(tokens.text.control)
                      .copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              // 内容预览
              if (pending.raw.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  pending.raw,
                  style: metaStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // 操作行
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  action(context.l10n.review_withdraw, onWithdraw),
                  action(
                    context.l10n.review_withdrawAndEdit,
                    onWithdrawAndEdit,
                    brand: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表骨架屏
class _PendingListSkeleton extends StatelessWidget {
  const _PendingListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: 4,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.pageMargin,
            vertical: AppSpace.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 60, height: 14),
                  const SizedBox(width: 12),
                  SkeletonBox(width: 70, height: 14),
                ],
              ),
              const SizedBox(height: 8),
              SkeletonBox(width: double.infinity, height: 18),
              const SizedBox(height: 4),
              SkeletonBox(width: 200, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
