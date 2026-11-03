import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/app_ui_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppUiScale.factor.value = 1.0);

  group('档位', () {
    test('紧凑、标准、舒适、放大', () {
      expect(AppUiScale.levels, [0.9, 1.0, 1.1, 1.2]);
    });

    test('不认识的值回到标准：备份里可能带来任何数字', () {
      expect(AppUiScale.normalize(1.1), 1.1);
      expect(AppUiScale.normalize(null), 1.0);
      expect(AppUiScale.normalize(5.0), 1.0);
      expect(AppUiScale.normalize(0.0), 1.0);
    });

    test('读保存的值', () async {
      SharedPreferences.setMockInitialValues({AppUiScale.prefKey: 1.2});
      AppUiScale.load(await SharedPreferences.getInstance());
      expect(AppUiScale.factor.value, 1.2);
    });

    testWidgets('改档位：保存并刷新 RenderView', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await AppUiScale.set(prefs, 1.1);
      expect(AppUiScale.factor.value, 1.1);
      expect(prefs.getDouble(AppUiScale.prefKey), 1.1);
    });
  });

  group('RenderView', () {
    testWidgets('放大：逻辑尺寸变小，像素比变大，物理尺寸不变', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final config = AppUiScale.configurationFor(tester.view, 1.2);
      expect(config.devicePixelRatio, closeTo(3.6, 1e-9));
      expect(config.logicalConstraints.biggest.width, closeTo(1200 / 3.6, 1e-6));
      expect(config.logicalConstraints.biggest.height, closeTo(2400 / 3.6, 1e-6));
      // 逻辑尺寸换回物理尺寸要正好铺满屏幕
      expect(
        config.toPhysicalSize(config.logicalConstraints.biggest),
        const Size(1200, 2400),
      );
    });

    testWidgets('缩小：逻辑尺寸变大', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final config = AppUiScale.configurationFor(tester.view, 0.9);
      expect(config.logicalConstraints.biggest.width, closeTo(900 / 2.7, 1e-6));
    });

    testWidgets('直接读 FlutterView 的代码用这个比例', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      AppUiScale.factor.value = 1.2;
      expect(AppUiScale.logicalRatioOf(tester.view), closeTo(3.6, 1e-9));
    });
  });

  group('触摸点', () {
    test('按比例换算，手指点在哪儿，命中的就是哪儿', () {
      final down = AppUiScale.scalePointer(
        const PointerDownEvent(position: Offset(120, 240)),
        1.2,
      );
      expect(down, isA<PointerDownEvent>());
      expect(down.position.dx, closeTo(100, 1e-9));
      expect(down.position.dy, closeTo(200, 1e-9));
    });

    test('滑动的增量也要换算，否则列表滚得比手指快', () {
      final move = AppUiScale.scalePointer(
        const PointerMoveEvent(position: Offset(120, 240), delta: Offset(0, 12)),
        1.2,
      );
      expect(move.delta.dy, closeTo(10, 1e-9));
    });

    test('标准比例原样返回', () {
      const event = PointerDownEvent(position: Offset(1, 2));
      expect(identical(AppUiScale.scalePointer(event, 1.0), event), isTrue);
    });
  });

  group('MediaQuery', () {
    const base = MediaQueryData(
      size: Size(400, 800),
      devicePixelRatio: 3,
      padding: EdgeInsets.only(top: 60, bottom: 30),
      viewPadding: EdgeInsets.only(top: 60, bottom: 30),
      viewInsets: EdgeInsets.only(bottom: 300),
      systemGestureInsets: EdgeInsets.only(left: 20),
    );

    test('尺寸、安全区、键盘都换算', () {
      final scaled = AppUiScale.scaleMedia(base, 1.25);
      expect(scaled.size, const Size(320, 640));
      expect(scaled.devicePixelRatio, 3.75);
      expect(scaled.padding.top, 48);
      expect(scaled.viewPadding.bottom, 24);
      expect(scaled.viewInsets.bottom, 240);
      expect(scaled.systemGestureInsets.left, 16);
    });

    test('字号比例不动：界面缩放已经带着文字一起放大，不能乘两次', () {
      final data = base.copyWith(textScaler: const TextScaler.linear(1.3));
      expect(AppUiScale.scaleMedia(data, 1.2).textScaler, const TextScaler.linear(1.3));
    });

    testWidgets('切档位时界面立即刷新，子树状态保留', (tester) async {
      Size? seen;
      var inits = 0;
      await tester.pumpWidget(
        MediaQuery(
          data: base,
          child: AppUiScaleScope(
            child: _InitCounter(
              onInit: () => inits++,
              child: Builder(
                builder: (context) {
                  seen = MediaQuery.sizeOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen, const Size(400, 800));
      AppUiScale.factor.value = 1.25;
      await tester.pump();
      expect(seen, const Size(320, 640));
      expect(inits, 1);
    });
  });
}

class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.onInit, required this.child});

  final VoidCallback onInit;
  final Widget child;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
