import 'dart:async';
import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/appearance_page.dart';
import 'package:fluxdo/pages/bottom_nav_settings_page.dart';
import 'package:fluxdo/pages/data_management_page.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/font_settings_page.dart';
import 'package:fluxdo/pages/network_settings_page/network_settings_page.dart';
import 'package:fluxdo/pages/reading_settings_page.dart';
import 'package:fluxdo/pages/settings_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart' show currentUsernameProvider;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 0.4.0 M8：设置各页出图（设了 SHOTS_DIR 才落盘），对照 Figma 设置与登录
// 52:2 / 阅读·功能·标签栏·数据管理 53:1241 / 393 抽查 55:2520。
// 没设 SHOTS_DIR 时只检查不溢出、无异常。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

/// 数据管理页读缓存目录；测试里指到一个空的临时目录，不碰真实数据
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWith(_FakeUser.new),
    // 用户名不走真站（Notion 配置按账号存，会去取用户名）
    currentUsernameProvider.overrideWith((ref) async => null),
  ];
}

void main() {
  setUpAll(loadUiFonts);

  late Directory tmp;
  late PathProviderPlatform originalPathProvider;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('settings_shots_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final pages = <String, Widget Function()>{
    'home': () => const SettingsPage(),
    'appearance': () => const AppearancePage(),
    'fonts': () => const FontSettingsPage(),
    'reading': () => const ReadingSettingsPage(),
    'bottomnav': () => const BottomNavSettingsPage(),
    'data': () => const DataManagementPage(),
    'network': () => const NetworkSettingsPage(),
    'diagnostics': () => const DiagnosticsPage(),
  };

  for (final variant in [
    UiVariant.lightDefault,
    const UiVariant(Brightness.dark, 1, UiDevice.proMax),
    const UiVariant(Brightness.light, 1, UiDevice.pro),
    const UiVariant(Brightness.light, 1, UiDevice.landscape),
  ]) {
    for (final entry in pages.entries) {
      testUi('出图 ${entry.key}（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          entry.value(),
          variant: variant,
          overrides: await _overrides(),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        // 出图用例只拦布局溢出：这些页启动时会读磁盘 / 平台服务，测试环境没有
        // 插件，后台异常不是这里要查的
        String drain() {
          try {
            return '${tester.takeException()}';
          } catch (e) {
            // 同一帧有多条异常时 takeException 自己会抛，文本里带着全部异常
            return '$e';
          }
        }

        expect(drain(), isNot(contains('overflowed')));
        await uiShot(tester, 'settings_${entry.key}_${variant.label}');
        // 出图时又补了几帧，后台服务的异常同样只看是不是溢出
        expect(drain(), isNot(contains('overflowed')));
      });
    }
  }
}
