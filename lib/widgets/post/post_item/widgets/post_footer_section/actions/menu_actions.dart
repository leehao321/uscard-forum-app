part of '../post_footer_section.dart';

extension _PostFooterMenuActions on _PostFooterSectionState {
  /// 复制这一层的文字（正文纯文本）
  Future<void> _copyText() async {
    final text = (html_parser.parse(widget.post.cooked).body?.text ?? '')
        .trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    CopySourceTracker.noteText(text, widget.post.postNumber);
    HapticFeedback.selectionClick();
    ToastService.showSuccess(S.current.common_copiedToClipboard);
  }

  /// 复制楼层链接（遵守匿名分享偏好，与「分享链接」同口径）
  Future<void> _copyFloorLink() async {
    final username = ref.read(currentUserProvider).value?.username ?? '';
    final url = ShareUtils.buildShareUrl(
      path: '/t/topic/${widget.topicId}/${widget.post.postNumber}',
      username: username,
      anonymousShare: ref.read(preferencesProvider).anonymousShare,
    );
    await Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.selectionClick();
    ToastService.showSuccess(S.current.common_copiedToClipboard);
  }

  /// 话题页已打开（有过滤状态可读）时才出现「只看该用户」
  bool get _canFilterByUser {
    final params = TopicDetailNotifier.activeParamsFor(widget.topicId);
    return params != null && ref.exists(topicDetailProvider(params));
  }

  bool get _isFilteringThisUser {
    final params = TopicDetailNotifier.activeParamsFor(widget.topicId);
    if (params == null || !ref.exists(topicDetailProvider(params))) {
      return false;
    }
    return ref.read(topicDetailProvider(params).notifier).usernameFilter ==
        widget.post.username;
  }

  void _toggleUserFilter() {
    ref
        .read(topicUserFilterRequestProvider.notifier)
        .request(
          topicId: widget.topicId,
          username: _isFilteringThisUser ? null : widget.post.username,
        );
  }

  Future<void> _sharePost() async {
    // 与话题详情页的「分享回复」同口径:走 buildShareUrl 并遵守匿名分享偏好,
    // 否则同一个动作在两个入口生成的链接不一样(带不带 ?u=)
    final username = ref.read(currentUserProvider).value?.username ?? '';
    final url = ShareUtils.buildShareUrl(
      path: '/t/topic/${widget.topicId}/${widget.post.postNumber}',
      username: username,
      anonymousShare: ref.read(preferencesProvider).anonymousShare,
    );
    await SharePlus.instance.share(ShareParams(text: url));
  }

  void _showFlagDialog(BuildContext context) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, // 举报表单(card):禁止下滑误关
      builder: (context) => PostFlagSheet(
        postId: widget.post.id,
        postUsername: widget.post.username,
        service: _service,
        onSuccess: () => ToastService.showSuccess(S.current.post_flagSubmitted),
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, ThemeData theme) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(context.l10n.post_deleteReplyTitle),
        content: Text(context.l10n.post_deleteReplyConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePost();
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
  }

  /// 楼层菜单（⋯ 按钮与长按浮起共用，设计说明 §3.2）：
  /// 常用操作一组，举报 / 恢复 / 删除单独一组。
  List<List<AppMenuItem<VoidCallback>>> _menuSections(BuildContext context) {
    final isGuest = ref.read(currentUserProvider).value == null;
    final l10n = context.l10n;
    final main = <AppMenuItem<VoidCallback>>[
      if (widget.onShowPostDetail != null)
        AppMenuItem(
          label: widget.postDetailLabel ?? l10n.post_detail,
          icon: widget.postDetailLabel != null
              ? AppIcons.openInNew
              : AppIcons.article,
          onTap: widget.onShowPostDetail,
        ),
      if (widget.onReply != null)
        AppMenuItem(
          label: l10n.post_replyThis,
          icon: AppIcons.reply,
          onTap: () => widget.onReply!(),
        ),
      if (widget.onQuotePost != null)
        AppMenuItem(
          label: l10n.post_quoteReply,
          icon: AppIcons.formatQuote,
          onTap: widget.onQuotePost,
        ),
      // 笔记按楼层（P9）：笔记存在本机，访客也能记
      AppMenuItem(
        label: '添加笔记',
        icon: AppIcons.note,
        onTap: () => showTopicNoteSheet(
          context,
          topicId: widget.topicId,
          title: widget.topicTitle ?? '',
          postNumber: widget.post.postNumber,
        ),
      ),
      if (!isGuest)
        AppMenuItem(
          label: _isBookmarked
              ? l10n.bookmark_editBookmark
              : l10n.common_addBookmark,
          icon: AppIcons.bookmark,
          onTap: () => _isBookmarked ? _editBookmark() : _addBookmark(),
        ),
      AppMenuItem(
        label: l10n.post_copyText,
        icon: AppIcons.copy,
        onTap: _copyText,
      ),
      AppMenuItem(
        label: l10n.post_copyFloorLink,
        icon: AppIcons.link,
        onTap: _copyFloorLink,
      ),
      if (_canFilterByUser)
        AppMenuItem(
          label: _isFilteringThisUser
              ? l10n.avatarMenu_cancelFilterPosts
              : l10n.avatarMenu_filterPosts,
          icon: _isFilteringThisUser ? AppIcons.filterOff : AppIcons.filter,
          onTap: _toggleUserFilter,
        ),
      // 菜单打开时才构建，用 read 避免给楼层常驻树增加监听。
      if (ref.read(preferencesProvider).aiTranslationEnabled &&
          ref.read(aiTranslationSelectedModelProvider) != null)
        AppMenuItem(
          label: l10n.ai_translationMenuLabel,
          icon: AppIcons.language,
          onTap: () =>
              showAiTranslationSheet(context, cookedHtml: widget.post.cooked),
        ),
      if (widget.onShareAsImage != null)
        AppMenuItem(
          label: l10n.post_generateShareImage,
          icon: AppIcons.image,
          onTap: widget.onShareAsImage,
        ),
      AppMenuItem(
        label: l10n.common_shareLink,
        icon: AppIcons.share,
        onTap: _sharePost,
      ),
      if (widget.post.canEdit && widget.onEdit != null)
        AppMenuItem(
          label: l10n.common_edit,
          icon: AppIcons.edit,
          onTap: widget.onEdit,
        ),
      if (!isGuest &&
          (widget.post.canAcceptAnswer || widget.post.canUnacceptAnswer))
        AppMenuItem(
          label: _isAcceptedAnswer
              ? l10n.post_unacceptSolution
              : l10n.post_acceptSolution,
          icon: AppIcons.checkCircle,
          checked: _isAcceptedAnswer,
          enabled: !_isTogglingAnswer,
          onTap: _toggleSolution,
        ),
      if (widget.canAssignPost && widget.onAssignPost != null)
        AppMenuItem(
          label: '指定帖子',
          icon: AppIcons.assign,
          onTap: widget.onAssignPost,
        ),

    ];
    final danger = <AppMenuItem<VoidCallback>>[
      if (!isGuest)
        AppMenuItem(
          label: l10n.common_report,
          icon: AppIcons.flag,
          destructive: true,
          onTap: () => _showFlagDialog(context),
        ),
      if (!isGuest && widget.post.canRecover)
        AppMenuItem(
          label: l10n.common_restore,
          icon: AppIcons.undo,
          enabled: !_isDeleting,
          onTap: _recoverPost,
        ),
      if (!isGuest && widget.post.canDelete && !widget.post.isDeleted)
        AppMenuItem(
          label: l10n.common_delete,
          icon: AppIcons.delete,
          destructive: true,
          enabled: !_isDeleting,
          onTap: () => _showDeleteConfirmDialog(context, Theme.of(context)),
        ),
    ];
    // 仅 debug build：复制 cooked HTML / 签名（给渲染引擎调试用）
    final debug = <AppMenuItem<VoidCallback>>[
      if (kDebugMode) ...[
        AppMenuItem(
          label: 'Copy cooked HTML (${widget.post.cooked.length})',
          icon: AppIcons.code,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.post.cooked));
            ToastService.showSuccess(
              'cooked HTML 已复制 (${widget.post.cooked.length} chars)',
            );
          },
        ),
        if (widget.post.effectiveSignature != null)
          AppMenuItem(
            label: 'Copy signature',
            icon: AppIcons.code,
            onTap: () async {
              final signature = widget.post.effectiveSignature!;
              await Clipboard.setData(ClipboardData(text: signature));
              ToastService.showSuccess('签名已复制 (${signature.length} chars)');
            },
          ),
      ],
    ];
    return [main, if (danger.isNotEmpty) danger, if (debug.isNotEmpty) debug];
  }

  Future<void> _showMoreMenu(BuildContext context, Rect anchor) async {
    final run = await showAppMenu<VoidCallback>(
      context: context,
      anchor: anchor,
      sections: _menuSections(context),
    );
    run?.call();
  }
}
