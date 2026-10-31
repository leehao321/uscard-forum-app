/// 「内容操作」按钮：把作用于**文字本身**的操作收进一个入口。
///
/// **为什么要单独一个按钮**：底部工具栏原来把两类完全不同的东西混在一条
/// 横栏里 —— 作用于「文字内容」的（全选/撤销/恢复/复制/粘贴/剪切）和作用
/// 于「文字样式」的（粗体/列表/引用…）。收成一个按钮后点按弹出 v2 菜单
/// （[AppMenu]），撤销/恢复随历史栈启用，复制/剪切随选区启用。
library;

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../../../../l10n/s.dart';

/// 内容操作的能力提供方。
///
/// 富文本走 `FluxdoEditorContentActions`（编辑器内核句柄），源码模式走
/// `TextEditingController` + `UndoHistoryController` —— 两者动作语义相同、
/// 实现完全不同，用这个接口抹平，按钮本身不关心背后是谁。
abstract class ContentActionsProvider {
  bool get canUndo;
  bool get canRedo;

  /// 是否有非折叠选区（决定复制/剪切是否可用）。
  bool get hasSelection;

  /// 编辑目标当前是否可用（未挂载/失焦时整个按钮禁用）。
  bool get isAvailable;

  void undo();
  void redo();
  void selectAll();
  void copy();
  void cut();
  void paste();
}

/// 内容操作按钮。
class ContentActionsButton extends StatelessWidget {
  const ContentActionsButton({
    super.key,
    required this.provider,
    required this.listenable,
    this.iconSize = 20,
  });

  final ContentActionsProvider provider;

  /// 驱动重建的信号源（编辑器状态 / controller）——菜单可用性随它变化。
  final Listenable listenable;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        // 「撤销可用」是这个按钮最主要的活跃信号：有历史 = 用户已经在写了
        final active = provider.canUndo;
        return Builder(
          builder: (buttonContext) => AppPressable(
            onTap: () => _showMenu(buttonContext),
            child: Semantics(
              button: true,
              label: S.current.toolbar_contentActions,
              excludeSemantics: true,
              onTap: () => _showMenu(buttonContext),
              child: SizedBox(
                width: AppSize.hit,
                height: AppSize.hit,
                child: Center(
                  child: AppIcon(
                    AppIcons.contentActions,
                    size: iconSize,
                    color: active
                        ? colors.textPrimary
                        : colors.textMeta.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 当前菜单项（顺序 = 使用频率降序）。
  List<AppMenuItem<VoidCallback>> _buildItems() {
    if (!provider.isAvailable) return const [];
    final s = S.current;
    return [
      AppMenuItem(
        icon: AppIcons.undo,
        label: s.toolbar_undo,
        enabled: provider.canUndo,
        onTap: provider.undo,
      ),
      AppMenuItem(
        icon: AppIcons.redo,
        label: s.toolbar_redo,
        enabled: provider.canRedo,
        onTap: provider.redo,
      ),
      AppMenuItem(
        icon: AppIcons.selectAll,
        label: s.toolbar_selectAll,
        onTap: provider.selectAll,
      ),
      AppMenuItem(
        icon: AppIcons.copy,
        label: s.common_copy,
        enabled: provider.hasSelection,
        onTap: provider.copy,
      ),
      AppMenuItem(
        icon: AppIcons.cut,
        label: s.toolbar_cut,
        enabled: provider.hasSelection,
        onTap: provider.cut,
      ),
      AppMenuItem(
        icon: AppIcons.paste,
        label: s.common_paste,
        onTap: provider.paste,
      ),
    ];
  }

  Future<void> _showMenu(BuildContext context) async {
    final items = _buildItems();
    if (items.isEmpty) return;
    await showAppMenu<VoidCallback>(
      context: context,
      anchor: globalRectOf(context),
      sections: [items],
      requestFocus: false,
    );
  }
}
