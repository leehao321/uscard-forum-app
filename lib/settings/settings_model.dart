import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置项分组
class SettingsGroup {
  final String title;
  final IconData icon;
  final List<SettingsModel> items;

  /// 是否用 Card 包裹 items，默认 true。
  /// 对于自定义布局的 section（如主题色网格、图标选择器），设为 false。
  final bool wrapInCard;

  /// 组页脚（13 meta）：原来塞在行副标题里的长说明放这里
  final String? footer;

  /// 组页眉右侧的文字按钮（如微调的「恢复默认」）
  final Widget? headerAction;

  const SettingsGroup({
    required this.title,
    required this.icon,
    required this.items,
    this.wrapInCard = true,
    this.footer,
    this.headerAction,
  });
}

/// 设置项基类（sealed）
sealed class SettingsModel {
  /// 唯一标识，用于搜索定位高亮
  final String id;

  /// 搜索标题
  final String title;

  /// 搜索副标题
  final String? subtitle;

  const SettingsModel({
    required this.id,
    required this.title,
    this.subtitle,
  });

  /// 搜索匹配
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        (subtitle?.toLowerCase().contains(q) ?? false);
  }

  /// 分组渲染前的可见性判断。
  ///
  /// 分段卡片组（SegmentedCardGroup）按位置决定首尾大圆角，隐藏项必须在
  /// 组装 children 前过滤掉——否则隐藏项以零高占位占走组尾位置，可见的
  /// 最后一项拿不到大圆角。默认恒可见。
  bool isVisible(WidgetRef ref) => true;

  /// 去掉副标题的副本（v2：行内只留一句话，长说明收进组页脚）。
  /// 没有副标题或不是简单行的类型原样返回。
  SettingsModel withoutSubtitle() => this;
}

/// 布尔开关
final class SwitchModel extends SettingsModel {
  final IconData icon;
  final bool Function(WidgetRef ref) getValue;
  final void Function(WidgetRef ref, bool value) onChanged;

  /// 依赖前置开关:返回 false 时本项整行隐藏(如「即时渲染」依赖
  /// 「富文本编辑器」开启才有意义,前置关闭时展示无意义)。null = 恒显示。
  final bool Function(WidgetRef ref)? enabledWhen;

  /// 动态副标题:需要根据运行时状态变化时使用(如渲染兼容模式在
  /// 检测到崩溃后追加「建议开启」)。返回非 null 时覆盖 [subtitle];
  /// 不提供时行为与以前完全一致。
  final String? Function(WidgetRef ref)? subtitleBuilder;

  const SwitchModel({
    required super.id,
    required super.title,
    super.subtitle,
    required this.icon,
    required this.getValue,
    required this.onChanged,
    this.enabledWhen,
    this.subtitleBuilder,
  });

  @override
  bool isVisible(WidgetRef ref) => enabledWhen?.call(ref) ?? true;

  @override
  SettingsModel withoutSubtitle() => SwitchModel(
    id: id,
    title: title,
    icon: icon,
    getValue: getValue,
    onChanged: onChanged,
    enabledWhen: enabledWhen,
  );
}

/// 浮点滑块（字体缩放等）
final class DoubleSliderModel extends SettingsModel {
  final IconData icon;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) labelBuilder;
  final double Function(WidgetRef ref) getValue;
  final void Function(WidgetRef ref, double value) onChanged;
  final void Function(WidgetRef ref)? onReset;

  const DoubleSliderModel({
    required super.id,
    required super.title,
    super.subtitle,
    required this.icon,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.getValue,
    required this.onChanged,
    this.onReset,
  });
}

/// 整数滑块（速率限制等）
final class IntSliderModel extends SettingsModel {
  final IconData icon;
  final int min;
  final int max;
  final String? valueSuffix;
  final int Function(WidgetRef ref) getValue;
  final void Function(WidgetRef ref, int value) onChanged;

  const IntSliderModel({
    required super.id,
    required super.title,
    super.subtitle,
    required this.icon,
    required this.min,
    required this.max,
    this.valueSuffix,
    required this.getValue,
    required this.onChanged,
  });
}

/// 点击项（导航/弹出 Dialog）
final class ActionModel extends SettingsModel {
  final IconData icon;

  /// 是否允许副标题按内容自然换行。
  ///
  /// 默认单行截断——[getDynamicSubtitle] 常用来显示当前值（URL、计数），
  /// 那类内容换行反而撑乱列表。只有静态说明文字长到一行放不下时才开。
  final bool wrapSubtitle;

  /// 动态副标题（如当前 URL）
  final String? Function(WidgetRef ref)? getDynamicSubtitle;

  /// 行右侧的当前值（13 meta，如「默认」「已开启」「286 MB」）；null 不显示
  final String? Function(WidgetRef ref)? valueBuilder;

  final void Function(BuildContext context, WidgetRef ref) onTap;

  const ActionModel({
    required super.id,
    required super.title,
    super.subtitle,
    required this.icon,
    this.wrapSubtitle = false,
    this.getDynamicSubtitle,
    this.valueBuilder,
    required this.onTap,
  });

  @override
  SettingsModel withoutSubtitle() => ActionModel(
    id: id,
    title: title,
    icon: icon,
    wrapSubtitle: wrapSubtitle,
    getDynamicSubtitle: null,
    valueBuilder: valueBuilder ?? getDynamicSubtitle,
    onTap: onTap,
  );
}

/// 自定义 Widget（复杂 UI）
final class CustomModel extends SettingsModel {
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  const CustomModel({
    required super.id,
    required super.title,
    super.subtitle,
    required this.builder,
  });
}

/// 平台条件包装
final class PlatformConditionalModel extends SettingsModel {
  final SettingsModel inner;
  final bool Function() condition;

  PlatformConditionalModel({
    required this.inner,
    required this.condition,
  }) : super(id: inner.id, title: inner.title, subtitle: inner.subtitle);

  bool get shouldShow => condition();

  @override
  bool isVisible(WidgetRef ref) => shouldShow && inner.isVisible(ref);
}

/// 把组内各行的副标题收进组页脚（0.4.0 v2：行内一句话，长说明放页脚）。
///
/// 行文案「标题：说明」逐行写进页脚；没有副标题的行不动。搜索索引用原始
/// 声明（副标题仍可被搜到），只有页面渲染时才收。
List<SettingsGroup> footerizeSubtitles(List<SettingsGroup> groups) {
  return [
    for (final g in groups)
      () {
        if (g.footer != null) return g;
        final notes = <String>[];
        final items = <SettingsModel>[];
        for (final item in g.items) {
          final inner = item is PlatformConditionalModel ? item.inner : item;
          final sub = inner.subtitle;
          if (sub != null && sub.isNotEmpty && inner is! CustomModel) {
            notes.add('${inner.title}：$sub');
            final stripped = inner.withoutSubtitle();
            items.add(
              item is PlatformConditionalModel
                  ? PlatformConditionalModel(
                      inner: stripped,
                      condition: item.condition,
                    )
                  : stripped,
            );
          } else {
            items.add(item);
          }
        }
        if (notes.isEmpty) return g;
        return SettingsGroup(
          title: g.title,
          icon: g.icon,
          items: items,
          wrapInCard: g.wrapInCard,
          headerAction: g.headerAction,
          footer: notes.join('\n'),
        );
      }(),
  ];
}
