import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/image_viewer_page.dart';
import 'package:fluxdo/pages/viewer_chrome.dart';
import 'package:fluxdo/providers/ai_topic_summary_provider.dart';
import 'package:fluxdo/services/ai_topic_summary_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:fluxdo/widgets/notes/topic_note_sheet.dart';
import 'package:fluxdo/widgets/topic/ai_segment_summary_card.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M5：笔记半屏、AI 局部总结卡三态、图片查看器外壳。
// AI 一律用假的流，不碰任何真实接口。

final _variants = [...UiVariant.portrait, ...UiVariant.landscape];

/// 1×1 透明 PNG
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  setUpAll(loadUiFonts);

  group('解析局部总结', () {
    test('要点 + 楼层号', () {
      final points = AiTopicSummaryService.parseSegmentSummary(
        '- 楼主说明了安装步骤 #1、#3\n- 有人遇到报错（#5）\n* 结论是重启 #7 #9',
      );
      expect(points.length, 3);
      expect(points[0].text, '楼主说明了安装步骤');
      expect(points[0].floors, [1, 3]);
      expect(points[1].text, '有人遇到报错');
      expect(points[1].floors, [5]);
      expect(points[2].floors, [7, 9]);
    });

    test('不按要点格式输出时整段保留，续行并进上一条', () {
      final plain = AiTopicSummaryService.parseSegmentSummary('只有一句话');
      expect(plain.single.text, '只有一句话');
      final cont = AiTopicSummaryService.parseSegmentSummary('- 第一条\n接着写 #2');
      expect(cont.single.text, '第一条 接着写');
      expect(cont.single.floors, [2]);
    });

    test('只取楼层范围内的楼层作为输入', () {
      final posts = fixtureTopicDetail().postStream.posts;
      final all = AiTopicSummaryService.buildSegmentInput(
        title: 't',
        posts: posts,
      );
      final part = AiTopicSummaryService.buildSegmentInput(
        title: 't',
        posts: posts,
        from: 2,
        to: 3,
      );
      expect(part.postCount, 2);
      expect(all.postCount, greaterThan(part.postCount));
    });
  });

  group('AI 局部总结卡', () {
    Widget card({void Function(int)? onJump, VoidCallback? onSettings}) =>
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: AiSegmentSummaryCard(
              title: '测试话题',
              posts: fixtureTopicDetail().postStream.posts,
              onJumpToPost: onJump,
              onOpenSettings: onSettings,
            ),
          ),
        );

    testUi('未配置：提示 + 去设置 + 不再显示', (tester) async {
      var settings = 0;
      await pumpUi(
        tester,
        card(onSettings: () => settings++),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue(null),
        ],
      );
      expect(find.textContaining('还没有配置 AI 模型'), findsOneWidget);
      await tester.tap(find.text('去设置'));
      expect(settings, 1);
      await tester.tap(find.text('不再显示'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI 总结'), findsNothing);
    });

    testUi('收起 → 加载 → 结果，楼层号可点', (tester) async {
      final stream = StreamController<String>();
      var requests = 0;
      final jumps = <int>[];
      await pumpUi(
        tester,
        card(onJump: jumps.add),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue((_) {
            requests++;
            return stream.stream;
          }),
        ],
      );
      // 默认不自动请求
      expect(requests, 0);
      expect(find.text('总结这一段'), findsOneWidget);

      await tester.tap(find.text('总结这一段'));
      await tester.pump();
      expect(requests, 1);
      expect(find.textContaining('正在总结'), findsOneWidget);
      expect(find.text('停止'), findsOneWidget);

      stream.add('- 第一个要点 #2\n- 第二个要点 #3');
      await tester.pump();
      await stream.close();
      await tester.pumpAndSettle();
      expect(find.text('第一个要点'), findsOneWidget);
      expect(find.text('重新总结'), findsOneWidget);

      await tester.tap(find.text('#3'));
      expect(jumps, [3]);
      expectNoUiException(tester);
    });

    testUi('出错：显示原因，重试会再次请求', (tester) async {
      var requests = 0;
      await pumpUi(
        tester,
        card(),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue((_) {
            requests++;
            return Stream<String>.error(Exception('boom'));
          }),
        ],
      );
      await tester.tap(find.text('总结这一段'));
      await tester.pumpAndSettle();
      expect(find.textContaining('总结失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'), warnIfMissed: true);
      await tester.pumpAndSettle();
      expect(requests, 2);
    });

    testUi('模型返回空内容算失败', (tester) async {
      await pumpUi(
        tester,
        card(),
        overrides: [
          aiTopicSummaryModelProvider.overrideWithValue(null),
          aiSegmentSummaryRunnerProvider.overrideWithValue(
            (_) => const Stream<String>.empty(),
          ),
        ],
      );
      await tester.tap(find.text('总结这一段'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有返回内容'), findsOneWidget);
    });

    for (final v in _variants) {
      testUi('三态不溢出（${v.label}）', (tester) async {
        final stream = StreamController<String>();
        await pumpUi(
          tester,
          card(onSettings: () {}),
          variant: v,
          overrides: [
            aiTopicSummaryModelProvider.overrideWithValue(null),
            aiSegmentSummaryRunnerProvider.overrideWithValue(
              (_) => stream.stream,
            ),
          ],
        );
        expectNoUiException(tester);
        await tester.tap(find.text('总结这一段'));
        await tester.pump();
        stream.add('- 一个很长很长很长很长很长很长很长很长很长的要点 #2、#3、#4、#5');
        await tester.pump();
        expectNoUiException(tester);
        await stream.close();
        await tester.pumpAndSettle();
        expectNoUiException(tester);
        await uiShot(tester, 'm5_ai_card_${v.label}');
      });
    }
  });

  group('笔记半屏', () {
    Widget host({int? postNumber, String? quote}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showTopicNoteSheet(
              context,
              topicId: 42,
              title: '一个话题',
              postNumber: postNumber,
              quote: quote,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    testUi('添加笔记：引用块 + 停笔 1 秒自动保存到这一楼', (tester) async {
      await pumpUi(tester, host(postNumber: 6, quote: '被引用的这一楼的内容'));
      await tester.runAsync(() => TopicNoteStore.delete(42));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('添加笔记'), findsOneWidget);
      expect(find.text('被引用的这一楼的内容'), findsOneWidget);
      expect(find.text('#6'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '这一楼讲得对');
      // 不到 1 秒还没存
      await tester.pump(const Duration(milliseconds: 500));
      expect(await tester.runAsync(() => TopicNoteStore.get(42)), isNull);
      await tester.pump(const Duration(milliseconds: 700));
      final note = await tester.runAsync(() => TopicNoteStore.get(42));
      expect(note?.floorNotes[6], '这一楼讲得对');
      expect(note?.text, isEmpty);
    });

    for (final v in _variants) {
      testUi('不溢出（${v.label}）', (tester) async {
        await pumpUi(
          tester,
          host(postNumber: 6, quote: '被引用的内容 ' * 30),
          variant: v,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expectNoUiException(tester);
        await uiShot(tester, 'm5_note_${v.label}');
      });
    }
  });

  group('查看器外壳', () {
    Widget shell({double? progress}) => Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const ViewerGradient(),
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(child: ViewerPageCapsule(index: 2, total: 12)),
          ),
          Positioned(
            top: 60,
            left: 20,
            child: ViewerCircleButton(
              icon: AppIcons.saveAlt,
              semanticLabel: '保存',
              onPressed: () {},
            ),
          ),
          Positioned(
            top: 60,
            right: 20,
            child: ViewerCircleButton(
              icon: AppIcons.close,
              semanticLabel: '关闭',
              busy: progress != null,
              onPressed: () {},
            ),
          ),
          ViewerLoadingPill(progress: progress),
          const ViewerFilename(
            name: 'a-very-long-file-name-that-keeps-going.jpeg',
          ),
        ],
      ),
    );

    for (final v in _variants) {
      testUi('不溢出（${v.label}）', (tester) async {
        await pumpUi(tester, shell(progress: 0.62), variant: v, settle: false);
        await tester.pump(const Duration(milliseconds: 300));
        expectNoUiException(tester);
        expect(find.text('原图加载中 62%'), findsOneWidget);
        await uiShot(tester, 'm5_viewer_${v.label}');
      });
    }

    testUi('圆钮 44×44，读屏可点；加载中的钮忽略点击', (tester) async {
      var taps = 0;
      await pumpUi(
        tester,
        Scaffold(
          body: Center(
            child: ViewerCircleButton(
              icon: AppIcons.close,
              semanticLabel: '关闭',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ViewerCircleButton)),
        const Size(44, 44),
      );
      await expectUiAccessibility(tester, textContrast: false);
      await tester.tap(find.byType(ViewerCircleButton));
      expect(taps, 1);
    });

    testUi('没有总大小时只显示「原图加载中」', (tester) async {
      await pumpUi(
        tester,
        const Scaffold(body: ViewerLoadingPill()),
        settle: false,
      );
      await tester.pump();
      expect(find.text('原图加载中'), findsOneWidget);
    });

    testUi('内存图片查看器：关闭、保存圆钮出现，不溢出', (tester) async {
      await pumpUi(tester, ImageViewerPage(imageBytes: _png), settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expectNoUiException(tester);
      expect(find.byType(ViewerCircleButton), findsNWidgets(2));
    });
  });
}
