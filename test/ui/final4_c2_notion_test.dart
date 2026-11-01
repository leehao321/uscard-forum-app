import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/notion_settings_page.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:fluxdo/services/notion/notion_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 补充稿 52 / 53：Notion 同步的配置步骤（状态行 + 三张步骤卡）与底部说明。

class _Env {
  _Env(this.prefs);

  final SharedPreferences prefs;

  List<Override> get overrides => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUsernameProvider.overrideWith((ref) async => 'tester'),
  ];

  NotionConfig get saved => NotionConfigRepository(prefs).read('tester');
}

Future<_Env> _env({NotionConfig? config}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (config != null) {
    await NotionConfigRepository(prefs).write('tester', config);
  }
  return _Env(prefs);
}

Future<void> _open(WidgetTester tester, _Env env) async {
  await pumpUi(
    tester,
    const NotionSettingsPage(),
    overrides: env.overrides,
    // 配置要等账号解析后异步加载，用 pumpAndSettle
  );
  await tester.pumpAndSettle();
}

/// 步骤卡片里的输入框（按占位 / 标签文字找）
Finder _fieldWith(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(AppFilledField));

Finder _textField(String text) => find.descendant(
  of: _fieldWith(text).first,
  matching: find.byType(TextField),
);

void main() {
  setUpAll(loadUiFonts);

  testUi('未配置：状态行「未连接」+ 三张带序号的步骤卡 + 4 个操作', (tester) async {
    final env = await _env();
    await _open(tester, env);

    // 顶部状态行
    expect(find.text('Notion 同步'), findsNWidgets(2)); // 导航标题 + 状态行标题
    expect(find.text('把帖子完整同步到你的 Notion Database'), findsOneWidget);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.byIcon(AppIcons.folderSync), findsOneWidget);
    // 三步：序号徽标 + 标题
    for (final t in ['1', '2', '3']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('创建 Integration 拿 Token'), findsOneWidget);
    expect(find.text('准备 Database'), findsOneWidget);
    expect(find.text('保存并测试'), findsOneWidget);
    // 步骤正文已换成稿里的措辞
    expect(
      find.textContaining('点 New integration，Type 选 Internal'),
      findsOneWidget,
    );
    // 按钮：打开 Integrations、一键创建、保存并测试连接
    expect(find.text('打开 Notion Integrations'), findsOneWidget);
    expect(find.text('一键创建模板 Database'), findsOneWidget);
    expect(find.text('保存并测试连接'), findsOneWidget);
    // 按钮 44 高，输入框 44 高
    expect(
      tester.getSize(find.text('打开 Notion Integrations').first).height,
      lessThan(44),
    );
    final buttonBox = find.ancestor(
      of: find.text('打开 Notion Integrations'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(buttonBox.first).height, 44);
    expect(tester.getSize(_fieldWith('Integration Token').first).height, 44);
    expect(tester.getSize(_fieldWith('Database ID').first).height, 44);
    expectNoUiException(tester);
  });

  testUi('Token 输入框：平时只有占位，聚焦或有内容时标签出现在框上方（品牌色），内容遮挡', (tester) async {
    final env = await _env();
    await _open(tester, env);

    // 没聚焦、没内容：只有占位一处文字
    expect(find.text('Integration Token'), findsOneWidget);
    final token = _textField('Integration Token');
    expect(tester.widget<TextField>(token).obscureText, isTrue);

    // 聚焦：框上方多出标签，品牌色；框线 1.5pt 品牌色
    await tester.tap(token);
    await tester.pump();
    expect(find.text('Integration Token'), findsNWidgets(2));
    final context = tester.element(token);
    final brand = context.tokens.colors.brandPrimary;
    final label = tester
        .widgetList<Text>(find.text('Integration Token'))
        .firstWhere((t) => t.style?.color == brand);
    expect(label.style?.color, brand);
    final decorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: _fieldWith('Integration Token').first,
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);
    expect(decorated.border!.top.width, 1.5);
    expect(decorated.border!.top.color, brand);

    // 输入内容并失焦：占位（透明）退场，标签留在框上方（13 号，和占位 17 号区分）；
    // 点眼睛切换显示 / 隐藏
    await tester.enterText(token, 'secret_abc123');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == 'Integration Token' &&
            w.style?.fontSize == 13,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(AppIcons.visibilityOff), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.visibilityOff));
    await tester.pump();
    expect(tester.widget<TextField>(token).obscureText, isFalse);
    expect(find.byIcon(AppIcons.visibility), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.visibility));
    await tester.pump();
    expect(tester.widget<TextField>(token).obscureText, isTrue);
  });

  testUi('Database ID：剪贴板图标把剪贴板内容粘进输入框', (tester) async {
    final env = await _env();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': '  0123456789abcdef0123456789abcdef '};
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
    await _open(tester, env);
    expect(find.byIcon(AppIcons.clipboard), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.clipboard));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_textField('Database ID')).controller!.text,
      '0123456789abcdef0123456789abcdef',
    );
  });

  testUi('没填 Token 和 Database 就点保存：提示补全，不写入配置', (tester) async {
    final env = await _env();
    await _open(tester, env);
    await tester.ensureVisible(find.text('保存并测试连接'));
    await tester.tap(find.text('保存并测试连接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请填写 Token 和 Database ID'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(env.saved.integrationToken, isNull);
    expect(env.saved.databaseId, isNull);
  });

  testUi('没填 Token 就点一键创建：提示先填 Token', (tester) async {
    final env = await _env();
    await _open(tester, env);
    await tester.ensureVisible(find.text('一键创建模板 Database'));
    await tester.tap(find.text('一键创建模板 Database'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请先填写 Integration Token'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testUi('底部说明：分组底色条 + lock 图标 + 本机存储说明', (tester) async {
    final env = await _env();
    await _open(tester, env);
    final note = find.text(
      'Token 只保存在本机，不会上传到任何服务器。建议单独创建一个 Internal Integration，只把目标 Database 分享给它。',
    );
    await tester.scrollUntilVisible(
      note,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(note, findsOneWidget);
    final lock = find.byIcon(AppIcons.lock);
    expect(lock, findsOneWidget);
    expect(tester.widget<Icon>(lock).size, 16);
    // 说明在一个 surface/grouped 的底色条里
    final context = tester.element(note);
    final bar = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: note, matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color == context.tokens.colors.surfaceGrouped);
    expect(bar.borderRadius, isNotNull);
  });

  testUi('已配置：状态行「已连接」，步骤折叠成一行；点修改配置展开，完成的步骤徽标变 ✓', (tester) async {
    final env = await _env(
      config: const NotionConfig(
        integrationToken: 'secret_x',
        databaseId: '0123456789abcdef0123456789abcdef',
      ),
    );
    await _open(tester, env);

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('未连接'), findsNothing);
    expect(find.text('已配置完成'), findsOneWidget);
    expect(find.text('创建 Integration 拿 Token'), findsNothing);

    await tester.tap(find.text('修改配置'));
    await tester.pumpAndSettle();
    expect(find.text('创建 Integration 拿 Token'), findsOneWidget);
    // 第 1、2 步已填：徽标是 ✓；第 3 步（编辑中）仍是序号
    expect(find.byIcon(AppIcons.check), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testUi('已配置时点右上「断开」：清掉配置，回到未连接并清空输入框', (tester) async {
    final env = await _env(
      config: const NotionConfig(
        integrationToken: 'secret_x',
        databaseId: '0123456789abcdef0123456789abcdef',
      ),
    );
    await _open(tester, env);
    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();
    expect(env.saved.integrationToken, isNull);
    expect(env.saved.databaseId, isNull);
    expect(find.text('未连接'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(_textField('Integration Token'))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
