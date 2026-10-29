import 'dart:convert';

/// 统计项类型（均来自 Summary API）
enum ProfileStatType {
  daysVisited,
  postsReadCount,
  likesReceived,
  likesGiven,
  topicCount,
  postCount,
  timeRead,
  recentTimeRead,
  bookmarkCount,
  topicsEntered,
}

/// 布局模式
enum StatsLayoutMode { grid, scroll }

/// 统计卡片配置
class ProfileStatsConfig {
  final List<ProfileStatType> enabledStats;
  final StatsLayoutMode layoutMode;
  final int columnsPerRow; // 网格模式 2/3/4

  /// 默认展示的统计项
  static const List<ProfileStatType> defaultStats = [
    ProfileStatType.daysVisited,
    ProfileStatType.postsReadCount,
    ProfileStatType.likesReceived,
    ProfileStatType.postCount,
  ];

  const ProfileStatsConfig({
    this.enabledStats = defaultStats,
    this.layoutMode = StatsLayoutMode.grid,
    this.columnsPerRow = 4,
  });

  ProfileStatsConfig copyWith({
    List<ProfileStatType>? enabledStats,
    StatsLayoutMode? layoutMode,
    int? columnsPerRow,
  }) {
    return ProfileStatsConfig(
      enabledStats: enabledStats ?? this.enabledStats,
      layoutMode: layoutMode ?? this.layoutMode,
      columnsPerRow: columnsPerRow ?? this.columnsPerRow,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledStats': enabledStats.map((e) => e.name).toList(),
    'layoutMode': layoutMode.name,
    'columnsPerRow': columnsPerRow,
  };

  factory ProfileStatsConfig.fromJson(Map<String, dynamic> json) {
    final rawStats = json['enabledStats'] as List<dynamic>?;
    // 已移除的统计项（如旧版 connect 数据源独有的项）直接丢弃并去重
    final stats = rawStats
        ?.map((e) => ProfileStatType.values.asNameMap()[e])
        .whereType<ProfileStatType>()
        .toSet()
        .toList();
    return ProfileStatsConfig(
      // 原来有内容却全被丢弃时回落默认值，免得升级后卡片变空；
      // 用户自己清空保存的空列表照常保留
      enabledStats: stats == null || (stats.isEmpty && rawStats!.isNotEmpty)
          ? defaultStats
          : stats,
      layoutMode: StatsLayoutMode.values.firstWhere(
        (v) => v.name == json['layoutMode'],
        orElse: () => StatsLayoutMode.grid,
      ),
      columnsPerRow: json['columnsPerRow'] as int? ?? 4,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ProfileStatsConfig.fromJsonString(String jsonStr) {
    return ProfileStatsConfig.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }
}
