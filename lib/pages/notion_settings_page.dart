import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/s.dart';
import '../providers/notion_config_provider.dart';
import '../services/notion/notion_client.dart';
import '../services/notion/notion_config.dart';
import '../services/notion/notion_sync_service.dart';
import '../services/toast_service.dart';

import 'package:m3e_ui/m3e_ui.dart';

/// Notion 同步设置页：分步引导 + 配置编辑。
class NotionSettingsPage extends ConsumerStatefulWidget {
  const NotionSettingsPage({super.key});

  @override
  ConsumerState<NotionSettingsPage> createState() => _NotionSettingsPageState();
}

class _NotionSettingsPageState extends ConsumerState<NotionSettingsPage> {
  final _tokenController = TextEditingController();
  final _databaseIdController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;
  bool _initialized = false;
  bool _editing = false;
  bool? _needsUpgrade; // null = 未检测;true/false = 检测结果
  bool _upgrading = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _databaseIdController.dispose();
    super.dispose();
  }

  void _ensureInitialFromConfig(NotionConfig cfg) {
    // 不再用一次性 _initialized 标记 —— 那会让 username 还在 loading 时
    // 同步进空 cfg 后再也不更新。改为:只要 controller 还是空 + cfg 有值
    // 就同步一次。这样首次 build 拿到的是空 cfg(controller 也空,不冲突),
    // notifier 异步加载完成后 cfg 变为有值,本方法被再次调用时把值灌入。
    // 用户主动清空 controller 想抹掉配置时不会被回填(因为对应 cfg 也会被 clear)。
    if (_tokenController.text.isEmpty &&
        (cfg.integrationToken ?? '').isNotEmpty) {
      _tokenController.text = cfg.integrationToken!;
    }
    if (_databaseIdController.text.isEmpty &&
        (cfg.databaseId ?? '').isNotEmpty) {
      _databaseIdController.text = cfg.databaseId!;
    }
    if (!_initialized && cfg.isComplete) {
      _initialized = true;
      _checkUpgrade(cfg);
    }
  }

  Future<void> _checkUpgrade(NotionConfig cfg) async {
    try {
      final svc = NotionSyncService(config: cfg);
      final ok = await svc.isDatabaseUpToDate();
      if (!mounted) return;
      setState(() => _needsUpgrade = !ok);
    } catch (_) {
      // 检测失败就当不需要升级,不打扰用户
      if (mounted) setState(() => _needsUpgrade = false);
    }
  }

  Future<void> _doUpgrade(NotionConfig cfg) async {
    setState(() => _upgrading = true);
    try {
      final svc = NotionSyncService(config: cfg);
      await svc.upgradeDatabase();
      if (!mounted) return;
      setState(() => _needsUpgrade = false);
      ToastService.showSuccess(S.current.notion_upgradeSucceed);
    } on NotionApiException catch (e) {
      ToastService.showError(S.current.notion_upgradeFailed(e.message));
    } catch (e) {
      ToastService.showError(S.current.notion_upgradeFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  Future<void> _saveAndTest() async {
    final token = _tokenController.text.trim();
    final dbId = _databaseIdController.text.trim();
    if (token.isEmpty || dbId.isEmpty) {
      ToastService.showError(S.current.notion_fillTokenAndDb);
      return;
    }
    setState(() => _testing = true);
    try {
      final svc = NotionSyncService(
        config: NotionConfig(integrationToken: token, databaseId: dbId),
      );
      final title = await svc.testConnection();
      await ref
          .read(notionConfigProvider.notifier)
          .update(
            ref
                .read(notionConfigProvider)
                .copyWith(integrationToken: token, databaseId: dbId),
          );
      if (!mounted) return;
      ToastService.showSuccess(S.current.notion_testOk(title));
    } on NotionApiException catch (e) {
      ToastService.showError(S.current.notion_testFailed(e.message));
    } catch (e) {
      ToastService.showError(S.current.notion_testFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(notionConfigProvider.notifier).clear();
    if (!mounted) return;
    _tokenController.clear();
    _databaseIdController.clear();
    ToastService.show(S.current.notion_disconnected);
  }

  Future<void> _openIntegrationsPage() async {
    final uri = Uri.parse('https://www.notion.so/my-integrations');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _createTemplateDatabase() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ToastService.showError(S.current.notion_tokenRequired);
      return;
    }
    final parentId = await _askParentPageId();
    if (parentId == null || parentId.isEmpty) return;
    setState(() => _testing = true);
    try {
      final client = NotionClient(token);
      final created = await client.createDatabaseForExport(
        parentPageId: parentId,
        title: 'USCard Forum 导出',
      );
      final dbId = created['id'] as String?;
      if (dbId == null) throw NotionApiException('No id in response');
      _databaseIdController.text = dbId;
      if (!mounted) return;
      ToastService.showSuccess(S.current.notion_databaseCreated);
    } on NotionApiException catch (e) {
      ToastService.showError(S.current.notion_dbCreateFailed(e.message));
    } catch (e) {
      ToastService.showError(S.current.notion_dbCreateFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<String?> _askParentPageId() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(S.current.notion_pickParentPage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.current.notion_pickParentPageHint,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Parent Page ID',
                hintText: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = ref.watch(notionConfigProvider);
    _ensureInitialFromConfig(cfg);
    // 已完整配置且没有点"编辑"时,把步骤折叠成一行徽标。
    final showSteps = !cfg.isComplete || _editing;

    return Scaffold(
      backgroundColor: context.tokens.colors.surfacePage,
      appBar: AppNavBar(
        title: context.l10n.notion_title,
        slotWidth: 100,
        trailing: [
          if (cfg.isComplete)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: context.tokens.colors.textDestructive,
                minimumSize: const Size(AppSize.hit, AppSize.hit),
                padding: EdgeInsets.zero,
              ),
              onPressed: _testing ? null : _disconnect,
              child: Text(context.l10n.notion_disconnect),
            ),
        ],
      ),
      body: ReadableBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.s,
            AppSpace.pageMargin,
            AppSpace.x32,
          ),
          children: [
            // 顶部状态行：图标 + 标题 / 说明 + 右侧连接状态
            _StatusRow(connected: cfg.isComplete),
            const SizedBox(height: AppSpace.l),

            if (cfg.isComplete && _needsUpgrade == true) ...[
              _UpgradeBanner(
                upgrading: _upgrading,
                onUpgrade: () => _doUpgrade(cfg),
              ),
              const SizedBox(height: 16),
            ],

            if (!showSteps) ...[
              _ConfiguredBanner(onEdit: () => setState(() => _editing = true)),
            ] else ...[
              // Step 1: Token
              _StepCard(
                index: 1,
                title: context.l10n.notion_step1Title,
                body: context.l10n.notion_step1Body,
                done:
                    cfg.integrationToken != null &&
                    cfg.integrationToken!.isNotEmpty,
                children: [
                  _StepButton(
                    icon: AppIcons.openInNew,
                    label: context.l10n.notion_openIntegrationsPage,
                    onPressed: _openIntegrationsPage,
                  ),
                  AppFilledField(
                    // 平时占位当标签；聚焦或有内容时标签出现在框上方（品牌色）
                    label: context.l10n.notion_tokenSection,
                    floatingLabel: true,
                    hintText: context.l10n.notion_tokenSection,
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    fillColor: context.tokens.colors.surfacePage,
                    suffix: AppIconButton(
                      icon: _obscureToken
                          ? AppIcons.visibilityOff
                          : AppIcons.visibility,
                      size: AppSize.iconM,
                      color: context.tokens.colors.textMeta,
                      semanticLabel: _obscureToken
                          ? context.l10n.notion_showToken
                          : context.l10n.notion_hideToken,
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.l),

              // Step 2: Database
              _StepCard(
                index: 2,
                title: context.l10n.notion_step2Title,
                body: context.l10n.notion_step2Body,
                done: cfg.databaseId != null && cfg.databaseId!.isNotEmpty,
                children: [
                  AppFilledField(
                    label: context.l10n.notion_databaseIdLabel,
                    floatingLabel: true,
                    hintText: context.l10n.notion_databaseIdLabel,
                    controller: _databaseIdController,
                    autocorrect: false,
                    enableSuggestions: false,
                    fillColor: context.tokens.colors.surfacePage,
                    suffix: AppIconButton(
                      icon: AppIcons.clipboard,
                      size: AppSize.iconM,
                      color: context.tokens.colors.textMeta,
                      semanticLabel: context.l10n.common_paste,
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final text = data?.text?.trim();
                        if (text != null && text.isNotEmpty) {
                          _databaseIdController.text = text;
                        }
                      },
                    ),
                  ),
                  _StepButton(
                    icon: AppIcons.autoAwesome,
                    label: context.l10n.notion_createTemplateDb,
                    onPressed: _testing ? null : _createTemplateDatabase,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.l),

              // Step 3: Save + test
              _StepCard(
                index: 3,
                title: context.l10n.notion_step3Title,
                body: context.l10n.notion_step3Body,
                done: cfg.isComplete && !_editing,
                children: [
                  _StepButton(
                    primary: true,
                    loading: _testing,
                    icon: AppIcons.checkCircle,
                    label: context.l10n.notion_saveAndTest,
                    onPressed: _testing
                        ? null
                        : () async {
                            await _saveAndTest();
                            if (mounted &&
                                ref.read(notionConfigProvider).isComplete) {
                              setState(() => _editing = false);
                            }
                          },
                  ),
                ],
              ),
            ],

            // Sync options
            if (cfg.isComplete) ...[
              const SizedBox(height: 24),
              _SectionTitle(context.l10n.notion_syncOptions),
              const SizedBox(height: 8),
              SegmentedCardGroup(
                children: [
                  SwitchListTile.adaptive(
                    title: Text(
                      context.l10n.notion_autoSyncOnBookmark,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.notion_autoSyncDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: cfg.autoSyncOnBookmark,
                    onChanged: (v) {
                      ref
                          .read(notionConfigProvider.notifier)
                          .update(cfg.copyWith(autoSyncOnBookmark: v));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.notion_syncScope,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        M3eButtonGroup<NotionSyncScope>(
                          items: [
                            M3eButtonGroupItem(
                              value: NotionSyncScope.firstPostOnly,
                              label: Text(context.l10n.export_firstPostOnly),
                            ),
                            M3eButtonGroupItem(
                              value: NotionSyncScope.allPosts,
                              label: Text(context.l10n.common_all),
                            ),
                          ],
                          selected: cfg.syncScope,
                          onSelected: (scope) {
                            ref
                                .read(notionConfigProvider.notifier)
                                .update(cfg.copyWith(syncScope: scope));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpace.l),
            // 底部说明：分组底色条 + lock 16 + 13 meta
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.tokens.colors.surfaceGrouped,
                borderRadius: BorderRadius.circular(
                  context.tokens.radius.card,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      child: Icon(
                        AppIcons.lock,
                        size: AppSize.iconS,
                        color: context.tokens.colors.textMeta,
                      ),
                    ),
                    const SizedBox(width: AppSpace.s),
                    Expanded(
                      child: Text(
                        context.l10n.notion_tokenSecurityNote,
                        style: theme.textTheme.bodySmall
                            ?.merge(context.tokens.text.meta)
                            .copyWith(color: context.tokens.colors.textMeta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Database 缺少新版字段时显示的升级 banner。
class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.upgrading, required this.onUpgrade});

  final bool upgrading;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = context.tokens.colors.brandPrimary;
    return Container(
      padding: const EdgeInsets.all(AppSpace.m),
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(context.tokens.radius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.up, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.notion_upgradeAvailable,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.notion_upgradeMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: upgrading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppFixedColors.white,
                      ),
                    )
                  : const Icon(AppIcons.rocket, size: 16),
              onPressed: upgrading ? null : onUpgrade,
              label: Text(context.l10n.notion_upgradeAction),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 已配置完成状态下显示的紧凑徽标,替代 3 张步骤卡。
/// 点"修改"可重新展开编辑。
class _ConfiguredBanner extends StatelessWidget {
  const _ConfiguredBanner({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              AppIcons.check,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.notion_configured,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            icon: const Icon(AppIcons.edit, size: 16),
            onPressed: onEdit,
            label: Text(context.l10n.notion_editConfig),
          ),
        ],
      ),
    );
  }
}

/// 顶部状态行（surface/grouped r12，64 高）：folder-sync 20 + 标题 17 / 说明 13 meta，
/// 右侧「未连接 / 已连接」17 meta
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m,
            vertical: AppSpace.m,
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.folderSync,
                size: AppSize.iconM,
                color: colors.brandPrimary,
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.notion_title,
                      style: base
                          .merge(tokens.text.control)
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      context.l10n.notion_subtitle,
                      style: base
                          .merge(tokens.text.meta)
                          .copyWith(color: colors.textMeta),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.m),
              Text(
                connected
                    ? context.l10n.notion_statusConnected
                    : context.l10n.notion_statusDisconnected,
                style: base
                    .merge(tokens.text.control)
                    .copyWith(color: colors.textMeta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 步骤卡片（surface/grouped r12，内边距 16）：序号徽标 24 + 标题 17 Medium，
/// 正文 13 meta，下面是输入框 / 按钮（各 44 高，间距 12）。完成的步骤徽标变成 ✓。
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
    required this.done,
    required this.children,
  });

  final int index;
  final String title;
  final String body;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // 序号徽标：24 圆，surface/page 底、13 Medium；完成后 brand 底 + ✓
                Container(
                  width: AppSize.iconL,
                  height: AppSize.iconL,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? colors.brandButton : colors.surfacePage,
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? Icon(
                          AppIcons.check,
                          size: AppSize.iconS,
                          color: colors.onBrandButton,
                        )
                      : Text(
                          '$index',
                          style: base
                              .merge(tokens.text.metaStrong)
                              .copyWith(
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                        ),
                ),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: Text(
                    title,
                    style: base
                        .merge(tokens.text.control)
                        .copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.m),
            Text(
              body,
              style: base
                  .merge(tokens.text.meta)
                  .copyWith(color: colors.textMeta),
            ),
            for (final child in children) ...[
              const SizedBox(height: AppSpace.m),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// 步骤卡片里的按钮：44 高 r12。次按钮是 surface/page 底 + brand 文字；
/// [primary] 是 brand/button 底 + 白字。[onPressed] 为空时变淡不可点。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final foreground = primary ? colors.onBrandButton : colors.brandPrimary;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Opacity(
      opacity: onPressed == null && !loading ? 0.4 : 1,
      child: AppPressable(
        onTap: onPressed,
        semanticLabel: label,
        excludeChildSemantics: true,
        child: Container(
          height: AppSize.hit,
          decoration: BoxDecoration(
            color: primary ? colors.brandButton : colors.surfacePage,
            borderRadius: BorderRadius.circular(tokens.radius.card),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? SizedBox(
                      width: AppSize.iconM,
                      height: AppSize.iconM,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  : Icon(icon, size: AppSize.iconM, color: foreground),
              const SizedBox(width: AppSpace.s),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base
                      .merge(tokens.text.control)
                      .copyWith(
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
