import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// [SegmentedCardGroup] 的全局外观(ThemeExtension),由宿主按平台注入。
///
/// m3e_ui 不依赖应用,所以平台差异(例如 iOS 的 inset-grouped 分组列表)
/// 通过这个扩展传入:未注册或 [insetGrouped] 为 false 时保持 M3E 分段卡片
/// 原样。
///
/// 注意:light/dark 两个 ThemeData 必须对称注册 —— ThemeData.lerp 对
/// "单边缺失"的 extension 不插值而是瞬时并入。
@immutable
class SegmentedCardGroupStyle extends ThemeExtension<SegmentedCardGroupStyle> {
  /// true 时整组渲染成一个圆角容器,条目间用发丝分隔线,无缝隙。
  final bool insetGrouped;

  /// inset-grouped 容器的圆角。
  final double radius;

  /// 分隔线前缘缩进。
  final double separatorIndent;

  /// 上一行带前导图标（ListTile.leading / SwitchListTile 等的 secondary）时
  /// 分隔线的缩进，对齐行内文字起点；null 时同 [separatorIndent]。
  final double? leadingSeparatorIndent;

  /// 分隔线颜色,null 时取 colorScheme.outlineVariant。
  final Color? separatorColor;

  /// 单元格底色,null 时取 cardTheme.color / surfaceContainerLow。
  /// 调用点显式传 `color` 时以调用点为准。
  final Color? cellColor;

  const SegmentedCardGroupStyle({
    this.insetGrouped = false,
    this.radius = 10,
    this.separatorIndent = 16,
    this.leadingSeparatorIndent,
    this.separatorColor,
    this.cellColor,
  });

  /// 读取当前主题的样式,未注册返回 null。
  static SegmentedCardGroupStyle? maybeOf(BuildContext context) =>
      Theme.of(context).extension<SegmentedCardGroupStyle>();

  /// 当前主题是否启用了 inset-grouped。
  static bool isInsetGrouped(BuildContext context) =>
      maybeOf(context)?.insetGrouped ?? false;

  @override
  SegmentedCardGroupStyle copyWith({
    bool? insetGrouped,
    double? radius,
    double? separatorIndent,
    double? leadingSeparatorIndent,
    Color? separatorColor,
    Color? cellColor,
  }) => SegmentedCardGroupStyle(
    insetGrouped: insetGrouped ?? this.insetGrouped,
    radius: radius ?? this.radius,
    separatorIndent: separatorIndent ?? this.separatorIndent,
    leadingSeparatorIndent:
        leadingSeparatorIndent ?? this.leadingSeparatorIndent,
    separatorColor: separatorColor ?? this.separatorColor,
    cellColor: cellColor ?? this.cellColor,
  );

  @override
  SegmentedCardGroupStyle lerp(
    ThemeExtension<SegmentedCardGroupStyle>? other,
    double t,
  ) {
    if (other is! SegmentedCardGroupStyle) return this;
    return SegmentedCardGroupStyle(
      // bool 无法插值:半程翻转
      insetGrouped: t < 0.5 ? insetGrouped : other.insetGrouped,
      radius: lerpDouble(radius, other.radius, t)!,
      separatorIndent: lerpDouble(separatorIndent, other.separatorIndent, t)!,
      leadingSeparatorIndent: lerpDouble(
        leadingSeparatorIndent,
        other.leadingSeparatorIndent,
        t,
      ),
      separatorColor: Color.lerp(separatorColor, other.separatorColor, t),
      cellColor: Color.lerp(cellColor, other.cellColor, t),
    );
  }

  // ThemeData 每次 build 都是新实例;extension 不可比较会让 AnimatedTheme
  // 在每次 rebuild 时空转一段 lerp 动画。
  @override
  bool operator ==(Object other) =>
      other is SegmentedCardGroupStyle &&
      other.insetGrouped == insetGrouped &&
      other.radius == radius &&
      other.separatorIndent == separatorIndent &&
      other.leadingSeparatorIndent == leadingSeparatorIndent &&
      other.separatorColor == separatorColor &&
      other.cellColor == cellColor;

  @override
  int get hashCode => Object.hash(
    insetGrouped,
    radius,
    separatorIndent,
    leadingSeparatorIndent,
    separatorColor,
    cellColor,
  );
}

/// 行是否带前导图标(列表行的文字因此右移)。
bool _hasLeading(Widget row) => switch (row) {
  ListTile(:final leading) => leading != null,
  SwitchListTile(:final secondary) => secondary != null,
  CheckboxListTile(:final secondary) => secondary != null,
  RadioListTile(:final secondary) => secondary != null,
  _ => false,
};

/// 发丝分隔线:厚度 = 1 物理像素。[above] 是分隔线上方那一行:
/// 带前导图标时缩进到文字起点(iOS 分组列表的规则)。
Widget _hairlineDivider(
  BuildContext context,
  SegmentedCardGroupStyle style,
  double? separatorIndent,
  Widget above,
) {
  final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
  return Divider(
    height: hairline,
    thickness: hairline,
    indent:
        separatorIndent ??
        (_hasLeading(above) ? style.leadingSeparatorIndent : null) ??
        style.separatorIndent,
    endIndent: 0,
    color: style.separatorColor ?? Theme.of(context).colorScheme.outlineVariant,
  );
}

/// 块背景色:调用点显式 color > 样式 cellColor > cardTheme > surfaceContainerLow。
Color _resolveBackground(
  ThemeData theme,
  SegmentedCardGroupStyle? style,
  Color? color,
) =>
    color ??
    style?.cellColor ??
    theme.cardTheme.color ??
    theme.colorScheme.surfaceContainerLow;

/// M3 Expressive 风格分段卡片组
///
/// 参照最新 Material 3 Expressive 列表规范（Chrome / Android 系统设置）：
/// 每个条目独立成块，组首/组尾用大圆角、相邻处用小圆角，块间以细缝分隔，
/// 取代旧式「整卡 + Divider」布局。
///
/// 主题注册了 [SegmentedCardGroupStyle] 且 `insetGrouped` 为 true(iOS)时,
/// 改为 inset-grouped:整组一个圆角容器,条目间发丝分隔线,无缝隙;
/// 此时 [outerRadius]/[innerRadius]/[gap] 不生效。
class SegmentedCardGroup extends StatelessWidget {
  final List<Widget> children;

  /// 组首/组尾的大圆角
  final double outerRadius;

  /// 相邻条目之间的小圆角
  final double innerRadius;

  /// 条目间距
  final double gap;

  /// 块背景色，默认跟随 cardTheme（surfaceContainerLow）
  final Color? color;

  /// inset-grouped 下分隔线的前缘缩进;为 null 时取主题
  /// [SegmentedCardGroupStyle.separatorIndent]。
  final double? separatorIndent;

  const SegmentedCardGroup({
    super.key,
    required this.children,
    this.outerRadius = 20,
    this.innerRadius = 5,
    this.gap = 3,
    this.color,
    this.separatorIndent,
  });

  @override
  Widget build(BuildContext context) {
    final style = SegmentedCardGroupStyle.maybeOf(context);
    if (style != null && style.insetGrouped) {
      return _buildInsetGrouped(context, style);
    }
    return Column(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          SegmentedCardItem(
            index: i,
            count: children.length,
            outerRadius: outerRadius,
            innerRadius: innerRadius,
            color: color,
            child: children[i],
          ),
        ],
      ],
    );
  }

  Widget _buildInsetGrouped(
    BuildContext context,
    SegmentedCardGroupStyle style,
  ) {
    final theme = Theme.of(context);
    return Material(
      color: _resolveBackground(theme, style, color),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: Column(
        // 容器只包住内容:不能像分段形态那样撑满父级给的高度
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              _hairlineDivider(context, style, separatorIndent, children[i - 1]),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 分段卡片组中的单个条目块
///
/// 根据 [index] / [count] 决定上下圆角。供 [SegmentedCardGroup] 内部使用；
/// 懒加载列表（ListView.builder）中也可直接按索引使用。
///
/// inset-grouped 下:仅组首上圆角、组尾下圆角,中间直角,非末项底部带
/// 发丝分隔线。懒加载列表的外部 separator(如 SizedBox)需自行在该模式下
/// 去掉,见 [SegmentedCardGroupStyle.isInsetGrouped]。
class SegmentedCardItem extends StatelessWidget {
  final int index;
  final int count;
  final double outerRadius;
  final double innerRadius;
  final Color? color;
  final Widget child;

  const SegmentedCardItem({
    super.key,
    required this.index,
    required this.count,
    this.outerRadius = 20,
    this.innerRadius = 5,
    this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = SegmentedCardGroupStyle.maybeOf(context);
    final inset = style != null && style.insetGrouped;
    // cellColor 只属于 inset-grouped,分段形态保持原有取色
    final background = _resolveBackground(theme, inset ? style : null, color);

    if (style != null && inset) {
      final radius = Radius.circular(style.radius);
      final isLast = index == count - 1;
      return Material(
        color: background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: index == 0 ? radius : Radius.zero,
            bottom: isLast ? radius : Radius.zero,
          ),
        ),
        child: isLast
            ? child
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  _hairlineDivider(context, style, null, child),
                ],
              ),
      );
    }

    return Material(
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(index == 0 ? outerRadius : innerRadius),
          bottom: Radius.circular(index == count - 1 ? outerRadius : innerRadius),
        ),
      ),
      child: child,
    );
  }
}
