import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/s.dart';
import '../../services/draft_controller.dart';
import 'composer_draft_status.dart';
import 'composer_page_chrome.dart';
import 'composer_view_mode_switcher.dart';
import 'composer_submit_button.dart';

typedef ComposerReviewBuilder = Widget Function(
  Widget Function(bool reviewing, VoidCallback? trigger) builder,
);

enum _HeaderAction { preview, review, discard, draft }

/// 创建、编辑和回复共用的文档操作区。窄屏优先给标题和提交按钮留空间。
class ComposerHeaderActions extends StatelessWidget {
  const ComposerHeaderActions({
    super.key,
    required this.availableWidth,
    required this.submitLabel,
    required this.onSubmit,
    required this.previewing,
    required this.onTogglePreview,
    this.submitIcon,
    this.submitting = false,
    this.showDiscard = false,
    this.onDiscard,
    this.reviewBuilder,
    this.draftStatus,
    this.onRetryDraft,
    this.minimumTitleWidth,
  });

  final double availableWidth;

  /// Measured title content, including decorations such as a reply avatar.
  final double? minimumTitleWidth;
  final String submitLabel;
  final IconData? submitIcon;
  final VoidCallback? onSubmit;
  final bool submitting;
  final bool previewing;
  final VoidCallback? onTogglePreview;
  final bool showDiscard;
  final VoidCallback? onDiscard;
  final ValueListenable<DraftSaveStatus>? draftStatus;
  final VoidCallback? onRetryDraft;

  /// 审核状态跨收纳保留，结果锚定当前外显按钮或菜单入口。
  final ComposerReviewBuilder? reviewBuilder;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    const submitWidth = 66.0;
    final actions = [
      _HeaderAction.preview,
      if (reviewBuilder != null) _HeaderAction.review,
      if (showDiscard && draftStatus == null) _HeaderAction.discard,
    ];
    // 保留导航和默认标题间距，标题至少容纳常规页面名称。
    final titleWidth = minimumTitleWidth ?? 120 * scaler.scale(22) / 22;
    final slots = math.max(
      1,
      ((availableWidth -
                  56 -
                  NavigationToolbar.kMiddleSpacing * 2 -
                  titleWidth -
                  16 -
                  submitWidth) /
              52)
          .floor(),
    );
    final inlineCount = draftStatus != null
        ? math.min(actions.length, slots - 1)
        : actions.length <= slots
        ? actions.length
        : slots - 1;
    final inline = actions.take(inlineCount).toList();
    final overflow = [
      if (draftStatus != null) _HeaderAction.draft,
      ...actions.skip(inlineCount),
      if (draftStatus != null && showDiscard) _HeaderAction.discard,
    ];
    // 草稿状态与舍弃固定收进菜单，其余操作按剩余空间收纳。
    assert(draftStatus != null || overflow.length != 1);

    String label(_HeaderAction action, bool reviewing) => switch (action) {
      _HeaderAction.preview =>
        previewing ? S.current.common_exitPreview : S.current.common_preview,
      _HeaderAction.review =>
        reviewing
            ? S.current.aiPostReview_reviewing
            : S.current.aiPostReview_button,
      _HeaderAction.discard => S.current.common_discard,
      _HeaderAction.draft => composerDraftStatusLabel(
        context,
        draftStatus!.value,
      ),
    };
    Object icon(_HeaderAction action) => switch (action) {
      _HeaderAction.preview => previewing ? AppIcons.edit : AppIcons.openBook,
      _HeaderAction.review => AppIcons.sparkles,
      _HeaderAction.discard => AppIcons.delete,
      _HeaderAction.draft => AppIcons.cloudUpload,
    };
    VoidCallback? callback(_HeaderAction action, VoidCallback? onReview) =>
        switch (action) {
          _HeaderAction.preview => onTogglePreview,
          _HeaderAction.review => onReview,
          _HeaderAction.discard => onDiscard,
          _HeaderAction.draft =>
            [
                  DraftSaveStatus.error,
                  DraftSaveStatus.local,
                  DraftSaveStatus.conflict,
                ].contains(draftStatus?.value)
                ? onRetryDraft
                : null,
        };

    Widget more(bool reviewing, VoidCallback? onReview) => Builder(
      builder: (buttonContext) {
        final colors = buttonContext.tokens.colors;
        final moreIcon = Icon(
          AppIcons.moreHoriz,
          size: AppSize.iconL,
          color: colors.textPrimary,
        );
        // 草稿状态在菜单打开期间会变（保存中 → 已保存 / 失败），整份菜单实时重取
        List<List<AppMenuItem<VoidCallback>>> menuSections() {
          final status = draftStatus?.value;
          final error =
              status == DraftSaveStatus.error ||
              status == DraftSaveStatus.conflict;
          final retryable = error || status == DraftSaveStatus.local;
          final saving =
              status == DraftSaveStatus.saving &&
              !MediaQuery.disableAnimationsOf(buttonContext);
          return [
            [
              for (final action in overflow)
                if (action == _HeaderAction.draft)
                  AppMenuItem(
                    rowKey: const ValueKey('composer-draft-status-item'),
                    icon: status == DraftSaveStatus.error
                        ? AppIcons.cloudOff
                        : AppIcons.cloudUpload,
                    leading: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : null,
                    label: retryable && onRetryDraft != null
                        ? '${label(action, false)} · ${status == DraftSaveStatus.conflict ? S.current.composer_draftResolve : S.current.common_retry}'
                        : label(action, false),
                    destructive: error,
                    enabled: retryable && onRetryDraft != null,
                    onTap: onRetryDraft,
                  )
                else
                  AppMenuItem(
                    rowKey: ValueKey('composer-header-${action.name}'),
                    // 预览图标是自绘的 AppCustomIcon，菜单行只认字体图标，退回文章图标
                    icon: icon(action) is IconData
                        ? icon(action) as IconData
                        : AppIcons.article,
                    label: label(action, reviewing),
                    destructive:
                        action == _HeaderAction.discard && onDiscard != null,
                    enabled: callback(action, onReview) != null,
                    onTap: callback(action, onReview),
                  ),
            ],
          ];
        }

        Future<void> open() async {
          await showAppMenu<VoidCallback>(
            context: buttonContext,
            anchor: globalRectOf(buttonContext),
            sections: menuSections(),
            requestFocus: false,
            refresh: draftStatus,
            liveSections: menuSections,
          );
        }

        return AppPressable(
          key: const ValueKey('composer-header-more'),
          onTap: open,
          child: Semantics(
            button: true,
            label: S.current.common_more,
            excludeSemantics: true,
            onTap: open,
            child: SizedBox.square(
              dimension: AppSize.hit,
              child: Center(
                child: draftStatus == null
                    ? moreIcon
                    : ComposerDraftAttention(
                        status: draftStatus!,
                        child: moreIcon,
                      ),
              ),
            ),
          ),
        );
      },
    );

    Widget reviewHost({required bool folded}) => KeyedSubtree(
      key: const ValueKey('composer-header-review-host'),
      child: reviewBuilder!(
        (reviewing, trigger) => folded
            ? more(reviewing, trigger)
            : ComposerActionButton(
                key: const ValueKey('composer-header-review-inline'),
                icon: AppIcons.sparkles,
                label: label(_HeaderAction.review, reviewing),
                busy: reviewing,
                onPressed: trigger,
              ),
      ),
    );

    return TextFieldTapRegion(
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (final action in inline)
              switch (action) {
                _HeaderAction.preview => ComposerPreviewButton(
                  key: const ValueKey('composer-header-preview-inline'),
                  previewing: previewing,
                  onPressed: onTogglePreview,
                ),
                _HeaderAction.review => reviewHost(folded: false),
                _HeaderAction.discard => ComposerActionButton(
                  key: const ValueKey('composer-header-discard-inline'),
                  icon: AppIcons.delete,
                  label: S.current.common_discard,
                  onPressed: onDiscard,
                ),
                _HeaderAction.draft => const SizedBox.shrink(),
              },
            if (overflow.isNotEmpty)
              overflow.contains(_HeaderAction.review)
                  ? reviewHost(folded: true)
                  : more(false, null),
            ComposerSubmitButton(
              label: submitLabel,
              icon: submitIcon,
              busy: submitting,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
