import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/pages/sites_page.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_data_cleaner.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:fluxdo/services/site_switch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SpyCleaner implements SiteDataCleaner {
  final cleared = <String>[];

  @override
  Future<bool> clearLogin(SiteProfile site) async {
    cleared.add(site.id);
    return true;
  }
}

void main() {
  final custom = SiteProfile(baseUrl: 'https://example.com', title: 'Example');
  late _SpyCleaner cleaner;
  late SiteRegistryService registry;
  late int exits;

  Widget app() {
    return TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: SitesPage(
          registry: registry,
          exitApp: () => exits++,
          siteCleaner: cleaner,
        ),
      ),
    );
  }

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
    SiteContext.debugReset();
    exits = 0;
    cleaner = _SpyCleaner();
    registry = SiteRegistryService();
  });

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await registry.init(await SharedPreferences.getInstance());
      await registry.addAndActivate(SitePresets.uscard);
      await registry.addOrUpdate(custom);
    });
  }

  tearDown(SiteContext.debugReset);

  testWidgets('列出所有站，当前站不能删也不能切', (tester) async {
    await seed(tester);
    await tester.pumpWidget(app());

    expect(find.text('USCard Forum'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
    expect(find.byTooltip('移除'), findsOneWidget);

    await tester.tap(find.text('USCard Forum'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(exits, 0);
  });

  testWidgets('切换：确认后持久化新站并退出，本次运行不变', (tester) async {
    await seed(tester);
    await tester.pumpWidget(app());

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();
    expect(find.text('切换到 Example？'), findsOneWidget);

    await tester.tap(find.text('切换并退出'));
    await tester.pumpAndSettle();

    expect(registry.current!.id, custom.id);
    expect(SiteContext.current.id, SitePresets.uscard.id);
    expect(exits, 1);
  });

  testWidgets('切换时取消，什么都不变', (tester) async {
    await seed(tester);
    await tester.pumpWidget(app());

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(registry.current!.id, SitePresets.uscard.id);
    expect(exits, 0);
  });

  testWidgets('移除：确认后从列表消失', (tester) async {
    await seed(tester);
    await tester.pumpWidget(app());

    await tester.tap(find.byTooltip('移除'));
    await tester.pumpAndSettle();
    expect(find.text('移除 Example？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();

    expect(find.text('Example'), findsNothing);
    expect(registry.sites.map((s) => s.id), [SitePresets.uscard.id]);
    expect(cleaner.cleared, [custom.id], reason: '移除时要清掉这个站的登录数据');
    expect(find.textContaining('保存的账号密码'), findsNothing);
  });

  testWidgets('移除前的提示说清楚会清掉什么', (tester) async {
    await seed(tester);
    await tester.pumpWidget(app());

    await tester.tap(find.byTooltip('移除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('登录状态和保存的账号密码会被清除'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cleaner.cleared, isEmpty);
  });

  group('编排骨架', () {
    test('按固定顺序执行', () async {
      final ran = <SiteSwitchStep>[];
      await SiteSwitchService.runNoRestartSteps({
        for (final step in SiteSwitchStep.values)
          step: () async => ran.add(step),
      });
      expect(ran, [
        SiteSwitchStep.stopMessageBus,
        SiteSwitchStep.clearCurrentUser,
        SiteSwitchStep.switchCookieJar,
        SiteSwitchStep.rebuildMainDio,
        SiteSwitchStep.resetPreloadedData,
        SiteSwitchStep.invalidateProviders,
        SiteSwitchStep.resetNavigation,
      ]);
    });

    test('缺步骤时拒绝运行，一步都不执行', () async {
      var ran = 0;
      await expectLater(
        SiteSwitchService.runNoRestartSteps({
          SiteSwitchStep.stopMessageBus: () async => ran++,
        }),
        throwsArgumentError,
      );
      expect(ran, 0);
    });
  });
}
