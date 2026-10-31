import 'package:common_ui/common_ui.dart';
import 'package:flutter/widgets.dart';

/// 楼层长按菜单的桥：页脚（持有所有楼层操作的状态）把菜单内容登记到这里，
/// 楼层外层的 [LiftedContextMenu] 长按时来取。
class PostMenuController {
  List<List<AppMenuItem<VoidCallback>>> Function(BuildContext context)? builder;
}

/// 楼层长按浮起菜单：正文区自带文字选择，长按先归选择；头部、页脚和空白处
/// 长按浮起整层并弹出菜单。没有登记菜单（没有页脚）时不响应。
class PostLongPressMenu extends StatelessWidget {
  const PostLongPressMenu({
    super.key,
    required this.controller,
    required this.child,
  });

  final PostMenuController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (itemContext) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () async {
          final sections = controller.builder?.call(itemContext);
          if (sections == null || sections.every((s) => s.isEmpty)) return;
          final run = await showLiftedContextMenu<VoidCallback>(
            context: itemContext,
            sourceRect: globalRectOf(itemContext),
            liftedBuilder: (_) => child,
            sections: sections,
          );
          run?.call();
        },
        child: child,
      ),
    );
  }
}
