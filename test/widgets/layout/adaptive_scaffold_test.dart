import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:fluxdo/widgets/layout/adaptive_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('手机端：浮动 Tab 胶囊常驻；barVisibility 为 0（强制隐藏）才滑出屏', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: AdaptiveScaffold(
              selectedIndex: 1,
              onDestinationSelected: (_) {},
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
                AdaptiveDestination(
                  id: 'bookmarks',
                  icon: Icon(Icons.bookmark_outline_rounded),
                  selectedIcon: Icon(Icons.bookmark_rounded),
                  label: '书签',
                ),
              ],
              body: const SizedBox.expand(child: Text('body')),
            ),
          ),
        ),
      ),
    );

    // 常驻：不再随滚动收放，也不再有 Material 底部导航栏
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FloatingTabBar), findsOneWidget);
    // 非首页 Tab 只有 Tab 胶囊，没有搜索胶囊
    expect(find.byType(SearchCapsule), findsNothing);
    final slide = find.ancestor(
      of: find.byType(FloatingTabBar),
      matching: find.byType(AnimatedSlide),
    );
    expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);

    container.read(barVisibilityProvider.notifier).state = 0;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(slide).offset.dy, greaterThan(1));

    container.read(barVisibilityProvider.notifier).state = 1;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
  });

  testWidgets('横屏二级平行视界隐藏全局侧栏', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1400, 900)),
            child: AdaptiveScaffold(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              hideNavigationRail: true,
              destinations: const [
                AdaptiveDestination(
                  id: 'home',
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
                AdaptiveDestination(
                  id: 'messages',
                  icon: Icon(Icons.mail_outline),
                  selectedIcon: Icon(Icons.mail),
                  label: '私信',
                ),
              ],
              body: const SizedBox.expand(child: Text('平行视界内容')),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AdaptiveNavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('平行视界内容'), findsOneWidget);
  });
}
