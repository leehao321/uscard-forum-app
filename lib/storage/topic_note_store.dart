import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帖子里摘出来的一段文字
@immutable
class NoteExcerpt {
  const NoteExcerpt({required this.text, required this.createdAt});

  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'text': text,
    'at': createdAt.millisecondsSinceEpoch,
  };

  factory NoteExcerpt.fromJson(Map<String, dynamic> j) => NoteExcerpt(
    text: j['text'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
  );
}

/// 一个话题的笔记：自由文字 + 摘录
@immutable
class TopicNote {
  const TopicNote({
    required this.topicId,
    required this.title,
    this.text = '',
    this.excerpts = const [],
    required this.updatedAt,
  });

  final int topicId;
  final String title;
  final String text;
  final List<NoteExcerpt> excerpts;
  final DateTime updatedAt;

  bool get isEmpty => text.trim().isEmpty && excerpts.isEmpty;

  /// 搜索用的小写全文
  String get searchText =>
      '$title\n$text\n${excerpts.map((e) => e.text).join('\n')}'.toLowerCase();

  TopicNote copyWith({
    String? title,
    String? text,
    List<NoteExcerpt>? excerpts,
  }) => TopicNote(
    topicId: topicId,
    title: title ?? this.title,
    text: text ?? this.text,
    excerpts: excerpts ?? this.excerpts,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': topicId,
    'title': title,
    'text': text,
    'excerpts': [for (final e in excerpts) e.toJson()],
    'updated': updatedAt.millisecondsSinceEpoch,
  };

  factory TopicNote.fromJson(Map<String, dynamic> j) => TopicNote(
    topicId: j['id'] as int? ?? 0,
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    excerpts: [
      for (final e in (j['excerpts'] as List? ?? const []))
        if (e is Map<String, dynamic>) NoteExcerpt.fromJson(e),
    ],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updated'] as int? ?? 0),
  );
}

/// 话题笔记的本机存储，不同步到论坛。
class TopicNoteStore {
  TopicNoteStore._();

  static const _prefsKey = 'topic_notes_v1';
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<Map<int, TopicNote>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return {
        for (final e in list)
          if (e is Map<String, dynamic>)
            (e['id'] as int? ?? 0): TopicNote.fromJson(e),
      }..remove(0);
    } catch (e) {
      debugPrint('[TopicNoteStore] 读取失败: $e');
      return {};
    }
  }

  static Future<void> _writeAll(Map<int, TopicNote> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final n in all.values) n.toJson()]),
    );
    changes.value++;
  }

  /// 全部笔记，最近修改的在前
  static Future<List<TopicNote>> list() async {
    final all = await _readAll();
    return all.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<TopicNote?> get(int topicId) async =>
      (await _readAll())[topicId];

  /// 保存；内容为空时删除
  static Future<void> save(TopicNote note) async {
    final all = await _readAll();
    if (note.isEmpty) {
      all.remove(note.topicId);
    } else {
      all[note.topicId] = note;
    }
    await _writeAll(all);
  }

  static Future<void> delete(int topicId) async {
    final all = await _readAll();
    if (all.remove(topicId) != null) await _writeAll(all);
  }
}
