import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/profile_stats_config.dart';

void main() {
  group('ProfileStatsConfig.fromJson', () {
    test('toJson 往返保持一致', () {
      const config = ProfileStatsConfig(
        enabledStats: [ProfileStatType.timeRead, ProfileStatType.likesGiven],
        layoutMode: StatsLayoutMode.scroll,
        columnsPerRow: 3,
      );

      final parsed = ProfileStatsConfig.fromJsonString(config.toJsonString());

      expect(parsed.enabledStats, config.enabledStats);
      expect(parsed.layoutMode, StatsLayoutMode.scroll);
      expect(parsed.columnsPerRow, 3);
    });

    test('旧版 connect 独有的统计项被丢弃，其余按原顺序去重保留', () {
      final parsed = ProfileStatsConfig.fromJson({
        'enabledStats': [
          'daysVisited',
          'topicsRepliedTo',
          'daysVisited',
          'likesReceivedUsers',
          'postCount',
        ],
        // 旧版的数据源字段不再识别，忽略即可
        'dataSource': 'connect',
      });

      expect(parsed.enabledStats, [
        ProfileStatType.daysVisited,
        ProfileStatType.postCount,
      ]);
    });

    test('只选了已移除统计项的旧配置回落默认值，不让卡片变空', () {
      final parsed = ProfileStatsConfig.fromJson({
        'enabledStats': ['topicsRepliedTo', 'likesReceivedDays'],
        'dataSource': 'connect',
      });

      expect(parsed.enabledStats, ProfileStatsConfig.defaultStats);
    });

    test('用户主动清空的空列表保留，缺字段时用默认值', () {
      expect(
        ProfileStatsConfig.fromJson({'enabledStats': <String>[]}).enabledStats,
        isEmpty,
      );
      expect(
        ProfileStatsConfig.fromJson(const {}).enabledStats,
        ProfileStatsConfig.defaultStats,
      );
    });
  });
}
