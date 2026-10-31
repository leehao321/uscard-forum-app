import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../models/user.dart';
import '../providers/discourse_providers.dart';
import '../providers/selected_topic_provider.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/smart_avatar.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/layout/master_detail_pane_host.dart';
import 'user_profile_page.dart';
import '../l10n/s.dart';

/// 关注/粉丝列表页面
class FollowListPage extends ConsumerStatefulWidget {
  final String username;
  final bool isFollowing; // true=关注列表, false=粉丝列表

  const FollowListPage({
    super.key,
    required this.username,
    required this.isFollowing,
  });

  @override
  ConsumerState<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends ConsumerState<FollowListPage> {
  List<FollowUser>? _users;
  bool _isLoading = true;
  Object? _error;
  StackTrace? _errorStack;

  /// 本页里被取消关注的用户（只在「我的关注」列表里出现，本地即时反映）
  final Set<String> _unfollowed = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorStack = null;
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final users = widget.isFollowing
          ? await service.getFollowing(widget.username)
          : await service.getFollowers(widget.username);

      if (mounted) {
        setState(() {
          _users = users;
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

  Future<void> _toggleFollow(String username) async {
    if (_busy.contains(username)) return;
    final wasUnfollowed = _unfollowed.contains(username);
    setState(() => _busy.add(username));
    try {
      final service = ref.read(discourseServiceProvider);
      if (wasUnfollowed) {
        await service.followUser(username);
      } else {
        await service.unfollowUser(username);
      }
      if (!mounted) return;
      setState(() {
        wasUnfollowed ? _unfollowed.remove(username) : _unfollowed.add(username);
      });
    } catch (_) {
      // 失败保持原状，不打扰
    } finally {
      if (mounted) setState(() => _busy.remove(username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUsername = ref.watch(currentUserProvider).value?.username;
    // 只有在自己的「关注」列表里才能就地取消 / 重新关注
    final canToggle = widget.isFollowing && currentUsername == widget.username;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;

    final list = Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(
        title: widget.isFollowing
            ? context.l10n.followList_following
            : context.l10n.followList_followers,
        showDivider: true,
      ),
      body: _isLoading
          ? const Center(child: LoadingSpinner())
          : _error != null
          ? ErrorView(
              error: _error!,
              stackTrace: _errorStack,
              onRetry: _loadUsers,
            )
          : _users == null || _users!.isEmpty
          ? AppStateView(
              icon: AppIcons.people,
              title: context.l10n.common_noData,
            )
          : M3eRefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: _users!.length,
                itemBuilder: (context, index) {
                  final user = _users![index];
                  final name = user.name?.isNotEmpty == true
                      ? user.name!
                      : user.username;
                  // v2 行：34 头像 + 名字 17 + @handle 11，发丝线缩进 20
                  return AppPressable(
                    highlight: true,
                    onTap: () {
                      // 宽屏进右栏,窄屏全屏 push。
                      if (MasterDetailLayout.canShowBothPanesFor(context)) {
                        ref
                            .read(selectedFollowPaneProvider.notifier)
                            .selectProfile(user.username);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProfilePage(username: user.username),
                        ),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colors.separator,
                            width: AppSpace.hairline,
                          ),
                        ),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: AppSize.row48,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.pageMargin,
                          vertical: AppSpace.s,
                        ),
                        child: Row(
                          children: [
                            SmartAvatar(
                              imageUrl: user.avatarTemplate != null
                                  ? user.getAvatarUrl(size: 96)
                                  : null,
                              radius: 17,
                              fallbackText: user.username,
                            ),
                            const SizedBox(width: AppSpace.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: base
                                        .merge(tokens.text.control)
                                        .copyWith(color: colors.textPrimary),
                                  ),
                                  const SizedBox(height: AppSpace.xxs),
                                  Text(
                                    '@${user.username}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: base
                                        .merge(tokens.text.caption)
                                        .copyWith(color: colors.textMeta),
                                  ),
                                ],
                              ),
                            ),
                            if (canToggle)
                              _FollowPill(
                                followed: !_unfollowed.contains(user.username),
                                busy: _busy.contains(user.username),
                                onTap: () => _toggleFollow(user.username),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );

    return MasterDetailPaneHost(
      stackProvider: selectedFollowPaneProvider,
      master: list,
    );
  }
}

/// 「已关注 / ＋关注」胶囊：32 高，已关注是灰底、未关注是品牌色描边
class _FollowPill extends StatelessWidget {
  const _FollowPill({
    required this.followed,
    required this.busy,
    required this.onTap,
  });

  final bool followed;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final label = followed
        ? context.l10n.followList_followed
        : context.l10n.followList_follow;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: AppPressable(
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.hit),
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: followed ? colors.avatarFill : null,
                shape: StadiumBorder(
                  side: followed
                      ? BorderSide.none
                      : BorderSide(color: colors.brandPrimary),
                ),
              ),
              child: Text(
                label,
                style: base
                    .merge(tokens.text.meta)
                    .copyWith(
                      color: followed ? colors.textPrimary : colors.brandPrimary,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
