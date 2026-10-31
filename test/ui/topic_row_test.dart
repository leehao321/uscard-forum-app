import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M3：列表行（设计说明 §3.1「列表行」、计划 §9 朗读顺序）。
// fixtureTopics 覆盖 置顶 / 有新回复 / 未读新话题 / 已关闭 / 超长标题。

Widget _list(List<Topic> topics, Map<int, Category> categories) => Scaffold(
  body: ListView(
    children: [
      for (final t in topics)
        t.pinned
            ? PinnedTopicRow(topic: t, onTap: () {})
            : TopicRow(
                topic: t,
                category: categories[int.tryParse(t.categoryId)],
                onTap: () {},
              ),
    ],
  ),
);

void main() {
  setUpAll(loadUiFonts);

  final categories = {for (final c in fixtureCategories()) c.id: c};

  group('渲染', () {
    for (final variant in UiVariant.portrait) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          _list(fixtureTopics(), categories),
          variant: variant,
        );
        expectNoUiException(tester);
        if (variant.textScale != 1.3) {
          await uiShot(tester, 'm3_rows_${variant.label}');
        }
      });
    }
  });

  testUi('列表行：标题最多 2 行，最小高 72，pad 20，计数在右', (tester) async {
    final topics = fixtureTopics();
    final long = topics.firstWhere((t) => t.id == 1004);
    final short = topics.firstWhere((t) => t.id == 1002);
    await pumpUi(
      tester,
      Scaffold(
        body: Column(
          children: [
            TopicRow(topic: long, category: categories[3], onTap: () {}),
            TopicRow(topic: short, category: categories[1], onTap: () {}),
          ],
        ),
      ),
    );
    final rows = find.byType(TopicRow);
    expect(tester.getSize(rows.first).height, greaterThanOrEqualTo(96));
    expect(tester.getSize(rows.last).height, greaterThanOrEqualTo(72));
    final title = tester.renderObject<RenderParagraph>(find.text(long.title));
    expect(title.maxLines, 2);
    expect(title.didExceedMaxLines, isTrue);
    expect(tester.getTopLeft(find.text(long.title)).dx, 20);
    // 计数靠右：右缘 = 页边距 20
    expect(
      tester.getTopRight(find.text('${short.replyCount}')).dx,
      closeTo(440 - 20, 0.5),
    );
  });

  testUi('有新回复时元信息行带 brand 色「N 条新回复」', (tester) async {
    final topic = fixtureTopics().firstWhere((t) => t.id == 1001);
    expect(TopicRow.newRepliesOf(topic), greaterThan(0));
    await pumpUi(
      tester,
      Scaffold(
        body: TopicRow(topic: topic, category: categories[1], onTap: () {}),
      ),
    );
    final n = TopicRow.newRepliesOf(topic);
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (r) => r.text.toPlainText().contains('条新回复'),
          orElse: () => fail('没有「条新回复」'),
        );
    expect(rich.text.toPlainText(), contains('$n'));
    // Text.rich 外面还套了一层样式 span，递归找带「条新回复」的那一段
    TextSpan? brand;
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').contains('条新回复')) {
        brand = span;
      }
      return true;
    });
    expect(brand, isNotNull);
    expect(brand!.style!.color, AppColors.light.brandPrimary);
  });

  testUi('未读的新话题不显示「N 条新回复」', (tester) async {
    final topic = fixtureTopics().firstWhere((t) => t.id == 1003);
    expect(TopicRow.newRepliesOf(topic), 0);
  });

  testUi('整行合并朗读：标题、分类、作者、时间、新回复、赞、回复', (tester) async {
    final topic = fixtureTopics().firstWhere((t) => t.id == 1001);
    await pumpUi(
      tester,
      Scaffold(
        body: TopicRow(topic: topic, category: categories[1], onTap: () {}),
      ),
    );
    final handle = tester.ensureSemantics();
    final label = tester.getSemantics(find.byType(TopicRow)).label;
    final order = [
      topic.title,
      categories[1]!.name,
      '条新回复',
      '点赞',
    ].map(label.indexOf).toList();
    expect(order.every((i) => i >= 0), isTrue, reason: label);
    expect([...order]..sort(), order, reason: '顺序：$label');
    expect(
      tester
          .getSemantics(find.byType(TopicRow))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );
    handle.dispose();
  });

  testUi('置顶折叠行：热区 ≥ 44，单行省略，朗读「置顶 · 标题」', (tester) async {
    final pinned = fixtureTopics().firstWhere((t) => t.pinned);
    await pumpUi(
      tester,
      Scaffold(
        body: PinnedTopicRow(topic: pinned, onTap: () {}),
      ),
    );
    expect(
      tester.getSize(find.byType(PinnedTopicRow)).height,
      greaterThanOrEqualTo(44),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(PinnedTopicRow)).label,
      contains(pinned.title),
    );
    expect(
      tester.getSemantics(find.byType(PinnedTopicRow)).label,
      contains('置顶'),
    );
    handle.dispose();
    await expectUiAccessibility(tester, textContrast: false);
  });

  testUi('点按和长按各自回调', (tester) async {
    final topic = fixtureTopics().firstWhere((t) => t.id == 1002);
    var tapped = 0;
    var long = 0;
    await pumpUi(
      tester,
      Scaffold(
        body: TopicRow(
          topic: topic,
          category: categories[1],
          onTap: () => tapped++,
          onLongPress: () => long++,
        ),
      ),
    );
    await tester.tap(find.byType(TopicRow));
    await tester.longPress(find.byType(TopicRow));
    expect((tapped, long), (1, 1));
  });
}
