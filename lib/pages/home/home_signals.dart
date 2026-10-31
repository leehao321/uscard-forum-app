// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

/// 递增计数的信号：每次 [trigger] 让监听者各自处理一次（回顶等）
class ScrollToTopNotifier extends StateNotifier<int> {
  ScrollToTopNotifier() : super(0);

  void trigger() => state++;
}

/// 回到顶部信号（底栏双击 / 重选 Tab 等）
final scrollToTopProvider = StateNotifierProvider<ScrollToTopNotifier, int>((
  ref,
) {
  return ScrollToTopNotifier();
});

/// 顶栏/底栏可见性进度（0.0 = 完全隐藏, 1.0 = 完全显示）。
///
/// 0.4.0 起浮动 Tab 胶囊常驻、不再随滚动收放；只有 0.0 这个「强制隐藏」
/// 通道还在用（书签工作台模式等），其余取值都当作显示。
final barVisibilityProvider = StateProvider<double>((ref) => 1.0);

/// 下拉刷新信号（底栏双击「刷新」等）：当前列表收到后走一次带指示器的刷新
final homeRefreshSignalProvider =
    StateNotifierProvider<ScrollToTopNotifier, int>((ref) {
      return ScrollToTopNotifier();
    });
