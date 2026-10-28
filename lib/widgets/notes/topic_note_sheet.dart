import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/toast_service.dart';
import '../../storage/topic_note_store.dart';
import '../../utils/time_utils.dart';

/// 打开某个话题的笔记：自由文字 + 摘录，只存在本机。
Future<void> showTopicNoteSheet(
  BuildContext context, {
  required int topicId,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TopicNoteSheet(topicId: topicId, title: title),
  );
}

class _TopicNoteSheet extends StatefulWidget {
  const _TopicNoteSheet({required this.topicId, required this.title});

  final int topicId;
  final String title;

  @override
  State<_TopicNoteSheet> createState() => _TopicNoteSheetState();
}

class _TopicNoteSheetState extends State<_TopicNoteSheet>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  List<NoteExcerpt> _excerpts = [];
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TopicNoteStore.get(widget.topicId).then((note) {
      if (!mounted) return;
      _text.text = note?.text ?? '';
      // 读完再挂监听，填入旧内容不算改动
      _text.addListener(_scheduleSave);
      setState(() {
        _excerpts = [...?note?.excerpts];
        _loaded = true;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台可能被系统回收，不会走 dispose：离开前台就先存
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _saveNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 关闭时自动保存，不需要单独的保存按钮
    _saveNow();
    _text.dispose();
    super.dispose();
  }

  /// 停笔 1 秒后自动保存
  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded || !_dirty) return;
    _dirty = false;
    unawaited(
      TopicNoteStore.save(
        TopicNote(
          topicId: widget.topicId,
          title: widget.title,
          text: _text.text,
          excerpts: List.of(_excerpts),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _pasteExcerpt() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ToastService.showError('剪贴板里没有文字，先在帖子里选中文字并复制');
      return;
    }
    if (_excerpts.any((e) => e.text == text)) {
      ToastService.showError('这段已经摘录过了');
      return;
    }
    setState(() {
      _excerpts.insert(0, NoteExcerpt(text: text, createdAt: DateTime.now()));
    });
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('笔记', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else ...[
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText: '写点什么，只保存在这台设备上',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('摘录', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pasteExcerpt,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('粘贴为摘录'),
                  ),
                ],
              ),
              if (_excerpts.isEmpty)
                Text(
                  '在帖子里长按选中文字，点「复制」，再回到这里点「粘贴为摘录」。',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              for (final e in _excerpts)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(e.text),
                              const SizedBox(height: 4),
                              Text(
                                TimeUtils.formatShortDate(e.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '删除摘录',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            setState(() => _excerpts.remove(e));
                            _scheduleSave();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
