import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/discourse/auth_probe_rules.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/auth/qr_login_sheet.dart';
import 'package:fluxdo/widgets/auth/two_factor_dialog.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('E-04 登录态检查', () {
    test('200 只有 JSON 才算确认失效：网页和空响应不算', () {
      expect(AuthProbeRules.isRejectedOk({'current_user': null}), isTrue);
      expect(AuthProbeRules.isRejectedOk('<html>portal</html>'), isFalse);
      expect(AuthProbeRules.isRejectedOk(''), isFalse);
      expect(AuthProbeRules.isRejectedOk(null), isFalse);
    });

    test('403 必须带 not_logged_in：Cloudflare 和其他 403 不算', () {
      expect(AuthProbeRules.isRejectedError(403, '<html>Just a moment</html>'), isFalse);
      expect(AuthProbeRules.isRejectedError(403, {'error_type': 'invalid_access'}), isFalse);
      expect(AuthProbeRules.isRejectedError(403, null), isFalse);
      expect(AuthProbeRules.isRejectedError(403, {'error_type': 'not_logged_in'}), isTrue);
      expect(AuthProbeRules.isRejectedError(401, {'error_type': 'not_logged_in'}), isTrue);
      expect(AuthProbeRules.isRejectedError(401, 'x'), isFalse);
    });

    test('404 仍然算没有这个用户；5xx 和网络失败不算', () {
      expect(AuthProbeRules.isRejectedError(404, null), isTrue);
      expect(AuthProbeRules.isRejectedError(500, null), isFalse);
      expect(AuthProbeRules.isRejectedError(null, null), isFalse);
    });

    test('isLoggedIn 用了这些规则', () {
      final src = _source('lib/services/discourse/_auth.dart');
      final body = src.substring(src.indexOf('Future<bool> isLoggedIn()'));
      expect(body, contains('AuthProbeRules.isRejectedOk(data)'));
      expect(body, contains('AuthProbeRules.isRejectedError('));
      expect(body, isNot(contains('status == 404 || status == 401 || status == 403')));
    });
  });

  group('E-05 探测结论不明确时不升级', () {
    test('网络失败、取消、CF 挡住：strike 再多也不登出', () {
      for (final (status, data) in [
        (null, null),
        (403, '<html>cf</html>'),
        (500, null),
        (429, {'errors': []}),
      ]) {
        expect(
          AuthProbeRules.shouldEscalateInconclusive(strikes: 9, status: status, data: data),
          isFalse,
          reason: 'status=$status',
        );
      }
    });

    test('服务端明确 not_logged_in 且 strike 够才升级', () {
      const body = {'error_type': 'not_logged_in'};
      expect(AuthProbeRules.shouldEscalateInconclusive(strikes: 2, status: 403, data: body), isTrue);
      expect(AuthProbeRules.shouldEscalateInconclusive(strikes: 1, status: 403, data: body), isFalse);
    });

    test('探测流程用了这条规则', () {
      final src = _source('lib/services/discourse/_auth.dart');
      expect(src, contains('AuthProbeRules.shouldEscalateInconclusive('));
      expect(src, isNot(contains('if (strikeSnapshot >= 2) {')));
    });
  });

  group('F3 登录响应判定', () {
    final service = DiscourseService();

    test('限流的 errors 响应不算成功', () {
      final result = service.parseSessionJsonBody(
        429,
        '{"errors":["You have performed this action too many times"],"error_type":"rate_limit"}',
      );
      expect(result, isA<LoginFailure>());
      expect((result as LoginFailure).message, contains('too many times'));
    });

    test('非 2xx 的 JSON 不算成功', () {
      expect(service.parseSessionJsonBody(403, '{"foo":1}'), isA<LoginFailure>());
      expect(service.parseSessionJsonBody(500, '{}'), isA<LoginFailure>());
    });

    test('200 带 errors 也不算成功', () {
      expect(service.parseSessionJsonBody(200, '{"errors":["no"]}'), isA<LoginFailure>());
    });

    test('正常登录、已有的错误分支不变', () {
      expect(service.parseSessionJsonBody(200, '{"user":{"id":1}}'), isA<LoginSuccess>());
      expect(
        service.parseSessionJsonBody(200, '{"error":"bad","reason":"invalid_second_factor"}'),
        isA<LoginFailure>(),
      );
      expect(service.parseSessionJsonBody(200, '{"error":"bad"}'), isA<LoginFailure>());
      expect(service.parseSessionJsonBody(200, 'not json'), isA<LoginFailure>());
    });
  });

  group('F2 改用备用码', () {
    testWidgets('二步验证框关闭、外层登录框收尾之后才进网页登录', (tester) async {
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              root = c;
              return const Scaffold();
            },
          ),
        ),
      );

      // 和 login_page 一样：外层登录框等二步验证结果，取消就带结果关闭自己
      var useWebView = false;
      int? outerResult;
      Future<void> run() async {
        final outer = await showDialog<int>(
          context: root,
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final code = await showTwoFactorDialog(
                  ctx,
                  onUseBackupCode: () => useWebView = true,
                );
                if (code == null && ctx.mounted) Navigator.of(ctx).pop(0);
              },
              child: const Text('NEED2FA'),
            ),
          ),
        );
        outerResult = outer;
        if (useWebView) {
          Navigator.of(root).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => const Scaffold(body: Text('WEBVIEW_PAGE')),
            ),
          );
        }
      }

      final done = run();
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEED2FA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('改用备用码 / 安全密钥'));
      await tester.pumpAndSettle();
      await done;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(outerResult, 0);
      expect(find.text('WEBVIEW_PAGE'), findsOneWidget);
      expect(find.text('NEED2FA', skipOffstage: false), findsNothing, reason: '登录框不能留在下面');
    });

    test('login_page 不在回调里直接跳转', () {
      final src = _source('lib/pages/login_page.dart');
      expect(src, isNot(contains('onUseBackupCode: () => _loginWithWebView()')));
      expect(src, contains('onUseBackupCode: () => useWebViewLogin = true'));
    });
  });

  group('F7 二维码轮询', () {
    test('uscard 不自动轮询，其他站保留', () {
      expect(qrAutoPollInterval(SitePresets.uscard), isNull);
      expect(qrAutoPollInterval(SitePresets.linuxdo), isNotNull);
      expect(
        qrAutoPollInterval(SiteProfile(baseUrl: 'https://example.com', title: 'E')),
        isNotNull,
      );
    });
  });
}
