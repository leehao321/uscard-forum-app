import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../providers/ai_translation_provider.dart';
import '../../../../providers/post_translation_provider.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../services/toast_service.dart';
import '../../../../services/translation_engine.dart';
import '../../../../widgets/common/anchor_guard_sliver.dart';

/// 楼层正文下方的译文：字号和正文一致，字色淡一点，左边一条细竖线，和原文连在一起读。
///
/// 没翻译时不占位。全帖翻译开着时，楼层一出现就排队翻译。
class PostTranslationBlock extends ConsumerStatefulWidget {
  const PostTranslationBlock({
    super.key,
    required this.post,
    required this.topicId,
  });

  final Post post;
  final int topicId;

  @override
  ConsumerState<PostTranslationBlock> createState() =>
      _PostTranslationBlockState();
}

class _PostTranslationBlockState extends ConsumerState<PostTranslationBlock> {
  /// 这个版本的正文已经请求过排队，build 重跑时不用再请求
  String? _requested;

  void _requestIfNeeded(bool immersive) {
    if (!immersive) {
      _requested = null;
      return;
    }
    final cooked = widget.post.cooked;
    if (_requested == cooked) return;
    _requested = cooked;
    // build 里不能改别的 provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(immersiveTranslationProvider(widget.topicId).notifier)
          .request(widget.post.id, cooked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    ref.listen(postTranslationProvider(post.id), (_, _) {
      // 高度变了。详情页是双向列表，上半场的楼层变高不锚定的话，内容会被顶走。
      AnchorGuardSliver.arm();
    });
    final immersive = ref.watch(immersiveTranslationProvider(widget.topicId));
    _requestIfNeeded(immersive);

    final state = ref.watch(postTranslationProvider(post.id));
    if (!state.isVisible || !state.isFor(post.cooked)) {
      return const SizedBox.shrink();
    }
    final result = state.result;
    // 全帖模式下，已经是目标语言的楼层不用每层提示一遍
    if (immersive &&
        state.status == PostTranslationStatus.ready &&
        result != null &&
        (result.isSameLanguageAs(state.targetLanguage!) || result.text.isEmpty)) {
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
        state: state,
        labelStyle: labelStyle,
        onCollapse: () => notifier.toggle(post.cooked),
      ),
      _ => Text(l10n.post_translationLoading, style: labelStyle),
    };

    return Container(
      key: const ValueKey('post-translation'),
      margin: const EdgeInsets.only(left: 2, bottom: 6),
      padding: const EdgeInsets.only(left: 9),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
      ),
      child: body,
    );
  }
}

class _ReadyBody extends ConsumerWidget {
  const _ReadyBody({
    required this.state,
    required this.labelStyle,
    required this.onCollapse,
  });

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
              : '${_sourceLabel(context, ref)}  ·  ${l10n.post_translationCollapse}',
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

  String _sourceLabel(BuildContext context, WidgetRef ref) =>
      ref.watch(translationSourceProvider) == TranslationSource.ai
      ? context.l10n.ai_translationSourceAiShort
      : context.l10n.post_translationSource;
}

/// 话题页顶栏的「沉浸式翻译全文」开关。
class ImmersiveTranslateButton extends ConsumerWidget {
  const ImmersiveTranslateButton({super.key, required this.topicId});

  final int topicId;

  /// 帖子内容会发给第三方，每次运行提醒一次
  static bool _noticeShown = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(immersiveTranslationProvider(topicId));
    final l10n = context.l10n;
    return IconButton(
      key: const ValueKey('immersive-translate'),
      tooltip: l10n.post_immersiveToggle,
      isSelected: on,
      icon: const Icon(Symbols.translate_rounded),
      selectedIcon: Icon(
        Symbols.translate_rounded,
        fill: 1,
        color: Theme.of(context).colorScheme.primary,
      ),
      onPressed: () {
        ref.read(immersiveTranslationProvider(topicId).notifier).toggle();
        if (!on &&
            !_noticeShown &&
            ref.read(translationSourceProvider) == TranslationSource.google) {
          _noticeShown = true;
          ToastService.showInfo(l10n.post_immersiveGoogleNotice);
        }
      },
    );
  }
}
