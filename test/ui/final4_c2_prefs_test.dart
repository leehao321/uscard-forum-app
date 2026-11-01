import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/preferences_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/secret_store_provider.dart';
import 'package:fluxdo/providers/sticker_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:fluxdo/services/crypto/crypto_key_store.dart';
import 'package:fluxdo/services/storage/secret_store.dart';
import 'package:fluxdo/services/sticker_market_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 补充稿 48 / 49：功能设置的「表情包数据源」行与对话框、「加解密工具箱」组。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

/// 假的表情包服务：只记录 setBaseUrl 的调用，不碰存储
class _FakeStickerService extends Fake implements StickerMarketService {
  _FakeStickerService(this.baseUrl);

  @override
  String baseUrl;

  final saved = <String>[];

  @override
  Future<void> setBaseUrl(String url) async {
    saved.add(url);
    baseUrl = url;
  }
}

class _Env {
  _Env(this.prefs, this.secrets, this.sticker);

  final SharedPreferences prefs;
  final InMemorySecretStore secrets;
  final _FakeStickerService sticker;

  List<Override> get overrides => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWith(_FakeUser.new),
    currentUsernameProvider.overrideWith((ref) async => null),
    secretStoreProvider.overrideWithValue(secrets),
    stickerMarketServiceProvider.overrideWithValue(sticker),
  ];
}

Future<_Env> _env({String? stickerUrl}) async {
  SharedPreferences.setMockInitialValues({});
  return _Env(
    await SharedPreferences.getInstance(),
    InMemorySecretStore(),
    _FakeStickerService(stickerUrl ?? StickerMarketService.defaultBaseUrl),
  );
}

Future<void> _open(WidgetTester tester, _Env env) async {
  await pumpUi(
    tester,
    const PreferencesPage(),
    overrides: env.overrides,
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Finder _dialogField() => find.descendant(
  of: find.byType(AppAlertDialog),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(loadUiFonts);

  testUi('编辑器组：表情包数据源行显示当前网址', (tester) async {
    final env = await _env();
    await _open(tester, env);
    await _scrollTo(tester, find.text('表情包数据源'));
    expect(find.text('表情包数据源'), findsOneWidget);
    expect(find.text(StickerMarketService.defaultBaseUrl), findsOneWidget);
  });

  testUi('表情包数据源对话框：标题靠左、填充输入框预填当前网址、恢复默认行', (tester) async {
    final env = await _env(stickerUrl: 'https://example.test');
    await _open(tester, env);
    await _scrollTo(tester, find.text('表情包数据源'));
    await tester.tap(find.text('表情包数据源'));
    await tester.pumpAndSettle();

    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(find.byType(AppFilledField), findsOneWidget);
    expect(
      tester.widget<TextField>(_dialogField()).controller!.text,
      'https://example.test',
    );
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.byIcon(AppIcons.restartAlt), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    // 标题靠左：标题文字左缘和输入框左缘对齐（居中的标题比输入框窄，左缘对不上）
    final field = tester.getRect(find.byType(AppFilledField));
    final title = tester.getRect(
      find.descendant(
        of: find.byType(AppAlertDialog),
        matching: find.text('表情包数据源'),
      ),
    );
    expect(title.left, closeTo(field.left, 0.5));
    // 标题文字块是撑满整行的，位置量不出对齐方式：再看标题实际用的对齐
    final titleElement = tester.element(
      find.descendant(
        of: find.byType(AppAlertDialog),
        matching: find.text('表情包数据源'),
      ),
    );
    expect(DefaultTextStyle.of(titleElement).textAlign, TextAlign.start);
    expectNoUiException(tester);
  });

  testUi('表情包数据源对话框：恢复默认把输入框填回默认网址，确定后保存', (tester) async {
    final env = await _env(stickerUrl: 'https://example.test');
    await _open(tester, env);
    await _scrollTo(tester, find.text('表情包数据源'));
    await tester.tap(find.text('表情包数据源'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_dialogField()).controller!.text,
      StickerMarketService.defaultBaseUrl,
    );
    // 恢复默认只是填回输入框，确定前不保存
    expect(env.sticker.saved, isEmpty);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(env.sticker.saved, [StickerMarketService.defaultBaseUrl]);
  });

  testUi('表情包数据源对话框：输入新网址确定保存，取消不保存，空网址不保存', (tester) async {
    final env = await _env();
    await _open(tester, env);
    await _scrollTo(tester, find.text('表情包数据源'));

    // 取消：不保存
    await tester.tap(find.text('表情包数据源'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), 'https://cancel.test');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(env.sticker.saved, isEmpty);

    // 空网址：对话框关闭，但不保存
    await tester.tap(find.text('表情包数据源'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), '   ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(env.sticker.saved, isEmpty);

    // 新网址：交给服务保存（末尾斜杠由服务去掉）
    await tester.tap(find.text('表情包数据源'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), 'https://new.test/');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(env.sticker.saved, ['https://new.test/']);
  });

  testUi('加解密工具箱组：两行都带行内说明，清除行是破坏性样式', (tester) async {
    final env = await _env();
    await _open(tester, env);
    await _scrollTo(tester, find.text('清除记住的密码'));

    expect(find.text('加解密工具箱'), findsOneWidget);
    expect(find.text('记住加密密码'), findsOneWidget);
    expect(find.text('用系统安全存储保存最近用过的密码'), findsOneWidget);
    expect(find.text('密码只保存在本机'), findsOneWidget);
    // 说明在行内，不再收进页脚
    expect(find.textContaining('记住加密密码：'), findsNothing);

    final title = tester.widget<Text>(find.text('清除记住的密码'));
    final context = tester.element(find.text('清除记住的密码'));
    expect(title.style?.color, context.tokens.colors.textDestructive);
    final other = tester.widget<Text>(find.text('记住加密密码'));
    expect(other.style?.color, isNot(context.tokens.colors.textDestructive));
  });

  testUi('加解密工具箱：清除记住的密码先确认，确认后清空，取消保留', (tester) async {
    final env = await _env();
    await CryptoKeyStore.rememberPassword(env.secrets, 'secret-1');
    expect(await CryptoKeyStore.readPasswords(env.secrets), ['secret-1']);
    await _open(tester, env);
    await _scrollTo(tester, find.text('清除记住的密码'));

    // 取消：密码还在
    await tester.tap(find.text('清除记住的密码'));
    await tester.pumpAndSettle();
    expect(find.text('确定清除所有记住的密码吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await CryptoKeyStore.readPasswords(env.secrets), ['secret-1']);

    // 确定：清空
    await tester.tap(find.text('清除记住的密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await CryptoKeyStore.readPasswords(env.secrets), isEmpty);
  });
}
