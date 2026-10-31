import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// v2 按钮的颜色分工（设计说明 §4）：
/// - 主按钮 = 主题里的 [FilledButton]：brand/button 底、白字；
/// - 次按钮 = [FilledButton] + [secondary]：avatar/fill 底、text/primary 字
///   （「重试」等）；OutlinedButton / ElevatedButton 的主题也是这个样子；
/// - 文字按钮 = [TextButton]：brand/primary 字。
///
/// 尺寸：默认 44 高胶囊；回复、楼层这类 48 高的用 [large]。
abstract final class AppButtonStyles {
  /// 次按钮
  static ButtonStyle secondary(BuildContext context) {
    final c = context.tokens.colors;
    return FilledButton.styleFrom(
      backgroundColor: c.avatarFill,
      foregroundColor: c.textPrimary,
      disabledBackgroundColor: c.avatarFill,
      disabledForegroundColor: c.textMeta,
    );
  }

  /// 48 高（r24）
  static const ButtonStyle large = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(64, AppSize.replyButton)),
  );
}
