import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../providers/ai_translation_provider.dart';
import '../../../../providers/post_translation_provider.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../widgets/common/anchor_guard_sliver.dart';

/// 楼层正文下方的译文：字号和正文一致，字色淡一点，稍微缩进，和原文连在一起读。
///
/// 没点过翻译时不占位。
class PostTranslationBlock extends ConsumerWidget {
  const PostTranslationBlock({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(postTranslationProvider(post.id), (_, _) {
      // 高度变了。详情页是双向列表，上半场的楼层变高不锚定的话，内容会被顶走。
      AnchorGuardSliver.arm();
    });
    final state = ref.watch(postTranslationProvider(post.id));
    if (!state.isVisible || !state.isFor(post.cooked)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurfaceVariant;
    final notifier = ref.read(postTranslationProvider(post.id).notifier);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: muted.withValues(alpha: 0.7),
    );

    final Widget body = switch (state.status) {
      PostTranslationStatus.failed => InkWell(
        onTap: () => notifier.retry(post.cooked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            l10n.post_translationFailed,
            style: labelStyle?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ),
      PostTranslationStatus.ready => _ReadyBody(
        post: post,
        state: state,
        labelStyle: labelStyle,
        onCollapse: () => notifier.toggle(post.cooked),
      ),
      _ => Text(l10n.post_translationLoading, style: labelStyle),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 6),
      child: body,
    );
  }
}

class _ReadyBody extends ConsumerWidget {
  const _ReadyBody({
    required this.post,
    required this.state,
    required this.labelStyle,
    required this.onCollapse,
  });

  final Post post;
  final PostTranslationState state;
  final TextStyle? labelStyle;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = state.result!;
    final target = state.targetLanguage!;
    final fontScale = ref.watch(
      preferencesProvider.select((p) => p.contentFontScale),
    );
    final sameLanguage = result.isSameLanguageAs(target) || result.text.isEmpty;

    final collapse = InkWell(
      onTap: onCollapse,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          sameLanguage
              ? l10n.post_translationSameLanguage(
                  aiTranslationLanguageLabel(target),
                )
              : '${l10n.post_translationSource}  ·  ${l10n.post_translationCollapse}',
          style: labelStyle,
        ),
      ),
    );
    if (sameLanguage) return collapse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          result.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * fontScale,
          ),
        ),
        if (result.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l10n.post_translationTruncated, style: labelStyle),
          ),
        const SizedBox(height: 2),
        collapse,
      ],
    );
  }
}
