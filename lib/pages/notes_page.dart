import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../storage/topic_note_store.dart';
import '../utils/dialog_utils.dart';
import '../utils/time_utils.dart';
import '../widgets/notes/topic_note_sheet.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// 我的笔记：所有话题的笔记和摘录，只存在本机。
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<TopicNote> _all = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    TopicNoteStore.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    TopicNoteStore.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await TopicNoteStore.list();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<TopicNote> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((n) => n.searchText.contains(q)).toList();
  }

  Future<void> _confirmDelete(TopicNote note) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('删除笔记'),
        content: Text('删除「${note.title}」的笔记和全部摘录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await TopicNoteStore.delete(note.topicId);
  }

  void _openTopic(TopicNote n, [int? postNumber]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: n.topicId,
          initialTitle: n.title,
          scrollToPostNumber: postNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final meta = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final items = _filtered;

    // v2「我的笔记」（设计说明 §5.3）：页内搜索框 + 行（标题 17 Semibold、
    // 笔记预览 13 meta 两行、元信息：楼层链接 brand · 条数 · 时间）+ chevron；
    // 左滑删除（需确认）
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: ReadableBody(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppNavBar(title: '我的笔记'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageMargin,
                  AppSpace.xs,
                  AppSpace.pageMargin,
                  AppSpace.s,
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: theme.textTheme.bodyLarge
                      ?.merge(tokens.text.control)
                      .copyWith(color: colors.textPrimary),
                  cursorColor: colors.brandPrimary,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索标题、笔记和摘录',
                    hintStyle: theme.textTheme.bodyLarge
                        ?.merge(tokens.text.control)
                        .copyWith(color: colors.textMeta),
                    prefixIcon: Icon(
                      AppIcons.search,
                      size: AppSize.iconM,
                      color: colors.textMeta,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceGrouped,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpace.m,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radius.field),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : items.isEmpty
                    ? AppStateView(
                        icon: AppIcons.note,
                        title: _all.isEmpty ? '还没有笔记' : '没有匹配的笔记',
                        message: _all.isEmpty
                            ? '在话题页右上角「更多」里选「笔记」，或长按楼层选「添加笔记」就能记录。'
                            : null,
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final n = items[i];
                          final preview = n.text.trim().isNotEmpty
                              ? n.text.trim()
                              : n.floors.isNotEmpty
                              ? n.floorNotes[n.floors.first]!.trim()
                              : n.excerpts.first.text;
                          final noteCount =
                              n.floors.length + (n.text.trim().isEmpty ? 0 : 1);
                          return Column(
                            children: [
                              SwipeActions(
                                actions: [
                                  SwipeActionItem(
                                    label: '删除',
                                    icon: AppIcons.delete,
                                    background: colors.textDestructive,
                                    onTap: () => _confirmDelete(n),
                                  ),
                                ],
                                child: AppPressable(
                                  highlight: true,
                                  onTap: () => showTopicNoteSheet(
                                    context,
                                    topicId: n.topicId,
                                    title: n.title,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpace.pageMargin,
                                      vertical: AppSpace.m,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodyLarge
                                                    ?.merge(tokens.text.control)
                                                    .copyWith(
                                                      color: colors.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(
                                                height: AppSpace.xs,
                                              ),
                                              Text(
                                                preview.replaceAll('\n', ' '),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: meta,
                                              ),
                                              const SizedBox(
                                                height: AppSpace.s,
                                              ),
                                              Wrap(
                                                spacing: AppSpace.s,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  if (n.floors.isEmpty)
                                                    Text('话题笔记', style: meta)
                                                  else
                                                    for (final f
                                                        in n.floors.take(3))
                                                      GestureDetector(
                                                        behavior:
                                                            HitTestBehavior
                                                                .opaque,
                                                        onTap: () =>
                                                            _openTopic(n, f),
                                                        child: Text(
                                                          '#$f',
                                                          style: meta.copyWith(
                                                            color: colors
                                                                .brandPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                  Text(
                                                    '· $noteCount 条笔记'
                                                    '${n.excerpts.isEmpty ? '' : ' · ${n.excerpts.length} 条摘录'}'
                                                    ' · ${TimeUtils.formatRelativeTime(n.updatedAt)}',
                                                    style: meta,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: AppSpace.s),
                                        Icon(
                                          AppIcons.chevronRight,
                                          size: AppSize.iconM,
                                          color: colors.textMeta,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const AppHairline(indent: AppSpace.pageMargin),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
