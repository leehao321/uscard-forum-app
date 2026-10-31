/// 「内容操作」按钮：菜单项随可用性变化 + 点选真的执行动作。
///
/// 这个按钮是移动端把 6 个内容操作（全选/撤销/恢复/复制/粘贴/剪切）收进
/// 一个入口的载体，所以重点验证「该出现的项出现、不该出现的不出现」——
/// 不可用项禁用但不换位置，保持长按选择的方向稳定。
library;

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/widgets/markdown_editor/content_actions_button.dart';
import 'package:fluxdo/widgets/markdown_editor/content_actions_providers.dart';

/// 可编程的假 provider，用来精确摆布各种可用性组合
class _FakeProvider extends ChangeNotifier implements ContentActionsProvider {
  _FakeProvider({
    this.canUndoValue = false,
    this.canRedoValue = false,
    this.hasSelectionValue = false,
  });

  bool canUndoValue;
  bool canRedoValue;
  bool hasSelectionValue;
  bool availableValue = true;

  final calls = <String>[];

  @override
  bool get canUndo => canUndoValue;
  @override
  bool get canRedo => canRedoValue;
  @override
  bool get hasSelection => hasSelectionValue;
  @override
  bool get isAvailable => availableValue;

  @override
  void undo() => calls.add('undo');
  @override
  void redo() => calls.add('redo');
  @override
  void selectAll() => calls.add('selectAll');
  @override
  void copy() => calls.add('copy');
  @override
  void cut() => calls.add('cut');
  @override
  void paste() => calls.add('paste');
}

Future<void> _pump(
  WidgetTester tester,
  _FakeProvider p, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    // S.current 走全局 navigatorKey 取本地化，必须把 key 接上
    TranslationProvider(
      child: MaterialApp(
        locale: const Locale('zh'),
        navigatorKey: navigatorKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: ContentActionsButton(provider: p, listenable: p),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('点按弹出菜单：无历史无选区时六个位置固定，撤销禁用', (tester) async {
    final p = _FakeProvider();
    await _pump(tester, p);

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();

    for (final label in ['撤销', '恢复', '全选', '复制', '剪切', '粘贴']) {
      expect(find.text(label), findsOneWidget);
    }
    AppPressable row(String label) => tester.widget<AppPressable>(
      find
          .ancestor(of: find.text(label), matching: find.byType(AppPressable))
          .first,
    );
    // 撤销 / 恢复 / 复制 / 剪切不可用，全选 / 粘贴可用
    expect(row('撤销').onTap, isNull);
    expect(row('恢复').onTap, isNull);
    expect(row('复制').onTap, isNull);
    expect(row('剪切').onTap, isNull);
    expect(row('全选').onTap, isNotNull);
    expect(row('粘贴').onTap, isNotNull);
    // 六项在同一列，自上而下固定顺序
    final tops = [
      for (final label in ['撤销', '恢复', '全选', '复制', '剪切', '粘贴'])
        tester.getTopLeft(find.text(label)),
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i].dx, tops[0].dx);
      expect(tops[i].dy, greaterThan(tops[i - 1].dy));
    }
  });

  testWidgets('有历史时出现撤销，撤销过后出现恢复', (tester) async {
    final p = _FakeProvider(canUndoValue: true, canRedoValue: true);
    await _pump(tester, p);

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();

    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
  });

  testWidgets('有选区时出现复制/剪切', (tester) async {
    final p = _FakeProvider(hasSelectionValue: true);
    await _pump(tester, p);

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('剪切'), findsOneWidget);
  });

  testWidgets('选中菜单项会执行对应动作', (tester) async {
    final p = _FakeProvider(canUndoValue: true);
    await _pump(tester, p);

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(p.calls, ['undo']);
  });

  testWidgets('可用性变化后菜单内容跟着变', (tester) async {
    final p = _FakeProvider();
    await _pump(tester, p);

    // 初始无撤销
    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);
    // 关掉菜单
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 产生历史后重开
    p.canUndoValue = true;
    p.notifyListeners();
    await tester.pump();

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);
  });

  testWidgets('菜单重开后按最新可用性执行，菜单位置不变', (tester) async {
    final p = _FakeProvider();
    await _pump(tester, p);
    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text('撤销'));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    p.canUndoValue = true;
    p.notifyListeners();
    await tester.pump();

    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('撤销')), before);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(p.calls, ['undo']);
  });

  testWidgets('320 宽、两倍字体与键盘占位下菜单不出屏且每项 ≥ 44 高', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 760);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.reset);
    final p = _FakeProvider(hasSelectionValue: true);
    await _pump(tester, p, scale: 2);
    await tester.tap(find.byType(ContentActionsButton));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(AppMenuPanel<VoidCallback>));
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.right, lessThanOrEqualTo(320));
    // 菜单是覆盖层，可以盖在键盘上，但不能出屏
    expect(panel.bottom, lessThanOrEqualTo(760));
    for (final label in ['撤销', '恢复', '全选', '复制', '剪切', '粘贴']) {
      final row = tester.getRect(
        find
            .ancestor(of: find.text(label), matching: find.byType(AppPressable))
            .first,
      );
      expect(row.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(p.calls, ['copy']);
  });

  group('源码模式 provider', () {
    testWidgets('全选覆盖全文', (tester) async {
      final c = TextEditingController(text: 'hello world');
      final u = UndoHistoryController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(u.dispose);
      addTearDown(f.dispose);

      final p = SourceContentActions(
        controller: c,
        undoController: u,
        focusNode: f,
      );
      p.selectAll();
      expect(c.selection.start, 0);
      expect(c.selection.end, 'hello world'.length);
      expect(p.hasSelection, isTrue);
    });

    testWidgets('剪切删除选区并写剪贴板', (tester) async {
      // 拦截剪贴板通道，避免依赖真实平台
      String? written;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              written = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final c = TextEditingController(text: 'hello world');
      final u = UndoHistoryController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(u.dispose);
      addTearDown(f.dispose);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

      final p = SourceContentActions(
        controller: c,
        undoController: u,
        focusNode: f,
      );
      p.cut();

      expect(written, 'hello');
      expect(c.text, ' world');
      expect(c.selection.isCollapsed, isTrue);
      expect(c.selection.start, 0);
    });

    testWidgets('选区无效时粘贴插到末尾而不是崩溃', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': '!'};
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final c = TextEditingController();
      final u = UndoHistoryController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(u.dispose);
      addTearDown(f.dispose);
      // text setter 会把 selection 置为 -1（无效）
      c.text = 'abc';
      expect(c.selection.isValid, isFalse);

      final p = SourceContentActions(
        controller: c,
        undoController: u,
        focusNode: f,
      );
      await p.paste();

      expect(c.text, 'abc!');
      expect(c.selection.baseOffset, 4);
    });
  });
}
