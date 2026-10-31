import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_nav_bar.dart' show kChromeMaxTextScale;
import 'app_pressable.dart';
import 'badges.dart';
import 'surfaces.dart';

/// 浮动 Tab 胶囊的一项
@immutable
class FloatingTabItem {
  const FloatingTabItem({
    required this.icon,
    required this.label,
    this.showDot = false,
  });

  final IconData icon;
  final String label;

  /// 图标右上角未读点
  final bool showDot;
}

/// 浮动 Tab 胶囊（设计说明 §3.1）：58 高、r29，pad 0 8，项间 4；项
/// 62×37（图标 22 + 文字 11，间距 2），热区 62×44；选中 brand/primary，
/// 未选 text/meta。最多 4 项。材质见 [CapsuleSurface]。
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length <= 4);

  final List<FloatingTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.labelSmall!;
    final localizations = MaterialLocalizations.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: CapsuleSurface(
        child: SizedBox(
          height: AppSize.tabCapsule,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.xs),
                  _TabButton(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                    semanticHint: localizations.tabLabel(
                      tabIndex: i + 1,
                      tabCount: items.length,
                    ),
                    textStyle: base.merge(tokens.text.caption),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.semanticHint,
    required this.textStyle,
  });

  final FloatingTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final String semanticHint;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final color = selected ? colors.brandPrimary : colors.textMeta;
    return AppPressable(
      onTap: onTap,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      semanticHint: semanticHint,
      child: SizedBox(
        width: AppSize.tabItemWidth,
        height: AppSize.tabCapsule,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon, size: 22, color: color),
                if (item.showDot)
                  const Positioned(top: -1, right: -3, child: UnreadDot()),
              ],
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safari 式搜索胶囊（设计说明 §3.1）：58 高、r29，左 16，search 19 +
/// 占位 17 meta，间距 8。
///
/// 不传 [controller] 时是一个按钮（点了去搜索页）；传了就是输入框。聚焦时
/// 贴在键盘上方由页面负责布局，旁边配 [SearchCloseButton]。
class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    super.key,
    required this.placeholder,
    this.onTap,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
  });

  final String placeholder;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction textInputAction;

  bool get _editable => controller != null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(
      context,
    ).textTheme.bodyLarge!.merge(tokens.text.control);
    final Widget field = _editable
        ? TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: textInputAction,
            cursorColor: colors.brandPrimary,
            style: base.copyWith(color: colors.textPrimary),
            // 输入区撑满整个胶囊高度，点击区 = 胶囊（不是 20 高的一行字）
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration.collapsed(
              hintText: placeholder,
              hintStyle: base.copyWith(color: colors.textMeta),
            ),
          )
        : Text(
            placeholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(color: colors.textMeta),
          );

    Widget capsule = CapsuleSurface(
      child: SizedBox(
        height: AppSize.searchCapsule,
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpace.l, right: AppSpace.l),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(AppIcons.search, size: 19, color: colors.textMeta),
              ),
              const SizedBox(width: AppSpace.s),
              Expanded(child: field),
            ],
          ),
        ),
      ),
    );
    if (!_editable) {
      capsule = AppPressable(
        onTap: onTap,
        pressedOpacity: 0.7,
        semanticLabel: placeholder,
        excludeChildSemantics: true,
        child: capsule,
      );
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: Material(type: MaterialType.transparency, child: capsule),
    );
  }
}

/// 搜索聚焦时右侧的 58×58 关闭圆钮（同胶囊材质）
class SearchCloseButton extends StatelessWidget {
  const SearchCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppPressable(
    onTap: onPressed,
    semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
    excludeChildSemantics: true,
    child: CapsuleSurface(
      shape: const CircleBorder(),
      child: SizedBox.square(
        dimension: AppSize.searchCapsule,
        child: Icon(
          AppIcons.close,
          size: 22,
          color: context.tokens.colors.textPrimary,
        ),
      ),
    ),
  );
}
