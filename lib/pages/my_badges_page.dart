import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../models/badge.dart';
import '../providers/discourse_providers.dart';
import '../services/discourse_cache_manager.dart';
import '../utils/url_helper.dart';
import '../widgets/badge/my_badges_skeleton.dart';
import '../widgets/common/error_view.dart';
import '../utils/font_awesome_helper.dart';
import '../widgets/badge/badge_ui_utils.dart';
import 'badge_page.dart';
import '../l10n/s.dart';

/// 我的徽章页面
class MyBadgesPage extends ConsumerStatefulWidget {
  const MyBadgesPage({super.key});

  @override
  ConsumerState<MyBadgesPage> createState() => _MyBadgesPageState();
}

class _MyBadgesPageState extends ConsumerState<MyBadgesPage> {
  Map<BadgeType, List<UserBadge>>? _groupedBadges;
  bool _isLoading = true;
  Object? _error;
  StackTrace? _errorStack;

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorStack = null;
    });

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) {
        setState(() {
          _error = Exception(S.current.error_unauthorizedExpired);
          _isLoading = false;
        });
        return;
      }

      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserBadges(username: user.username);

      final Map<BadgeType, List<UserBadge>> grouped = {};
      for (var userBadge in response.userBadges) {
        if (userBadge.badge == null) continue;
        final type = userBadge.badge!.badgeType;
        if (!grouped.containsKey(type)) {
          grouped[type] = [];
        }
        grouped[type]!.add(userBadge);
      }

      if (mounted) {
        setState(() {
          _groupedBadges = grouped;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      if (mounted) {
        setState(() {
          _error = e;
          _errorStack = s;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    // 卡片高度随字号放大：头像 48 + 两行名称 + 一行类型 + 内边距
    final ts = MediaQuery.textScalerOf(context).scale(13) / 13;
    final cardExtent = 82 + 52 * ts;
    // 金银铜顺序展开成一个三列网格（设计说明 §5.2：金银铜只写字，不加颜色）
    final all = <UserBadge>[
      for (final type in [BadgeType.gold, BadgeType.silver, BadgeType.bronze])
        ...?_groupedBadges?[type],
    ];

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(title: context.l10n.myBadges_title),
      body: _isLoading
          ? const MyBadgesSkeleton()
          : _error != null
          ? ErrorView(
              error: _error!,
              stackTrace: _errorStack,
              onRetry: _loadBadges,
            )
          : M3eRefreshIndicator(
              onRefresh: _loadBadges,
              child: CustomScrollView(
                slivers: [
                  if (all.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppStateView(
                        icon: AppIcons.medal,
                        title: context.l10n.myBadges_empty,
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.pageMargin,
                          AppSpace.l,
                          AppSpace.pageMargin,
                          AppSpace.s,
                        ),
                        child: Text(
                          '${context.l10n.myBadges_totalEarned} · ${all.length}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.merge(context.tokens.text.meta)
                              .copyWith(color: colors.textMeta),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.pageMargin,
                        0,
                        AppSpace.pageMargin,
                        AppSpace.xxl,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: AppSpace.s,
                              crossAxisSpacing: AppSpace.s,
                              mainAxisExtent: cardExtent,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildBadgeItem(all[index]),
                          childCount: all.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// 三列卡片：surface/grouped r12 pad 12；48 圆（award 24 brand 或徽章图）
  /// + 名称 13 Semibold + 「金 · ×2」11 meta
  Widget _buildBadgeItem(UserBadge userBadge) {
    final badge = userBadge.badge!;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final type = badge.badgeType;
    final base = Theme.of(context).textTheme.bodySmall!;

    Widget icon;
    final fallback = FaIcon(
      badge.icon != null && badge.icon!.isNotEmpty
          ? (FontAwesomeHelper.getIcon(badge.icon!) ??
                BadgeUIUtils.getBadgeIcon(type))
          : BadgeUIUtils.getBadgeIcon(type),
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

    final typeName = BadgeUIUtils.getBadgeTypeName(type);
    final sub = userBadge.count > 1
        ? '$typeName · ×${userBadge.count}'
        : typeName;

    return Semantics(
      button: true,
      label: '${badge.name}，$sub',
      excludeSemantics: true,
      child: AppPressable(
        onTap: () {
          final user = ref.read(currentUserProvider).value;
          if (user != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => BadgePage(
                  badgeId: badge.id,
                  badgeSlug: badge.slug,
                  username: user.username,
                ),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpace.m),
          decoration: BoxDecoration(
            color: colors.surfaceGrouped,
            borderRadius: BorderRadius.circular(tokens.radius.card),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfacePage,
                ),
                child: icon,
              ),
              const SizedBox(height: AppSpace.s),
              Text(
                badge.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: base
                    .merge(tokens.text.metaStrong)
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: base
                    .merge(tokens.text.caption)
                    .copyWith(color: colors.textMeta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
