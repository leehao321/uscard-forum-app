import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_switch_service.dart';
import 'package:fluxdo/widgets/site/site_switch_host.dart';

class _FakeWork implements SiteSwitchWork {
  _FakeWork({this.onUnmount});

  final log = <String>[];
  final Future<void> Function()? onUnmount;
  Object? failAt;
  Completer<void>? holdRestart;

  void _step(String name) {
    log.add(name);
    if (failAt == name) throw StateError('boom');
  }

  @override
  void stopWork() => _step('stop');

  @override
  Future<void> waitForUnmount() async {
    _step('unmount');
    await onUnmount?.call();
  }

  @override
  Future<void> drainWork() async => _step('drain');

  @override
  Future<Object?> prepareSite(SiteProfile site) async {
    _step('prepare');
    return 'jar-of-${site.id}';
  }

  @override
  void commitSite(SiteProfile site, Object? prepared) {
    _step('commit');
    SiteContext.activate(site);
    log.add('$prepared');
  }

  @override
  Future<void> restartWork() async {
    _step('restart');
    await holdRestart?.future;
  }
}

class _Tracked extends StatefulWidget {
  const _Tracked({required this.label, required this.events});

  final String label;
  final List<String> events;

  @override
  State<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<_Tracked> {
  @override
  void initState() {
    super.initState();
    widget.events.add('init ${widget.label} @${SiteContext.current.id}');
  }

  @override
  void dispose() {
    widget.events.add('dispose ${widget.label} @${SiteContext.current.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

final _siteNameProvider = Provider<String>((ref) => SiteContext.current.id);
final _counterProvider = NotifierProvider<_Counter, int>(_Counter.new);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void add() => state++;
}

void main() {
  final a = SitePresets.uscard;
  final b = SiteProfile(baseUrl: 'https://b.example.com', title: 'B');

  setUp(() => SiteContext.activate(a));
  tearDown(SiteContext.debugReset);

  group('步骤顺序', () {
    test('先停工作、卸界面、收尾，再换站，最后重启工作', () async {
      final work = _FakeWork();
      final controller = SiteSwitchController(work: work);
      expect(await controller.switchTo(b), isTrue);
      expect(work.log, [
        'stop',
        'unmount',
        'drain',
        'prepare',
        'commit',
        'jar-of-${b.id}',
        'restart',
      ]);
      expect(SiteContext.current.id, b.id);
      expect(controller.phase, SiteSwitchPhase.idle);
    });

    test('已是当前站：什么都不做', () async {
      final work = _FakeWork();
      final controller = SiteSwitchController(work: work);
      expect(await controller.switchTo(a), isFalse);
      expect(work.log, isEmpty);
    });

    test('切换中再点：忽略，不会并发切两次', () async {
      final work = _FakeWork()..holdRestart = Completer();
      final controller = SiteSwitchController(work: work);
      final first = controller.switchTo(b);
      await Future<void>.delayed(Duration.zero);
      final c = SiteProfile(baseUrl: 'https://c.example.com', title: 'C');
      expect(await controller.switchTo(c), isFalse);
      work.holdRestart!.complete();
      expect(await first, isTrue);
      expect(SiteContext.current.id, b.id);
      expect(work.log.where((s) => s == 'commit').length, 1);
    });

    test('步骤缺失时拒绝运行，一步都不执行', () async {
      var ran = 0;
      await expectLater(
        SiteSwitchService.runNoRestartSteps({
          SiteSwitchStep.stopWork: () async => ran++,
        }),
        throwsArgumentError,
      );
      expect(ran, 0);
    });
  });

  group('中途失败', () {
    for (final step in ['stop', 'drain', 'prepare', 'commit', 'restart']) {
      test('$step 失败：进失败态，不会回到正常界面', () async {
        final work = _FakeWork()..failAt = step;
        final controller = SiteSwitchController(work: work);
        expect(await controller.switchTo(b), isFalse);
        expect(controller.phase, SiteSwitchPhase.failed);
        expect(await controller.switchTo(b), isFalse, reason: '失败后不能再切');
      });
    }

    test('换站之前失败：当前站没变', () async {
      final work = _FakeWork()..failAt = 'prepare';
      await SiteSwitchController(work: work).switchTo(b);
      expect(SiteContext.current.id, a.id);
      expect(work.log, isNot(contains('commit')));
    });
  });

  group('界面树', () {
    /// 这条记录为什么不能只换 ProviderScope 的 key：同一帧里 GlobalKey 的 Navigator
    /// 会连页面栈一起被搬到新树上。框架行为变了这条会红，那时可以重新评估。
    testWidgets('只换 key：旧页面栈会活下来', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      Widget tree(String key) => KeyedSubtree(
        key: ValueKey(key),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Text('home'),
        ),
      );

      await tester.pumpWidget(tree('a'));
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('a-page')),
      );
      await tester.pumpAndSettle();
      expect(find.text('a-page'), findsOneWidget);

      await tester.pumpWidget(tree('b'));
      await tester.pumpAndSettle();
      expect(find.text('a-page'), findsOneWidget, reason: '旧页面还在');
    });

    testWidgets('切站后旧页面栈和 Riverpod 状态都没了，新站是全新的树', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final events = <String>[];
      final work = _FakeWork(onUnmount: () => tester.pump());
      final controller = SiteSwitchController(work: work);

      await tester.pumpWidget(
        SiteSwitchHost(
          controller: controller,
          builder: (_) => ProviderScope(
            key: ValueKey(SiteContext.current.id),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    _Tracked(label: 'home', events: events),
                    Text('site=${ref.watch(_siteNameProvider)}'),
                    Text('count=${ref.watch(_counterProvider)}'),
                    TextButton(
                      onPressed: () =>
                          ref.read(_counterProvider.notifier).add(),
                      child: const Text('add'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pump();
      expect(find.text('count=1'), findsOneWidget);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => _Tracked(label: 'a-page', events: events),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('a-page'), findsOneWidget);
      events.clear();

      await controller.switchTo(b);
      await tester.pumpAndSettle();

      expect(find.text('a-page'), findsNothing);
      expect(find.text('site=${b.id}'), findsOneWidget);
      expect(find.text('count=0'), findsOneWidget);
      // 旧树销毁时还是旧站（收尾请求发给 A），新树建立时已经是新站
      expect(events.last, 'init home @${b.id}');
      expect(
        events.take(2),
        unorderedEquals(['dispose a-page @${a.id}', 'dispose home @${a.id}']),
      );
      expect(events.length, 3);
    });

    testWidgets('切换中只有占位，界面点不到', (tester) async {
      final work = _FakeWork()..holdRestart = Completer();
      final controller = SiteSwitchController(work: work);
      await tester.pumpWidget(
        SiteSwitchHost(
          controller: controller,
          builder: (_) => const MaterialApp(home: Text('content')),
        ),
      );
      final pending = controller.switchTo(b, placeholderColor: Colors.red);
      await tester.pump();
      await tester.pump();
      expect(find.text('content'), findsNothing);
      final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
      expect(box.color, Colors.red);
      work.holdRestart!.complete();
      await pending;
      await tester.pump();
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('切换失败：显示提示，不挂界面，不依赖 MaterialApp', (tester) async {
      final work = _FakeWork()..failAt = 'prepare';
      final controller = SiteSwitchController(work: work);
      await tester.pumpWidget(
        TranslationProvider(
          child: SiteSwitchHost(
            controller: controller,
            builder: (_) => const MaterialApp(home: Text('content')),
          ),
        ),
      );
      await controller.switchTo(b);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('content'), findsNothing);
      expect(find.textContaining('App'), findsOneWidget);
    });
  });
}
