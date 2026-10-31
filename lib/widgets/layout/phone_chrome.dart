import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../navigation/nav_action_bus.dart';
import '../../pages/home/home_signals.dart';
import '../../pages/search_page.dart';
import '../../providers/message_bus/notification_providers.dart';
import '../../providers/preferences_provider.dart';
import 'adaptive_navigation.dart';

/// 手机底部的浮动 Tab 胶囊（+ 首页的搜索胶囊），0.4.0 计划 §5 M3。
///
/// 常驻，不随滚动隐藏；叠在内容上方。内容要给它留出 [kPhoneChromeHeight]
/// 的底部空间（[AdaptiveScaffold] 通过 MediaQuery 注入）。
class PhoneChrome extends ConsumerStatefulWidget {
  const PhoneChrome({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.forceHidden = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;

  /// 平行视界投影态：整条滑出屏幕
  final bool forceHidden;

  /// 胶囊底边在底部安全区之上的距离
  static const double bottomGap = AppSpace.xs + 2;

  @override
  ConsumerState<PhoneChrome> createState() => _PhoneChromeState();
}

/// 内容需要为浮动胶囊预留的高度（不含底部安全区）：胶囊 58 + 与安全区间距 6 + 呼吸 8
const double kPhoneChromeHeight =
    AppSize.tabCapsule + PhoneChrome.bottomGap + AppSpace.s;

class _PhoneChromeState extends ConsumerState<PhoneChrome> {
  int? _lastActiveTapIndex;
  DateTime? _lastActiveTapTime;
  Timer? _pendingSingleTap;

  static const _doubleTapWindow = Duration(milliseconds: 300);

  @override
  void dispose() {
    _pendingSingleTap?.cancel();
    super.dispose();
  }

  void _cancelPendingSingleTap() {
    _pendingSingleTap?.cancel();
    _pendingSingleTap = null;
  }

  /// 点击已选中的 tab：沿用原来的单击 / 双击动作（回顶、刷新等）
  void _handleTap(int index) {
    if (index != widget.selectedIndex) {
      _cancelPendingSingleTap();
      widget.onDestinationSelected(index);
      _lastActiveTapIndex = null;
      _lastActiveTapTime = null;
      return;
    }

    final prefs = ref.read(preferencesProvider);
    final single = prefs.bottomSingleTapAction;
    final doubleAction = prefs.bottomDoubleTapAction;
    final hasSingle = single != NavTapAction.none;
    final hasDouble = doubleAction != NavTapAction.none;
    if (!hasSingle && !hasDouble) return;

    final now = DateTime.now();
    final id = widget.destinations[index].id;
    final isDouble =
        hasDouble &&
        _lastActiveTapIndex == index &&
        _lastActiveTapTime != null &&
        now.difference(_lastActiveTapTime!) < _doubleTapWindow;

    if (isDouble) {
      _cancelPendingSingleTap();
      final navAction = doubleAction.toNavAction();
      if (navAction != null) ref.dispatchNavAction(id, navAction);
      _lastActiveTapIndex = null;
      _lastActiveTapTime = null;
      return;
    }

    _lastActiveTapIndex = index;
    _lastActiveTapTime = now;
    if (!hasSingle) return;
    final navAction = single.toNavAction();
    if (navAction == null) return;

    if (hasDouble) {
      _cancelPendingSingleTap();
      _pendingSingleTap = Timer(_doubleTapWindow, () {
        _pendingSingleTap = null;
        if (!mounted) return;
        ref.dispatchNavAction(id, navAction);
        if (_lastActiveTapIndex == index) {
          _lastActiveTapIndex = null;
          _lastActiveTapTime = null;
        }
      });
    } else {
      ref.dispatchNavAction(id, navAction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(
      notificationCountStateProvider.select((s) => s.allUnread > 0),
    );
    final items = [
      for (final d in widget.destinations)
        FloatingTabItem(
          icon: d.iconData,
          label: d.label,
          showDot: d.id == NavEntryIds.notifications && unread,
        ),
    ];
    final onHome =
        widget.destinations.isNotEmpty &&
        widget.selectedIndex >= 0 &&
        widget.selectedIndex < widget.destinations.length &&
        widget.destinations[widget.selectedIndex].id == NavEntryIds.home;

    // 0.0 是各页的「强制隐藏」通道（书签工作台模式等）
    final hidden =
        widget.forceHidden || ref.watch(barVisibilityProvider) == 0.0;
    final insets = readableInsets(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        offset: Offset(0, hidden ? 1.5 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: EdgeInsets.only(
            left: insets.left,
            right: insets.right,
            bottom: safeBottom + PhoneChrome.bottomGap,
          ),
          child: Row(
            children: [
              FloatingTabBar(
                items: items,
                currentIndex: widget.selectedIndex.clamp(0, items.length - 1),
                onTap: _handleTap,
              ),
              if (onHome) ...[
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: SearchCapsule(
                    placeholder: context.l10n.search_capsulePlaceholder,
                    compactPlaceholder: context.l10n.search_capsuleCompact,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
