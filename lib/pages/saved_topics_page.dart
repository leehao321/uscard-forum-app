import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

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
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
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
      builder: (ctx) => AlertDialog(
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
    final theme = Theme.of(context);
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('已存帖子'),
        actions: [
          if (_all.isNotEmpty)
            IconButton(
              icon: const Icon(Symbols.delete_sweep_rounded),
              tooltip: '清空',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('看过就存'),
            subtitle: const Text('打开并加载过的话题自动保存到本机，不额外联网'),
            value: _enabled,
            onChanged: _toggleEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.search_rounded),
                hintText: '搜索标题和正文',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Center(
                    child: Text(
                      _all.isEmpty ? '还没有保存的话题' : '没有匹配的话题',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final meta = items[index];
                      return Dismissible(
                        key: ValueKey(meta.topicId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: theme.colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(
                            Symbols.delete_rounded,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (_) =>
                            SavedTopicStore.delete(meta.topicId),
                        child: ListTile(
                          title: Text(
                            meta.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${meta.postCount} 个楼层 · 保存于 '
                            '${TimeUtils.formatShortDate(meta.savedAt)}',
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  SavedTopicViewPage(topicId: meta.topicId),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 离线查看一个已存话题（纯文本显示楼层内容）。
class SavedTopicViewPage extends StatelessWidget {
  const SavedTopicViewPage({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<SavedTopic?>(
      future: SavedTopicStore.load(topicId),
      builder: (context, snapshot) {
        final topic = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(topic?.meta.title ?? '已存帖子')),
          body: snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : topic == null
              ? const Center(child: Text('读取失败或已被删除'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: topic.posts.length,
                  separatorBuilder: (_, _) => const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final post = topic.posts[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${post.postNumber}  ${post.name?.isNotEmpty == true ? post.name : post.username}'
                          '${post.createdAt == null ? '' : '  ·  ${TimeUtils.formatShortDate(post.createdAt!)}'}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          AiTranslationService.extractPlainText(post.cooked),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
