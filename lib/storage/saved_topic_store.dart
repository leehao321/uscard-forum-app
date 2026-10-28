import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「看过就存」里保存的单个楼层（只留离线阅读需要的字段）。
class SavedPost {
  const SavedPost({
    required this.postId,
    required this.postNumber,
    required this.username,
    required this.cooked,
    this.name,
    this.createdAt,
  });

  final int postId;
  final int postNumber;
  final String username;
  final String? name;

  /// 楼层正文 HTML（Discourse 渲染后的 cooked）
  final String cooked;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': postId,
    'n': postNumber,
    'u': username,
    if (name != null) 'name': name,
    'c': cooked,
    if (createdAt != null) 't': createdAt!.toUtc().toIso8601String(),
  };

  factory SavedPost.fromJson(Map<String, dynamic> json) => SavedPost(
    postId: json['id'] as int? ?? 0,
    postNumber: json['n'] as int? ?? 0,
    username: json['u'] as String? ?? '',
    name: json['name'] as String?,
    cooked: json['c'] as String? ?? '',
    createdAt: DateTime.tryParse(json['t'] as String? ?? '')?.toLocal(),
  );
}

/// 列表页用的话题摘要（不含正文）。
class SavedTopicMeta {
  const SavedTopicMeta({
    required this.topicId,
    required this.title,
    required this.postCount,
    required this.savedAt,
    this.slug,
    this.searchText = '',
  });

  final int topicId;
  final String title;
  final String? slug;
  final int postCount;
  final DateTime savedAt;

  /// 小写后的全文检索文本（标题 + 各楼层纯文本的前若干字符）
  final String searchText;

  Map<String, dynamic> toJson() => {
    'id': topicId,
    'title': title,
    if (slug != null) 'slug': slug,
    'count': postCount,
    'savedAt': savedAt.toUtc().toIso8601String(),
    's': searchText,
  };

  factory SavedTopicMeta.fromJson(Map<String, dynamic> json) => SavedTopicMeta(
    topicId: json['id'] as int? ?? 0,
    title: json['title'] as String? ?? '',
    slug: json['slug'] as String?,
    postCount: json['count'] as int? ?? 0,
    savedAt:
        DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    searchText: json['s'] as String? ?? '',
  );
}

/// 完整的已保存话题。
class SavedTopic {
  const SavedTopic({required this.meta, required this.posts});

  final SavedTopicMeta meta;
  final List<SavedPost> posts;
}

/// 「看过就存」本地存储。
///
/// 只保存用户在 App 里打开并加载出来的话题内容：不额外联网，也不批量抓取。
/// 每个话题一个 JSON 文件，外加一个 index.json 供列表和搜索使用，
/// 存放在应用私有目录 `saved_topics/` 下。再次浏览同一话题时按楼层号合并，
/// 已存的楼层不会丢，新看到的楼层会补进来。
class SavedTopicStore {
  SavedTopicStore._();

  static const String enabledPrefKey = 'saved_topics_enabled';
  static const String _indexName = 'index.json';
  static const int _searchTextPerPost = 400;
  static const int _searchTextMax = 6000;

  /// 测试可注入：替换存储目录。
  @visibleForTesting
  static Directory? debugDirectory;

  /// 列表变化通知（保存 / 删除 / 清空后自增），供页面刷新。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 同一时刻只允许一个写操作，避免 index.json 被并发改坏。
  static Future<void> _writeChain = Future<void>.value();

  static Future<Directory> _dir() async {
    final base = debugDirectory ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'saved_topics'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 是否开启「看过就存」，默认开启。
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledPrefKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPrefKey, value);
  }

  static Future<Map<int, SavedTopicMeta>> _readIndex(Directory dir) async {
    final file = File(p.join(dir.path, _indexName));
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      return {
        for (final item in raw.cast<Map<String, dynamic>>())
          (item['id'] as int): SavedTopicMeta.fromJson(item),
      };
    } catch (e) {
      debugPrint('[SavedTopicStore] 读取索引失败，重建: $e');
      return _rebuildIndex(dir);
    }
  }

  static Future<Map<int, SavedTopicMeta>> _rebuildIndex(Directory dir) async {
    final result = <int, SavedTopicMeta>{};
    await for (final entity in dir.list()) {
      if (entity is! File || p.basename(entity.path) == _indexName) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final meta = SavedTopicMeta.fromJson(
          json['meta'] as Map<String, dynamic>,
        );
        result[meta.topicId] = meta;
      } catch (_) {}
    }
    await _writeIndex(dir, result);
    return result;
  }

  static Future<void> _writeIndex(
    Directory dir,
    Map<int, SavedTopicMeta> index,
  ) async {
    final file = File(p.join(dir.path, _indexName));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(index.values.map((m) => m.toJson()).toList()),
    );
    await tmp.rename(file.path);
  }

  static File _topicFile(Directory dir, int topicId) =>
      File(p.join(dir.path, '$topicId.json'));

  /// 保存（或合并）一个话题。[plainTextOf] 把 cooked HTML 转成纯文本，用于搜索索引。
  static Future<void> save({
    required int topicId,
    required String title,
    String? slug,
    required List<SavedPost> posts,
    required String Function(String cooked) plainTextOf,
  }) {
    final task = _writeChain.then((_) async {
      if (posts.isEmpty) return;
      final dir = await _dir();
      final index = await _readIndex(dir);

      final merged = <int, SavedPost>{};
      final file = _topicFile(dir, topicId);
      if (await file.exists()) {
        try {
          final json =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          for (final item in (json['posts'] as List).cast<Map<String, dynamic>>()) {
            final post = SavedPost.fromJson(item);
            merged[post.postNumber] = post;
          }
        } catch (_) {}
      }
      for (final post in posts) {
        merged[post.postNumber] = post;
      }
      final ordered = merged.values.toList()
        ..sort((a, b) => a.postNumber.compareTo(b.postNumber));

      final searchBuffer = StringBuffer(title.toLowerCase());
      for (final post in ordered) {
        if (searchBuffer.length >= _searchTextMax) break;
        final text = plainTextOf(post.cooked);
        searchBuffer
          ..write(' ')
          ..write(
            (text.length > _searchTextPerPost
                    ? text.substring(0, _searchTextPerPost)
                    : text)
                .toLowerCase(),
          );
      }

      final meta = SavedTopicMeta(
        topicId: topicId,
        title: title,
        slug: slug,
        postCount: ordered.length,
        savedAt: DateTime.now(),
        searchText: searchBuffer.toString(),
      );
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'meta': meta.toJson(),
          'posts': ordered.map((e) => e.toJson()).toList(),
        }),
      );
      await tmp.rename(file.path);
      index[topicId] = meta;
      await _writeIndex(dir, index);
      changes.value++;
    });
    // 写失败只打日志，不阻断后续写入链
    _writeChain = task.catchError((Object e) {
      debugPrint('[SavedTopicStore] 保存失败: $e');
    });
    return _writeChain;
  }

  /// 已保存话题列表，按保存时间倒序。
  static Future<List<SavedTopicMeta>> list() async {
    await _writeChain;
    final dir = await _dir();
    final list = (await _readIndex(dir)).values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  static Future<SavedTopic?> load(int topicId) async {
    await _writeChain;
    final dir = await _dir();
    final file = _topicFile(dir, topicId);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SavedTopic(
        meta: SavedTopicMeta.fromJson(json['meta'] as Map<String, dynamic>),
        posts: (json['posts'] as List)
            .cast<Map<String, dynamic>>()
            .map(SavedPost.fromJson)
            .toList(),
      );
    } catch (e) {
      debugPrint('[SavedTopicStore] 读取话题 $topicId 失败: $e');
      return null;
    }
  }

  static Future<void> delete(int topicId) {
    final task = _writeChain.then((_) async {
      final dir = await _dir();
      final file = _topicFile(dir, topicId);
      if (await file.exists()) await file.delete();
      final index = await _readIndex(dir);
      if (index.remove(topicId) != null) await _writeIndex(dir, index);
      changes.value++;
    });
    _writeChain = task.catchError((Object e) {
      debugPrint('[SavedTopicStore] 删除失败: $e');
    });
    return _writeChain;
  }

  static Future<void> clear() {
    final task = _writeChain.then((_) async {
      final dir = await _dir();
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
      changes.value++;
    });
    _writeChain = task.catchError((Object e) {
      debugPrint('[SavedTopicStore] 清空失败: $e');
    });
    return _writeChain;
  }
}
