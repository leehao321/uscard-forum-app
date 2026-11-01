import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';

import '../../../l10n/s.dart';
import '../../../utils/dialog_utils.dart';
import '../../../utils/responsive.dart';
import 'revision_view.dart';

/// 显示帖子编辑历史 Modal。
///
/// - 移动端: 底部 sheet,高度固定 85%vh(避免内容加载后跳变)
/// - 桌面/平板: 居中 Dialog,宽 720,高度最多 70%vh(超出滚动)
///
/// [initialRevision] 默认 null,加载 latest revision;
/// 通知跳转携带的 revision_number 通过此参数定位到指定版本。
Future<void> showPostRevisionSheet({
  required BuildContext context,
  required int postId,
  int? initialRevision,
  bool useRootNavigator = true,
}) async {
  final isMobile = Responsive.isMobile(context);
  if (isMobile) {
    await _showAsBottomSheet(
      context: context,
      postId: postId,
      initialRevision: initialRevision,
      useRootNavigator: useRootNavigator,
    );
  } else {
    await _showAsDialog(
      context: context,
      postId: postId,
      initialRevision: initialRevision,
      useRootNavigator: useRootNavigator,
    );
  }
}

Future<void> _showAsBottomSheet({
  required BuildContext context,
  required int postId,
  required int? initialRevision,
  required bool useRootNavigator,
}) async {
  await showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: useRootNavigator,
    builder: (sheetContext) {
      // 固定高度,避免内容加载/切换 revision 时 sheet 高度跳变
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.85;
      // 共享半屏外壳：拖拽条 + 「编辑历史」标题 + 右上 x；
      // 内容区自己带 20 的左右边距（补充稿 29–31）
      return SizedBox(
        height: maxHeight,
        child: AppSheetScaffold(
          title: sheetContext.l10n.postRevision_modalTitle,
          expandToFill: true,
          contentPadding: EdgeInsets.zero,
          child: PostRevisionView(
            postId: postId,
            initialRevision: initialRevision,
          ),
        ),
      );
    },
  );
}

Future<void> _showAsDialog({
  required BuildContext context,
  required int postId,
  required int? initialRevision,
  required bool useRootNavigator,
}) async {
  await showAppDialog<void>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final width = size.width.clamp(480.0, 880.0);
      // 限制弹窗高度,内部用 ScrollView 滚动,不让 dialog 跟随内容长度跳变
      final height = (size.height * 0.78).clamp(360.0, 720.0);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: width,
          height: height,
          child: _RevisionSheetFrame(
            postId: postId,
            initialRevision: initialRevision,
          ),
        ),
      );
    },
  );
}

class _RevisionSheetFrame extends StatelessWidget {
  final int postId;
  final int? initialRevision;

  const _RevisionSheetFrame({
    required this.postId,
    required this.initialRevision,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                AppIcons.history,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.postRevision_modalTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.close,
                size: AppSize.iconM,
                semanticLabel: MaterialLocalizations.of(
                  context,
                ).closeButtonLabel,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PostRevisionView(
            postId: postId,
            initialRevision: initialRevision,
          ),
        ),
      ],
    );
  }
}
