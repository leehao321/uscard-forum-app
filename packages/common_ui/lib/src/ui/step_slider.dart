import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';

/// 档位滑块（设计说明 §4，同阅读页时间轴）：轨道 4 高 r2 avatar/fill，
/// 已选部分 brand/primary，拇指 24 白（0.5 quote/rule 描边 + 阴影），
/// 拇指不出轨道。可选两端「A」示意（13 / 17）和档位刻度文字（11 meta）。
///
/// 无障碍：朗读为滑块，上下轻扫 ±1 档。
class StepSlider extends StatelessWidget {
  const StepSlider({
    super.key,
    required this.value,
    required this.count,
    required this.onChanged,
    this.labels,
    this.semanticLabel,
    this.showTextSizeEnds = false,
  }) : assert(count >= 2),
       assert(value >= 0 && value < count);

  /// 当前档位（0 起）
  final int value;
  final int count;
  final ValueChanged<int>? onChanged;

  /// 每一档的文字（刻度显示在轨道下方，也用作朗读值）
  final List<String>? labels;
  final String? semanticLabel;

  /// 两端显示小「A」和大「A」（字号档用）
  final bool showTextSizeEnds;

  static const double _thumb = 24;
  static const double _track = 4;

  String _valueText(int i) => labels?[i] ?? '${i + 1}';

  void _set(int i) {
    final next = i.clamp(0, count - 1);
    if (next == value || onChanged == null) return;
    HapticFeedback.selectionClick();
    onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);

    Widget track = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 父约束极窄时不能除以 0（M-11）
        final usable = math.max(1.0, width - _thumb);
        int indexAt(double dx) =>
            (((dx - _thumb / 2) / usable) * (count - 1)).round();
        final x = _thumb / 2 + usable * value / (count - 1);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onChanged == null
              ? null
              : (d) => _set(indexAt(d.localPosition.dx)),
          onHorizontalDragUpdate: onChanged == null
              ? null
              : (d) => _set(indexAt(d.localPosition.dx)),
          child: SizedBox(
            height: AppSize.hit,
            child: CustomPaint(
              painter: _StepTrackPainter(
                x: x,
                count: count,
                usable: usable,
                inactive: tokens.colors.avatarFill,
                active: tokens.colors.brandPrimary,
                border: tokens.colors.quoteRule,
              ),
            ),
          ),
        );
      },
    );

    // 档位文字和轨道放在同一列里，两端的大小 A 再放到这一列的两侧，
    // 这样文字不会跟轨道错位（M-11）
    Widget core = track;
    final labels = this.labels;
    if (labels != null) {
      core = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          track,
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: i == 0
                          ? TextAlign.start
                          : i == labels.length - 1
                          ? TextAlign.end
                          : TextAlign.center,
                      style: base
                          .merge(tokens.text.caption)
                          .copyWith(
                            color: i == value
                                ? tokens.colors.brandPrimary
                                : tokens.colors.textMeta,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    Widget slider = core;
    if (showTextSizeEnds) {
      // 两端的 A 是图形，不随系统字号放大
      final endStyle = meta.copyWith(color: tokens.colors.textMeta);
      Widget end(TextStyle style) => SizedBox(
        height: AppSize.hit,
        child: Center(
          child: ExcludeSemantics(
            child: Text('A', style: style, textScaler: TextScaler.noScaling),
          ),
        ),
      );
      slider = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          end(endStyle),
          const SizedBox(width: AppSpace.m),
          Expanded(child: core),
          const SizedBox(width: AppSpace.m),
          end(endStyle.merge(tokens.text.control)),
        ],
      );
    }

    return Semantics(
      slider: true,
      label: semanticLabel,
      value: _valueText(value),
      increasedValue: value < count - 1 ? _valueText(value + 1) : null,
      decreasedValue: value > 0 ? _valueText(value - 1) : null,
      onIncrease: onChanged != null && value < count - 1
          ? () => _set(value + 1)
          : null,
      onDecrease: onChanged != null && value > 0 ? () => _set(value - 1) : null,
      child: ExcludeSemantics(child: slider),
    );
  }
}

class _StepTrackPainter extends CustomPainter {
  _StepTrackPainter({
    required this.x,
    required this.count,
    required this.usable,
    required this.inactive,
    required this.active,
    required this.border,
  });

  final double x;
  final int count;
  final double usable;
  final Color inactive;
  final Color active;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const half = StepSlider._track / 2;
    final radius = const Radius.circular(half);
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - half, size.width, cy + half, radius),
      Paint()..color = inactive,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - half, x, cy + half, radius),
      Paint()..color = active,
    );
    final center = Offset(x, cy);
    const r = StepSlider._thumb / 2;
    canvas.drawCircle(
      center + AppMaterials.thumbShadow.offset,
      r,
      AppMaterials.thumbShadow.toPaint(),
    );
    canvas.drawCircle(center, r, Paint()..color = AppMaterials.thumbFill);
    canvas.drawCircle(
      center,
      r - AppSpace.hairline / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppSpace.hairline
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_StepTrackPainter old) =>
      old.x != x ||
      old.count != count ||
      old.usable != usable ||
      old.inactive != inactive ||
      old.active != active ||
      old.border != border;
}
