import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/s.dart';
import '../providers/font_provider.dart';
import '../providers/theme_provider.dart';
import '../services/font_import_service.dart';
import '../services/toast_service.dart';
import '../settings/settings_model.dart';
import '../utils/dialog_utils.dart';
import '../widgets/settings/settings_group_page.dart';

/// 外观 › 字体（0.4.0 计划 §M8）
///
/// 预览卡（界面一行、正文一行）；「界面字体」「正文字体」分开单选；
/// 「已导入的字体」带删除；「＋ 导入字体文件」只收 .ttf / .otf / .ttc。
class FontSettingsPage extends ConsumerStatefulWidget {
  const FontSettingsPage({super.key, this.pickFile});

  /// 测试用：替换系统文件选择器，返回要导入的文件路径（null = 取消）
  final Future<String?> Function()? pickFile;

  @override
  ConsumerState<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends ConsumerState<FontSettingsPage> {
  FontImportCancelToken? _cancel;
  String? _importingName;
  int _done = 0;
  int _total = 0;

  bool get _importing => _importingName != null;

  @override
  void initState() {
    super.initState();
    unawaited(FontImportService.instance.ensureLoaded());
  }

  Future<void> _import() async {
    final picked = await (widget.pickFile?.call() ?? _pickWithSystem());
    if (picked == null || !mounted) return;
    final name = p.basename(picked);
    final cancel = FontImportCancelToken();
    setState(() {
      _cancel = cancel;
      _importingName = name;
      _done = 0;
      _total = 0;
    });
    try {
      await FontImportService.instance.import(
        picked,
        cancel: cancel,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
    } on FontImportException catch (e) {
      switch (e.failure) {
        case FontImportFailure.notAFont:
          ToastService.showInfo(S.current.appearance_fontNotAFont(name));
        case FontImportFailure.failed:
          ToastService.showError(S.current.appearance_fontImportFailed);
        case FontImportFailure.cancelled:
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingName = null;
          _cancel = null;
        });
      }
    }
  }

  Future<String?> _pickWithSystem() async {
    // 能限制扩展名就限制成 ttf / otf / ttc；平台不支持过滤时退回全部文件，
    // 选完仍由导入服务按扩展名和文件头魔数把关
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf', 'ttc'],
      );
    } catch (_) {
      result = await FilePicker.platform.pickFiles(type: FileType.any);
    }
    return result?.files.single.path;
  }

  Future<void> _confirmDelete(ImportedFont font) async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.appearance_fontDeleteTitle(font.displayName)),
        content: Text(l10n.appearance_fontDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: ctx.tokens.colors.textDestructive,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.appearance_fontDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(themeProvider.notifier);
    final theme = ref.read(themeProvider);
    // 正在用它的选择换回默认：界面字体回系统，正文字体回跟随界面字体
    if (theme.importedUiFamily == font.family) {
      await notifier.setImportedUiFamily(null);
    }
    if (theme.bodyFontFamily == font.family) {
      await notifier.setBodyFontFamily(null);
    }
    await FontImportService.instance.delete(font.id);
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${_mb(bytes)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fonts = ref.watch(importedFontsProvider);
    final theme = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);

    final uiSelected = theme.importedUiFamily != null
        ? 'imported:${theme.importedUiFamily}'
        : theme.fontFamily == AppFontFamily.miSans
        ? 'misans'
        : 'system';
    final bodySelected = theme.bodyFontFamily == null
        ? 'follow'
        : theme.bodyFontFamily == 'MiSans'
        ? 'misans'
        : 'imported:${theme.bodyFontFamily}';

    Widget radioRow({
      required String title,
      required bool selected,
      required VoidCallback onTap,
      String? family,
    }) => Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: ListTile(
        title: Text(title, style: TextStyle(fontFamily: family)),
        trailing: selected
            ? Icon(
                AppIcons.check,
                size: AppSize.iconM,
                color: context.tokens.colors.brandPrimary,
              )
            : null,
        onTap: onTap,
      ),
    );

    return SettingsGroupPage(
      title: l10n.appearance_font,
      pinnedHeader: _FontPreview(
        uiFamily: theme.fontFamilyName,
        bodyFamily: theme.bodyFontFamily ?? theme.fontFamilyName,
      ),
      groupsBuilder: (context) => [
        SettingsGroup(
          title: l10n.appearance_fontUi,
          icon: AppIcons.description,
          items: [
            CustomModel(
              id: 'uiFont',
              title: l10n.appearance_fontUi,
              builder: (context, ref) => Column(
                children: [
                  radioRow(
                    title: l10n.appearance_fontSystem,
                    selected: uiSelected == 'system',
                    onTap: () =>
                        notifier.setFontFamily(AppFontFamily.system),
                  ),
                  radioRow(
                    title: l10n.appearance_fontMiSans,
                    family: 'MiSans',
                    selected: uiSelected == 'misans',
                    onTap: () =>
                        notifier.setFontFamily(AppFontFamily.miSans),
                  ),
                  for (final font in fonts)
                    radioRow(
                      title: font.displayName,
                      family: font.family,
                      selected: uiSelected == 'imported:${font.family}',
                      onTap: () => notifier.setImportedUiFamily(font.family),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.appearance_fontBody,
          icon: AppIcons.description,
          items: [
            CustomModel(
              id: 'bodyFont',
              title: l10n.appearance_fontBody,
              builder: (context, ref) => Column(
                children: [
                  radioRow(
                    title: l10n.appearance_fontFollowUi,
                    selected: bodySelected == 'follow',
                    onTap: () => notifier.setBodyFontFamily(null),
                  ),
                  radioRow(
                    title: l10n.appearance_fontMiSans,
                    family: 'MiSans',
                    selected: bodySelected == 'misans',
                    onTap: () => notifier.setBodyFontFamily('MiSans'),
                  ),
                  for (final font in fonts)
                    radioRow(
                      title: font.displayName,
                      family: font.family,
                      selected: bodySelected == 'imported:${font.family}',
                      onTap: () => notifier.setBodyFontFamily(font.family),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (fonts.isNotEmpty)
          SettingsGroup(
            title: l10n.appearance_fontImported,
            icon: AppIcons.description,
            items: [
              for (final font in fonts)
                CustomModel(
                  id: 'font_${font.id}',
                  title: font.displayName,
                  builder: (context, ref) => _ImportedFontRow(
                    font: font,
                    sizeText: _size(font.size),
                    onDelete: () => _confirmDelete(font),
                  ),
                ),
            ],
          ),
        SettingsGroup(
          title: '',
          icon: AppIcons.add,
          wrapInCard: false,
          footer: l10n.appearance_fontFooter,
          items: [
            CustomModel(
              id: 'importFont',
              title: l10n.appearance_fontImport,
              builder: (context, ref) => Column(
                children: [
                  if (_importing) ...[
                    _ImportProgress(
                      name: _importingName!,
                      done: _done,
                      total: _total,
                      mb: _mb,
                      onCancel: () => _cancel?.cancel(),
                    ),
                    const SizedBox(height: AppSpace.s),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: AppButtonStyles.secondary(context),
                      // 导入期间置灰
                      onPressed: _importing ? null : _import,
                      icon: const Icon(AppIcons.add, size: AppSize.iconM),
                      label: Text(l10n.appearance_fontImport),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 预览卡：界面一行、正文一行，用当前选择的字体写
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.uiFamily, required this.bodyFamily});

  final String? uiFamily;
  final String? bodyFamily;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.xs,
        AppSpace.pageMargin,
        AppSpace.s,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfacePage,
          borderRadius: BorderRadius.circular(tokens.radius.card),
          border: Border.all(color: colors.separator, width: AppSpace.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appearance_fontSample,
                style: base
                    .merge(tokens.text.headline)
                    .copyWith(color: colors.textPrimary, fontFamily: uiFamily),
              ),
              const SizedBox(height: AppSpace.s),
              Text(
                l10n.appearance_fontBodySample,
                style: base
                    .merge(tokens.text.body)
                    .copyWith(
                      color: colors.textPrimary,
                      fontFamily: bodyFamily,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportedFontRow extends StatelessWidget {
  const _ImportedFontRow({
    required this.font,
    required this.sizeText,
    required this.onDelete,
  });

  final ImportedFont font;
  final String sizeText;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final detail = [
      '${font.fileName} · $sizeText',
      if (font.isCollection) l10n.appearance_fontTtcNote,
    ].join('，');
    return ListTile(
      leading: Container(
        width: AppSize.avatarS,
        height: AppSize.avatarS,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.avatarFill,
          borderRadius: BorderRadius.circular(tokens.radius.table),
        ),
        child: Text(
          '字',
          style: TextStyle(
            fontFamily: font.family,
            fontSize: 17,
            color: colors.textPrimary,
          ),
        ),
      ),
      title: Text(font.displayName),
      subtitle: Text(detail, style: meta, maxLines: 2),
      trailing: AppIconButton(
        icon: AppIcons.delete,
        semanticLabel: l10n.appearance_fontDelete,
        color: colors.textDestructive,
        onPressed: onDelete,
      ),
    );
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({
    required this.name,
    required this.done,
    required this.total,
    required this.mb,
    required this.onCancel,
  });

  final String name;
  final int done;
  final int total;
  final String Function(int bytes) mb;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    return Container(
      padding: const EdgeInsets.all(AppSpace.m),
      decoration: BoxDecoration(
        color: colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.appearance_fontImporting} · $name',
            style: base
                .merge(tokens.text.control)
                .copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpace.s),
          LinearProgressIndicator(
            value: total == 0 ? null : done / total,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              Text(
                total == 0 ? '' : '${mb(done)} / ${mb(total)} MB',
                style: meta,
              ),
              const Spacer(),
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.appearance_fontCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
