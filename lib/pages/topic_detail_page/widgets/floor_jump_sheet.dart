import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/s.dart';
import '../../../utils/dialog_utils.dart';

/// 楼层跳转半屏（0.4.0 v2，设计说明 §2.6 / §3.2「楼层跳转半屏」）。
///
/// 头行「跳转到楼层」+ x；输入行：输入框（44 高 r10 elevated）+「跳转」
/// （66×44 主按钮）；时间轴滑块（轨 4 高，拇指 24，可访问：上下轻扫 ±1
/// 楼）；两行 48 高选项「回到上次阅读位置」「回到跳转前」。
///
/// 校验 1–[total]：无效时留在输入框里并显示有效范围，不关闭；有效则一次
/// 点击直接跳转并关闭。
class FloorJumpSheet extends StatefulWidget {
  const FloorJumpSheet({
    super.key,
    required this.total,
    required this.current,
    required this.onJump,
    this.onBackToLastRead,
    this.onBackToBeforeJump,
  });

  /// 最高楼层
  final int total;

  /// 当前阅读到的楼层
  final int current;

  /// 跳到某一楼
  final ValueChanged<int> onJump;

  /// 「回到上次阅读位置」；null 时不显示
  final VoidCallback? onBackToLastRead;

  /// 「回到跳转前」；null 时不显示（没有跳转历史）
  final VoidCallback? onBackToBeforeJump;

  /// 解析输入：合法返回楼层号，否则 null
  static int? parseFloor(String text, int total) {
    final n = int.tryParse(text.trim());
    if (n == null || n < 1 || n > total) return null;
    return n;
  }

  @override
  State<FloorJumpSheet> createState() => _FloorJumpSheetState();
}

class _FloorJumpSheetState extends State<FloorJumpSheet> {
  late final TextEditingController _controller = TextEditingController();
  late int _floor = widget.current.clamp(1, widget.total);
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = FloorJumpSheet.parseFloor(_controller.text, widget.total);
    if (n == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop();
    widget.onJump(n);
  }

  void _setFloor(int n) {
    final next = n.clamp(1, widget.total);
    if (next == _floor) return;
    HapticFeedback.selectionClick();
    setState(() {
      _floor = next;
      _controller.text = '$next';
      _invalid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);

    final input = TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.go,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      cursorColor: colors.brandPrimary,
      style: base
          .merge(tokens.text.control)
          .copyWith(color: colors.textPrimary),
      onChanged: (_) => setState(() => _invalid = false),
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.m,
          vertical: AppSpace.m,
        ),
        hintText: l10n.topic_floorInputHint(widget.total),
        hintStyle: base
            .merge(tokens.text.control)
            .copyWith(color: colors.textMeta),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius.field),
          borderSide: BorderSide.none,
        ),
      ),
    );

    Widget optionRow(IconData icon, String label, VoidCallback onTap) =>
        AppPressable(
          highlight: true,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.row48),
            child: Row(
              children: [
                Icon(icon, size: AppSize.iconM, color: colors.textPrimary),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: Text(
                    label,
                    style: base
                        .merge(tokens.text.control)
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        );

    return AppSheetScaffold(
      title: l10n.topic_jumpToFloor,
      maxHeightFactor: 0.8,
      // 横屏矮屏放不下时可滚动
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: input),
                const SizedBox(width: AppSpace.s),
                FilledButton(onPressed: _submit, child: Text(l10n.topic_jump)),
              ],
            ),
            if (_invalid)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(
                    l10n.topic_floorInvalid(widget.total),
                    style: meta.copyWith(color: colors.textDestructive),
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.l),
            Row(
              children: [
                Text('#1', style: meta),
                const Spacer(),
                Text('#${widget.total}', style: meta),
              ],
            ),
            _FloorSlider(
              value: _floor,
              total: widget.total,
              onChanged: _setFloor,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.topic_floorSliderValue(_floor, widget.total),
                style: meta,
              ),
            ),
            const SizedBox(height: AppSpace.m),
            if (widget.onBackToLastRead != null) ...[
              const AppHairline(),
              optionRow(AppIcons.history, l10n.topic_backToLastRead, () {
                Navigator.of(context).pop();
                widget.onBackToLastRead!();
              }),
            ],
            if (widget.onBackToBeforeJump != null) ...[
              const AppHairline(),
              optionRow(AppIcons.undo, l10n.topic_backToBeforeJump, () {
                Navigator.of(context).pop();
                widget.onBackToBeforeJump!();
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// 楼层时间轴滑块：和 [StepSlider] 同样的轨道与拇指，但档位多到上千，
/// 拖动是连续的；VoiceOver 上下轻扫 ±1 楼。
class _FloorSlider extends StatelessWidget {
  const _FloorSlider({
    required this.value,
    required this.total,
    required this.onChanged,
  });

  final int value;
  final int total;
  final ValueChanged<int> onChanged;

  static const double _thumb = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = context.l10n;
    return Semantics(
      slider: true,
      label: l10n.topic_jumpToFloor,
      value: l10n.topic_floorSliderValue(value, total),
      increasedValue: value < total
          ? l10n.topic_floorSliderValue(value + 1, total)
          : null,
      decreasedValue: value > 1
          ? l10n.topic_floorSliderValue(value - 1, total)
          : null,
      onIncrease: value < total ? () => onChanged(value + 1) : null,
      onDecrease: value > 1 ? () => onChanged(value - 1) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final usable = constraints.maxWidth - _thumb;
            int floorAt(double dx) {
              if (total <= 1) return 1;
              final t = ((dx - _thumb / 2) / usable).clamp(0.0, 1.0);
              return 1 + (t * (total - 1)).round();
            }

            final t = total <= 1 ? 0.0 : (value - 1) / (total - 1);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onChanged(floorAt(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  onChanged(floorAt(d.localPosition.dx)),
              child: SizedBox(
                height: AppSize.hit,
                child: CustomPaint(
                  painter: _FloorTrackPainter(
                    x: _thumb / 2 + usable * t,
                    inactive: tokens.colors.avatarFill,
                    active: tokens.colors.brandPrimary,
                    border: tokens.colors.quoteRule,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloorTrackPainter extends CustomPainter {
  _FloorTrackPainter({
    required this.x,
    required this.inactive,
    required this.active,
    required this.border,
  });

  final double x;
  final Color inactive;
  final Color active;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const half = 2.0;
    const radius = Radius.circular(half);
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - half, size.width, cy + half, radius),
      Paint()..color = inactive,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - half, x, cy + half, radius),
      Paint()..color = active,
    );
    final center = Offset(x, cy);
    const r = _FloorSlider._thumb / 2;
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
  bool shouldRepaint(_FloorTrackPainter old) =>
      old.x != x ||
      old.inactive != inactive ||
      old.active != active ||
      old.border != border;
}

/// 打开楼层跳转半屏
Future<void> showFloorJumpSheet(
  BuildContext context, {
  required int total,
  required int current,
  required ValueChanged<int> onJump,
  VoidCallback? onBackToLastRead,
  VoidCallback? onBackToBeforeJump,
}) {
  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FloorJumpSheet(
      total: total,
      current: current,
      onJump: onJump,
      onBackToLastRead: onBackToLastRead,
      onBackToBeforeJump: onBackToBeforeJump,
    ),
  );
}
