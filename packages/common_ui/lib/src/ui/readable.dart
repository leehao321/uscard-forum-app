import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens/tokens.dart';

/// 阅读列宽（`layout/readable-max-width`，0.4.0 计划 §7）：含列内 20，
/// 正文行宽 600。
const double kReadableMaxWidth = 640;

/// 阅读列左右边距（计划 §7）。
///
/// 可用宽 W = 屏宽 − 左右安全区：W ≥ 640 时左右各取
/// max(安全区, (屏宽 − 640) / 2)，否则就是安全区；再加列内 [gutter]
/// （默认页边距 20）。竖屏手机上就是左右各 20。
///
/// 导航栏、工具栏、胶囊的底色铺满整宽，里面的控件用这个边距对齐阅读列。
EdgeInsets readableInsets(
  BuildContext context, {
  double gutter = AppSpace.pageMargin,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final safe = MediaQuery.paddingOf(context);
  final available = width - safe.left - safe.right;
  var left = safe.left;
  var right = safe.right;
  if (available >= kReadableMaxWidth) {
    final side = (width - kReadableMaxWidth) / 2;
    left = math.max(safe.left, side);
    right = math.max(safe.right, side);
  }
  return EdgeInsets.only(left: left + gutter, right: right + gutter);
}

/// 盒子版阅读列：子组件左右按 [readableInsets] 留白（含列内 20）。
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({
    super.key,
    required this.child,
    this.gutter = AppSpace.pageMargin,
  });

  final Widget child;

  /// 列内边距；整行可点的列表传 0，行内自己留 20
  final double gutter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: readableInsets(context, gutter: gutter),
    child: child,
  );
}

/// Sliver 版阅读列：给滚动内容套一层 [SliverPadding]。
class SliverReadable extends StatelessWidget {
  const SliverReadable({
    super.key,
    required this.sliver,
    this.gutter = AppSpace.pageMargin,
  });

  final Widget sliver;
  final double gutter;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: readableInsets(context, gutter: gutter),
    sliver: sliver,
  );
}

/// 页面主体的阅读列限宽（计划 §7）：**手机横屏**（短边 < 600、去掉左右安全区后
/// 宽 ≥ 640）时把主体居中限宽到 [kReadableMaxWidth]，其余情况原样返回，所以竖屏、
/// 平板、桌面都不受影响。导航栏、工具栏的底色仍铺满整宽，只有正文列居中。
///
/// 套在 `Scaffold.body` 上；页面里原有的 20 页边距照旧留在列内。
class ReadableBody extends StatelessWidget {
  const ReadableBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final available = size.width - safe.left - safe.right;
    if (size.shortestSide >= 600 || available < kReadableMaxWidth) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
        child: child,
      ),
    );
  }
}

/// 顶部导航栏的横屏阅读列（设计 §5.6，Figma「阅读页 · 横屏」62:1483）：**手机横屏**
/// （短边 < 600、去掉安全区后宽 ≥ 640）时，导航栏背景仍横跨整个屏宽，左右按钮和标题按
/// 640 列对齐；竖屏、平板、桌面原样返回。
///
/// 给 Material 的 [AppBar] 用：AppBar 的内容包在 SafeArea 里，所以只要把这里的左右安全区
/// 加宽到阅读列边缘，背景（在 SafeArea 外面）不动，按钮和标题就跟着进到 640 列里。
/// [AppNavBar] 自己已经按 [readableInsets] 对齐，不需要再包。
class ReadableAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReadableAppBar({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safe = media.padding;
    if (size.shortestSide >= 600 ||
        size.width - safe.left - safe.right < kReadableMaxWidth) {
      return child;
    }
    // 用导航栏所在区域的实际宽度算（半屏里的 Scaffold 不是屏宽），区域 ≤ 640 时不再加宽
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          0.0,
          (constraints.maxWidth - kReadableMaxWidth) / 2,
        );
        if (side <= 0) return child;
        final left = math.max(safe.left, side);
        final right = math.max(safe.right, side);
        return MediaQuery(
          data: media.copyWith(
            padding: safe.copyWith(left: left, right: right),
            viewPadding: media.viewPadding.copyWith(left: left, right: right),
          ),
          child: child,
        );
      },
    );
  }
}
