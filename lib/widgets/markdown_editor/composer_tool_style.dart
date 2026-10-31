import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart';

/// 工具条按钮（v2）：44×44 热区，图标 20；激活态 brand 色 + 12% 底。
ButtonStyle composerToolButtonStyle(
  BuildContext context, {
  bool active = false,
}) {
  final colors = context.tokens.colors;
  final motion =
      M3eFlags.of(context).enabled && !MediaQuery.disableAnimationsOf(context);
  return IconButton.styleFrom(
    minimumSize: const Size.square(AppSize.hit),
    maximumSize: const Size.square(AppSize.hit),
    padding: const EdgeInsets.all(AppSpace.m),
    visualDensity: VisualDensity.standard,
    foregroundColor: active ? colors.brandPrimary : colors.textPrimary,
    backgroundColor: active
        ? colors.brandPrimary.withValues(alpha: 0.12)
        : Colors.transparent,
  ).copyWith(
    animationDuration: motion
        ? const Duration(milliseconds: 150)
        : Duration.zero,
  );
}

/// 内容处理和光标共享一个轻量底色，模式切换留在组外。
class ComposerEditingControls extends StatelessWidget {
  const ComposerEditingControls({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(AppSize.hit / 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}
