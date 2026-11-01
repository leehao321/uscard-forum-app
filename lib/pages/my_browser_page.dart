import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_model_manager/ai_model_manager.dart'
    show SwipeActionCell, SwipeAction, SwipeActionScope;

import '../models/web_bookmark.dart';
import '../models/web_history_item.dart';
import '../providers/web_bookmark_provider.dart';
import '../providers/web_history_provider.dart';
import '../utils/time_utils.dart';
import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

import 'package:m3e_ui/m3e_ui.dart';

import 'webview_page.dart';
import 'download_list_page.dart';

// ---------------------------------------------------------------------------
// 内置浏览器主页 — 地址栏 + 功能入口（补充稿 38）
// ---------------------------------------------------------------------------

/// 地址栏里输入的文字补成可打开的网址：去掉首尾空白，没写协议的补 https://；
/// 空输入返回 null（不打开）
String? normalizeBrowserInput(String input) {
  final url = input.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://$url';
}

class MyBrowserPage extends ConsumerWidget {
  const MyBrowserPage({super.key, this.onOpenUrl});

  /// 地址栏提交后怎么打开；默认用内置浏览器页（测试里换成记录用的假回调）
  final void Function(BuildContext context, String url)? onOpenUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarkCount = ref.watch(
      webBookmarkProvider.select((list) => list.length),
    );
    final tokens = context.tokens;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      appBar: ReadableAppBar(child: AppNavBar(title: l10n.myBrowser_title)),
      body: ReadableBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.s,
            AppSpace.pageMargin,
            AppSpace.x32,
          ),
          children: [
            // 地址栏
            _AddressBar(onSubmit: (url) => _openUrl(context, url)),
            const SizedBox(height: AppSpace.l),
            // 功能入口：收藏、浏览历史、下载管理（和论坛书签、论坛浏览历史分开）
            SegmentedCardGroup(
              separatorIndent: AppSpace.m + AppSize.iconM + AppSpace.m,
              children: [
                _EntryTile(
                  icon: AppIcons.star,
                  title: l10n.myBrowser_bookmarks,
                  subtitle: l10n.myBrowser_bookmarkCount(bookmarkCount),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _BookmarkListPage(),
                    ),
                  ),
                ),
                _EntryTile(
                  icon: AppIcons.history,
                  title: l10n.myBrowser_history,
                  subtitle: l10n.myBrowser_historyDesc,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const _WebHistoryPage()),
                  ),
                ),
                _EntryTile(
                  icon: AppIcons.download,
                  title: l10n.myBrowser_downloads,
                  subtitle: l10n.myBrowser_downloadsDesc,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadListPage()),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.m,
                AppSpace.s,
                AppSpace.m,
                0,
              ),
              child: Text(
                l10n.myBrowser_footer,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: tokens.colors.textMeta),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUrl(BuildContext context, String input) {
    final url = normalizeBrowserInput(input);
    if (url == null) return;
    final open = onOpenUrl;
    if (open != null) {
      open(context, url);
    } else {
      WebViewPage.open(context, url);
    }
  }
}

/// 地址输入栏：44 高 r10 surface/grouped，左 globe 20、输入 17、右 arrow-right 20
class _AddressBar extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const _AddressBar({required this.onSubmit});

  @override
  State<_AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<_AddressBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;

    return SizedBox(
      height: AppSize.hit,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        cursorColor: tokens.colors.brandPrimary,
        style: base
            .merge(tokens.text.control)
            .copyWith(color: tokens.colors.textPrimary),
        decoration: InputDecoration(
          hintText: context.l10n.myBrowser_inputUrl,
          hintStyle: base
              .merge(tokens.text.control)
              .copyWith(color: tokens.colors.textMeta),
          prefixIcon: Icon(
            AppIcons.globe,
            size: AppSize.iconM,
            color: tokens.colors.textMeta,
          ),
          suffixIcon: AppIconButton(
            icon: AppIcons.forward,
            size: AppSize.iconM,
            color: tokens.colors.textMeta,
            semanticLabel: context.l10n.myBrowser_open,
            onPressed: _submit,
          ),
          filled: true,
          fillColor: tokens.colors.surfaceGrouped,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radius.field),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
  }
}

/// 功能入口行：前导图标 20 brand、标题 17、说明 13 meta、右侧 chevron-right 16
class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return AppPressable(
      highlight: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m,
            vertical: AppSpace.s,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppSize.iconM, color: tokens.colors.brandPrimary),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: base
                          .merge(tokens.text.control)
                          .copyWith(color: tokens.colors.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: base
                          .merge(tokens.text.meta)
                          .copyWith(color: tokens.colors.textMeta),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s),
              Icon(
                AppIcons.chevronRight,
                size: AppSize.iconS,
                color: tokens.colors.textMeta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 收藏列表页（二级页面）
// ---------------------------------------------------------------------------

/// 添加收藏对话框里网址框的预填前缀
const _urlPrefix = 'https://';

class _BookmarkListPage extends ConsumerWidget {
  const _BookmarkListPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(webBookmarkProvider);

    return Scaffold(
      // 补充稿 46：返回 + 标题 + 右上「+」
      appBar: AppNavBar(
        title: context.l10n.myBrowser_bookmarks,
        trailing: [
          AppIconButton(
            icon: AppIcons.add,
            semanticLabel: context.l10n.myBrowser_addManually,
            onPressed: () => _showAddDialog(context, ref),
          ),
        ],
      ),
      body: ReadableBody(
        child: bookmarks.isEmpty
            ? AppStateView(
                bareIcon: true,
                icon: AppIcons.star,
                title: context.l10n.myBrowser_empty,
                message: context.l10n.myBrowser_emptyHint,
              )
            : SwipeActionScope(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final item = bookmarks[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index < bookmarks.length - 1 ? 12 : 0,
                      ),
                      child: SwipeActionCell(
                        key: ValueKey(item.url),
                        trailingActions: [
                          SwipeAction(
                            icon: AppIcons.edit,
                            color: context.tokens.colors.brandButton,
                            label: S.current.myBrowser_edit,
                            onPressed: () =>
                                _showEditDialog(context, ref, item),
                          ),
                          SwipeAction(
                            icon: AppIcons.delete,
                            color: context.tokens.colors.textDestructive,
                            label: S.current.myBrowser_delete,
                            onPressed: () => _confirmDelete(context, ref, item),
                          ),
                        ],
                        child: _BookmarkCard(
                          item: item,
                          onTap: () => WebViewPage.open(
                            context,
                            item.url,
                            title: item.title,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    // 网址框预填 https://，用户直接接着输入；只剩前缀等于没填
    final urlController = TextEditingController(text: _urlPrefix);
    final titleController = TextEditingController();

    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.myBrowser_addManually),
        titleAlign: TextAlign.start,
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpace.l,
          AppSpace.xl,
          AppSpace.l,
          AppSpace.l,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpace.l,
          AppSpace.xs,
          AppSpace.l,
          AppSpace.m,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFilledField(
              label: S.current.myBrowser_urlLabel,
              controller: urlController,
              autofocus: true,
              focusRing: false,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              fillColor: ctx.tokens.colors.surfaceElevated,
            ),
            const SizedBox(height: AppSpace.s),
            AppFilledField(
              label: S.current.myBrowser_inputTitle,
              controller: titleController,
              hintText: S.current.myBrowser_titleHint,
              focusRing: false,
              fillColor: ctx.tokens.colors.surfaceElevated,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              var url = urlController.text.trim();
              // 网址必填：空，或只剩预填的前缀，都不添加
              if (url.isEmpty || url == _urlPrefix) return;
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                url = 'https://$url';
              }
              ref
                  .read(webBookmarkProvider.notifier)
                  .add(
                    WebBookmark(
                      url: url,
                      title: titleController.text.trim(),
                      createdAt: DateTime.now(),
                    ),
                  );
              Navigator.pop(ctx);
            },
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, WebBookmark item) {
    final titleController = TextEditingController(text: item.title);

    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.myBrowser_editTitle),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.current.myBrowser_inputTitle,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              final notifier = ref.read(webBookmarkProvider.notifier);
              notifier.removeByUrl(item.url);
              notifier.add(
                WebBookmark(
                  url: item.url,
                  title: titleController.text.trim(),
                  createdAt: item.createdAt,
                ),
              );
              Navigator.pop(ctx);
            },
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, WebBookmark item) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.myBrowser_delete),
        content: Text(S.current.myBrowser_confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(webBookmarkProvider.notifier).removeByUrl(item.url);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(S.current.myBrowser_delete),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 浏览历史页（二级页面）
// ---------------------------------------------------------------------------

class _WebHistoryPage extends ConsumerWidget {
  const _WebHistoryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(webHistoryProvider);

    return Scaffold(
      appBar: AppNavBar(
        title: context.l10n.myBrowser_history,
        trailing: [
          if (history.isNotEmpty)
            AppIconButton(
              icon: AppIcons.delete,
              semanticLabel: context.l10n.myBrowser_clearHistory,
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: ReadableBody(
        child: history.isEmpty
            ? AppStateView(
                bareIcon: true,
                icon: AppIcons.history,
                title: context.l10n.myBrowser_historyEmpty,
                message: context.l10n.myBrowser_historyEmptyHint,
              )
            : SwipeActionScope(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index < history.length - 1 ? 12 : 0,
                      ),
                      child: SwipeActionCell(
                        key: ValueKey(
                          '${item.url}_${item.visitedAt.millisecondsSinceEpoch}',
                        ),
                        trailingActions: [
                          SwipeAction(
                            icon: AppIcons.delete,
                            color: context.tokens.colors.textDestructive,
                            label: S.current.myBrowser_delete,
                            onPressed: () => ref
                                .read(webHistoryProvider.notifier)
                                .removeByUrl(item.url),
                          ),
                        ],
                        child: _HistoryCard(
                          item: item,
                          onTap: () => WebViewPage.open(
                            context,
                            item.url,
                            title: item.title,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.myBrowser_clearHistory),
        content: Text(S.current.myBrowser_clearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(webHistoryProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(S.current.myBrowser_clearHistory),
          ),
        ],
      ),
    );
  }
}

/// 历史卡片
class _HistoryCard extends StatelessWidget {
  final WebHistoryItem item;
  final VoidCallback onTap;

  const _HistoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(item.url);
    final host = uri?.host ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.tokens.colors.avatarFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                AppIcons.history,
                color: context.tokens.colors.brandPrimary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isNotEmpty ? item.title : item.url,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          host.isNotEmpty ? host : item.url,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TimeUtils.formatRelativeTime(item.visitedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevronRight,
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// 收藏卡片 — 不包 Card，由外层 SwipeActionCell 提供容器
class _BookmarkCard extends StatelessWidget {
  final WebBookmark item;
  final VoidCallback onTap;

  const _BookmarkCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(item.url);
    final host = uri?.host ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                AppIcons.language,
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isNotEmpty ? item.title : item.url,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          host.isNotEmpty ? host : item.url,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TimeUtils.formatRelativeTime(item.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevronRight,
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
