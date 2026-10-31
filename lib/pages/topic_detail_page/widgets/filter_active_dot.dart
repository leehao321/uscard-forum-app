import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// ⋮ 菜单按钮右上角的小点：阅读页的筛选（只看楼主 / 热门回复 / 只看顶层 /
/// 嵌套视图）开着时亮起，页面上看得出现在不是完整楼层。
class FilterActiveDot extends StatelessWidget {
  const FilterActiveDot({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 8,
          top: 8,
          child: IgnorePointer(
            child: UnreadDot(
              key: const ValueKey('filter-active-dot'),
              color: context.tokens.colors.brandPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
