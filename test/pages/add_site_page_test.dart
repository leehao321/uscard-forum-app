import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/pages/add_site_page.dart';
import 'package:fluxdo/services/site_probe_service.dart';

class _FakeProbe implements SiteProbeService {
  _FakeProbe(this.result);

  final SiteProbeResult result;
  final List<String> probed = [];

  @override
  Future<SiteProbeResult> probe(String baseUrl) async {
    probed.add(baseUrl);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<SiteProfile> confirmed;

  Widget app(SiteProbeService probe) {
    return TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: AddSitePage(
          probeService: probe,
          onConfirmed: (site) async => confirmed.add(site),
        ),
      ),
    );
  }

  setUp(() {
    confirmed = [];
    LocaleSettings.setLocaleSync(AppLocale.zh);
  });

  final notUsed = _FakeProbe(
    const SiteProbeFailure(SiteProbeFailureReason.unreachable),
  );

  testWidgets('默认选中USCard，直接继续不发任何探测请求', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeFailure(SiteProbeFailureReason.unreachable),
    );
    await tester.pumpWidget(app(probe));

    expect(find.text('USCard Forum'), findsOneWidget);
    expect(find.text('LINUX DO'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pump();

    expect(confirmed.single.baseUrl, SitePresets.uscard.baseUrl);
    expect(probe.probed, isEmpty);
  });

  testWidgets('点 linux.do 卡片后继续', (tester) async {
    await tester.pumpWidget(app(notUsed));

    await tester.tap(find.text('LINUX DO'));
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pump();

    expect(confirmed.single.baseUrl, SitePresets.linuxdo.baseUrl);
  });

  testWidgets('地址格式不对时提示，不探测', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeFailure(SiteProbeFailureReason.unreachable),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'not a domain');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pump();

    expect(find.text('地址格式不对，请输入类似 example.com 的域名。'), findsOneWidget);
    expect(probe.probed, isEmpty);
    expect(confirmed, isEmpty);
  });

  testWidgets('手输预置站域名时直接用预置站，不探测', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeFailure(SiteProbeFailureReason.unreachable),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'uscardforum.com');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pump();

    expect(confirmed.single.featurePack, SiteFeaturePack.uscard);
    expect(probe.probed, isEmpty);
  });

  testWidgets('自由输入：探测成功后确认才添加', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeSuccess(
        baseUrl: 'https://example.com/forum',
        title: 'Example',
        version: '3.5.0',
        loginRequired: true,
      ),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'example.com/forum/');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(probe.probed.single, 'https://example.com/forum');
    expect(find.text('添加这个论坛？'), findsOneWidget);
    expect(find.text('Discourse 版本 3.5.0'), findsOneWidget);
    expect(find.text('这个论坛需要登录后才能浏览。'), findsOneWidget);
    expect(confirmed, isEmpty);

    await tester.tap(find.text('添加'));
    await tester.pump();

    expect(confirmed.single.baseUrl, 'https://example.com/forum');
    expect(confirmed.single.featurePack, SiteFeaturePack.generic);
  });

  testWidgets('确认框取消后不添加，可以再操作', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeSuccess(baseUrl: 'https://example.com', title: 'Example'),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(confirmed, isEmpty);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('不是 Discourse 时提示，且没有“仍然添加”', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeFailure(SiteProbeFailureReason.notDiscourse),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('这个地址不是 Discourse 论坛，或者论坛部署在其他路径。'), findsOneWidget);
    expect(find.text('仍然添加'), findsNothing);
    expect(confirmed, isEmpty);
  });

  testWidgets('Cloudflare 挡住时可以仍然添加，改地址后按钮消失', (tester) async {
    final probe = _FakeProbe(
      const SiteProbeFailure(SiteProbeFailureReason.cloudflareChallenge),
    );
    await tester.pumpWidget(app(probe));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('仍然添加'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.pump();
    expect(find.text('仍然添加'), findsNothing);

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仍然添加'));
    await tester.pump();

    expect(confirmed.single.baseUrl, 'https://example.com');
    expect(confirmed.single.title, 'example.com');
  });
}
