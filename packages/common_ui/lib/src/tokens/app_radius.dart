import 'package:flutter/foundation.dart';

import 'appearance_tiers.dart';

/// v2 圆角（设计说明 §6 提议转正），随圆角档 ×0.75 / 1 / 1.25 缩放。
/// 胶囊（[pill]）和 App 图标不随档位变化。
@immutable
class AppRadius {
  const AppRadius({this.factor = 1});

  factory AppRadius.forTier(RadiusTier tier) => AppRadius(factor: tier.factor);

  final double factor;

  /// 半屏顶角、对话框
  double get sheet => 16 * factor;

  /// AI 卡片、分组列表、菜单、预设格、浮起楼层
  double get card => 12 * factor;

  /// 输入框
  double get field => 10 * factor;

  /// 表格外框、缩略图、AI 服务商方块
  double get table => 8 * factor;

  /// 楼主标签、骨架条、统计柱
  double get tag => 4 * factor;

  /// 拖拽条
  double get handle => 3 * factor;

  /// 分类条下划线、时间轴
  double get bar => 2 * factor;

  /// 胶囊与圆形按钮：高度的一半
  static double pill(double height) => height / 2;

  /// App 图标（96 / 64 两种尺寸）
  static const double appIcon96 = 22;
  static const double appIcon64 = 16;

  @override
  bool operator ==(Object other) =>
      other is AppRadius && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;
}
