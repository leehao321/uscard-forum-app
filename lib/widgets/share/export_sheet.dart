import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart' show LoadingSpinner;
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../models/topic.dart';
import '../../l10n/s.dart';
import '../../pages/notion_settings_page.dart';
import '../../providers/export_history_provider.dart';
import '../../providers/notion_config_provider.dart';
import '../../services/notion/notion_client.dart';
import '../../services/notion/notion_config.dart';
import '../../services/notion/notion_sync_service.dart';
import '../../services/public_file_channel.dart';
import '../../services/toast_service.dart';
import '../../storage/export_history_dao.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/export_utils.dart';
import '../../utils/platform_utils.dart';
import '../../utils/share_utils.dart';

/// 用户在 sheet 上点的"去向"。
/// 本地 MD/HTML 走 ExportUtils.exportTopic；Notion 走 NotionSyncService。
enum _ExportAction { save, saveAs, share, notion }

/// 导出选项 Sheet
class ExportSheet extends ConsumerStatefulWidget {
  /// 话题详情
  final TopicDetail detail;

  const ExportSheet({super.key, required this.detail});

  /// 显示导出 Sheet
  static Future<void> show(BuildContext context, TopicDetail detail) {
    return showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExportSheet(detail: detail),
    );
  }

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportScope _scope = ExportScope.firstPostOnly;
  ExportFormat _format = ExportFormat.markdown;

  /// 正在执行的去向（null = 空闲）。执行中其余行禁用。
  _ExportAction? _running;
  int _progress = 0;
  int _total = 0;
  String? _phaseLabel; // Notion 同步的阶段文案

  int get _totalPostsCount => widget.detail.postStream.stream.length;

  bool get _willBeLimited =>
      _format == ExportFormat.markdown &&
      _scope == ExportScope.allPosts &&
      _totalPostsCount > ExportUtils.maxMarkdownPosts;

  Future<void> _run(_ExportAction action) async {
    if (_running != null) return;
    setState(() {
      _running = action;
      _progress = 0;
      _total = 0;
      _phaseLabel = null;
    });

    try {
      switch (action) {
        case _ExportAction.save:
          await _exportLocal(ExportDelivery.save);
          break;
        case _ExportAction.saveAs:
          await _exportLocal(ExportDelivery.saveAs);
          break;
        case _ExportAction.share:
          await _exportLocal(ExportDelivery.share);
          break;
        case _ExportAction.notion:
          await _exportNotion();
          break;
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.export_failed('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = null;
          _phaseLabel = null;
        });
      }
    }
  }

  Future<void> _exportLocal(ExportDelivery delivery) async {
    final result = await ExportUtils.exportTopic(
      detail: widget.detail,
      scope: _scope,
      format: _format,
      delivery: delivery,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progress = current;
            _total = total;
          });
        }
      },
    );
    // 保存/另存为被用户取消（未选位置）时不写历史、不关闭 sheet
    final isSaving =
        delivery == ExportDelivery.save || delivery == ExportDelivery.saveAs;
    if (isSaving && !result.shared) return;
    await ref
        .read(exportHistoryProvider.notifier)
        .add(
          ExportHistoryEntry(
            id: const Uuid().v4(),
            sourceType: ExportHistorySource.topic,
            sourceTopicId: widget.detail.id,
            sourceTitle: widget.detail.title,
            format: _format == ExportFormat.markdown
                ? ExportHistoryFormat.markdown
                : ExportHistoryFormat.html,
            // 分享不产生本地文件:写临时路径进历史,点开只会是「文件已不存在」,
            // 桌面端还会把用户带到临时目录
            targetType: isSaving
                ? ExportHistoryTarget.localFile
                : ExportHistoryTarget.shared,
            targetRef: isSaving ? (result.finalPath ?? '') : '',
            status: ExportHistoryStatus.success,
            createdAt: DateTime.now(),
            size: result.byteSize,
            postCount: result.postCount,
          ),
        );
    if (isSaving) {
      final name = result.displayName?.isNotEmpty == true
          ? result.displayName!
          : p.basename(result.finalPath ?? '');
      ToastService.showSuccess(S.current.export_savedAs(name));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _exportNotion() async {
    final cfg = ref.read(notionConfigProvider);
    if (!cfg.isComplete) {
      // 未配置：跳转设置页让用户先配
      final go = await _askGoToSettings();
      if (go == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotionSettingsPage()),
        );
      }
      return;
    }

    final scope = _scope == ExportScope.firstPostOnly
        ? NotionSyncScope.firstPostOnly
        : NotionSyncScope.allPosts;
    final svc = NotionSyncService(config: cfg);

    Future<NotionSyncResult> doSync(DuplicateAction onDup) {
      return svc.syncTopic(
        detail: widget.detail,
        scope: scope,
        onDuplicate: onDup,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _phaseLabel = _labelForPhase(p);
            _progress = p.current;
            _total = p.total;
          });
        },
      );
    }

    NotionSyncResult result;
    try {
      result = await doSync(DuplicateAction.skip);
    } on NotionApiException catch (e) {
      throw Exception(e.message);
    }

    // 命中重复时,弹框让用户选 skip / overwrite
    if (result.duplicated) {
      final action = await _askDuplicate();
      if (action == null) {
        // 用户取消 → 把刚才"命中已有"那条记录也写进历史,
        // 既反映"曾尝试过"也方便用户跳过去原 page
        await _writeNotionHistory(result);
        return;
      }
      if (action == DuplicateAction.overwrite) {
        result = await doSync(DuplicateAction.overwrite);
      }
      // skip 就用原 result
    }

    await _writeNotionHistory(result);
    if (mounted) {
      ToastService.showSuccess(S.current.notion_syncSucceed);
      Navigator.pop(context);
    }
  }

  Future<void> _writeNotionHistory(NotionSyncResult result) {
    return ref
        .read(exportHistoryProvider.notifier)
        .add(
          ExportHistoryEntry(
            id: const Uuid().v4(),
            sourceType: ExportHistorySource.topic,
            sourceTopicId: widget.detail.id,
            sourceTitle: widget.detail.title,
            format: ExportHistoryFormat.notion,
            targetType: ExportHistoryTarget.notion,
            targetRef: result.pageUrl,
            status: ExportHistoryStatus.success,
            createdAt: DateTime.now(),
            postCount: result.postCount,
          ),
        );
  }

  String _labelForPhase(NotionSyncProgress p) {
    switch (p.phase) {
      case SyncPhase.fetch:
        if (p.total > 0) {
          return S.current.notion_syncingFetch(p.current, p.total);
        }
        return S.current.notion_syncing;
      case SyncPhase.convert:
        return S.current.notion_syncingConvert;
      case SyncPhase.create:
        return S.current.notion_syncingCreate;
      case SyncPhase.append:
        return S.current.notion_syncingAppend(p.current, p.total);
      case SyncPhase.done:
        return S.current.notion_syncing;
    }
  }

  Future<bool?> _askGoToSettings() {
    return showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.notion_title),
        content: Text(S.current.notion_notConfigured),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<DuplicateAction?> _askDuplicate() {
    return showAppDialog<DuplicateAction?>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.notion_duplicateTitle),
        content: Text(S.current.notion_duplicateMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, DuplicateAction.skip),
            child: Text(S.current.notion_duplicateSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, DuplicateAction.overwrite),
            child: Text(S.current.notion_duplicateOverwrite),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 订阅 notionConfigProvider,保证它在打开 sheet 的整段生命周期里都在
    // 重建到 username 解析完后的"已配置"状态。否则首次进入时 ref.read
    // 拿到的可能是 username 还在 loading 时构造的空 cfg,误判"未配置"。
    final notionCfg = ref.watch(notionConfigProvider);
    final busy = _running != null;
    final isDesktop = PlatformUtils.isDesktop;

    // 主操作：桌面端「保存」本身就是另存为对话框；移动端是「另存为…」。
    // iOS 没有「公共目录」这一说:沙盒外无处可写,Documents 里躺着
    // 数据库/cookie/日志(不能靠 UIFileSharingEnabled 整目录暴露),
    // 所以那边只给「另存为」,由用户导出到「文件」App。
    final primaryAction = isDesktop ? _ExportAction.save : _ExportAction.saveAs;
    // 其余去向放在 Notion 下面一行：安卓保存到「下载」目录；
    // Linux 上 share_plus 不支持分享文件，隐藏分享。
    final canSaveToDownloads = !isDesktop && PublicFileChannel.hasPublicDownloads;
    final canShare = ShareUtils.canShareFiles;

    return AppSheetScaffold(
      title: context.l10n.export_title,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.pageMargin,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 导出范围
            _sectionLabel(context, context.l10n.export_range),
            AppSegmentedControl<ExportScope>(
              semanticLabel: context.l10n.export_range,
              value: _scope,
              onChanged: busy ? null : (v) => setState(() => _scope = v),
              segments: [
                AppSegment(
                  value: ExportScope.firstPostOnly,
                  label: context.l10n.export_firstPostOnly,
                ),
                AppSegment(
                  value: ExportScope.allPosts,
                  label: context.l10n.export_allPosts,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.m),
            // 文件格式（只作用于"保存"/"分享"，Notion 固定以页面写入）
            _sectionLabel(context, context.l10n.export_format),
            AppSegmentedControl<ExportFormat>(
              semanticLabel: context.l10n.export_format,
              value: _format,
              onChanged: busy ? null : (v) => setState(() => _format = v),
              segments: const [
                AppSegment(value: ExportFormat.markdown, label: 'Markdown'),
                AppSegment(value: ExportFormat.html, label: 'HTML'),
              ],
            ),
            // Markdown 限制提示
            if (_willBeLimited) ...[
              const SizedBox(height: AppSpace.s),
              Row(
                children: [
                  Icon(
                    AppIcons.info,
                    size: 14,
                    color: context.tokens.colors.brandPrimary,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      context.l10n.export_markdownLimit(
                        ExportUtils.maxMarkdownPosts,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.tokens.colors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.xxl),
            // 去向：点哪个即执行哪个。另存为（主按钮）/ 同步到 Notion（次按钮）
            _deliveryButton(
              context,
              action: primaryAction,
              icon: AppIcons.download,
              title: isDesktop
                  ? context.l10n.export_deliverSave
                  : context.l10n.export_deliverSaveAs,
              primary: true,
            ),
            const SizedBox(height: AppSpace.l),
            _deliveryButton(
              context,
              action: _ExportAction.notion,
              icon: AppIcons.refresh,
              title: context.l10n.export_deliverNotion,
              primary: false,
            ),
            if (!notionCfg.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  context.l10n.export_deliverNotionUnconfigured,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.merge(
                    context.tokens.text.meta.copyWith(
                      color: context.tokens.colors.textMeta,
                    ),
                  ),
                ),
              ),
            if (canSaveToDownloads || canShare)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (canSaveToDownloads)
                      _extraAction(
                        context,
                        action: _ExportAction.save,
                        icon: AppIcons.save,
                        title: context.l10n.export_deliverSave,
                      ),
                    if (canShare)
                      _extraAction(
                        context,
                        action: _ExportAction.share,
                        icon: AppIcons.share,
                        title: context.l10n.export_deliverShare,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 分区标题：13 meta，下面 8
  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.merge(context.tokens.text.meta)
            .copyWith(color: context.tokens.colors.textMeta),
      ),
    );
  }

  /// 一个去向按钮（48 高）。执行中的那个显示进度文案与转圈，其余禁用。
  Widget _deliveryButton(
    BuildContext context, {
    required _ExportAction action,
    required IconData icon,
    required String title,
    required bool primary,
  }) {
    final isRunning = _running == action;
    final disabled = _running != null;
    final base = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSize.replyButton),
    );
    return FilledButton.icon(
      onPressed: disabled ? null : () => _run(action),
      style: primary
          ? base
          : base.merge(AppButtonStyles.secondary(context)),
      icon: isRunning
          ? LoadingSpinner(
              size: 18,
              color: primary ? AppFixedColors.white : null,
            )
          : Icon(
              icon,
              size: AppSize.iconM,
              color: primary ? null : context.tokens.colors.brandPrimary,
            ),
      label: Text(
        isRunning ? _progressLabel(context) : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 次要去向（保存到「下载」、分享）：文字按钮，44 高
  Widget _extraAction(
    BuildContext context, {
    required _ExportAction action,
    required IconData icon,
    required String title,
  }) {
    final isRunning = _running == action;
    return TextButton.icon(
      onPressed: _running != null ? null : () => _run(action),
      icon: isRunning
          ? const LoadingSpinner(size: 16)
          : Icon(icon, size: AppSize.iconS),
      label: Text(isRunning ? _progressLabel(context) : title),
    );
  }

  String _progressLabel(BuildContext context) {
    if (_phaseLabel != null) return _phaseLabel!;
    if (_total > 0) {
      return context.l10n.export_exporting(_progress, _total);
    }
    return context.l10n.export_exportingNoProgress;
  }
}
