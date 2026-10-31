import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_submit_button.dart';

// 0.4.0 M5：发送按钮换成 v2 的 44 高胶囊（66 宽起），提交中文字换菊花、尺寸不变。

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('胶囊 44 高、66 宽起，显示文字', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        ComposerSubmitButton(
          label: '发送',
          busy: false,
          onPressed: () => calls++,
        ),
      ),
    );
    final button = find.byKey(const ValueKey('composer-header-submit'));
    final size = tester.getSize(button);
    expect(size.height, 44);
    expect(size.width, greaterThanOrEqualTo(66));
    expect(find.text('发送'), findsOneWidget);
    await tester.tap(button);
    expect(calls, 1);
  });

  testWidgets('提交中置灰、显示菊花、尺寸不变，失败恢复后可重试', (tester) async {
    var busy = false;
    var calls = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: Center(
                child: ComposerSubmitButton(
                  label: '发送',
                  busy: busy,
                  onPressed: () => setState(() {
                    calls++;
                    busy = true;
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
    final button = find.byKey(const ValueKey('composer-header-submit'));
    final bounds = tester.getRect(button);
    await tester.tap(button);
    expect(calls, 1, reason: '请求立即开始');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.getRect(button), bounds, reason: '提交中按钮尺寸不变');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(button, warnIfMissed: false);
    expect(calls, 1);

    update(() => busy = false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('发送'), findsOneWidget);
    await tester.tap(button);
    expect(calls, 2);
  });

  testWidgets('保存编辑带图标', (tester) async {
    await tester.pumpWidget(
      _host(
        ComposerSubmitButton(
          label: '保存',
          icon: AppIcons.check,
          busy: false,
          onPressed: () {},
        ),
      ),
    );
    expect(find.byIcon(AppIcons.check), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
