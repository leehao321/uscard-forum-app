import '../services/app_lock_service.dart';
import 'app_lock_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/shortcut_binding.dart';
import '../providers/appearance_provider.dart';
import '../providers/notion_config_provider.dart';
import '../services/network/rhttp/rhttp_settings_service.dart';
import '../services/network/webview/webview_adapter_settings_service.dart';
import '../utils/app_version.dart';
import '../providers/shortcut_provider.dart';
import '../settings/search/settings_search_index.dart';
import '../utils/appearance_warmup.dart';
import '../utils/platform_utils.dart';
import '../utils/responsive.dart';
import 'package:m3e_ui/m3e_ui.dart';
import '../widgets/esc_fallback_observer.dart';
import '../widgets/layout/master_detail_layout.dart';
import 'about_page.dart';
import 'appearance_page.dart';
import 'bottom_nav_settings_page.dart';
import 'diagnostics_page.dart';
import 'data_management_page.dart';
import 'network_settings_page/network_settings_page.dart';
import 'notion_settings_page.dart';
import 'preferences_page.dart';
import 'reading_settings_page.dart';
import 'shortcut_settings_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  static const double parallelMasterWidth = PaneBreakpoints.settingsMasterWidth;
  static const double parallelMinDetailWidth =
      PaneBreakpoints.settingsMinDetailWidth;

  /// 平行视界嵌入模式：AppBar 用 [onEmbeddedBack] 关闭当前层，而不是
  /// Navigator pop（嵌入面板不在 Navigator 路由栈里）。页面自身宽度
  /// 足够时，子设置页会进入右侧的独立 Navigator；窄屏仍全屏 push。
  final bool embeddedMode;
  final VoidCallback? onEmbeddedBack;

  /// 宿主 tab 是否活跃(嵌入模式下用于 surface 注册失活:IndexedStack
  /// 常驻页共享根路由,非活跃 tab 的注册会截胡活跃 tab 的按键)。
  final bool parentActive;

  const SettingsPage({
    super.key,
    this.embeddedMode = false,
    this.onEmbeddedBack,
    this.parentActive = true,
  });

  @visibleForTesting
  static bool canShowParallelFor(BuildContext context) {
    return MasterDetailLayout.canShowBothPanesFor(
      context,
      masterWidth: parallelMasterWidth,
      minDetailWidth: parallelMinDetailWidth,
    );
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _detailNavigatorKey = GlobalKey<NavigatorState>();
  late final ShortcutSurfaceBinding _shortcutSurfaceBinding =
      ShortcutSurfaceBinding(
        ref: ref,
        id: ShortcutSurfaceIds.settings,
        triggerAction: ShortcutAction.openSettings,
        kind: ShortcutSurfaceKind.route,
        repeatBehavior: ShortcutSurfaceRepeatBehavior.reveal,
        passthroughActions: ShortcutSurfaceActionSets.globalRoutePassthrough,
        // 嵌入在 IndexedStack 常驻 tab 里时,宿主不活跃则本 surface 不
        // 参与分发(否则 blocksShortcuts 会拦掉其他 tab 的按键)。
        enabled: () => !widget.embeddedMode || widget.parentActive,
      );
  ModalRoute<dynamic>? _route;
  String _query = '';
  String _version = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_version.isEmpty) {
      loadDisplayVersion().then((v) {
        if (mounted) setState(() => _version = v);
      }).catchError((_) {});
    }
    // 趁界面静止把外观页首帧的一次性开销（MiSans 字体懒加载）提前做掉，
    // 否则首次进入外观页会明显顿一下。
    AppearanceWarmup.schedule();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _route = route;
    _shortcutSurfaceBinding.registerDeferred(
      context,
      onClose: () => Navigator.of(context).maybePop(),
      onFocus: _revealSelf,
    );
  }

  void _revealSelf() {
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null || route.isCurrent) return;
    navigator.popUntil((candidate) => identical(candidate, route));
  }

  @override
  void dispose() {
    _shortcutSurfaceBinding.disposeDeferred();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isSearching = _query.isNotEmpty;

    final master = _buildSettingsScaffold(theme, l10n, isSearching);
    final canShowParallel = SettingsPage.canShowParallelFor(context);
    if (!canShowParallel) return master;

    return MasterDetailLayout(
      masterWidth: SettingsPage.parallelMasterWidth,
      minDetailWidth: SettingsPage.parallelMinDetailWidth,
      minMasterRatio: 0.28,
      maxMasterRatio: 0.48,
      preferredMasterRatio: 0.34,
      master: master,
      detail: Navigator(
        key: _detailNavigatorKey,
        // 内栏子页登记 ESC 兜底(共享全局登记表):有子页时 ESC 先退
        // 子页;退到内栏基层(isFirst 不登记)后落回设置页自身 surface
        // 关整页——修掉"宽屏设置 ESC 直接关整页"的旧行为。
        observers: [EscFallbackObserver()],
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: const RouteSettings(name: 'settings-detail-empty'),
          builder: (_) => _buildDetailEmptyState(theme),
        ),
      ),
    );
  }

  Widget _buildSettingsScaffold(
    ThemeData theme,
    AppLocalizations l10n,
    bool isSearching,
  ) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      // embeddedMode 但 onEmbeddedBack 为空（master 面板"上一层预览"，
      // 非当前可交互栈顶）时不能出返回键——返回会退化成默认
      // Navigator.maybePop()，直接捅穿到应用根导航栈（见
      // user_profile_page.dart 同类修复的注释）。
      appBar: AppNavBar(
        title: l10n.settings_title,
        showDivider: false,
        automaticallyImplyLeading: !widget.embeddedMode,
        leading: widget.embeddedMode && widget.onEmbeddedBack != null
            ? AppIconButton(
                icon: AppIcons.back,
                semanticLabel: MaterialLocalizations.of(
                  context,
                ).backButtonTooltip,
                onPressed: widget.onEmbeddedBack,
              )
            : null,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
          child: Column(
            children: [
              _buildSearchField(theme, l10n),
              Expanded(
                child: isSearching
                    ? _buildSearchResults(theme)
                    : _buildCategoryList(theme, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 页内搜索框：44 高 r10 elevated；有输入时右侧出「取消」
  Widget _buildSearchField(ThemeData theme, AppLocalizations l10n) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = theme.textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.xs,
        AppSpace.pageMargin,
        AppSpace.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: AppSize.hit,
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: (value) => setState(() => _query = value.trim()),
                textInputAction: TextInputAction.search,
                cursorColor: colors.brandPrimary,
                style: base
                    .merge(tokens.text.control)
                    .copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.settings_searchHint,
                  hintStyle: base
                      .merge(tokens.text.control)
                      .copyWith(color: colors.textMeta),
                  prefixIcon: Icon(
                    AppIcons.search,
                    size: AppSize.iconM,
                    color: colors.textMeta,
                  ),
                  filled: true,
                  fillColor: colors.surfaceGrouped,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.m,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius.field),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
                _focusNode.unfocus();
              },
              child: Text(context.l10n.common_cancel),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailEmptyState(ThemeData theme) {
    final colors = context.tokens.colors;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.settings, size: 56, color: colors.quoteRule),
            const SizedBox(height: AppSpace.m),
            Text(
              context.l10n.settings_selectHint,
              style: theme.textTheme.bodyLarge
                  ?.merge(context.tokens.text.control)
                  .copyWith(color: colors.textMeta),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsPage(WidgetBuilder builder) {
    final canShowParallel = SettingsPage.canShowParallelFor(context);
    if (!canShowParallel) {
      Navigator.push(context, MaterialPageRoute(builder: builder));
      return;
    }

    void pushIntoDetail() {
      final navigator = _detailNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: builder),
        (route) => route.isFirst,
      );
    }

    if (_detailNavigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) pushIntoDetail();
      });
    } else {
      pushIntoDetail();
    }
  }

  /// 搜索结果（自动从数据声明派生）：行 = 名称（命中字 brand）+ 路径（13 meta）
  Widget _buildSearchResults(ThemeData theme) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final allResults = buildSearchIndex(context);
    final q = _query.toLowerCase();
    final filtered = allResults.where((r) => r.model.matchesQuery(q)).toList();

    if (filtered.isEmpty) {
      return AppStateView(
        icon: AppIcons.searchOff,
        title: context.l10n.settings_searchEmpty,
      );
    }

    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final titleStyle = theme.textTheme.bodyMedium!
        .merge(tokens.text.control)
        .copyWith(color: colors.textPrimary);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        0,
        AppSpace.pageMargin,
        MediaQuery.paddingOf(context).bottom + AppSpace.x32,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.m,
            AppSpace.s,
            AppSpace.m,
            AppSpace.s,
          ),
          child: Text(
            context.l10n.settings_resultCount(filtered.length),
            style: metaStyle,
          ),
        ),
        SegmentedCardGroup(
          children: [
            for (final result in filtered)
              ListTile(
                title: Text.rich(
                  _highlightSpan(
                    result.model.title,
                    q,
                    titleStyle,
                    colors.brandPrimary,
                  ),
                ),
                subtitle: Text(result.path, style: metaStyle),
                trailing: Icon(
                  AppIcons.chevronRight,
                  size: AppSize.iconS,
                  color: colors.textMeta,
                ),
                onTap: () => _openSettingsPage(
                  (_) => result.pageBuilder(highlightId: result.model.id),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 命中的字用 brand 色，不加底色
  static TextSpan _highlightSpan(
    String text,
    String lowerQuery,
    TextStyle base,
    Color highlight,
  ) {
    final i = text.toLowerCase().indexOf(lowerQuery);
    if (lowerQuery.isEmpty || i < 0) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(
          text: text.substring(i, i + lowerQuery.length),
          style: TextStyle(color: highlight),
        ),
        TextSpan(text: text.substring(i + lowerQuery.length)),
      ],
    );
  }

  /// 外观行右侧的当前值：预设名或「自定义」
  String _appearanceValue(AppLocalizations l10n) {
    final preset = AppearancePreset.match(ref.watch(appearanceProvider));
    return switch (preset) {
      AppearancePreset.standard => l10n.settings_presetStandard,
      AppearancePreset.compact => l10n.settings_presetCompact,
      AppearancePreset.comfortable => l10n.settings_presetComfortable,
      AppearancePreset.largeText => l10n.settings_presetLargeText,
      null => l10n.settings_valueCustom,
    };
  }

  /// 网络引擎行右侧的当前值：标准 / 高性能 / 兼容 / 自定义
  String _engineValue(AppLocalizations l10n) {
    final rhttp = RhttpSettingsService.instance.current;
    final webview = WebViewAdapterSettingsService.instance.enabled;
    if (!rhttp.enabled && !webview) return l10n.settings_engineStandard;
    if (rhttp.enabled && rhttp.mode == RhttpMode.always && !webview) {
      return l10n.settings_engineHigh;
    }
    if (!rhttp.enabled && webview) return l10n.settings_engineCompat;
    return l10n.settings_engineCustom;
  }

  /// 默认分类列表：显示与阅读 / 安全与网络 / 数据 / 高级
  Widget _buildCategoryList(ThemeData theme, AppLocalizations l10n) {
    final lockOn =
        AppLockService.isSupportedPlatform && AppLockService.instance.enabled;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        0,
        AppSpace.pageMargin,
        MediaQuery.paddingOf(context).bottom + AppSpace.x32,
      ),
      children: [
        _group(l10n.settings_groupDisplay, [
          _optionTile(
            icon: AppIcons.palette,
            title: l10n.settings_appearance,
            value: _appearanceValue(l10n),
            onTap: () => _openSettingsPage((_) => const AppearancePage()),
          ),
          _optionTile(
            icon: AppIcons.autoStories,
            title: l10n.settings_reading,
            onTap: () => _openSettingsPage((_) => const ReadingSettingsPage()),
          ),
          _optionTile(
            icon: AppIcons.menu,
            title: l10n.settings_bottomNav,
            onTap: () =>
                _openSettingsPage((_) => const BottomNavSettingsPage()),
          ),
          _optionTile(
            icon: AppIcons.tune,
            title: l10n.settings_preferences,
            onTap: () => _openSettingsPage((_) => const PreferencesPage()),
          ),
        ]),
        _group(l10n.settings_groupSecurity, [
          if (AppLockService.isSupportedPlatform)
            _optionTile(
              icon: AppIcons.lock,
              title: l10n.settings_appLock,
              value: lockOn ? l10n.settings_valueOn : l10n.settings_valueOff,
              onTap: () =>
                  _openSettingsPage((_) => const AppLockSettingsPage()),
            ),
          _optionTile(
            icon: AppIcons.serverOff,
            title: l10n.settings_network,
            value: _engineValue(l10n),
            onTap: () => _openSettingsPage((_) => const NetworkSettingsPage()),
          ),
        ]),
        _group(l10n.settings_groupData, [
          _optionTile(
            icon: AppIcons.folder,
            title: l10n.settings_dataManagement,
            onTap: () => _openSettingsPage((_) => const DataManagementPage()),
          ),
          _optionTile(
            icon: AppIcons.cloud,
            title: l10n.notion_title,
            value: ref.watch(notionConfigProvider).isComplete
                ? l10n.settings_valueConnected
                : l10n.settings_valueDisconnected,
            onTap: () => _openSettingsPage((_) => const NotionSettingsPage()),
          ),
        ]),
        _group(l10n.settings_groupAdvanced, [
          // 快捷键（仅桌面端）
          if (PlatformUtils.isDesktop)
            _optionTile(
              icon: AppIcons.code,
              title: l10n.settings_shortcuts,
              onTap: () =>
                  _openSettingsPage((_) => const ShortcutSettingsPage()),
            ),
          _optionTile(
            icon: AppIcons.history,
            title: l10n.settings_diagnostics,
            onTap: () => _openSettingsPage((_) => const DiagnosticsPage()),
          ),
          _optionTile(
            icon: AppIcons.info,
            title: l10n.settings_about,
            value: _version.isEmpty ? null : _version,
            onTap: () => _openSettingsPage((_) => const AboutPage()),
          ),
        ]),
      ],
    );
  }

  Widget _group(String title, List<Widget> children) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.m,
              AppSpace.s,
              AppSpace.m,
              AppSpace.s,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: tokens.colors.textMeta),
              ),
            ),
          ),
          SegmentedCardGroup(children: children),
        ],
      ),
    );
  }

  /// 分组行：20 brand 图标 + 17 标题 + 右侧当前值（13 meta）+ chevron
  Widget _optionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? value,
  }) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return ListTile(
      leading: Icon(icon, color: colors.brandPrimary),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: colors.textMeta),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          Icon(
            AppIcons.chevronRight,
            size: AppSize.iconS,
            color: colors.textMeta,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
