import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/login_page.dart';
import 'package:fluxdo/pages/onboarding_page.dart';
import 'package:fluxdo/widgets/auth/login_form.dart';
import 'package:fluxdo/widgets/auth/two_factor_dialog.dart';
import 'package:fluxdo/widgets/common/app_mark.dart';

import 'support/ui_harness.dart';

// 0.4.0 M9：登录相关。不请求论坛：登录表单的提交回调是假的，二步验证只看输入。

Widget _form({
  required List<String> log,
  bool ok = false,
  String? savedUsername,
}) => Scaffold(
  body: SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const AppMark(size: 64),
          const SizedBox(height: 16),
          LoginForm(
            savedUsername: savedUsername,
            onForgotPassword: () => log.add('forgot'),
            onSubmit:
                ({
                  required String identifier,
                  required String password,
                  required bool rememberCredentials,
                }) async {
                  log.add('$identifier/$password/$rememberCredentials');
                  return ok;
                },
          ),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(loadUiFonts);

  group('登录表单', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出、可访问（${variant.label}）', (tester) async {
        await pumpUi(tester, _form(log: []), variant: variant);
        expectNoUiException(tester);
        await expectUiAccessibility(tester, textContrast: false);
      });
    }

    testUi('空表单不提交；填好后提交并带上「记住密码」', (tester) async {
      final log = <String>[];
      await pumpUi(tester, _form(log: log));
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(log, isEmpty);

      await tester.enterText(find.byType(TextField).first, 'chan');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('记住密码'));
      await tester.pump();
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(log, ['chan/secret/true']);
    });

    testUi('忘记密码可点，密码默认掩码、点眼睛后显示', (tester) async {
      final log = <String>[];
      await pumpUi(tester, _form(log: log));
      await tester.tap(find.text('忘记密码？'));
      expect(log, ['forgot']);

      TextField password() =>
          tester.widget<TextField>(find.byType(TextField).last);
      expect(password().obscureText, isTrue);
      await tester.tap(find.bySemanticsLabel('显示密码'));
      await tester.pump();
      expect(password().obscureText, isFalse);
    });

    testUi('点按区域 ≥ 44', (tester) async {
      await pumpUi(tester, _form(log: []));
      final remember = tester.getSize(find.text('记住密码'));
      expect(remember.height, lessThanOrEqualTo(44));
      final button = tester.getSize(
        find.ancestor(of: find.text('登录'), matching: find.byType(FilledButton)),
      );
      expect(button.height, greaterThanOrEqualTo(48));
      expect(button.width, greaterThan(300));
    });
  });

  group('二步验证', () {
    Widget host(List<String?> results) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(
              await showTwoFactorDialog(context, onUseBackupCode: () {}),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('对话框不溢出（${variant.label}）', (tester) async {
        await pumpUi(tester, host([]), variant: variant);
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 400));
        expectNoUiException(tester);
        expect(find.text('二步验证'), findsOneWidget);
        await uiShot(tester, 'm9_2fa_${variant.label}');
      });
    }

    testUi('6 格：未满 6 位「验证」置灰，满 6 位自动提交', (tester) async {
      final results = <String?>[];
      await pumpUi(tester, host(results));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(results, isEmpty);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 400));
      expect(results, ['123456']);
    });
  });

  group('LoginPage 整页（注入假服务）', () {
    LoginPageServices fake(
      List<String> log, {
      String? username,
      String? password,
    }) => LoginPageServices(
      loadCredentials: () async => (username: username, password: password),
      clearCredentials: () async => log.add('clear'),
      submit:
          ({
            required String identifier,
            required String password,
            required bool rememberCredentials,
          }) async {
            log.add('submit:$identifier');
            return false;
          },
    );

    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出、可访问（${variant.label}）', (tester) async {
        await pumpUi(tester, LoginPage(services: fake([])), variant: variant);
        expectNoUiException(tester);
        expect(find.text('登录美卡论坛'), findsOneWidget);
        expect(find.text('用浏览器授权登录'), findsOneWidget);
        expect(find.text('扫码登录'), findsOneWidget);
        await uiShot(tester, 'm9_login_${variant.label}');
        await expectUiAccessibility(tester, textContrast: false);
      });
    }

    testUi('读到已保存的账号时预填并显示清除钮；点清除后回到空表单', (tester) async {
      final log = <String>[];
      await pumpUi(
        tester,
        LoginPage(
          services: fake(log, username: 'chan', password: 'pw'),
        ),
      );
      expect(find.text('chan'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('清除保存的账号'));
      await tester.pump();
      expect(log, ['clear']);
      expect(find.bySemanticsLabel('清除保存的账号'), findsNothing);
    });

    testUi('没有保存账号时没有清除钮；提交走注入的服务', (tester) async {
      final log = <String>[];
      await pumpUi(tester, LoginPage(services: fake(log)));
      expect(find.bySemanticsLabel('清除保存的账号'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'a@b.c');
      await tester.enterText(find.byType(TextField).last, 'pw');
      await tester.tap(find.text('登录').last);
      await tester.pump();
      expect(log, ['submit:a@b.c']);
    });

    testUi('顶部有网络设置入口（44 点击区）', (tester) async {
      await pumpUi(tester, LoginPage(services: fake([])));
      final size = tester.getSize(find.bySemanticsLabel('网络设置'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('OnboardingPage 整页', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出、可访问（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          OnboardingPage(onComplete: () {}, initializeDeepLink: false),
          variant: variant,
        );
        expectNoUiException(tester);
        expect(find.text('美卡论坛'), findsOneWidget);
        await uiShot(tester, 'm9_onboarding_${variant.label}');
        await expectUiAccessibility(tester, textContrast: false);
      });
    }

    testUi('「先逛逛」直接完成引导', (tester) async {
      var done = 0;
      await pumpUi(
        tester,
        OnboardingPage(onComplete: () => done++, initializeDeepLink: false),
      );
      await tester.tap(find.widgetWithText(TextButton, '先逛逛'));
      expect(done, 1);
    });
  });

  testUi('App 图标：静态、读屏不读', (tester) async {
    await pumpUi(tester, const Scaffold(body: Center(child: AppMark())));
    expect(tester.getSize(find.byType(AppMark)), const Size(96, 96));
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });
}
