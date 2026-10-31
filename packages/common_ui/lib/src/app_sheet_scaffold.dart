import 'package:flutter/material.dart';

import 'tokens/tokens.dart';
import 'ui/app_nav_bar.dart' show AppCloseButton;
import 'ui/surfaces.dart';

/// [AppSheetScaffold] 的外观覆盖(ThemeExtension,可选)。
///
/// common_ui 不依赖应用,圆角/标题字阶由宿主通过这个扩展传入;未注册时
/// 取 v2 token(顶部圆角 sheet、标题 17 Regular)。
///
/// 注意:light/dark 两个 ThemeData 必须对称注册 —— ThemeData.lerp 对
/// "单边缺失"的 extension 不插值而是瞬时并入。
@immutable
class AppSheetShellStyle extends ThemeExtension<AppSheetShellStyle> {
  /// 顶部圆角。
  final double topRadius;

  /// 标题样式(不含颜色与 fontFamily,外壳按 textTheme 补字体与颜色)。
  final TextStyle? titleStyle;

  const AppSheetShellStyle({this.topRadius = 16, this.titleStyle});

  @override
  AppSheetShellStyle copyWith({double? topRadius, TextStyle? titleStyle}) =>
      AppSheetShellStyle(
        topRadius: topRadius ?? this.topRadius,
        titleStyle: titleStyle ?? this.titleStyle,
      );

  @override
  AppSheetShellStyle lerp(ThemeExtension<AppSheetShellStyle>? other, double t) {
    if (other is! AppSheetShellStyle) return this;
    return AppSheetShellStyle(
      topRadius: topRadius + (other.topRadius - topRadius) * t,
      titleStyle: TextStyle.lerp(titleStyle, other.titleStyle, t),
    );
  }

  // ThemeData 每次 build 都是新实例;extension 不可比较会让 AnimatedTheme
  // 在每次 rebuild 时空转一段 lerp 动画。
  @override
  bool operator ==(Object other) =>
      other is AppSheetShellStyle &&
      other.topRadius == topRadius &&
      other.titleStyle == titleStyle;

  @override
  int get hashCode => Object.hash(topRadius, titleStyle);
}

/// 底部弹框的两种受控形态。
enum AppSheetStyle {
  /// 列表式:默认带拖拽条、可下滑关闭。适合浏览 / 选择 / 列表 / 快速输入。
  edge,

  /// 表单式:默认无拖拽条、带关闭按钮,并由弹出入口(AppBottomSheet.show)
  /// 禁止下滑关闭,避免误关丢失输入。适合表单 / 编辑 / 确认。
  card,
}

/// v2 通用半屏外壳(设计说明 §4「半屏(通用)」,与楼层跳转半屏一致)。
///
/// - 底:浅色 surface/page、深色 surface/grouped(#1C1C1E);顶部圆角 16;
/// - 拖拽条 36×5 r3 quote/rule,距顶 8;
/// - 头行:标题 17 Regular 左对齐 + 右侧 x 22(热区 44);
/// - 左右内边距 20,底部留安全区(至少 16);
/// - 内部分组列表(卡片色)和输入框换成 surface/elevated。
///
/// 全平台同一套(计划 P2)。纯外壳,零业务依赖,主 app 与各子包共用。
class AppSheetScaffold extends StatelessWidget {
  const AppSheetScaffold({
    super.key,
    this.style = AppSheetStyle.edge,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.showCloseButton = true,
    this.showDragHandle,
    this.showTitleDivider = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSpace.pageMargin,
    ),
    this.maxHeightFactor = 0.9,
    this.expandToFill = false,
    this.footer,
    required this.child,
  });

  /// 外壳形态
  final AppSheetStyle style;

  /// 标题文字(为空且无 [titleWidget] 时不显示头行)
  final String? title;

  /// 自定义标题(优先于 [title])
  final Widget? titleWidget;

  /// 头行右侧操作按钮(位于关闭按钮左侧)
  final List<Widget> actions;

  /// 是否显示头行右侧关闭按钮(仅在有头行时生效)
  final bool showCloseButton;

  /// 是否显示顶部拖拽条;为 null 时按 [style] 默认(列表式显示、表单式隐藏)
  final bool? showDragHandle;

  /// 是否在头行下方显示分隔线
  final bool showTitleDivider;

  /// 内容内边距
  final EdgeInsetsGeometry contentPadding;

  /// 普通模式下高度上限(占屏比);[expandToFill] 为 true 时忽略
  final double maxHeightFactor;

  /// 是否撑满给定高度。用于 [DraggableScrollableSheet] 等已经定高的场景:
  /// 此时内容用 [Expanded] 撑满,且不再叠加键盘内边距(交由内容自身处理)。
  final bool expandToFill;

  /// 固定在内容下方、不随内容滚动的底部区域(如确认/提交按钮)。
  final Widget? footer;

  /// 内容
  final Widget child;

  bool get _hasTitle => title != null || titleWidget != null;

  /// 半屏内部的主题:分组列表、卡片、输入框用 surface/elevated
  static ThemeData innerTheme(ThemeData theme, AppTokens tokens) {
    final elevated = tokens.colors.surfaceElevated;
    return theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(color: elevated),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: elevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final shellStyle = theme.extension<AppSheetShellStyle>();
    final topRadius = shellStyle?.topRadius ?? tokens.radius.sheet;
    final isCard = style == AppSheetStyle.card;
    final resolvedShowHandle = showDragHandle ?? !isCard;

    final body = Padding(padding: contentPadding, child: child);
    final content = expandToFill
        ? Expanded(child: body)
        : Flexible(child: body);

    final shell = Material(
      color: tokens.materials.sheetFill,
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: innerTheme(theme, tokens),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: AppSpace.l),
          child: Column(
            mainAxisSize: expandToFill ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (resolvedShowHandle) _DragHandle(radius: tokens.radius.handle),
              if (_hasTitle)
                _buildTitleRow(context, tokens, shellStyle, resolvedShowHandle)
              else
                // 没有头行:拖拽条下面直接留 16;连拖拽条也没有时留 8
                SizedBox(height: resolvedShowHandle ? AppSpace.l : AppSpace.s),
              if (_hasTitle && showTitleDivider)
                const AppHairline(indent: AppSpace.pageMargin),
              content,
              // footer 给 tight 宽约束,让它自己决定要不要占满
              ?footer,
            ],
          ),
        ),
      ),
    );

    final labelled = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: shell,
    );

    // 可拖拽模式:高度由 DraggableScrollableSheet 决定,不封顶、不叠加键盘内边距。
    if (expandToFill) return labelled;

    // 贴屏幕底、仅顶部圆角;键盘弹出时整体上顶(需配合 isScrollControlled)。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: labelled,
      ),
    );
  }

  /// 头行 44 高(x 的热区),视觉上和拖拽条、内容各隔 16:
  /// 22 的图标在 44 里上下各空 11,所以外面只再留 5。
  Widget _buildTitleRow(
    BuildContext context,
    AppTokens tokens,
    AppSheetShellStyle? shellStyle,
    bool hasHandle,
  ) {
    const iconOverhang = (AppSize.hit - 22) / 2;
    const outerGap = AppSpace.l - iconOverhang;
    final titleStyle = Theme.of(context).textTheme.bodyLarge!
        .merge(shellStyle?.titleStyle ?? tokens.text.control)
        .copyWith(color: tokens.colors.textPrimary, letterSpacing: 0);
    final trailing = <Widget>[
      ...actions,
      if (showCloseButton) const AppCloseButton(),
    ];
    return Padding(
      padding: EdgeInsets.only(
        top: hasHandle ? outerGap : AppSpace.s,
        bottom: outerGap,
        left: AppSpace.pageMargin,
        right: AppSpace.pageMargin - iconOverhang,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.hit),
        child: Row(
          children: [
            Expanded(
              child:
                  titleWidget ??
                  Semantics(
                    header: true,
                    child: Text(
                      title!,
                      style: titleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpace.s),
      child: Center(
        child: Container(
          width: AppSize.sheetHandleWidth,
          height: AppSize.sheetHandleHeight,
          decoration: BoxDecoration(
            color: context.tokens.colors.quoteRule,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    ),
  );
}
