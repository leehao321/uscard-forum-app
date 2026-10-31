import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../providers/topic_list/filter_provider.dart';

class TopicListUpdateBanner extends StatelessWidget {
  const TopicListUpdateBanner({
    super.key,
    required this.count,
    required this.filter,
    required this.newNewView,
    required this.loading,
    required this.onTap,
  });

  final int count;
  final TopicListFilter filter;
  final bool newNewView;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final label = switch (filter) {
      TopicListFilter.unread => context.l10n.topics_viewUnreadTopics(count),
      TopicListFilter.newTopics when !newNewView =>
        context.l10n.topics_viewNewOnlyTopics(count),
      _ => context.l10n.topics_viewNewTopics(count),
    };
    // 列表顶部 44 高的行内提示：brand 文字 + 上箭头，整行可点，发丝线收底
    return Semantics(
      liveRegion: true,
      child: AppPressable(
        highlight: true,
        onTap: loading ? null : onTap,
        child: SizedBox(
          height: AppSize.hit,
          child: Center(
            child: loading
                ? const CupertinoActivityIndicator(radius: AppSize.iconS / 2)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.up,
                        size: AppSize.iconS,
                        color: colors.brandPrimary,
                      ),
                      const SizedBox(width: AppSpace.s),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall!
                            .merge(tokens.text.meta)
                            .copyWith(color: colors.brandPrimary),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
