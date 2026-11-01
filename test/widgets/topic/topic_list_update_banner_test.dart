import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/widgets/topic/topic_list_update_banner.dart';

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    for (final brightness in Brightness.values) {
      testWidgets('更新横幅 $size $brightness 保持原有加载态，禁止重复点击', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var taps = 0;
        Future<void> pump(bool loading) => tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: brightness,
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(size: size, disableAnimations: true),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ListView(
                      children: [
                        TopicListUpdateBanner(
                          count: 123,
                          loading: loading,
                          onTap: () => taps++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await pump(false);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(find.byType(TopicListUpdateBanner));
        expect(rect.width, lessThanOrEqualTo(size.width));
        // Figma「首页 · 新话题提示条」：文案固定、不显示数量；40 高胶囊，外框上下 8、左右 20
        expect(find.text('有新的或更新的话题，点按查看'), findsOneWidget);
        expect(find.textContaining('123'), findsNothing);
        expect(rect.height, 56);
        final pill = tester.getRect(
          find.descendant(
            of: find.byType(TopicListUpdateBanner),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(pill.height, 40);
        expect(pill.left - rect.left, 20);
        expect(rect.right - pill.right, 20);
        expect(pill.top - rect.top, 8);
        await tester.tap(find.byType(TopicListUpdateBanner));
        expect(taps, 1);
        await pump(true);
        // 0.4.0：加载态是系统菊花
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TopicListUpdateBanner),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        await tester.tap(find.byType(TopicListUpdateBanner));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
