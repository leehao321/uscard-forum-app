import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';

import '../../l10n/s.dart';
import '../../services/draft_controller.dart';
import '../../utils/dialog_utils.dart';

enum _DraftConflictChoice { reload, overwrite }

Future<bool> confirmComposerDraftOverwrite(
  BuildContext context, {
  Future<void> Function()? onReload,
}) async {
  final choice = await showAppDialog<_DraftConflictChoice>(
    context: context,
    builder: (context) => AppAlertDialog(
      scrollable: true,
      title: Text(context.l10n.composer_draftConflictTitle),
      content: Text(context.l10n.composer_draftConflictBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _DraftConflictChoice.overwrite),
          child: Text(context.l10n.composer_draftOverwrite),
        ),
        if (onReload != null)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _DraftConflictChoice.reload),
            child: Text(context.l10n.composer_draftUseRemote),
          ),
      ],
    ),
  );
  if (choice == _DraftConflictChoice.reload) await onReload?.call();
  return choice == _DraftConflictChoice.overwrite;
}

String composerDraftStatusLabel(BuildContext context, DraftSaveStatus status) =>
    switch (status) {
      DraftSaveStatus.idle => context.l10n.composer_draftAutoSave,
      DraftSaveStatus.pending => context.l10n.composer_draftPending,
      DraftSaveStatus.saving => context.l10n.composer_draftSaving,
      DraftSaveStatus.saved => context.l10n.composer_draftSaved,
      DraftSaveStatus.local => context.l10n.composer_draftLocal,
      DraftSaveStatus.conflict => context.l10n.composer_draftConflict,
      DraftSaveStatus.error => context.l10n.composer_draftError,
    };

/// 失败只标记既有的更多入口，不占新栏位，也不触发正文的布局变化。
class ComposerDraftAttention extends StatelessWidget {
  const ComposerDraftAttention({
    super.key,
    required this.status,
    required this.child,
  });

  final ValueListenable<DraftSaveStatus> status;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DraftSaveStatus>(
    valueListenable: status,
    builder: (context, value, _) => Semantics(
      value: value == DraftSaveStatus.error || value == DraftSaveStatus.conflict
          ? composerDraftStatusLabel(context, value)
          : null,
      liveRegion:
          value == DraftSaveStatus.error || value == DraftSaveStatus.conflict,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (value == DraftSaveStatus.error ||
              value == DraftSaveStatus.conflict)
            Positioned(
              right: -3,
              top: -1,
              child: DecoratedBox(
                key: const ValueKey('composer-draft-attention'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 6),
              ),
            ),
        ],
      ),
    ),
  );
}
