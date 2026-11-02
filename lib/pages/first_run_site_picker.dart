import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/s.dart';
import '../services/site_registry_service.dart';
import 'add_site_page.dart';

/// 首次启动选站，选好后返回。
///
/// 在其余服务初始化之前运行：Cookie、Dio、预加载都依赖当前站点，这样它们一启动
/// 就能读到确定的站点。main() 随后的 runApp 会替换掉这里的界面。
Future<void> runFirstRunSitePicker() async {
  await LocaleSettings.useDeviceLocale();

  final selected = Completer<void>();
  runApp(
    TranslationProvider(
      child: Builder(
        builder: (context) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Pulse Flow',
          locale: TranslationProvider.of(context).flutterLocale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
          ),
          home: AddSitePage(
            onConfirmed: (site) async {
              await SiteRegistryService.instance.addAndActivate(site);
              if (!selected.isCompleted) selected.complete();
            },
          ),
        ),
      ),
    ),
  );
  await selected.future;
}
