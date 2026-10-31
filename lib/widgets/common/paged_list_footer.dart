import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 分页脚（v2，设计说明 §4）：44 高居中 13 meta——加载中是系统菊花，
/// 失败是「加载更多失败 · 重试」（重试 brand，整条可点），到底是「没有更多了」。
class PagedListFooter extends StatelessWidget {
  const PagedListFooter({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isLoadMoreFailed,
    required this.onRetry,
    this.padding = EdgeInsets.zero,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final bool isLoadMoreFailed;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final meta = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);

    Widget child;
    if (isLoadMoreFailed) {
      child = AppPressable(
        onTap: onRetry,
        child: SizedBox(
          height: AppSize.hit,
          child: Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${context.l10n.common_loadMoreFailed} · '),
                  TextSpan(
                    text: context.l10n.common_retry,
                    style: TextStyle(color: tokens.colors.brandPrimary),
                  ),
                ],
              ),
              style: meta,
            ),
          ),
        ),
      );
    } else if (isLoadingMore) {
      child = const SizedBox(
        height: AppSize.hit,
        child: Center(
          child: CupertinoActivityIndicator(radius: AppSize.iconS / 2),
        ),
      );
    } else if (!hasMore) {
      child = SizedBox(
        height: AppSize.hit,
        child: Center(child: Text(context.l10n.common_noMore, style: meta)),
      );
    } else {
      child = const SizedBox(height: AppSize.hit);
    }

    return Padding(padding: padding, child: child);
  }
}
