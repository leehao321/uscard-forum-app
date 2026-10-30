import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 测试底座自检：夹具能按接口形状解析，pumpUi 设好的尺寸、安全区、
// 字号、明暗和平台都生效。

class _Probe extends StatelessWidget {
  const _Probe(this.onBuild);

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: () {}, child: const Text('确定')),
      ),
    );
  }
}

void main() {
  setUpAll(loadUiFonts);

  test('字体：MiSans、Material Symbols、Lucide 各字重', () {
    expect(
      loadedUiFonts,
      containsAll([
        'MiSans',
        'packages/material_symbols_icons/MaterialSymbolsRounded',
        'packages/lucide_icons_flutter/Lucide',
        for (final w in [100, 200, 300, 400, 500, 600])
          'packages/lucide_icons_flutter/Lucide$w',
      ]),
    );
  });

  group('夹具', () {
    test('话题列表', () {
      final topics = fixtureTopics();
      expect(topics, hasLength(5));
      expect(topics.first.pinned, isTrue);
      expect(topics.first.posters.first.user?.username, 'chase_fan');
      expect(topics.first.lastPostedAt, isNotNull);
      expect(topics[2].unseen, isTrue);
      expect(topics[3].closed, isTrue);
    });

    test('分类含子分类', () {
      final categories = fixtureCategories();
      expect(categories.where((c) => c.parentCategoryId == 1), hasLength(1));
    });

    test('话题详情', () {
      final detail = fixtureTopicDetail(replies: 4);
      final posts = detail.postStream.posts;
      expect(posts, hasLength(6));
      expect(posts.first.postNumber, 1);
      expect(posts.first.cooked, contains('<blockquote>'));
      expect(posts[1].cooked, contains('<table>'));
      expect(detail.postStream.stream, hasLength(6));
    });

    test('通知', () {
      final notifications = fixtureNotifications();
      expect(notifications, hasLength(5));
      expect(notifications.where((n) => !n.read), hasLength(3));
      expect(
        notifications.map((n) => n.notificationType),
        contains(NotificationType.likedConsolidated),
      );
    });

    test('用户', () {
      expect(fixtureUser().username, 'hao');
    });
  });

  group('pumpUi', () {
    for (final v in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 2.0, UiDevice.pro),
      const UiVariant(Brightness.light, 1.3, UiDevice.landscape),
    ]) {
      testUi('环境生效（${v.label}）', (tester) async {
        late MediaQueryData media;
        late ThemeData theme;
        await pumpUi(
          tester,
          _Probe((context) {
            media = MediaQuery.of(context);
            theme = Theme.of(context);
          }),
          variant: v,
        );
        expectNoUiException(tester);
        expect(media.size, v.device.size);
        expect(media.padding, v.device.padding);
        expect(media.textScaler.scale(10), closeTo(10 * v.textScale, 0.001));
        expect(theme.brightness, v.brightness);
        expect(theme.platform, TargetPlatform.iOS);
        expect(defaultTargetPlatform, TargetPlatform.iOS);
        await uiShot(tester, 'harness_${v.label}');
      });
    }

    testUi('无障碍检查可用', (tester) async {
      await pumpUi(tester, _Probe((_) {}));
      await expectUiAccessibility(tester);
    });
  });
}
