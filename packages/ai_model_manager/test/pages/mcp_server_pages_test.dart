import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// MCP 服务列表页 / 编辑页：明文警告、测试连接、工具开关与「可能会修改数据」提示、保存。

/// 假 MCP 服务：三个工具（只读 / 没标注 / 标了不只读）
McpClientService _service({int status = 200}) => McpClientService(
  clientFactory: () => MockClient.streaming((req, body) async {
    final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
    if (status != 200) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'error': {'message': 'nope'}}))),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    Map<String, dynamic> ok(Map<String, dynamic> r) => {'jsonrpc': '2.0', 'id': j['id'], 'result': r};
    http.StreamedResponse resp(Object o) => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(o))),
      200,
      headers: {'content-type': 'application/json'},
    );
    switch (j['method']) {
      case 'initialize':
        return resp(ok({'protocolVersion': '2025-06-18'}));
      case 'notifications/initialized':
        return http.StreamedResponse(const Stream.empty(), 202);
      default:
        return resp(ok({
          'tools': [
            {'name': 'search', 'description': '搜索', 'annotations': {'readOnlyHint': true}},
            {'name': 'plain', 'description': '没有标注'},
            {'name': 'write', 'description': '写入', 'annotations': {'readOnlyHint': false}},
          ],
        }));
    }
  }),
);

/// 真实时钟上等一会儿（MockClient 的异步不在 pump 的假时钟里）
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<void> pump(WidgetTester tester, Widget home, {McpClientService? service}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSharedPreferencesProvider.overrideWithValue(prefs),
          if (service != null) mcpClientServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('编辑页：地址是 http:// 时给出明文警告，https 时没有；两种都能保存', (tester) async {
    await pump(tester, const McpServerEditPage());
    expect(find.byKey(const ValueKey('mcp-plain-warning')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'http://192.168.1.2:8080/mcp');
    await tester.pump();
    expect(find.byKey(const ValueKey('mcp-plain-warning')), findsOneWidget);
    expect(find.textContaining('明文传输'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'https://mcp.example.com/mcp');
    await tester.pump();
    expect(find.byKey(const ValueKey('mcp-plain-warning')), findsNothing);

    // http 地址允许保存
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'http://192.168.1.2:8080/mcp');
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await _settle(tester);
    final saved = jsonDecode(prefs.getString(McpServerListNotifier.storageKey)!) as List;
    expect((saved.single as Map)['url'], 'http://192.168.1.2:8080/mcp');
  });

  testWidgets('测试连接：显示工具数量；默认只开只读的，其余关；手动打开会修改数据的工具时出现提示', (tester) async {
    await pump(tester, const McpServerEditPage(), service: _service());
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'https://mcp.example.com/mcp');
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('mcp-test-ok')), findsOneWidget);
    expect(find.text('连接正常：3 个工具'), findsOneWidget);
    Switch switchOf(String tool) => tester.widget<Switch>(
      find.descendant(of: find.byKey(ValueKey('mcp-tool-$tool')), matching: find.byType(Switch)),
    );
    expect(switchOf('search').value, isTrue);
    expect(switchOf('plain').value, isFalse);
    expect(switchOf('write').value, isFalse);
    expect(find.byKey(const ValueKey('mcp-modify-plain')), findsNothing, reason: '关着的时候不提示');

    await tester.ensureVisible(find.byKey(const ValueKey('mcp-tool-write')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('mcp-tool-write')), matching: find.byType(Switch)));
    await tester.pump();
    expect(find.byKey(const ValueKey('mcp-modify-write')), findsOneWidget);
    expect(find.text('这个工具可能会修改数据'), findsOneWidget);
    // 只读的工具即使打开也没有这行
    expect(find.byKey(const ValueKey('mcp-modify-search')), findsNothing);
  });

  testWidgets('测试连接失败：显示可读原因，不显示工具', (tester) async {
    await pump(tester, const McpServerEditPage(), service: _service(status: 401));
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'https://mcp.example.com/mcp');
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('mcp-test-error')), findsOneWidget);
    expect(find.textContaining('认证失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-test-ok')), findsNothing);
  });

  testWidgets('保存：工具开关存下来；Token 和请求头进安全存储，不在偏好设置里', (tester) async {
    await pump(tester, const McpServerEditPage(), service: _service());
    await tester.enterText(find.byKey(const ValueKey('mcp-url')), 'https://mcp.example.com/mcp');
    await tester.enterText(find.byType(TextField).at(2), 'TOKEN-ABC');
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-headers-show')));
    await tester.tap(find.byKey(const ValueKey('mcp-headers-show')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('mcp-headers')), 'X-Key: HEADER-XYZ');
    await tester.tap(find.byKey(const ValueKey('mcp-test')));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('mcp-tool-plain')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('mcp-tool-plain')), matching: find.byType(Switch)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await _settle(tester);

    final raw = prefs.getString(McpServerListNotifier.storageKey)!;
    expect(raw, isNot(contains('TOKEN-ABC')));
    expect(raw, isNot(contains('HEADER-XYZ')));
    final cfg = (jsonDecode(raw) as List).single as Map;
    expect(cfg['tools'], {'search': true, 'plain': true, 'write': false});
    final secret = await const FlutterSecureStorage().read(key: SecureMcpSecretStore.keyOf(cfg['id'] as String));
    expect(secret, contains('TOKEN-ABC'));
    expect(secret, contains('HEADER-XYZ'));
  });

  testWidgets('列表页：显示服务、明文 http 标注；开关能关掉服务', (tester) async {
    await pump(tester, const McpServersPage());
    expect(find.text('还没有 MCP 服务。点右上角添加一个。'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(McpServersPage)));
    await container.read(mcpServerListProvider.notifier).add(name: '文档搜索', url: 'https://docs.example.com/mcp');
    await container.read(mcpServerListProvider.notifier).add(name: '内网', url: 'http://10.0.0.5/mcp');
    await tester.pumpAndSettle();
    expect(find.text('文档搜索'), findsOneWidget);
    expect(find.text('docs.example.com'), findsOneWidget);
    expect(find.text('10.0.0.5 · 明文 http'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(container.read(mcpServerListProvider).first.enabled, isFalse);
  });
}
