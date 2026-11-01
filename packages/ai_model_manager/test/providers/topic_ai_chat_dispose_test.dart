import 'dart:async';
import 'dart:typed_data';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:ai_model_manager/services/dio_http_bridge.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟 cupertino_http：有请求在进行时 close 会抛 StateError，响应流也不会自己结束；
/// 记下收到的取消信号和 close 次数。
class _HangingAdapter implements HttpClientAdapter {
  bool cancelFired = false;
  bool running = false;
  int closeCalls = 0;
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    running = true;
    cancelFuture?.then((_) {
      cancelFired = true;
      running = false;
    });
    if (!started.isCompleted) started.complete();
    // 一直不出数据、不结束
    return ResponseBody(
      Stream<Uint8List>.fromFuture(Completer<Uint8List>().future),
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {
    closeCalls++;
    if (running) throw StateError('cannot close with running requests');
  }
}

const _provider = AiProvider(
  id: 'p1',
  name: 'p',
  type: AiProviderType.openai,
  baseUrl: 'https://api.example.com/v1',
);
const _model = AiModel(id: 'gpt-x');

Future<(TopicAiChatNotifier, _HangingAdapter)> _make() async {
  SharedPreferences.setMockInitialValues({'ai_apikey_p1': 'sk-test'});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _HangingAdapter();
  final notifier = TopicAiChatNotifier(
    chatService: AiChatService(),
    storageService: AiChatStorageService(prefs),
    topicId: 1,
    requestClientFactory: () => DioBackedHttpClient(adapter),
  );
  return (notifier, adapter);
}

Future<void> _startSending(TopicAiChatNotifier n, _HangingAdapter adapter) async {
  unawaited(
    n.sendMessage(
      '你好',
      ContextScope.first5,
      selectedModel: (provider: _provider, model: _model),
    ),
  );
  await adapter.started.future.timeout(const Duration(seconds: 5));
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('请求进行中 dispose：底层请求被取消，不抛异常（close 在有请求时会抛 StateError 的传输层）', () async {
    final (n, adapter) = await _make();
    await _startSending(n, adapter);
    expect(adapter.running, isTrue, reason: '请求确实在进行中');

    expect(n.dispose, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.cancelFired, isTrue, reason: '底层连接收到取消信号');
    expect(adapter.closeCalls, greaterThanOrEqualTo(1), reason: '取消之后关闭了 adapter');
  });

  test('请求进行中点停止：底层请求被取消，不抛异常，状态回到非生成中', () async {
    final (n, adapter) = await _make();
    await _startSending(n, adapter);
    expect(n.state.isGenerating, isTrue);

    expect(n.stopGeneration, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.cancelFired, isTrue);
    expect(n.state.isGenerating, isFalse);
    n.dispose();
  });
}
