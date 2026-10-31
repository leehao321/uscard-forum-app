import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 静态 App 图标（v2：登录、引导、预热、锁屏共用，设计说明 §5.4）。
///
/// brand/button 底，系统图标圆角（边长 × 0.2273：96→22、64→14.5），
/// 白色罗盘线条图标；不动、不发光、不漂浮（D23 / D29）。
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.brandButton,
          borderRadius: BorderRadius.circular(size * 0.2273),
        ),
        child: Icon(
          AppIcons.compass,
          size: size * 0.5,
          color: AppFixedColors.white,
        ),
      ),
    );
  }
}
