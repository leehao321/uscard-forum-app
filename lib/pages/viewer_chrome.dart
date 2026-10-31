import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../widgets/common/app_bottom_sheet.dart';

/// 图片 / 图表查看器共用的外壳零件（0.4.0 v2，计划 M5）。
///
/// 查看器是黑底，不跟主题走：控件是黑色半透明圆钮 + 白色图标。
/// 圆钮 44×44（热区同大），页码是胶囊，加载进度是「原图加载中 62%」胶囊。
const Color kViewerScrim = Colors.black54;
const Color kViewerForeground = Colors.white;

/// 顶部或底部的渐变遮罩，让状态栏和文字在亮图上也看得清。
class ViewerGradient extends StatelessWidget {
  const ViewerGradient({super.key, this.fromTop = true, this.height = 100});

  final bool fromTop;
  final double height;

  @override
  Widget build(BuildContext context) => Positioned(
    top: fromTop ? 0 : null,
    bottom: fromTop ? null : 0,
    left: 0,
    right: 0,
    height: height,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
          ),
        ),
      ),
    ),
  );
}

/// 44 圆钮：关闭、保存、分享。[busy] 时显示菊花并忽略点击。
class ViewerCircleButton extends StatelessWidget {
  const ViewerCircleButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    enabled: !busy && onPressed != null,
    excludeSemantics: true,
    onTap: busy ? null : onPressed,
    child: AppPressable(
      onTap: busy ? null : onPressed,
      child: Container(
        width: AppSize.hit,
        height: AppSize.hit,
        decoration: const BoxDecoration(
          color: kViewerScrim,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: busy
            ? const CupertinoActivityIndicator(
                radius: 9,
                color: kViewerForeground,
              )
            : Icon(icon, size: AppSize.iconL, color: kViewerForeground),
      ),
    ),
  );
}

/// 页码胶囊「3 / 12」
class ViewerPageCapsule extends StatelessWidget {
  const ViewerPageCapsule({
    super.key,
    required this.index,
    required this.total,
  });

  /// 从 0 起
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '第 ${index + 1} 张，共 $total 张',
    excludeSemantics: true,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
      decoration: const ShapeDecoration(
        color: kViewerScrim,
        shape: StadiumBorder(),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1} / $total',
        style: Theme.of(context).textTheme.bodySmall
            ?.merge(context.tokens.text.meta)
            .copyWith(color: kViewerForeground),
      ),
    ),
  );
}

/// 底部文件名
class ViewerFilename extends StatelessWidget {
  const ViewerFilename({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.pageMargin,
          right: AppSpace.pageMargin,
          top: AppSpace.m,
          bottom: MediaQuery.paddingOf(context).bottom + AppSpace.m,
        ),
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.merge(context.tokens.text.meta)
              .copyWith(color: kViewerForeground),
        ),
      ),
    ),
  );
}

/// 「原图加载中 62%」。[progress] 为空表示不知道总大小，只显示文字。
class ViewerLoadingPill extends StatelessWidget {
  const ViewerLoadingPill({super.key, this.progress});

  /// 0–1
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final percent = progress == null ? null : (progress! * 100).round();
    final label = percent == null ? '原图加载中' : '原图加载中 $percent%';
    return Center(
      child: Semantics(
        label: label,
        liveRegion: true,
        excludeSemantics: true,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
          decoration: const ShapeDecoration(
            color: kViewerScrim,
            shape: StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(
                radius: 8,
                color: kViewerForeground,
              ),
              const SizedBox(width: AppSpace.s),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.merge(context.tokens.text.meta)
                    .copyWith(color: kViewerForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按操作表里的一行
class ViewerAction {
  const ViewerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// 长按出的操作表：每行 48 高，图标 + 文字，点完自动关闭。
Future<void> showViewerActionSheet(
  BuildContext context,
  List<ViewerAction> actions,
) {
  return AppBottomSheet.show<void>(
    context: context,
    contentPadding: EdgeInsets.zero,
    builder: (ctx) {
      final colors = ctx.tokens.colors;
      final style = Theme.of(ctx).textTheme.bodyMedium!
          .merge(ctx.tokens.text.control)
          .copyWith(color: colors.textPrimary);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions)
            AppPressable(
              highlight: true,
              onTap: () {
                Navigator.pop(ctx);
                a.onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.row48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.pageMargin,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a.icon,
                        size: AppSize.iconM,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: AppSpace.m),
                      Expanded(child: Text(a.label, style: style)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
