import 'package:flutter/material.dart';

import '../storage/topic_note_store.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('我的笔记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '搜索标题、笔记和摘录',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _all.isEmpty
                            ? '还没有笔记。在话题页右上角「更多」里选「笔记」就能记录。'
                            : '没有匹配的笔记',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final preview = n.text.trim().isNotEmpty
                          ? n.text.trim()
                          : n.excerpts.first.text;
                      return ListTile(
                        title: Text(
                          n.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${preview.replaceAll('\n', ' ')}\n'
                          '${n.excerpts.length} 条摘录 · '
                          '${TimeUtils.formatRelativeTime(n.updatedAt)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                        isThreeLine: true,
                        onTap: () => showTopicNoteSheet(
                          context,
                          topicId: n.topicId,
                          title: n.title,
                        ),
                        onLongPress: () => _confirmDelete(n),
                        trailing: IconButton(
                          tooltip: '打开话题',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TopicDetailPage(
                                topicId: n.topicId,
                                initialTitle: n.title,
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
    );
  }
}
