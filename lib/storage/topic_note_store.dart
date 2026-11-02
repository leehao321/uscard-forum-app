import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/site_context.dart';

/// 帖子里摘出来的一段文字
@immutable
class NoteExcerpt {
  const NoteExcerpt({
    required this.text,
    required this.createdAt,
    this.postNumber,
  });

  final String text;
  final DateTime createdAt;

  /// 摘自第几楼（v2 起记录；v1 迁移来的摘录没有）
  final int? postNumber;

  Map<String, dynamic> toJson() => {
    'text': text,
    'at': createdAt.millisecondsSinceEpoch,
    if (postNumber != null) 'post': postNumber,
  };

  factory NoteExcerpt.fromJson(Map<String, dynamic> j) => NoteExcerpt(
    text: j['text'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
    postNumber: j['post'] as int?,
  );
}

/// 一个话题的笔记：话题级自由文字 + 按楼层的笔记（v2）+ 摘录
@immutable
class TopicNote {
  const TopicNote({
    required this.topicId,
    required this.title,
    this.text = '',
    this.excerpts = const [],
    this.floorNotes = const {},
    required this.updatedAt,
  });

  final int topicId;
  final String title;
  final String text;
  final List<NoteExcerpt> excerpts;

  /// 按楼层的笔记：楼层号 → 文字（v2）
  final Map<int, String> floorNotes;
  final DateTime updatedAt;

  bool get isEmpty =>
      text.trim().isEmpty &&
      excerpts.isEmpty &&
      floorNotes.values.every((t) => t.trim().isEmpty);

  /// 搜索用的小写全文
  String get searchText =>
      '$title\n$text\n${floorNotes.values.join('\n')}\n'
              '${excerpts.map((e) => e.text).join('\n')}'
          .toLowerCase();

  /// 有笔记的楼层，从小到大
  List<int> get floors =>
      floorNotes.entries
          .where((e) => e.value.trim().isNotEmpty)
          .map((e) => e.key)
          .toList()
        ..sort();

  TopicNote copyWith({
    String? title,
    String? text,
    List<NoteExcerpt>? excerpts,
    Map<int, String>? floorNotes,
  }) => TopicNote(
    topicId: topicId,
    title: title ?? this.title,
    text: text ?? this.text,
    excerpts: excerpts ?? this.excerpts,
    floorNotes: floorNotes ?? this.floorNotes,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': topicId,
    'title': title,
    'text': text,
    'excerpts': [for (final e in excerpts) e.toJson()],
    if (floorNotes.isNotEmpty)
      'floors': {for (final e in floorNotes.entries) '${e.key}': e.value},
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
    floorNotes: {
      for (final e in (j['floors'] as Map? ?? const {}).entries)
        if (int.tryParse('${e.key}') != null && e.value is String)
          int.parse('${e.key}'): e.value as String,
    },
    updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updated'] as int? ?? 0),
  );
}

/// 话题笔记的本机存储，不同步到论坛。
///
/// v2（0.4.0）：存 `topic_notes_v2`，格式 `{"v":2,"notes":[...]}`，笔记可以
/// 挂在某一楼上。第一次读 v2 时若还没有，就把 v1 迁过来；v1 的键原样保留
/// （回退到旧版本时笔记还在），迁移之后只读写 v2。
class TopicNoteStore {
  TopicNoteStore._();

  static String get _prefsKey => SiteContext.scopedKey('topic_notes_v2');
  static String get _legacyKey => SiteContext.scopedKey('topic_notes_v1');
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static List<TopicNote> _decode(Object? decoded) {
    final list = decoded is Map ? decoded['notes'] : decoded;
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) TopicNote.fromJson(e),
    ];
  }

  static Future<Map<int, TopicNote>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_prefsKey);
    var migrating = false;
    if (raw == null || raw.isEmpty) {
      raw = prefs.getString(_legacyKey);
      migrating = true;
    }
    if (raw == null || raw.isEmpty) return {};
    try {
      final all = {
        for (final n in _decode(jsonDecode(raw)))
          if (n.topicId != 0) n.topicId: n,
      };
      if (migrating && all.isNotEmpty) {
        await prefs.setString(_prefsKey, _encode(all));
      }
      return all;
    } catch (e) {
      debugPrint('[TopicNoteStore] 读取失败: $e');
      return {};
    }
  }

  static String _encode(Map<int, TopicNote> all) => jsonEncode({
    'v': 2,
    'notes': [for (final n in all.values) n.toJson()],
  });

  static Future<void> _writeAll(Map<int, TopicNote> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(all));
    changes.value++;
  }

  /// 导入 0.3.x 备份后把 v1 笔记并进 v2（M-1）。
  ///
  /// [_readAll] 只在 v2 还没有时才迁 v1；本机已经写过 0.4.0 笔记再导入旧备份时，
  /// 备份里的 v1 会被整个忽略。这里按话题合并：只在 v1 里有的话题直接加入；
  /// 两边都有的话题保留 v2 的话题文字和楼层笔记，话题文字为空时用 v1 的，
  /// 摘录取并集（文字相同的算同一条）。
  static Future<void> mergeLegacyFromPrefs(SharedPreferences prefs) async {
    final rawV1 = prefs.getString(_legacyKey);
    if (rawV1 == null || rawV1.isEmpty) return;
    final rawV2 = prefs.getString(_prefsKey);
    if (rawV2 == null || rawV2.isEmpty) {
      // 本机没有 v2：照常读一次，读取时会自动迁移
      await _readAll();
      changes.value++;
      return;
    }
    try {
      final legacy = {
        for (final n in _decode(jsonDecode(rawV1)))
          if (n.topicId != 0) n.topicId: n,
      };
      final all = await _readAll();
      var changed = false;
      for (final old in legacy.values) {
        final cur = all[old.topicId];
        if (cur == null) {
          all[old.topicId] = old;
          changed = true;
          continue;
        }
        final seen = {for (final e in cur.excerpts) e.text};
        final extra = [
          for (final e in old.excerpts)
            if (!seen.contains(e.text)) e,
        ];
        final useOldText = cur.text.trim().isEmpty && old.text.trim().isNotEmpty;
        if (extra.isEmpty && !useOldText) continue;
        all[old.topicId] = TopicNote(
          topicId: cur.topicId,
          title: cur.title,
          text: useOldText ? old.text : cur.text,
          excerpts: [...cur.excerpts, ...extra],
          floorNotes: cur.floorNotes,
          updatedAt: cur.updatedAt.isAfter(old.updatedAt)
              ? cur.updatedAt
              : old.updatedAt,
        );
        changed = true;
      }
      if (changed) await _writeAll(all);
    } catch (e) {
      debugPrint('[TopicNoteStore] 合并旧版笔记失败: $e');
    }
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
