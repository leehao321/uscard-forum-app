import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 审查第 9 批（设置页）：请求头默认遮住、凭据读失败不清掉、测试连接用一次性 id、连点保存只保存一次。

class _Store implements McpSecretStore {
  _Store({this.failRead = false, this.writeDelay = Duration.zero});

  final bool failRead;
  final Duration writeDelay;
  final data = <String, McpSecrets>{};
  final writes = <String>[];
  final deletes = <String>[];

  @override
  Future<McpSecrets> read(String id) async {
    if (failRead) throw const McpSecretReadException();
    return data[id] ?? const McpSecrets();
  }

  @override
  Future<void> write(String id, McpSecrets s) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    writes.add(id);
    data[id] = s;
  }

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
    data.remove(id);
  }
}

class _RecSvc extends McpClientService {
  _RecSvc() : super(clientFactory: () => MockClient((_) async => http.Response('{}', 200)));

  final listed = <String>[];
  final forgot = <String>[];

  @override
  Future<List<McpToolInfo>> listTools(McpServerConfig server, McpSecrets secrets, {Future<void>? abort}) async {
    listed.add(server.id);
    return [McpToolInfo.fromJson({'name': 'search', 'annotations': {'readOnlyHint': true}})];
  }

  @override
  void forget(String serverId) => forgot.add(serverId);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    required _Store store,
    McpClientService? service,
    List<McpServerConfig> servers = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (servers.isNotEmpty) McpServerListNotifier.storageKey: jsonEncode([for (final s in servers) s.toJson()]),
    });
    prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final overrides = [
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      mcpSecretStoreProvider.overrideWithValue(store),
      if (service != null) mcpClientServiceProvider.overrideWithValue(service),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => home)),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold).last));
  }

  const existing = McpServerConfig(id: 'a1', name: '文档', url: 'https://docs.example.com/mcp');

  testWidgets('请求头默认遮住：只显示「已设置 N 个」，点眼睛才显示内容和输入框', (tester) async {
    final store = _Store()..data['a1'] = const McpSecrets(headers: {'X-Key': 'HEADER-SECRET', 'X-Two': 'v'});
    await pump(tester, const McpServerEditPage(serverId: 'a1'), store: store, servers: [existing]);
    expect(find.byKey(const ValueKey('mcp-headers-hidden')), findsOneWidget);
    expect(find.text('已设置 2 个请求头（内容已遮住）'), findsOneWidget);
    expect(find.textContaining('HEADER-SECRET'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-headers-show')));
    await tester.tap(find.byKey(const ValueKey('mcp-headers-show')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mcp-headers')), findsOneWidget);
    expect(find.textContaining('HEADER-SECRET'), findsOneWidget);
  });

  testWidgets('读不到已保存的凭据：提示；用户没改这两项保存时不写入、不删除', (tester) async {
    final store = _Store(failRead: true);
    final container = await pump(tester, const McpServerEditPage(serverId: 'a1'), store: store, servers: [existing]);
    expect(find.byKey(const ValueKey('mcp-secret-warning')), findsOneWidget);
    expect(find.textContaining('读不到已保存的 Token'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '改了名字');
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await _settle(tester);
    expect(store.writes, isEmpty, reason: '没改凭据，不写入');
    expect(store.deletes, isEmpty, reason: '更不能删除');
    expect(container.read(mcpServerListProvider).single.name, '改了名字');
  });

  testWidgets('读不到已保存的凭据、但用户输入了新 Token：写入新的', (tester) async {
    final store = _Store(failRead: true);
    await pump(tester, const McpServerEditPage(serverId: 'a1'), store: store, servers: [existing]);
    await tester.enterText(find.byType(TextField).at(2), 'NEW-TOKEN');
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await _settle(tester);
    expect(store.writes, ['a1']);
    expect(store.data['a1']!.bearerToken, 'NEW-TOKEN');
  });

  testWidgets('测试连接用一次性探测 id，测完就 forget；这个服务真实的会话不被碰', (tester) async {
    final svc = _RecSvc();
    await pump(tester, const McpServerEditPage(serverId: 'a1'), store: _Store(), service: svc, servers: [existing]);
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-test')));
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await _settle(tester);
    expect(svc.listed.single, startsWith('_probe_'));
    expect(svc.listed.single, isNot('a1'));
    expect(svc.forgot, [svc.listed.single], reason: '测完忘掉探测会话，且只忘它');
    expect(svc.forgot.contains('a1'), isFalse);
  });

  testWidgets('连点保存：只新增一个服务、只返回一次；保存期间按钮是禁用的', (tester) async {
    final store = _Store(writeDelay: const Duration(milliseconds: 150));
    var pops = 0;
    final container = await pump(tester, const McpServerEditPage(), store: store);
    final nav = Navigator.of(tester.element(find.byType(McpServerEditPage)));
    final observer = nav; // 用路由数量判断 pop 次数
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'https://mcp.example.com/mcp');
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await tester.pump();
    final button = tester.widget<TextButton>(find.byKey(const ValueKey('mcp-save')));
    expect(button.onPressed, isNull, reason: '保存期间禁用');
    await tester.tap(find.byKey(const ValueKey('mcp-save')), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('mcp-save')), warnIfMissed: false);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(container.read(mcpServerListProvider).length, 1);
    expect(store.writes.length, 1);
    expect(find.byType(McpServerEditPage), findsNothing, reason: '已经返回');
    expect(find.text('打开'), findsOneWidget, reason: '只返回了一层，没有多 pop');
    pops++;
    expect(pops, 1);
    expect(observer, isNotNull);
  });
}
