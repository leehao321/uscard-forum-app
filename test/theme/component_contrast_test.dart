import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 0.4.0 M2：共享组件里每一组「文字色 × 底色」的对比度，按 token 精确计算。
//
// 界面测试里的 textContrastGuideline 按每个逻辑像素取 1 个点，13 号中文
// 笔画被抗锯齿冲淡，量出来偏低（见 test/ui/support/ui_harness.dart），
// 所以对比度在这里按 token 算：正文 / 元信息 ≥ 4.5（WCAG AA 正常字号）。

void main() {
  for (final b in Brightness.values) {
    for (final accent in AccentPreset.values) {
      final tokens = AppTokens.resolve(brightness: b, accent: accent);
      final c = tokens.colors;
      final m = tokens.materials;

      // （组件，文字色，底色）
      final pairs = <(String, Color, Color)>[
        // 页面、列表行、导航栏
        ('页面正文', c.textPrimary, c.surfacePage),
        ('页面元信息', c.textMeta, c.surfacePage),
        ('页面 brand 文字', c.brandPrimary, c.surfacePage),
        ('页面破坏性文字', c.textDestructive, c.surfacePage),
        // 分组列表、筛选胶囊、行内错误、空错状态圆底
        ('分组正文', c.textPrimary, c.surfaceGrouped),
        ('分组元信息', c.textMeta, c.surfaceGrouped),
        ('分组 brand（选中的筛选胶囊）', c.brandPrimary, c.surfaceGrouped),
        ('分组破坏性行', c.textDestructive, c.surfaceGrouped),
        // 半屏 / 对话框底（浅 page、深 grouped）
        ('对话框标题', c.textPrimary, m.sheetFill),
        ('对话框说明', c.textMeta, m.sheetFill),
        ('对话框按钮', c.brandPrimary, m.sheetFill),
        ('对话框破坏性按钮', c.textDestructive, m.sheetFill),
        // 半屏里的分组、输入框，深色菜单
        ('elevated 正文', c.textPrimary, c.surfaceElevated),
        ('elevated 元信息', c.textMeta, c.surfaceElevated),
        ('菜单勾选（深色 elevated）', c.brandPrimary, c.surfaceElevated),
        // 按钮
        ('主按钮白字', c.onBrandButton, c.brandButton),
        ('次按钮', c.textPrimary, c.avatarFill),
      ];

      for (final (name, fg, bg) in pairs) {
        test('${b.name} · ${accent.name}：$name ≥ 4.5', () {
          expect(AppColors.contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }
    }
  }
}
