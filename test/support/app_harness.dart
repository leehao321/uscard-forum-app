import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;

/// 带本地化和 ProviderScope 的最小 App，界面测试共用。
Widget testApp(
  Widget home, {
  List<dynamic> overrides = const [],
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: TranslationProvider(
      child: MaterialApp(
        // S.current 靠它取 context
        navigatorKey: navigatorKey,
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: home,
      ),
    ),
  );
}

/// 把 [home] 放进 [testApp] 并等它稳定；有持续动画时传 `settle: false`。
Future<void> pumpApp(
  WidgetTester tester,
  Widget home, {
  List<dynamic> overrides = const [],
  bool settle = true,
}) async {
  LocaleSettings.setLocaleSync(AppLocale.zh);
  await tester.pumpWidget(testApp(home, overrides: overrides));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
