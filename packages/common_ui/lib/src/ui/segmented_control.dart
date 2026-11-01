import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// [AppSegmentedControl] 的一个选项
@immutable
class AppSegment<T> {
  const AppSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// v2 分段控件（Figma「导出文章 · 半屏」的导出范围 / 文件格式）：
/// 轨道 surface/elevated、圆角 10、内边距 4；选中的滑块 surface/page、圆角 8，
/// 文字 13（选中 Semibold text/primary，未选 Regular text/meta）。
///
/// 轨道视觉高 40，点击区撑到 44（上下各 2 透明热区，不改变布局）。
/// 选项宽度均分。[onChanged] 为 null 时整体禁用。
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  }) : assert(segments.length >= 2);

  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  /// 整个控件的无障碍标签（如「导出范围」）
  final String? semanticLabel;

  /// 轨道视觉高度
  static const double trackHeight = 40;

  static const double _inset = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final selectedIndex = segments.indexWhere((s) => s.value == value);
    final n = segments.length;
    final enabled = onChanged != null;

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          height: AppSize.hit,
          child: Stack(
            children: [
              // 轨道 + 滑块（视觉 40 高，上下各留 2）
              Positioned.fill(
                top: (AppSize.hit - trackHeight) / 2,
                bottom: (AppSize.hit - trackHeight) / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radius.field),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(_inset),
                    child: selectedIndex < 0
                        ? null
                        : AnimatedAlign(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            alignment: Alignment(
                              n == 1 ? 0 : -1 + 2 * selectedIndex / (n - 1),
                              0,
                            ),
                            child: FractionallySizedBox(
                              widthFactor: 1 / n,
                              heightFactor: 1,
                              child: DecoratedBox(
                                key: const ValueKey('segment_thumb'),
                                decoration: BoxDecoration(
                                  color: c.surfacePage,
                                  borderRadius: BorderRadius.circular(
                                    tokens.radius.table,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // 文字与点击区（整行 44 高）
              Positioned.fill(
                left: _inset,
                right: _inset,
                child: Row(
                  children: [
                    for (final s in segments)
                      Expanded(
                        child: _SegmentCell<T>(
                          segment: s,
                          selected: s.value == value,
                          onTap: enabled ? () => onChanged!(s.value) : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentCell<T> extends StatelessWidget {
  const _SegmentCell({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final AppSegment<T> segment;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final style = (selected ? tokens.text.metaStrong : tokens.text.meta)
        .copyWith(color: selected ? c.textPrimary : c.textMeta);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: segment.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.merge(style) ?? style,
          ),
        ),
      ),
    );
  }
}
