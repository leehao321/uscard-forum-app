import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 某一天的阅读量
@immutable
class ReadingDay {
  const ReadingDay({
    required this.day,
    required this.date,
    this.millis = 0,
    this.topics = const {},
  });

  /// YYYY-MM-DD（本地日期）
  final String day;

  /// 当天本地零点
  final DateTime date;
  final int millis;
  final Set<int> topics;

  Duration get duration => Duration(milliseconds: millis);
}

/// 阅读统计：话题页停留计时累加到本机，按天保存最近 [keepDays] 天。
///
/// 数据来自话题页已有的阅读计时，不额外请求论坛，也不上传。
class ReadingStatsStore {
  ReadingStatsStore._();

  static final ReadingStatsStore instance = ReadingStatsStore._();

  static const _prefsKey = 'reading_stats_v1';
  static const keepDays = 120;
  static const _saveDelay = Duration(seconds: 15);

  final ValueNotifier<int> changes = ValueNotifier(0);
  final Map<String, int> _millis = {};
  final Map<String, Set<int>> _topics = {};
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw != null) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          json.forEach((day, v) {
            if (v is! Map) return;
            _millis[day] = (_millis[day] ?? 0) + ((v['ms'] as num?)?.toInt() ?? 0);
            _topics.putIfAbsent(day, () => <int>{}).addAll([
              for (final t in (v['t'] as List? ?? const []))
                if (t is int) t,
            ]);
          });
        }
      } catch (e) {
        debugPrint('[ReadingStats] 读取失败: $e');
      }
      _loaded = true;
    }();
  }

  /// 话题页计时每走一格调用一次
  void addReading(int topicId, int millis) {
    if (millis <= 0) return;
    // 单次最多算 5 秒，防止从后台回来时一次性累积很久
    final ms = millis > 5000 ? 5000 : millis;
    final day = dayKey(DateTime.now());
    _millis[day] = (_millis[day] ?? 0) + ms;
    _topics.putIfAbsent(day, () => <int>{}).add(topicId);
    _saveTimer ??= Timer(_saveDelay, _save);
  }

  Future<void> _save() async {
    _saveTimer = null;
    await _ensureLoaded();
    final today = DateTime.now();
    final cutoff = dayKey(today.subtract(const Duration(days: keepDays)));
    _millis.removeWhere((day, _) => day.compareTo(cutoff) < 0);
    _topics.removeWhere((day, _) => day.compareTo(cutoff) < 0);
    final json = {
      for (final day in _millis.keys)
        day: {
          'ms': _millis[day],
          't': [...?_topics[day]],
        },
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(json));
    } catch (e) {
      debugPrint('[ReadingStats] 保存失败: $e');
    }
    changes.value++;
  }

  /// 立刻写入（统计页打开前调用，保证看到最新数据）
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  /// 最近 [days] 天，从早到晚，没有阅读的日子也包含在内
  Future<List<ReadingDay>> recent(int days) async {
    await _ensureLoaded();
    final now = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final date = DateTime(now.year, now.month, now.day - i);
          final key = dayKey(date);
          return ReadingDay(
            day: key,
            date: date,
            millis: _millis[key] ?? 0,
            topics: {...?_topics[key]},
          );
        }(),
    ];
  }

  /// 连续阅读天数（今天没读时从昨天开始算）
  Future<int> streak() async {
    await _ensureLoaded();
    final now = DateTime.now();
    var count = 0;
    var offset = (_millis[dayKey(now)] ?? 0) >= 60 * 1000 ? 0 : 1;
    while (true) {
      final key = dayKey(DateTime(now.year, now.month, now.day - offset));
      if ((_millis[key] ?? 0) < 60 * 1000) break;
      count++;
      offset++;
    }
    return count;
  }

  @visibleForTesting
  void resetForTest() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _millis.clear();
    _topics.clear();
    _loaded = false;
    _loading = null;
  }
}
