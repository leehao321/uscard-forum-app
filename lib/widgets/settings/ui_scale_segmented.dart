import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 分段控件里的一个选项。
typedef ScaleOption = ({double value, String label});

/// iOS 风格的分段控件：浅色内嵌的圆角轨道，选中项是一块浮起的滑块。
///
/// 没有外框和竖向分隔线。滑块在选项之间滑动；系统关了动画就直接跳过去。
class UiScaleSegmentedControl extends StatelessWidget {
  const UiScaleSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  static const trackPadding = 3.0;
  static const trackRadius = 12.0;
  static const thumbRadius = 9.0;
  static const segmentHeight = 40.0;

  final List<ScaleOption> options;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final selectedIndex = options.indexWhere((o) => o.value == value);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(trackRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(trackPadding),
        child: SizedBox(
          height: segmentHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              final segmentWidth = box.maxWidth / options.length;
              return Stack(
                children: [
                  if (selectedIndex >= 0)
                    AnimatedPositioned(
                      key: const ValueKey('ui-scale-thumb'),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      left: segmentWidth * selectedIndex,
                      width: segmentWidth,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          // 浅色是白色滑块，深色是比轨道亮一档的灰
                          color: dark
                              ? scheme.surfaceContainerHighest
                              : scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(thumbRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: dark ? 0.32 : 0.10,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (final option in options)
                        Expanded(
                          child: _Segment(
                            label: option.label,
                            selected: option.value == value,
                            onTap: () {
                              if (option.value == value) return;
                              HapticFeedback.selectionClick();
                              onChanged(option.value);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          // 4 个选项挤在一行，大字号或窄屏时缩小到放得下，不换行不省略
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
