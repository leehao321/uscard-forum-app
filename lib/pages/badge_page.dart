import 'package:flutter/material.dart' hide Badge;
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/badge.dart';
import '../providers/core_providers.dart';
import '../services/discourse/discourse_service.dart';
import '../widgets/common/relative_time_text.dart';
import '../utils/font_awesome_helper.dart';
import '../services/discourse_cache_manager.dart';
import '../utils/url_helper.dart';
import '../widgets/common/error_view.dart';

import 'package:m3e_ui/m3e_ui.dart';

import '../widgets/common/smart_avatar.dart';
import '../widgets/badge/badge_ui_utils.dart';
import '../utils/fluxdo_render_callbacks.dart';
import '../services/emoji_handler.dart';
import '../providers/selected_topic_provider.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/layout/master_detail_pane_host.dart';
import 'topic_detail_page/topic_detail_page.dart';
import 'user_profile_page.dart';
import '../l10n/s.dart';

import 'package:app_icons/app_icons.dart';

/// 徽章详情页面
class BadgePage extends ConsumerStatefulWidget {
  final int badgeId;
  final String? badgeSlug;
  final String? username; // 可选，筛选特定用户

  const BadgePage({
    super.key,
    required this.badgeId,
    this.badgeSlug,
    this.username,
  });

  @override
  ConsumerState<BadgePage> createState() => _BadgePageState();
}

class _BadgePageState extends ConsumerState<BadgePage> {
  // 走 provider，测试里才能换成假服务（M-3）
  DiscourseService get _service => ref.read(discourseServiceProvider);
  BadgeDetailResponse? _badgeDetail;
  bool _isLoading = true;
  Object? _error;
  StackTrace? _errorStack;

  @override
  void initState() {
    super.initState();
    _loadBadgeDetail();
  }

  Future<void> _loadBadgeDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorStack = null;
    });

    try {
      final badge = await _service.getBadge(badgeId: widget.badgeId);
      final usersResponse = await _service.getBadgeUsers(
        badgeId: widget.badgeId,
        username: widget.username,
      );

      if (mounted) {
        setState(() {
          _badgeDetail = BadgeDetailResponse(
            badge: badge,
            userBadges: usersResponse.userBadges,
            grantedBies: usersResponse.grantedBies,
            totalCount: usersResponse.totalCount,
          );
          _isLoading = false;
        });
      }
    } catch (e, s) {
      debugPrint('Error loading badge detail: $e');
      if (mounted) {
        setState(() {
          _error = e;
          _errorStack = s;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadBadgeDetail();
  }

  @override
  Widget build(BuildContext context) {
    final list = Scaffold(
      // 内容加载出来后顶栏在 CustomScrollView 里；加载和出错态没有顶栏，补一个带返回键的
      appBar: (_isLoading || _error != null)
          ? AppNavBar(title: context.l10n.badge_defaultName)
          : null,
      body: ReadableBody(
        child: _isLoading
            ? const Center(child: LoadingSpinner())
            : _error != null
            ? ErrorView(
                error: _error!,
                stackTrace: _errorStack,
                onRetry: _onRefresh,
              )
            : M3eRefreshIndicator(
                onRefresh: _onRefresh,
                child: CustomScrollView(
                  slivers: [
                    // Modern Sliver App Bar
                    _buildSliverAppBar(context),

                    // Badge Info Card (Floating effect)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: _BadgeInfoCard(badge: _badgeDetail!.badge),
                      ),
                    ),

                    // Users Header
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.people,
                              color: Theme.of(context).colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.badge_grantees,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: AppFontSize.body,
                                  ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                context.l10n.badge_granteeCount(
                                  _badgeDetail!.totalCount,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // User List
                    _badgeDetail!.userBadges.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    AppIcons.userOff,
                                    size: 48,
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    context.l10n.badge_noGrantees,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final userBadge = _badgeDetail!.userBadges[index];

                              if (_badgeDetail!.grantedBies.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              // 只认 id 对得上的授予人，对不上就不显示这一行
                              final user = _badgeDetail!.grantedBies
                                  .where((u) => u.id == userBadge.userId)
                                  .firstOrNull;
                              if (user == null) return const SizedBox.shrink();

                              return _UserBadgeItem(
                                userBadge: userBadge,
                                user: user,
                              );
                            }, childCount: _badgeDetail!.userBadges.length),
                          ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
                  ],
                ),
              ),
      ),
    );

    return MasterDetailPaneHost(
      stackProvider: selectedBadgePaneProvider,
      master: list,
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    // v2：没有渐变头图，只留一条页面底色的导航
    final colors = context.tokens.colors;
    return SliverAppBar(
      pinned: true,
      backgroundColor: colors.surfacePage,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: colors.textPrimary),
    );
  }
}

/// 徽章详情头：居中 48 圆 + 名称 17 Semibold + 说明 13 meta + 「金 · 1,204 人获得」11
class _BadgeInfoCard extends StatelessWidget {
  final Badge badge;

  const _BadgeInfoCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final badgeType = badge.badgeType;
    final typeName = BadgeUIUtils.getBadgeTypeName(badgeType);
    final base = theme.textTheme.bodySmall!;

    Widget icon;
    final fallback = FaIcon(
      badge.icon != null && badge.icon!.isNotEmpty
          ? (FontAwesomeHelper.getIcon(badge.icon!) ?? FontAwesomeHelper.medal)
          : FontAwesomeHelper.medal,
      size: 24,
      color: colors.brandPrimary,
    );
    if (badge.imageUrl != null && badge.imageUrl!.isNotEmpty) {
      icon = Image(
        image: discourseImageProvider(
          UrlHelper.resolveUrlWithCdn(badge.imageUrl!),
        ),
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      icon = fallback;
    }

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surfaceGrouped,
          ),
          child: icon,
        ),
        SizedBox(height: AppSpace.m),
        Semantics(
          header: true,
          child: Text(
            badge.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.merge(tokens.text.title)
                .copyWith(
                  color: colors.textPrimary,
                  fontSize: AppFontSize.body,
                ),
          ),
        ),
        SizedBox(height: AppSpace.s),
        // 徽章描述属只读展示：走新引擎 FluxdoRender，关闭划词选区；
        // 仍保留 EmojiHandler().replaceEmojis 预处理表情。
        FluxdoRenderCallbacks.generic(
          heroTagNamespace: 'badge_${badge.id}_desc',
        ).render(
          cookedHtml: EmojiHandler().replaceEmojis(badge.description),
          baseTextStyle: base
              .merge(tokens.text.meta)
              .copyWith(color: colors.textMeta),
          selectionEnabled: false,
        ),
        if (badge.longDescription != null &&
            badge.longDescription!.isNotEmpty) ...[
          SizedBox(height: AppSpace.m),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(AppSpace.m),
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            child:
                FluxdoRenderCallbacks.generic(
                  heroTagNamespace: 'badge_${badge.id}_longdesc',
                ).render(
                  cookedHtml: EmojiHandler().replaceEmojis(
                    badge.longDescription!,
                  ),
                  baseTextStyle: base
                      .merge(tokens.text.meta)
                      .copyWith(color: colors.textMeta),
                  selectionEnabled: false,
                ),
          ),
        ],
        SizedBox(height: AppSpace.m),
        // 金银铜只写字，不加颜色
        Text(
          '$typeName · ${context.l10n.badge_grantedCount(badge.grantCount)}',
          style: base
              .merge(tokens.text.caption)
              .copyWith(color: colors.textMeta),
        ),
      ],
    );
  }
}

/// 用户列表项 - 现代化
class _UserBadgeItem extends StatelessWidget {
  final UserBadge userBadge;
  final BadgeUser user;

  const _UserBadgeItem({required this.userBadge, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: userBadge.topicId != null ? () => _navigateToTopic(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Expanded Avatar
            GestureDetector(
              onTap: () => _navigateToUser(context),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                    width: 1,
                  ),
                ),
                child: SmartAvatar(
                  imageUrl: user.getAvatarUrl(),
                  radius: 24,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  fallbackText: user.username,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name line
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _navigateToUser(context),
                          child: Text(
                            user.username,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (user.admin == true) ...[
                        const SizedBox(width: 4),
                        Icon(
                          AppIcons.shield,
                          size: 14,
                          color: context.tokens.colors.textDestructive,
                        ),
                      ] else if (user.moderator == true) ...[
                        const SizedBox(width: 4),
                        Icon(
                          AppIcons.shield,
                          size: 14,
                          color: context.tokens.colors.brandPrimary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Date
                  RelativeTimeText(
                    dateTime: userBadge.grantedAt,
                    displayStyle: TimeDisplayStyle.suffixed,
                    suffix: context.l10n.badge_grantedSuffix,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),

                  // Topic Link
                  if (userBadge.topicTitle != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            AppIcons.article,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              userBadge.topicTitle!,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: AppFontSize.meta,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToUser(BuildContext context) {
    // 宽屏进本页右栏,窄屏全屏 push(平行视界宿主标准分流)。
    if (MasterDetailLayout.canShowBothPanesFor(context)) {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(selectedBadgePaneProvider.notifier).selectProfile(user.username);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: user.username),
      ),
    );
  }

  void _navigateToTopic(BuildContext context) {
    if (userBadge.topicId != null) {
      if (MasterDetailLayout.canShowBothPanesFor(context)) {
        ProviderScope.containerOf(context, listen: false)
            .read(selectedBadgePaneProvider.notifier)
            .select(
              topicId: userBadge.topicId!,
              scrollToPostNumber: userBadge.postNumber,
            );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TopicDetailPage(
            topicId: userBadge.topicId!,
            scrollToPostNumber: userBadge.postNumber,
          ),
        ),
      );
    }
  }
}
