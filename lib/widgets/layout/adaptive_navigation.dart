
import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../navigation/nav_action_bus.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/platform_utils.dart';

/// 导航目标项配置
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.iconData = AppIcons.home,
  });

  /// 稳定 id（home / profile / notifications / ...），用于 NavActionBus 定向派发
  /// 以及页面发布滚动进度到 [navScrollProgressProvider]。
  final String id;
  final Widget icon;
  final Widget selectedIcon;
  final String label;

  /// 浮动 Tab 胶囊用的线框图标（侧栏仍用 [icon]）
  final IconData iconData;
}

/// 侧边导航栏组件 (平板/桌面)
/// 支持将最后 N 个导航项固定在底部
class AdaptiveNavigationRail extends StatelessWidget {
  const AdaptiveNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.categoryShortcuts,
    this.extended = false,
    this.leading,
    this.bottomLeading,
    this.topDestinationCount = 0,
    this.bottomDestinationCount = 1,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;
  final Widget? categoryShortcuts;
  final bool extended;
  final Widget? leading;

  /// 底部导航项上方的自定义组件
  final Widget? bottomLeading;

  /// 固定在顶部的导航项数量（从前往后算起）
  final int topDestinationCount;

  /// 固定在底部的导航项数量（从末尾算起）
  final int bottomDestinationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = PlatformUtils.isDesktop;

    final safeTopCount = topDestinationCount.clamp(0, destinations.length);
    final remainingAfterTop = destinations.length - safeTopCount;
    final safeBottomCount = bottomDestinationCount.clamp(0, remainingAfterTop);
    final bottomStartIndex = destinations.length - safeBottomCount;
    final topDestinations = destinations.sublist(0, safeTopCount);
    // 既不在 top 也不在 bottom 的剩余项，渲染在 categoryShortcuts 下方、
    // bottomDestinations 上方（视觉上仍归属"底部分组"，只是排在底部分组之前）。
    // 当 topCount + bottomCount == destinations.length 时为空。
    final extraBottomDestinations = destinations.sublist(
      safeTopCount,
      bottomStartIndex,
    );
    final bottomDestinations = destinations.sublist(bottomStartIndex);

    Widget rail = SafeArea(
      child: SizedBox(
        width: extended ? 180 : 72,
        child: Column(
          children: [
            if (leading != null) ...[leading!, const SizedBox(height: 8)],
            const SizedBox(height: 16),
            // 顶部导航项
            ...topDestinations.asMap().entries.map((entry) {
              final index = entry.key;
              final dest = entry.value;
              final selected = index == selectedIndex;

              return _NavigationRailItem(
                icon: selected
                    ? _ActiveDestinationIcon(
                        dest: dest,
                        defaultIcon: dest.selectedIcon,
                      )
                    : dest.icon,
                label: dest.label,
                selected: selected,
                extended: extended,
                colorScheme: colorScheme,
                onTap: () => onDestinationSelected(index),
              );
            }),
            if (categoryShortcuts != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 4),
                  child: categoryShortcuts!,
                ),
              )
            else
              const Spacer(),
            if (bottomLeading != null) ...[
              bottomLeading!,
              const SizedBox(height: 8),
            ],
            ...extraBottomDestinations.asMap().entries.map((entry) {
              final index = entry.key + safeTopCount;
              final dest = entry.value;
              final selected = index == selectedIndex;

              return _NavigationRailItem(
                icon: selected
                    ? _ActiveDestinationIcon(
                        dest: dest,
                        defaultIcon: dest.selectedIcon,
                      )
                    : dest.icon,
                label: dest.label,
                selected: selected,
                extended: extended,
                colorScheme: colorScheme,
                onTap: () => onDestinationSelected(index),
              );
            }),
            // 底部导航项
            ...bottomDestinations.asMap().entries.map((entry) {
              final index = entry.key + bottomStartIndex;
              final dest = entry.value;
              final selected = index == selectedIndex;

              return _NavigationRailItem(
                icon: selected
                    ? _ActiveDestinationIcon(
                        dest: dest,
                        defaultIcon: dest.selectedIcon,
                      )
                    : dest.icon,
                label: dest.label,
                selected: selected,
                extended: extended,
                colorScheme: colorScheme,
                onTap: () => onDestinationSelected(index),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    // 桌面平台：透明背景让窗口 acrylic 效果透出 + 拖动窗口
    if (isDesktop) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        child: rail,
      );
    }

    return rail;
  }
}

class _NavigationRailItem extends StatelessWidget {
  const _NavigationRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.colorScheme,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final bool extended;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? colorScheme.secondaryContainer
        : Colors.transparent;
    final iconColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: extended
                ? Row(
                    children: [
                      const SizedBox(width: 16),
                      IconTheme(
                        data: IconThemeData(color: iconColor, size: 24),
                        child: icon,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: iconColor,
                            fontWeight: selected
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: IconTheme(
                      data: IconThemeData(color: iconColor, size: 24),
                      child: icon,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 已选中 tab 的动态图标
///
/// 根据 [navScrollProgressProvider] 和用户配置的 [NavTapAction] 决定显示：
/// - 距顶 < 阈值 或 单击动作为 none 或 动作无对应图标 → 显示默认 selectedIcon
/// - 距顶 ≥ [navScrollIconThreshold] → 显示单击动作对应的反馈图标
///
/// 这样用户滚到深处后就能"预览"单击会发生什么，符合 Twitter/Telegram 的交互惯例。
/// 只应放在 NavigationBar 的 selectedIcon 位置（或侧栏 selected 状态下）。
class _ActiveDestinationIcon extends ConsumerWidget {
  const _ActiveDestinationIcon({required this.dest, required this.defaultIcon});

  final AdaptiveDestination dest;
  final Widget defaultIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(navScrollProgressProvider(dest.id));
    final action = ref.watch(
      preferencesProvider.select((p) => p.bottomSingleTapAction),
    );

    final actionIcon = action.icon;
    final showActionIcon =
        progress >= navScrollIconThreshold &&
        action != NavTapAction.none &&
        actionIcon != null;

    final child = showActionIcon
        ? Icon(actionIcon, key: ValueKey('nav-action-${action.name}'))
        : KeyedSubtree(key: const ValueKey('nav-default'), child: defaultIcon);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(anim),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// 悬浮底栏外壳：宽度随入口数量自适应的胶囊，悬浮于内容之上（Scaffold
/// 已 extendBody，内容从胶囊后面透出）。
///
/// 几何全部取自 [_CapsuleMetrics]（对齐 Telegram 双端：iOS
/// `TabBarComponent` / Android `MainTabsActivity` +
/// `BlurredBackgroundProviderImpl.mainTabs`）：
/// - 胶囊高 = item 高 + 内边距 ×2，圆角 = 全高一半（stadium）
/// - 槽宽 = item 高 × [_CapsuleMetrics.slotAspect]：与高绑定，
///   改高时选中 pill 的胖瘦比例不漂移
/// - 左右/底部外边距见 [_CapsuleMetrics.outerMargin] / `bottomMargin`
/// - 最大宽 [_CapsuleMetrics.maxWidth]：宽屏不铺满，居中悬浮
/// - 描边 0.4，上浅下深（模拟玻璃边缘的受光差）
/// - 阴影极柔：blur 24 / 黑 6%，offset (0,2)。TG 的影子几乎不可见
///   （iOS 黑 4%），重影会让胶囊显得「贴纸」而非「悬浮」
///
/// 安全区由外层 SafeArea 统一承担（留白在胶囊之外），内部不再嵌套
/// 任何会消费底部 padding 的组件。

