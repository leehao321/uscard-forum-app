import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/s.dart';
import '../../../models/post_revision.dart';
import '../../../providers/category_provider.dart';
import '../../../providers/core_providers.dart';
import '../../../services/app_error_handler.dart';
import '../../../services/discourse/discourse_service.dart';
import '../../../services/toast_service.dart';
import '../../../utils/dialog_utils.dart';
import '../../../utils/fluxdo_render_callbacks.dart';
import '../../../utils/responsive.dart';
import '../../../utils/time_utils.dart';

import 'package:m3e_ui/m3e_ui.dart';
import 'package:common_ui/common_ui.dart';

import '../../common/smart_avatar.dart';
import 'revision_diff_utils.dart';

/// 帖子编辑历史主视图(放入 modal/page 内)。
///
/// 负责:
/// - 加载并切换 revision(初始为 [initialRevision] 或 latest)
/// - 渲染顶部导航(版本号 + 上一版/下一版,溢出菜单含首版/末版/diff 模式)
/// - 渲染元信息(编辑者 / 时间 / 原因 / 隐藏 badge)
/// - 渲染非 body 变化(标题、分类、标签、wiki 等"旧 → 新")
/// - 渲染正文 diff(根据屏宽自适应默认模式,可手动切换)
/// - 渲染 staff 操作栏(隐藏 / 显示 / 回退 / 永久删除)
///
/// staff 操作成功后,依赖 MessageBus / topic_detail provider 自动刷新对应帖子;
/// 本视图不主动调用 refreshPost,避免与上层 provider 绑定。
class PostRevisionView extends ConsumerStatefulWidget {
  final int postId;
  final int? initialRevision;

  const PostRevisionView({
    super.key,
    required this.postId,
    this.initialRevision,
  });

  @override
  ConsumerState<PostRevisionView> createState() => _PostRevisionViewState();
}

enum _DiffMode { inline, sideBySide, sideBySideMarkdown }

class _PostRevisionViewState extends ConsumerState<PostRevisionView> {
  late final DiscourseService _service = ref.read(discourseServiceProvider);
  PostRevision? _revision;
  bool _loading = true;
  bool _busy = false; // staff 操作进行中
  Object? _error;
  _DiffMode _diffMode = _DiffMode.inline;
  bool _diffModeInitialized = false;

  @override
  void initState() {
    super.initState();
    _load(widget.initialRevision);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首次进入根据屏宽确定 diff 默认模式:桌面/平板默认 side-by-side,
    // 移动端默认 inline。仅初始化一次,避免旋转/分屏触发模式切换。
    if (!_diffModeInitialized) {
      _diffModeInitialized = true;
      _diffMode = Responsive.isMobile(context)
          ? _DiffMode.inline
          : _DiffMode.sideBySide;
    }
  }

  Future<void> _load(int? revision) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = revision != null
          ? await _service.getPostRevision(widget.postId, revision)
          : await _service.getLatestPostRevision(widget.postId);
      if (!mounted) return;
      setState(() {
        _revision = result;
        _loading = false;
      });
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _navigateTo(int revision) async {
    if (_busy || _loading) return;
    await _load(revision);
  }

  Future<void> _hideRevision() async {
    final revision = _revision;
    if (revision == null) return;
    final successMessage = context.l10n.postRevision_hideSuccess(
      revision.currentRevision,
    );
    await _runStaffAction(
      () => _service.hidePostRevision(widget.postId, revision.currentRevision),
      successMessage: successMessage,
      reloadAfter: true,
    );
  }

  Future<void> _showRevision() async {
    final revision = _revision;
    if (revision == null) return;
    final successMessage = context.l10n.postRevision_showSuccess(
      revision.currentRevision,
    );
    await _runStaffAction(
      () => _service.showPostRevision(widget.postId, revision.currentRevision),
      successMessage: successMessage,
      reloadAfter: true,
    );
  }

  Future<void> _revertRevision() async {
    final revision = _revision;
    if (revision == null) return;
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.postRevision_revertConfirmTitle(revision.currentRevision),
      body: l10n.postRevision_revertConfirmBody,
    );
    if (!confirmed) return;
    final successMessage = l10n.postRevision_revertSuccess(
      revision.currentRevision,
    );
    await _runStaffAction(
      () => _service.revertPostToRevision(
        widget.postId,
        revision.currentRevision,
      ),
      successMessage: successMessage,
      closeAfter: true,
    );
  }

  Future<void> _permanentlyDelete() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.postRevision_permanentlyDeleteTitle,
      body: l10n.postRevision_permanentlyDeleteBody,
      destructive: true,
    );
    if (!confirmed) return;
    final successMessage = l10n.postRevision_deleteAllSuccess;
    await _runStaffAction(
      () => _service.permanentlyDeletePostRevisions(widget.postId),
      successMessage: successMessage,
      closeAfter: true,
    );
  }

  Future<void> _runStaffAction(
    Future<void> Function() action, {
    required String successMessage,
    bool reloadAfter = false,
    bool closeAfter = false,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      ToastService.showSuccess(successMessage);
      if (!mounted) return;
      if (closeAfter) {
        Navigator.of(context).maybePop();
        return;
      }
      if (reloadAfter) {
        final revision = _revision;
        if (revision != null) {
          await _load(revision.currentRevision);
        }
      }
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) {
        ToastService.showError(context.l10n.postRevision_actionFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    bool destructive = false,
  }) async {
    final result = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.tokens;
        return AppAlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? TextButton.styleFrom(
                      foregroundColor: tokens.colors.textDestructive,
                    )
                  : null,
              child: Text(dialogContext.l10n.common_confirm),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _revision == null) {
      return const Center(child: LoadingSpinner(size: 36));
    }
    if (_error != null && _revision == null) {
      return _ErrorView(
        error: _error!,
        onRetry: () => _load(widget.initialRevision),
      );
    }
    final revision = _revision;
    if (revision == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(context.l10n.postRevision_emptyHistory),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RevisionToolbar(
              revision: revision,
              diffMode: _diffMode,
              onModeChanged: revision.bodyChanges == null
                  ? null
                  : (mode) => setState(() => _diffMode = mode),
              onFirst: revision.currentRevision == revision.firstRevision
                  ? null
                  : () => _navigateTo(revision.firstRevision),
              onPrevious: revision.hasPreviousRevision
                  ? () => _navigateTo(revision.previousRevision)
                  : null,
              onNext: revision.hasNextRevision
                  ? () => _navigateTo(revision.nextRevision!)
                  : null,
              onLast: revision.currentRevision == revision.lastRevision
                  ? null
                  : () => _navigateTo(revision.lastRevision),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageMargin,
                  AppSpace.s,
                  AppSpace.pageMargin,
                  AppSpace.l,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthorMeta(revision: revision),
                    if (revision.hasMetaChanges) ...[
                      const SizedBox(height: AppSpace.m),
                      _MetaChanges(revision: revision),
                    ],
                    const SizedBox(height: AppSpace.l),
                    _BodyDiff(revision: revision, mode: _diffMode),
                  ],
                ),
              ),
            ),
            _StaffActions(
              revision: revision,
              busy: _busy,
              onHide: _hideRevision,
              onShow: _showRevision,
              onRevert: _revertRevision,
              onPermanentlyDelete: _permanentlyDelete,
            ),
          ],
        ),
        if (_busy || (_loading && _revision != null))
          const Positioned.fill(child: _BlockingOverlay()),
      ],
    );
  }
}

/// 工具栏（补充稿 29–31）：左侧「‹ 上一版 → 当前版 ›」切换版本，右侧是当前对比方式
/// （brand/primary 13 + ⌄），点开菜单换成 行内差异 / 并排 Markdown / 渲染后对比。
/// 桌面端另外平铺首版 / 末版；手机端把它们收进溢出菜单。
/// 只有一个版本（没有上一版也没有下一版）时不画箭头。
class _RevisionToolbar extends StatelessWidget {
  final PostRevision revision;
  final _DiffMode diffMode;
  final ValueChanged<_DiffMode>? onModeChanged;
  final VoidCallback? onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onLast;

  const _RevisionToolbar({
    required this.revision,
    required this.diffMode,
    required this.onModeChanged,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onLast,
  });

  /// 菜单里的顺序：行内差异 / 并排 Markdown / 渲染后对比
  static const modeOrder = [
    _DiffMode.inline,
    _DiffMode.sideBySideMarkdown,
    _DiffMode.sideBySide,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final l10n = context.l10n;
    final isMobile = Responsive.isMobile(context);
    final hasNav = onPrevious != null || onNext != null;
    final label = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textPrimary);

    return Padding(
      // 箭头的 44 热区里图标居中，左缘要和 20 的页边距对齐
      padding: EdgeInsets.only(
        left: hasNav ? AppSpace.s : AppSpace.pageMargin,
        right: AppSpace.pageMargin,
      ),
      child: Row(
        children: [
          // 左组「‹ 上一版 → 当前版 ›」占满剩余宽度，对比方式靠右
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMobile)
                    AppIconButton(
                      icon: AppIcons.chevronFirst,
                      size: AppSize.iconM,
                      semanticLabel: l10n.postRevision_first,
                      onPressed: onFirst,
                    ),
                  if (hasNav)
                    AppIconButton(
                      key: const ValueKey('revision_previous'),
                      icon: AppIcons.chevronLeft,
                      size: AppSize.iconM,
                      semanticLabel: l10n.postRevision_previous,
                      onPressed: onPrevious,
                    ),
                  Flexible(
                    child: Semantics(
                      label: l10n.postRevision_versionLabel(
                        revision.currentVersion,
                        revision.versionCount,
                      ),
                      child: Text(
                        l10n.postRevision_compareLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: label,
                      ),
                    ),
                  ),
                  if (hasNav)
                    AppIconButton(
                      key: const ValueKey('revision_next'),
                      icon: AppIcons.chevronRight,
                      size: AppSize.iconM,
                      semanticLabel: l10n.postRevision_next,
                      onPressed: onNext,
                    ),
                  if (!isMobile)
                    AppIconButton(
                      icon: AppIcons.chevronLast,
                      size: AppSize.iconM,
                      semanticLabel: l10n.postRevision_last,
                      onPressed: onLast,
                    ),
                ],
              ),
            ),
          ),
          if (onModeChanged != null)
            AppMenuAnchor<_DiffMode>(
              key: const ValueKey('revision_mode_menu'),
              semanticLabel: _modeLabel(l10n, diffMode),
              onSelected: onModeChanged,
              sectionsBuilder: (_) => [
                [
                  for (final mode in modeOrder)
                    AppMenuItem<_DiffMode>(
                      label: _modeLabel(l10n, mode),
                      value: mode,
                      checked: mode == diffMode,
                      rowKey: ValueKey('revision_mode_${mode.name}'),
                    ),
                ],
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.hit),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _modeLabel(l10n, diffMode),
                      key: const ValueKey('revision_mode_label'),
                      style: label?.copyWith(color: tokens.colors.brandPrimary),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Icon(
                      AppIcons.chevronDown,
                      size: AppSize.iconS,
                      color: tokens.colors.brandPrimary,
                    ),
                  ],
                ),
              ),
            ),
          if (isMobile && (onFirst != null || onLast != null))
            AppMenuButton<String>(
              icon: AppIcons.moreVert,
              semanticLabel: MaterialLocalizations.of(
                context,
              ).moreButtonTooltip,
              onSelected: (value) {
                if (value == 'first') onFirst?.call();
                if (value == 'last') onLast?.call();
              },
              sectionsBuilder: (_) => [
                [
                  if (onFirst != null)
                    AppMenuItem<String>(
                      label: l10n.postRevision_first,
                      value: 'first',
                      icon: AppIcons.chevronFirst,
                    ),
                  if (onLast != null)
                    AppMenuItem<String>(
                      label: l10n.postRevision_last,
                      value: 'last',
                      icon: AppIcons.chevronLast,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  static String _modeLabel(AppLocalizations l10n, _DiffMode mode) {
    switch (mode) {
      case _DiffMode.inline:
        return l10n.postRevision_diffInline;
      case _DiffMode.sideBySide:
        return l10n.postRevision_diffSideBySide;
      case _DiffMode.sideBySideMarkdown:
        return l10n.postRevision_diffSideBySideMarkdown;
    }
  }
}

/// 编辑者信息：不画底色的两行小字——「v2 / 5 · 由 X 编辑 · 时间」和编辑原因。
class _AuthorMeta extends StatelessWidget {
  final PostRevision revision;

  const _AuthorMeta({required this.revision});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final l10n = context.l10n;
    final avatarUrl = revision.getAvatarUrl();
    final timeText = TimeUtils.formatDetailTime(revision.createdAt);
    final meta = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    final version = l10n.postRevision_versionLabel(
      revision.currentVersion,
      revision.versionCount,
    );
    final editedBy = l10n.postRevision_editedBy(
      revision.actingUserName ?? revision.displayActor,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (avatarUrl.isNotEmpty) ...[
              SmartAvatar(imageUrl: avatarUrl, radius: 10),
              const SizedBox(width: AppSpace.s),
            ],
            Expanded(
              child: Text(
                '$version · $editedBy · $timeText',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ),
            if (revision.currentHidden)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s,
                  vertical: AppSpace.xxs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.colors.textDestructive),
                  borderRadius: BorderRadius.circular(tokens.radius.tag),
                ),
                child: Text(
                  l10n.postRevision_revisionHidden,
                  style: tokens.text.caption.copyWith(
                    color: tokens.colors.textDestructive,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          revision.editReason != null
              ? l10n.postRevision_editReason(revision.editReason!)
              : l10n.postRevision_editReasonEmpty,
          style: meta?.copyWith(
            fontStyle: revision.editReason == null
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        ),
      ],
    );
  }
}

class _MetaChanges extends ConsumerWidget {
  final PostRevision revision;

  const _MetaChanges({required this.revision});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final categoryMap =
        ref.watch(categoryMapProvider).whenOrNull(data: (m) => m) ?? const {};

    final entries = <_MetaEntry>[];
    final title = revision.titleChanges;
    if (title != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_titleChange,
          previous: title.previous ?? '—',
          current: title.current ?? '—',
        ),
      );
    }
    final category = revision.categoryIdChanges;
    if (category != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_categoryChange,
          previous: _categoryName(categoryMap, category.previous),
          current: _categoryName(categoryMap, category.current),
        ),
      );
    }
    final tags = revision.tagsChanges;
    if (tags != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_tagsChange,
          previous: tags.previous?.join(', ') ?? '—',
          current: tags.current?.join(', ') ?? '—',
        ),
      );
    }
    final wiki = revision.wikiChanges;
    if (wiki != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_wikiChange,
          previous: '${wiki.previous ?? false}',
          current: '${wiki.current ?? false}',
        ),
      );
    }
    final postType = revision.postTypeChanges;
    if (postType != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_postTypeChange,
          previous: '${postType.previous}',
          current: '${postType.current}',
        ),
      );
    }
    final replyTo = revision.replyToPostNumberChanges;
    if (replyTo != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_replyToChange,
          previous: replyTo.previous != null ? '#${replyTo.previous}' : '—',
          current: replyTo.current != null ? '#${replyTo.current}' : '—',
        ),
      );
    }
    final user = revision.userChanges;
    if (user != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_userChange,
          previous: user.previousUsername ?? '—',
          current: user.currentUsername ?? '—',
        ),
      );
    }
    final locale = revision.localeChanges;
    if (locale != null) {
      entries.add(
        _MetaEntry(
          label: l10n.postRevision_localeChange,
          previous: locale.previous ?? '—',
          current: locale.current ?? '—',
        ),
      );
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.m),
      decoration: BoxDecoration(
        color: tokens.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const AppHairline(),
            _MetaRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }

  String _categoryName(Map<int, dynamic> map, int? id) {
    if (id == null) return '—';
    final category = map[id];
    if (category == null) return '#$id';
    final name = (category as dynamic).name as String?;
    return name == null || name.isEmpty ? '#$id' : name;
  }
}

class _MetaEntry {
  final String label;
  final String previous;
  final String current;

  const _MetaEntry({
    required this.label,
    required this.previous,
    required this.current,
  });
}

class _MetaRow extends StatelessWidget {
  final _MetaEntry entry;

  const _MetaRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              entry.label,
              style: theme.textTheme.bodySmall
                  ?.merge(tokens.text.metaStrong)
                  .copyWith(color: tokens.colors.textMeta),
            ),
          ),
          const SizedBox(width: AppSpace.s),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.s,
              runSpacing: AppSpace.xs,
              children: [
                // 旧值：text/destructive + 删除线；新值：brand/primary
                _MetaChip(
                  text: entry.previous,
                  color: tokens.colors.textDestructive,
                  strike: true,
                ),
                Icon(
                  AppIcons.moveRight,
                  size: AppSize.iconS,
                  color: tokens.colors.textMeta,
                ),
                _MetaChip(
                  text: entry.current,
                  color: tokens.colors.brandPrimary,
                  strike: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool strike;

  const _MetaChip({
    required this.text,
    required this.color,
    required this.strike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        decoration: strike ? TextDecoration.lineThrough : null,
        decorationColor: color,
      ),
    );
  }
}

class _BodyDiff extends StatelessWidget {
  final PostRevision revision;
  final _DiffMode mode;

  const _BodyDiff({required this.revision, required this.mode});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (revision.diffError) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.m),
        decoration: BoxDecoration(
          color: tokens.colors.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radius.card),
        ),
        child: Text(
          context.l10n.postRevision_diffError,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: tokens.colors.textDestructive,
          ),
        ),
      );
    }
    final body = revision.bodyChanges;
    if (body == null || body.isEmpty) {
      return const SizedBox.shrink();
    }

    // 删除 text/destructive（删除线）、新增 brand/primary
    String paint(String html) => colorizeDiffHtml(
      html,
      insColor: tokens.colors.brandPrimary,
      delColor: tokens.colors.textDestructive,
    );

    switch (mode) {
      case _DiffMode.inline:
        final html = body.inline ?? body.sideBySide ?? body.sideBySideMarkdown;
        if (html == null || html.isEmpty) return const SizedBox.shrink();
        // 行内差异：一张 surface/elevated 卡片，里面是交错的新旧文字
        return _DiffCard(
          child: FluxdoRenderCallbacks.generic(
            heroTagNamespace: 'revision_inline',
          ).render(cookedHtml: paint(html), selectionEnabled: false),
        );

      case _DiffMode.sideBySide:
        final raw = body.sideBySide ?? body.sideBySideMarkdown ?? body.inline;
        if (raw == null || raw.isEmpty) return const SizedBox.shrink();
        // 后端返回两个并排 div: `<div class="revision-content --previous">A</div><div class="revision-content --current">B</div>`
        // 拆开用 Row 渲染(单列 fallback 走新引擎 FluxdoRender)。
        final parts = _splitSideBySide(raw);
        if (parts == null) {
          return _DiffCard(
            child: FluxdoRenderCallbacks.generic(
              heroTagNamespace: 'revision_sbs',
            ).render(cookedHtml: paint(raw), selectionEnabled: false),
          );
        }
        return _TwoColumnDiff(
          previousHtml: paint(parts.$1),
          currentHtml: paint(parts.$2),
        );

      case _DiffMode.sideBySideMarkdown:
        final raw = body.sideBySideMarkdown ?? body.sideBySide ?? body.inline;
        if (raw == null || raw.isEmpty) return const SizedBox.shrink();
        // markdown 模式后端给的是 <table>：每行两个 td，内容是 markdown 原文。
        // 直接渲染 table 会触发自定义 table_builder 的固定列宽 + 虚拟化，
        // 所以拆成行，用系统等宽字体按行画（左上一版、右当前版）。
        final rows = parseMarkdownDiffRows(raw);
        if (rows == null) {
          return _DiffCard(
            child: FluxdoRenderCallbacks.generic(
              heroTagNamespace: 'revision_sbsmd',
            ).render(cookedHtml: raw, selectionEnabled: false),
          );
        }
        return _MarkdownDiffTable(rows: rows);
    }
  }

  /// 拆 discourse 的 `<div class="revision-content --previous">…</div><div class="revision-content --current">…</div>`
  /// 成 `(previous, current)` 两段 HTML; 任一缺失返回 null,由上层 fallback 直接渲染原 HTML。
  static (String, String)? _splitSideBySide(String raw) {
    final pattern = RegExp(
      r'<div\s+class="revision-content\s+--previous">([\s\S]*?)</div>\s*<div\s+class="revision-content\s+--current">([\s\S]*?)</div>\s*$',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(raw.trim());
    if (match == null) return null;
    return (match.group(1) ?? '', match.group(2) ?? '');
  }
}

/// 正文差异的卡片：surface/elevated、r12、内边距 16
class _DiffCard extends StatelessWidget {
  final Widget child;

  const _DiffCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('revision_diff_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.l),
      decoration: BoxDecoration(
        color: tokens.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: child,
    );
  }
}

/// 「上一版 / 当前版」两列的小标题（13 meta）
class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s),
      child: Row(
        children: [
          Expanded(
            child: Text(context.l10n.postRevision_columnPrevious, style: style),
          ),
          const SizedBox(width: AppSpace.s),
          Expanded(
            child: Text(context.l10n.postRevision_columnCurrent, style: style),
          ),
        ],
      ),
    );
  }
}

/// 渲染后对比：左上一版、右当前版，两张卡片
class _TwoColumnDiff extends StatelessWidget {
  final String previousHtml;
  final String currentHtml;

  const _TwoColumnDiff({required this.previousHtml, required this.currentHtml});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ColumnHeaders(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DiffColumn(html: previousHtml)),
            const SizedBox(width: AppSpace.s),
            Expanded(child: _DiffColumn(html: currentHtml)),
          ],
        ),
      ],
    );
  }
}

class _DiffColumn extends StatelessWidget {
  final String html;

  const _DiffColumn({required this.html});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpace.m),
      decoration: BoxDecoration(
        color: tokens.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      // 左右两列 html 不同,用 hashCode 保证 heroTagNamespace 唯一。
      child: FluxdoRenderCallbacks.generic(
        heroTagNamespace: 'revision_col_${html.hashCode}',
      ).render(cookedHtml: html, selectionEnabled: false),
    );
  }
}

/// 并排 Markdown（补充稿 31）：左上一版、右当前版，源码用系统等宽（D37）。
/// 逐行对齐：每行是左右两格，整行等高；被删的行 text/destructive，新增的行
/// brand/primary，没改的 text/primary。两列各自是一张 surface/elevated 卡片
/// （上下圆角只落在第一行和最后一行）。
class _MarkdownDiffTable extends StatelessWidget {
  final List<DiffRow> rows;

  const _MarkdownDiffTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ColumnHeaders(),
        for (var i = 0; i < rows.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MarkdownCell(
                    cell: rows[i].previous,
                    first: i == 0,
                    last: i == rows.length - 1,
                  ),
                ),
                const SizedBox(width: AppSpace.s),
                Expanded(
                  child: _MarkdownCell(
                    cell: rows[i].current,
                    first: i == 0,
                    last: i == rows.length - 1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MarkdownCell extends StatelessWidget {
  final DiffCell cell;
  final bool first;
  final bool last;

  const _MarkdownCell({
    required this.cell,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius = Radius.circular(tokens.radius.card);
    final color = switch (cell.kind) {
      DiffLineKind.deleted => tokens.colors.textDestructive,
      DiffLineKind.added => tokens.colors.brandPrimary,
      DiffLineKind.common => tokens.colors.textPrimary,
    };
    final theme = Theme.of(context);
    // 系统等宽；中文字形回退到界面字体（等宽字体里没有）
    final appFont = theme.textTheme.bodySmall?.fontFamily;
    final mono = tokens.text.monoUrl;
    final base = mono.copyWith(
      color: color,
      fontFamilyFallback: [...?mono.fontFamilyFallback, ?appFont],
    );
    final style = theme.textTheme.bodySmall?.merge(base) ?? base;
    // 空格（占位的空行）也要占一行高度，左右两格才对得齐
    final text = cell.isEmpty ? ' ' : null;
    return Container(
      key: ValueKey('revision_md_${cell.kind.name}'),
      padding: EdgeInsets.fromLTRB(
        AppSpace.m,
        first ? AppSpace.m : 0,
        AppSpace.m,
        last ? AppSpace.m : 0,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.surfaceElevated,
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
      ),
      child: text != null
          ? Text(text, style: style)
          : Text.rich(
              TextSpan(
                style: style,
                children: [
                  for (final seg in cell.segments)
                    TextSpan(
                      text: seg.text,
                      // 行内被改的片段加粗，整行颜色不变
                      style: seg.changed
                          ? const TextStyle(fontWeight: FontWeight.w600)
                          : null,
                    ),
                ],
              ),
            ),
    );
  }
}

class _StaffActions extends ConsumerWidget {
  final PostRevision revision;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onShow;
  final VoidCallback onRevert;
  final VoidCallback onPermanentlyDelete;

  const _StaffActions({
    required this.revision,
    required this.busy,
    required this.onHide,
    required this.onShow,
    required this.onRevert,
    required this.onPermanentlyDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser == null || !currentUser.isStaff) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.colors.separator,
            width: AppSpace.hairline,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (revision.currentHidden)
            OutlinedButton.icon(
              onPressed: busy ? null : onShow,
              icon: const Icon(AppIcons.visibility, size: 16),
              label: Text(l10n.postRevision_show),
            )
          else
            OutlinedButton.icon(
              onPressed: busy ? null : onHide,
              icon: const Icon(AppIcons.visibilityOff, size: 16),
              label: Text(l10n.postRevision_hide),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.colors.textDestructive,
              ),
            ),
          if (revision.hasPreviousRevision)
            OutlinedButton.icon(
              onPressed: busy ? null : onRevert,
              icon: const Icon(AppIcons.history, size: 16),
              label: Text(l10n.postRevision_revert),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.colors.textDestructive,
              ),
            ),
          if (revision.previousHidden)
            OutlinedButton.icon(
              onPressed: busy ? null : onPermanentlyDelete,
              icon: const Icon(AppIcons.delete, size: 16),
              label: Text(l10n.postRevision_permanentlyDelete),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.colors.textDestructive,
              ),
            ),
        ],
      ),
    );
  }
}

class _BlockingOverlay extends StatelessWidget {
  const _BlockingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
      child: const Center(child: LoadingSpinner(size: 32)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.error, color: theme.colorScheme.error, size: 36),
            const SizedBox(height: 12),
            Text(
              l10n.postRevision_loadFailed,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(l10n.postRevision_retry),
            ),
          ],
        ),
      ),
    );
  }
}
