import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cross_file/cross_file.dart';
import 'package:ai_model_manager/ai_model_manager.dart';

import '../l10n/s.dart';
import '../utils/share_utils.dart';
import '../providers/app_state_refresher.dart';
import '../providers/core_providers.dart';
import '../providers/theme_provider.dart';
import '../utils/dialog_utils.dart';
import '../services/data_management/cache_size_service.dart';
import '../services/data_management/data_backup_service.dart';
import '../services/toast_service.dart';
import '../settings/definitions/data_management_defs.dart';
import '../settings/settings_model.dart';
import 'package:m3e_ui/m3e_ui.dart';
import 'package:path/path.dart' as p;
import '../widgets/settings/settings_group_page.dart';

/// 数据管理页面（数据驱动版）
class DataManagementPage extends StatelessWidget {
  final String? highlightId;

  const DataManagementPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.dataManagement_title,
      groupsBuilder: (c) => footerizeSubtitles(buildDataManagementGroups(c)),
      highlightId: highlightId,
    );
  }
}

// ─────────────────────────────────────────────
// 缓存管理区块（有状态，被 CustomModel 包装）
// ─────────────────────────────────────────────

/// 缓存管理区块 —— Telegram Storage Usage 式信息架构:
///
/// - 图片缓存(可再下载)细分六类,**多选勾选 + 单一「清理所选」按钮**,
///   顶部分段彩条总览(分类色 = 勾选框色,取消勾选实时从彩条移除);
/// - AI 聊天 / Cookie 是本地数据(清了就没/要重登),**不进多选**,
///   保持独立行 + 各自确认 —— 对齐 Telegram 把 Local Database 与
///   可再下载缓存分离的原则。
class CacheManagementSection extends ConsumerStatefulWidget {
  const CacheManagementSection({super.key, this.localOnly = false});

  /// true = 只显示「清除本地数据」破坏性分组（AI 聊天记录、Cookie），
  /// false = 只显示图片缓存勾选与「清理所选」
  final bool localOnly;

  @override
  ConsumerState<CacheManagementSection> createState() =>
      _CacheManagementSectionState();
}

class _CacheManagementSectionState
    extends ConsumerState<CacheManagementSection> {
  /// null = 计算中
  Map<ImageCacheCategory, int>? _breakdown;
  int _aiChatDataSize = -1;
  int _cookieCacheSize = -1;
  bool _isClearing = false;

  /// 勾选状态。默认全选(Telegram 同款)。
  final Set<ImageCacheCategory> _selected = {...ImageCacheCategory.values};

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final results = await Future.wait([
      CacheSizeService.getImageCacheBreakdown(),
      CacheSizeService.getAiChatDataSize(prefs),
      CacheSizeService.getCookieCacheSize(),
    ]);
    if (mounted) {
      setState(() {
        _breakdown = results[0] as Map<ImageCacheCategory, int>;
        _aiChatDataSize = results[1] as int;
        _cookieCacheSize = results[2] as int;
      });
    }
  }

  int get _imageTotal =>
      _breakdown?.values.fold(0, (a, b) => a! + b) ?? -1;

  int get _selectedSize {
    final b = _breakdown;
    if (b == null) return 0;
    var total = 0;
    for (final c in _selected) {
      total += b[c] ?? 0;
    }
    return total;
  }

  String _formatCacheSize(int size) {
    if (size < 0) return S.current.dataManagement_calculating;
    if (size == 0) return S.current.dataManagement_noCache;
    return CacheSizeService.formatSize(size);
  }

  String _categoryName(ImageCacheCategory c) => switch (c) {
        ImageCacheCategory.content => S.current.dataManagement_categoryContent,
        ImageCacheCategory.emoji => S.current.dataManagement_categoryEmoji,
        ImageCacheCategory.avatar => S.current.dataManagement_categoryAvatar,
        ImageCacheCategory.sticker => S.current.dataManagement_categorySticker,
        ImageCacheCategory.external =>
          S.current.dataManagement_categoryExternal,
        ImageCacheCategory.other => S.current.dataManagement_categoryOther,
      };

  Future<void> _clearSelected() async {
    final size = _selectedSize;
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearSelectedTitle,
      content: S.current.dataManagement_clearSelectedContent,
      confirmText: S.current.common_clear,
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      for (final c in _selected) {
        await CacheSizeService.clearImageCacheCategory(c);
      }
      PaintingBinding.instance.imageCache.clear();
      ToastService.showSuccess(
        S.current.dataManagement_freedSpace(CacheSizeService.formatSize(size)),
      );
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
        await _loadCacheSizes();
      }
    }
  }

  Future<void> _clearAiChatData() async {
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearAiChatTitle,
      content: S.current.dataManagement_clearAiChatContent,
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await AiChatStorageService(prefs).deleteAllSessions();
      setState(() => _aiChatDataSize = 0);
      ToastService.showSuccess(S.current.dataManagement_aiChatCleared);
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearCookieCache() async {
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearCookieTitle,
      content: S.current.dataManagement_clearCookieContent,
      confirmText: S.current.dataManagement_clearAndLogout,
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() => _isClearing = true);
    try {
      await _doClearCookies();
      setState(() => _cookieCacheSize = 0);
      ToastService.showSuccess(S.current.dataManagement_cookieCleared);
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// 清除 Cookie，并同步执行退出登录链路的状态销毁。
  Future<void> _doClearCookies() async {
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(discourseServiceProvider).logout(callApi: false);
    await AppStateRefresher.resetForLogout(container);
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    String? confirmText,
    bool isDestructive = false,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(confirmText ?? context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.localOnly) return _buildLocalGroup(theme);
    final breakdown = _breakdown;

    // 按大小降序(Telegram 同款);计算中保持枚举顺序。
    final categories = [...ImageCacheCategory.values];
    if (breakdown != null) {
      categories.sort((a, b) => (breakdown[b] ?? 0) - (breakdown[a] ?? 0));
    }

    // 缓存总大小：异步算完才显示，算不出来（或没有缓存）就不显示
    final totalSize = breakdown == null
        ? 0
        : breakdown.values.fold<int>(0, (sum, v) => sum + (v > 0 ? v : 0));
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totalSize > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.m,
              0,
              AppSpace.m,
              AppSpace.xs,
            ),
            child: Text(
              context.l10n.dataManagement_cacheTotal(
                CacheSizeService.formatSize(totalSize),
              ),
              style: theme.textTheme.bodySmall
                  ?.merge(tokens.text.meta)
                  .copyWith(color: tokens.colors.textMeta),
            ),
          ),
        SegmentedCardGroup(
          children: [
            // 六类勾选行
            for (final c in categories)
              _buildCategoryTile(theme, c, breakdown?[c]),
            // 清理所选按钮(通栏,高度对齐 M3 FilledButton 规格)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: AppButtonStyles.secondary(context),
                  onPressed: _isClearing ||
                          breakdown == null ||
                          _selectedSize <= 0
                      ? null
                      : _clearSelected,
                  child: _isClearing
                      ? const LoadingSpinner(size: 18)
                      : Text(
                          S.current.dataManagement_clearSelected(
                            CacheSizeService.formatSize(_selectedSize),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 破坏性单独一组：清除 AI 聊天记录、清除 Cookie 并退出登录，均需确认
  Widget _buildLocalGroup(ThemeData theme) {
    return SegmentedCardGroup(
      children: [
        _buildLocalDataTile(
          theme: theme,
          icon: AppIcons.autoAwesome,
          title: context.l10n.dataManagement_clearAiChat,
          size: _aiChatDataSize,
          onClear: _isClearing ? null : _clearAiChatData,
        ),
        _buildLocalDataTile(
          theme: theme,
          icon: AppIcons.lock,
          title: context.l10n.dataManagement_clearCookieLogout,
          size: _cookieCacheSize,
          onClear: _isClearing ? null : _clearCookieCache,
        ),
      ],
    );
  }

  Widget _buildCategoryTile(
    ThemeData theme,
    ImageCacheCategory c,
    int? size,
  ) {
    final tokens = context.tokens;
    final color = tokens.colors.brandPrimary;
    final empty = size != null && size <= 0;
    final checked = _selected.contains(c) && !empty;
    final total = _imageTotal;
    // 占比:Telegram 同款,名称后跟小号加粗百分比;<1% 显示 <1%。
    String? percent;
    if (size != null && size > 0 && total > 0) {
      final p = size * 100 / total;
      percent = p < 1 ? '<1%' : '${p.round()}%';
    }
    return ListTile(
      dense: true,
      enabled: !empty && !_isClearing,
      leading: Checkbox(
        value: checked,
        shape: const CircleBorder(),
        activeColor: color,
        side: BorderSide(
          color: empty ? tokens.colors.separator : tokens.colors.quoteRule,
          width: 1.5,
        ),
        onChanged: empty || _isClearing
            ? null
            : (v) => setState(() {
                  if (v == true) {
                    _selected.add(c);
                  } else {
                    _selected.remove(c);
                  }
                }),
      ),
      title: Text.rich(
        TextSpan(
          text: _categoryName(c),
          children: [
            if (percent != null)
              TextSpan(
                text: '  $percent',
                style: theme.textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: tokens.colors.textMeta),
              ),
          ],
        ),
      ),
      trailing: size == null
          ? _ShimmerBox(width: 48, height: 14, theme: theme)
          : Text(
              _formatCacheSize(size),
              style: theme.textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: tokens.colors.textMeta),
            ),
      onTap: empty || _isClearing
          ? null
          : () => setState(() {
                if (_selected.contains(c)) {
                  _selected.remove(c);
                } else {
                  _selected.add(c);
                }
              }),
    );
  }

  Widget _buildLocalDataTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required int size,
    required VoidCallback? onClear,
  }) {
    final tokens = context.tokens;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: tokens.colors.textDestructive),
      ),
      trailing: Text(
        _formatCacheSize(size),
        style: theme.textTheme.bodySmall!
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta),
      ),
      enabled: size > 0 && onClear != null,
      onTap: size <= 0 ? null : onClear,
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.theme,
  });

  final double width;
  final double height;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTokens.of(context).colors.avatarFill,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 数据备份区块（被 CustomModel 包装）
// ─────────────────────────────────────────────

/// 数据备份区块，封装了导出和导入逻辑
class DataBackupSection extends ConsumerWidget {
  const DataBackupSection({super.key});

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    // 导出前敏感信息提示(备份 v2 含 API Key / 代理密码 / Notion Token)
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.dataManagement_exportConfirmTitle),
        content: Text(S.current.dataManagement_exportSensitiveWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.common_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final filePath = await DataBackupService.exportToFile(prefs);
      // 只保存、不走分享面板:备份里是明文 API Key / 代理密码 / Notion Token,
      // 分享面板一手滑就发进聊天软件了。
      final outcome = await ShareUtils.saveFile(
        XFile(filePath, mimeType: 'application/json'),
      );
      if (outcome.shared) {
        final name = outcome.displayName ?? p.basename(filePath);
        ToastService.showSuccess(S.current.export_savedAs(name));
      }
    } catch (e) {
      ToastService.showError(
          S.current.dataManagement_exportFailed(e.toString()));
    }
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final backup = await DataBackupService.parseBackupFile(filePath);
      final data = backup['data'] as Map<String, dynamic>;
      final apiKeys = backup['apiKeys'] as Map<String, dynamic>?;
      final appVersion =
          backup['appVersion'] as String? ?? S.current.common_unknown;
      final exportTime =
          backup['exportTime'] as String? ?? S.current.common_unknown;

      if (!context.mounted) return;

      final details = StringBuffer()
        ..writeln(S.current.dataManagement_backupSource(appVersion))
        ..writeln(S.current.dataManagement_exportTime(exportTime))
        ..writeln(S.current.dataManagement_settingsCount(data.length));
      if (apiKeys != null && apiKeys.isNotEmpty) {
        details.writeln(S.current.dataManagement_apiKeysCount(apiKeys.length));
      }
      details.write('\n${S.current.dataManagement_importWarning}');

      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AppAlertDialog(
          title: Text(S.current.dataManagement_confirmImport),
          content: Text(details.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.current.dataManagement_importAndRestart),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final prefs = ref.read(sharedPreferencesProvider);
      await DataBackupService.importData(prefs, backup);
      ToastService.showSuccess(S.current.dataManagement_importSuccess);
    } on FormatException catch (e) {
      ToastService.showError(e.message);
    } catch (e) {
      ToastService.showError(
          S.current.dataManagement_importFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedCardGroup(
      children: [
        ListTile(
          leading: Icon(AppIcons.upload, color: context.tokens.colors.brandPrimary),
          title: Text(context.l10n.dataManagement_exportData),
          trailing: Icon(
            AppIcons.chevronRight,
            color: context.tokens.colors.textMeta,
            size: AppSize.iconS,
          ),
          onTap: () => _exportData(context, ref),
        ),
        ListTile(
          leading: Icon(AppIcons.download, color: context.tokens.colors.brandPrimary),
          title: Text(context.l10n.dataManagement_importData),
          trailing: Icon(
            AppIcons.chevronRight,
            color: context.tokens.colors.textMeta,
            size: AppSize.iconS,
          ),
          onTap: () => _importData(context, ref),
        ),
      ],
    );
  }
}
