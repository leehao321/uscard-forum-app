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

  const ProfileStatsConfig({
    this.enabledStats = const [
      ProfileStatType.daysVisited,
      ProfileStatType.postsReadCount,
      ProfileStatType.likesReceived,
      ProfileStatType.postCount,
    ],
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
    return ProfileStatsConfig(
      // 已移除的统计项（如旧版 connect 数据源独有的项）直接丢弃
      enabledStats: (json['enabledStats'] as List<dynamic>?)
          ?.map((e) => ProfileStatType.values.asNameMap()[e])
          .whereType<ProfileStatType>()
          .toSet()
          .toList() ?? const [
        ProfileStatType.daysVisited,
        ProfileStatType.postsReadCount,
        ProfileStatType.likesReceived,
        ProfileStatType.postCount,
      ],
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
