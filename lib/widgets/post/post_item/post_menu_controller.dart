import 'package:common_ui/common_ui.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';

/// 楼层长按菜单的桥：页脚（持有所有楼层操作的状态）把菜单内容登记到这里，
/// 楼层外层的 [LiftedContextMenu] 长按时来取。
class PostMenuController {
  List<List<AppMenuItem<VoidCallback>>> Function(BuildContext context)? builder;
}

/// 页脚里「会显示在楼层菜单里」的状态：书签、采纳解决方案、删除中。
///
/// 分段长帖有两份页脚 State（页脚段里的真页脚 + 头部段里只登记菜单的隐形页脚），
/// 它们读写同一份，在页脚里点了书签后，长按菜单里立刻就是「编辑书签」。
/// 短帖只有一份页脚，用自己私有的一份。
class PostFooterShared {
  bool isBookmarked = false;
  int? bookmarkId;
  String? bookmarkName;
  DateTime? bookmarkReminderAt;
  bool isBookmarking = false;
  bool isAcceptedAnswer = false;
  bool isTogglingAnswer = false;
  bool isDeleting = false;

  final Map<Object, VoidCallback> _listeners = {};

  void addListener(Object owner, VoidCallback listener) =>
      _listeners[owner] = listener;

  void removeListener(Object owner) => _listeners.remove(owner);

  /// 通知别的页脚重建（发出变化的那份自己已经 setState 过了）
  void changed(Object from) {
    for (final entry in _listeners.entries.toList()) {
      if (!identical(entry.key, from)) entry.value();
    }
  }
}

/// 分段长帖（头部段、正文段、页脚段是互相独立的 Sliver）按帖子 id 共用同一个
/// [PostMenuController]：菜单内容由一个藏在头部段里的 [PostFooterSection]
/// （`menuOnly`，不画任何东西）登记，三段各自挂 [PostLongPressMenu]。
class PostMenuRegistry {
  PostMenuRegistry._();

  static final Map<int, PostMenuController> _controllers = {};

  static final Map<int, PostFooterShared> _shared = {};

  static PostMenuController of(int postId) =>
      _controllers.putIfAbsent(postId, PostMenuController.new);

  static PostFooterShared sharedOf(int postId) =>
      _shared.putIfAbsent(postId, PostFooterShared.new);

  @visibleForTesting
  static void reset() {
    _controllers.clear();
    _shared.clear();
  }
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
