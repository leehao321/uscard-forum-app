import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:m3e_ui/m3e_ui.dart' show LoadingSpinner;

import '../services/ai_translation_service.dart';
import '../services/toast_service.dart';
import '../storage/saved_topic_store.dart';
import '../utils/time_utils.dart';

/// 已存帖子页：「看过就存」保存在本机的话题，离线可搜可看。
class SavedTopicsPage extends StatefulWidget {
  const SavedTopicsPage({super.key});

  @override
  State<SavedTopicsPage> createState() => _SavedTopicsPageState();
}

class _SavedTopicsPageState extends State<SavedTopicsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<SavedTopicMeta> _all = const [];
  bool _loading = true;
  int _bytes = 0;
  bool _enabled = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    SavedTopicStore.changes.addListener(_reload);
    _reload();
    SavedTopicStore.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  @override
  void dispose() {
    SavedTopicStore.changes.removeListener(_reload);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await SavedTopicStore.list();
    final bytes = await SavedTopicStore.totalBytes();
    if (!mounted) return;
    setState(() {
      _all = list;
      _bytes = bytes;
      _loading = false;
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  List<SavedTopicMeta> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((m) => m.searchText.contains(q)).toList();
  }

  Future<void> _toggleEnabled(bool value) async {
    await SavedTopicStore.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('清空已存帖子'),
        content: Text('将删除本机保存的 ${_all.length} 个话题，不影响论坛上的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await SavedTopicStore.clear();
      if (mounted) ToastService.showSuccess('已清空');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final items = _filtered;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(
        showDivider: true,
        slotWidth: 100,
        title: '已存帖子',
        trailing: [
          // 右侧红字「清空」（破坏性，点开仍有确认）
          if (_all.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(AppSize.hit, AppSize.hit),
                foregroundColor: colors.textDestructive,
              ),
              onPressed: _confirmClear,
              child: const Text('清空'),
            ),
        ],
      ),
      body: ReadableBody(
        child: Column(
          children: [
            // 开关行：标题 17 + 说明 13 meta
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.pageMargin,
                vertical: AppSpace.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '看过就存',
                          style: base
                              .merge(tokens.text.control)
                              .copyWith(color: colors.textPrimary),
                        ),
                        Text(
                          '打开并加载过的话题自动保存到本机，不额外联网',
                          style: base
                              .merge(tokens.text.meta)
                              .copyWith(color: colors.textMeta),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.m),
                  Switch.adaptive(value: _enabled, onChanged: _toggleEnabled),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                0,
                AppSpace.pageMargin,
                AppSpace.s,
              ),
              child: TextField(
                controller: _searchController,
                style: base
                    .merge(tokens.text.control)
                    .copyWith(color: colors.textPrimary),
                cursorColor: colors.brandPrimary,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    AppIcons.search,
                    size: AppSize.iconM,
                    color: colors.textMeta,
                  ),
                  hintText: '搜索标题和正文',
                  hintStyle: TextStyle(color: colors.textMeta),
                  filled: true,
                  fillColor: colors.surfaceGrouped,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.m,
                    vertical: AppSpace.m,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius.field),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: LoadingSpinner())
                  : items.isEmpty
                  ? AppStateView(
                      icon: _all.isEmpty ? AppIcons.inbox : AppIcons.searchOff,
                      title: _all.isEmpty ? '还没有保存的话题' : '没有匹配的话题',
                    )
                  : ListView.builder(
                      itemCount: items.length + 1,
                      itemBuilder: (context, index) {
                        // 页脚：共 N 个话题 · 占用 · 只保存在本机
                        if (index == items.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpace.pageMargin,
                              vertical: tokens.rowPadV,
                            ),
                            child: Text(
                              '共 ${items.length} 个话题 · 占用 ${_formatBytes(_bytes)} · 只保存在这台设备上',
                              style: base
                                  .merge(tokens.text.meta)
                                  .copyWith(color: colors.textMeta),
                            ),
                          );
                        }
                        final meta = items[index];
                        return SwipeActions(
                          actions: [
                            SwipeActionItem(
                              label: '删除',
                              icon: AppIcons.delete,
                              background: colors.textDestructive,
                              onTap: () => SavedTopicStore.delete(meta.topicId),
                            ),
                          ],
                          child: AppPressable(
                            highlight: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SavedTopicViewPage(topicId: meta.topicId),
                              ),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfacePage,
                                border: Border(
                                  bottom: BorderSide(
                                    color: colors.separator,
                                    width: AppSpace.hairline,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: AppSpace.pageMargin,
                                  vertical: tokens.rowPadV,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      meta.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: base
                                          .merge(tokens.text.headline)
                                          .copyWith(color: colors.textPrimary),
                                    ),
                                    const SizedBox(height: AppSpace.s),
                                    Text(
                                      '${meta.postCount} 个楼层 · 保存于 '
                                      '${TimeUtils.formatShortDate(meta.savedAt)}',
                                      style: base
                                          .merge(tokens.text.meta)
                                          .copyWith(color: colors.textMeta),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 离线查看一个已存话题：和阅读页同一套楼层样式（作者 13 Semibold、楼号和
/// 日期 13 meta、正文 17 / 行高档，发丝线分隔），内容是纯文本。
class SavedTopicViewPage extends StatelessWidget {
  const SavedTopicViewPage({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return FutureBuilder<SavedTopic?>(
      future: SavedTopicStore.load(topicId),
      builder: (context, snapshot) {
        final topic = snapshot.data;
        return Scaffold(
          backgroundColor: colors.surfacePage,
          appBar: AppNavBar(
            showDivider: true,
            title: topic?.meta.title ?? '已存帖子',
          ),
          body: ReadableBody(
            child: snapshot.connectionState != ConnectionState.done
                ? const Center(child: LoadingSpinner())
                : topic == null
                ? const AppStateView(
                    icon: AppIcons.dataError,
                    title: '读取失败或已被删除',
                  )
                : ReadableColumn(
                    child: ListView.builder(
                      itemCount: topic.posts.length,
                      itemBuilder: (context, index) {
                        final post = topic.posts[index];
                        final who = post.name?.isNotEmpty == true
                            ? post.name!
                            : post.username;
                        final date = post.createdAt == null
                            ? ''
                            : '  ${TimeUtils.formatShortDate(post.createdAt!)}';
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: colors.separator,
                                width: AppSpace.hairline,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpace.pageMargin,
                              vertical: tokens.rowPadV,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  who,
                                  style: base
                                      .merge(tokens.text.metaStrong)
                                      .copyWith(color: colors.textPrimary),
                                ),
                                Text(
                                  '#${post.postNumber}$date',
                                  style: base
                                      .merge(tokens.text.meta)
                                      .copyWith(color: colors.textMeta),
                                ),
                                const SizedBox(height: AppSpace.s),
                                SelectableText(
                                  AiTranslationService.extractPlainText(
                                    post.cooked,
                                  ),
                                  style: base
                                      .merge(tokens.text.body)
                                      .copyWith(color: colors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }
}
