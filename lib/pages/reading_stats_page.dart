import 'package:common_ui/common_ui.dart';
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
    final tokens = context.tokens;
    final colors = tokens.colors;
    final meta = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final caption = theme.textTheme.labelSmall!
        .merge(tokens.text.caption)
        .copyWith(color: colors.textMeta);
    if (_loading) {
      return Scaffold(
        backgroundColor: colors.surfacePage,
        body: ReadableBody(
          child: const SafeArea(
            child: Column(
              children: [
                AppNavBar(title: '阅读统计'),
                Expanded(
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final today = _days.last;
    final week = _days.sublist(_days.length - 7);
    Duration sum(Iterable<ReadingDay> ds) =>
        ds.fold(Duration.zero, (a, d) => a + d.duration);
    Set<int> topics(Iterable<ReadingDay> ds) => {
      for (final d in ds) ...d.topics,
    };
    final weekTotal = sum(week);
    final monthTotal = sum(_days);
    final activeDays = _days.where((d) => d.millis >= 60 * 1000).length;
    final maxMs = week.fold<int>(1, (m, d) => d.millis > m ? d.millis : m);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.merge(tokens.text.control)
                .copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(label, style: meta),
        ],
      ),
    );

    Widget card(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.l),
      decoration: BoxDecoration(
        color: colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: child,
    );

    // 柱：今天 brand，其余 avatar/fill（设计说明 §5.3）
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: ReadableBody(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppNavBar(title: '阅读统计'),
              Expanded(
                child: RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.pageMargin,
                      AppSpace.m,
                      AppSpace.pageMargin,
                      AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      card(
                        Row(
                          children: [
                            stat('今天', _fmt(today.duration)),
                            stat('今天读过', '${today.topics.length} 个话题'),
                            stat('连续阅读', '$_streak 天'),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.m),
                      card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '最近 7 天',
                              style: theme.textTheme.bodyMedium
                                  ?.merge(tokens.text.metaStrong)
                                  .copyWith(color: colors.textPrimary),
                            ),
                            const SizedBox(height: AppSpace.m),
                            SizedBox(
                              // 数字 + 柱（最高 100）+ 星期，系统字号调大时柱子自己让出空间
                              height: 150,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (final d in week)
                                    Expanded(
                                      child: Semantics(
                                        label:
                                            '${d == today ? '今天' : '星期${weekdays[d.date.weekday - 1]}'}，${_fmt(d.duration)}',
                                        excludeSemantics: true,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              d.millis >= 60 * 1000
                                                  ? '${d.duration.inMinutes}'
                                                  : '',
                                              style: caption,
                                            ),
                                            const SizedBox(height: AppSpace.xs),
                                            Flexible(
                                              child: Container(
                                                width: 24,
                                                height:
                                                    4 + 96 * d.millis / maxMs,
                                                decoration: BoxDecoration(
                                                  color: d == today
                                                      ? colors.brandPrimary
                                                      : colors.avatarFill,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        tokens.radius.tag,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: AppSpace.xs),
                                            Text(
                                              d == today
                                                  ? '今天'
                                                  : weekdays[d.date.weekday -
                                                        1],
                                              style: d == today
                                                  ? caption.copyWith(
                                                      color:
                                                          colors.brandPrimary,
                                                    )
                                                  : caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpace.s),
                            Text(
                              '共 ${_fmt(weekTotal)}，读过 ${topics(week).length} 个话题（柱上数字为分钟）',
                              style: meta,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.m),
                      card(
                        Row(
                          children: [
                            stat('30 天合计', _fmt(monthTotal)),
                            stat('读过话题', '${topics(_days).length}'),
                            stat(
                              '日均',
                              _fmt(
                                Duration(
                                  milliseconds: monthTotal.inMilliseconds ~/ 30,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.m),
                      Text(
                        '统计的是话题页里实际停留阅读的时间（三分钟不滚动会暂停计时），'
                        '30 天里有 $activeDays 天读了至少 1 分钟。数据只保存在本机，最多保留 '
                        '${ReadingStatsStore.keepDays} 天。',
                        style: meta,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
