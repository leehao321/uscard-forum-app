import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';
import 'app_nav_bar.dart' show kChromeMaxTextScale;

/// [AppSegmentedControl] 的一个选项
@immutable
class AppSegment<T> {
  const AppSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// 分段控件轨道的底色：放在 surface/page 的页面上用 [grouped]，
/// 放在 surface/grouped 的半屏上用 [elevated]。
enum AppSegmentedTrack { elevated, grouped }

/// v2 分段控件（导出文章的导出范围 / 文件格式、并发与限流预设、快捷词的图像 / 文本）：
/// 轨道圆角 10、内边距 4；选中的滑块 surface/page、圆角 8，
/// 文字 13（选中 Semibold text/primary，未选 Regular text/meta）。
///
/// 轨道视觉高 40，点击区撑到 44（上下各 2 透明热区，不改变布局）。
/// 选项宽度均分；点已选中的那一段不回调。[onChanged] 为 null 时整体禁用。
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.track = AppSegmentedTrack.elevated,
    this.padding = EdgeInsets.zero,
  }) : assert(segments.length >= 2);

  /// 按下标选的分段（选项就是一串文案）；[selectedIndex] 为 -1 表示一段都不选。
  /// 轨道默认用 [AppSegmentedTrack.grouped]（页面底上的分段）。
  static AppSegmentedControl<int> indexed({
    Key? key,
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int>? onChanged,
    String? semanticLabel,
    AppSegmentedTrack track = AppSegmentedTrack.grouped,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return AppSegmentedControl<int>(
      key: key,
      segments: [
        for (var i = 0; i < labels.length; i++)
          AppSegment(value: i, label: labels[i]),
      ],
      value: selectedIndex,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
      track: track,
      padding: padding,
    );
  }

  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  /// 整个控件的无障碍标签（如「导出范围」）
  final String? semanticLabel;

  final AppSegmentedTrack track;

  /// 控件外的内边距
  final EdgeInsetsGeometry padding;

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

    final bar = Semantics(
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
                    color: track == AppSegmentedTrack.grouped
                        ? c.surfaceGrouped
                        : c.surfaceElevated,
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
                          onTap: enabled && s.value != value
                              ? () {
                                  HapticFeedback.selectionClick();
                                  onChanged!(s.value);
                                }
                              : null,
                          enabled: enabled,
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
    return Padding(
      padding: padding,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: kChromeMaxTextScale,
        child: bar,
      ),
    );
  }
}

class _SegmentCell<T> extends StatelessWidget {
  const _SegmentCell({
    required this.segment,
    required this.selected,
    required this.onTap,
    required this.enabled,
  });

  final AppSegment<T> segment;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final style = (selected ? tokens.text.metaStrong : tokens.text.meta)
        .copyWith(color: selected ? c.textPrimary : c.textMeta);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
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
