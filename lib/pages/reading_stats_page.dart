import 'package:flutter/material.dart';

import '../storage/reading_stats_store.dart';

/// 阅读统计：今天、最近 7 天和 30 天的阅读时长与话题数，数据只在本机。
class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  List<ReadingDay> _days = const [];
  int _streak = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ReadingStatsStore.instance;
    await store.flush();
    final days = await store.recent(30);
    final streak = await store.streak();
    if (!mounted) return;
    setState(() {
      _days = days;
      _streak = streak;
      _loading = false;
    });
  }

  static String _fmt(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return d.inSeconds > 0 ? '不到 1 分钟' : '0 分钟';
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('阅读统计')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final today = _days.last;
    final week = _days.sublist(_days.length - 7);
    Duration sum(Iterable<ReadingDay> ds) =>
        ds.fold(Duration.zero, (a, d) => a + d.duration);
    Set<int> topics(Iterable<ReadingDay> ds) =>
        {for (final d in ds) ...d.topics};
    final weekTotal = sum(week);
    final monthTotal = sum(_days);
    final activeDays = _days.where((d) => d.millis >= 60 * 1000).length;
    final maxMs = week.fold<int>(1, (m, d) => d.millis > m ? d.millis : m);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    stat('今天', _fmt(today.duration)),
                    stat('今天读过', '${today.topics.length} 个话题'),
                    stat('连续阅读', '$_streak 天'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最近 7 天', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in week)
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    d.millis >= 60 * 1000
                                        ? '${d.duration.inMinutes}'
                                        : '',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 18,
                                    height: 4 + 96 * d.millis / maxMs,
                                    decoration: BoxDecoration(
                                      color: d == today
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.primary
                                                .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    weekdays[d.date.weekday - 1],
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: muted),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '共 ${_fmt(weekTotal)}，读过 ${topics(week).length} 个话题（柱上数字为分钟）',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    stat('30 天合计', _fmt(monthTotal)),
                    stat('读过话题', '${topics(_days).length}'),
                    stat(
                      '日均',
                      _fmt(Duration(milliseconds: monthTotal.inMilliseconds ~/ 30)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '统计的是话题页里实际停留阅读的时间（三分钟不滚动会暂停计时），'
              '30 天里有 $activeDays 天读了至少 1 分钟。数据只保存在本机，最多保留 '
              '${ReadingStatsStore.keepDays} 天。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
