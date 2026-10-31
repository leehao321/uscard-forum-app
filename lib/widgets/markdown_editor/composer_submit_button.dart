import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 编辑器头部的「发送 / 保存」主按钮（v2：44 高胶囊，brand/button 底白字）。
///
/// 提交中文字换成菊花，按钮置灰但保持原尺寸，不等动效才发请求。
class ComposerSubmitButton extends StatelessWidget {
  const ComposerSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
    this.icon,
    this.animateFlight = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// 紧凑输入条里同样 44 高，仅保留参数兼容旧调用。
  final bool compact;

  /// 旧版起飞动效已取消，保留参数兼容旧调用。
  final bool animateFlight;

  /// 保存编辑等动作可提供自己的图标，显示在文字前。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: FilledButton(
        key: const ValueKey('composer-header-submit'),
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(66, AppSize.hit),
          fixedSize: const Size.fromHeight(AppSize.hit),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.l),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          disabledBackgroundColor: busy ? colors.brandButton : null,
          disabledForegroundColor: busy ? colors.onBrandButton : null,
        ),
        child: Semantics(
          label: label,
          child: ExcludeSemantics(
            // 文字始终参与布局（提交中透明），菊花盖在上面，按钮宽度不跳
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: busy ? 0 : 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: AppSize.iconS),
                        const SizedBox(width: AppSpace.xs),
                      ],
                      Text(label),
                    ],
                  ),
                ),
                if (busy)
                  SizedBox.square(
                    dimension: AppSize.iconS,
                    child: CircularProgressIndicator(
                      color: colors.onBrandButton,
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
