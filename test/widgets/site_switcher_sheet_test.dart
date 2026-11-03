import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:fluxdo/services/site_switch_service.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:fluxdo/widgets/site/site_switcher_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';

class _Work implements SiteSwitchWork {
  final switched = <String>[];

  @override
  void stopWork() {}

  @override
  Future<void> waitForUnmount() async {}

  @override
  Future<void> drainWork() async {}

  @override
  Future<Object?> prepareSite(SiteProfile site) async => null;

  @override
  void commitSite(SiteProfile site, Object? prepared) {
    switched.add(site.id);
    SiteContext.activate(site);
  }

  @override
  Future<void> restartWork() async {}
}

void main() {
  final a = SitePresets.uscard;
  final b = SiteProfile(baseUrl: 'https://b.example.com', title: 'Forum B');
  late SharedPreferences prefs;
  late SiteRegistryService registry;
  late _Work work;
  late SiteSwitchController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    registry = SiteRegistryService();
    await registry.init(prefs);
    await registry.addOrUpdate(a);
    await registry.addOrUpdate(b);
    await registry.setCurrent(a.id);
    SiteContext.activate(a);
    work = _Work();
    controller = SiteSwitchController(work: work);
  });

  tearDown(SiteContext.debugReset);

  Future<void> pumpChip(WidgetTester tester) => pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: CurrentSiteChip(registry: registry, controller: controller),
      ),
    ),
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  group('胶囊和面板', () {
    testWidgets('胶囊显示当前论坛名', (tester) async {
      await pumpChip(tester);
      expect(find.text(a.title), findsOneWidget);
    });

    testWidgets('点开列出已保存的论坛，只有当前站打勾，底部能添加', (tester) async {
      await pumpChip(tester);
      await tester.tap(find.byType(CurrentSiteChip));
      await tester.pumpAndSettle();

      expect(find.text('切换论坛'), findsOneWidget);
      expect(find.text('Forum B'), findsOneWidget);
      expect(find.text('添加新论坛'), findsOneWidget);
      expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
      final current = find.ancestor(
        of: find.byIcon(Symbols.check_rounded),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: current, matching: find.text(a.id)),
        findsOneWidget,
      );
    });

    testWidgets('点别的论坛：关面板并切过去，不弹确认框', (tester) async {
      await pumpChip(tester);
      await tester.tap(find.byType(CurrentSiteChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forum B'));
      await tester.pumpAndSettle();

      expect(work.switched, [b.id]);
      expect(find.text('切换论坛'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('点当前论坛：只关面板，不切', (tester) async {
      await pumpChip(tester);
      await tester.tap(find.byType(CurrentSiteChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(a.id));
      await tester.pumpAndSettle();

      expect(work.switched, isEmpty);
      expect(find.text('切换论坛'), findsNothing);
    });

    testWidgets('论坛名很长也不溢出', (tester) async {
      await registry.addOrUpdate(
        SiteProfile(baseUrl: 'https://long.example.com', title: '名' * 200),
      );
      await pumpChip(tester);
      await tester.tap(find.byType(CurrentSiteChip));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('底栏长按「我的」', () {
    final destinations = [
      const AdaptiveDestination(
        id: NavEntryIds.home,
        icon: Icon(Icons.home),
        selectedIcon: Icon(Icons.home),
        label: '首页',
      ),
      const AdaptiveDestination(
        id: NavEntryIds.profile,
        icon: Icon(Icons.person),
        selectedIcon: Icon(Icons.person),
        label: '我的',
      ),
    ];

    Future<List<int>> pumpNav(
      WidgetTester tester, {
      required bool floating,
    }) async {
      await prefs.setBool('pref_bottom_nav_floating', floating);
      final tapped = <int>[];
      await pumpApp(
        tester,
        Scaffold(
          bottomNavigationBar: AdaptiveBottomNavigation(
            selectedIndex: 0,
            onDestinationSelected: tapped.add,
            destinations: destinations,
          ),
        ),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      return tapped;
    }

    for (final floating in [false, true]) {
      final name = floating ? '悬浮底栏' : '贴底底栏';

      testWidgets('$name：长按震动并呼出面板', (tester) async {
        final haptics = <String?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String?);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await registry.setCurrent(a.id);
        final tapped = await pumpNav(tester, floating: floating);
        await tester.longPress(find.text('我的'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('切换论坛'), findsOneWidget);
        expect(haptics, isNotEmpty);
        expect(tapped, isEmpty, reason: '长按不算点击');
      });

      testWidgets('$name：单击还是切 Tab', (tester) async {
        final tapped = await pumpNav(tester, floating: floating);
        await tester.tap(find.text('我的'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tapped, [1]);
      });

      testWidgets('$name：长按别的 Tab 不呼出', (tester) async {
        await pumpNav(tester, floating: floating);
        await tester.longPress(find.text('首页'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('切换论坛'), findsNothing);
      });
    }
  });
}
