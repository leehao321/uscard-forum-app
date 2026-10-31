import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_model_manager/services/dio_http_bridge.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._respond);

  final Future<ResponseBody> Function(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) _respond;

  RequestOptions? lastOptions;
  List<int>? lastBody;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      lastBody = chunks.expand((c) => c).toList();
    }
    return _respond(options, requestStream);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

/// 模拟 cupertino_http：有请求在进行时 close 会抛 StateError，也不会自己中断响应流
class _CupertinoLikeAdapter implements HttpClientAdapter {
  _CupertinoLikeAdapter(this.stream);

  final Stream<Uint8List> stream;
  bool cancelFutureFired = false;
  bool running = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    running = true;
    cancelFuture?.then((_) => cancelFutureFired = true);
    return ResponseBody(stream, 200, headers: {
      'content-type': ['text/event-stream'],
    });
  }

  @override
  void close({bool force = false}) {
    if (running) throw StateError('cannot close with running requests');
  }
}

void main() {
  group('DioBackedHttpClient', () {
    test('GET 透传 method/url/headers，并解析响应 body', () async {
      final adapter = _RecordingAdapter((options, _) async {
        return ResponseBody.fromString(
          '{"ok":true}',
          200,
          headers: {
            'content-type': ['application/json'],
            'content-length': ['11'],
          },
          statusMessage: 'OK',
        );
      });
      final client = DioBackedHttpClient(adapter);

      final response = await client.get(
        Uri.parse('https://api.example.com/v1/hello?x=1'),
        headers: {'Authorization': 'Bearer abc', 'X-Test': '1'},
      );

      expect(adapter.lastOptions!.method, 'GET');
      expect(adapter.lastOptions!.path,
          'https://api.example.com/v1/hello?x=1');
      expect(adapter.lastOptions!.headers['authorization'], 'Bearer abc');
      expect(adapter.lastOptions!.headers['x-test'], '1');
      expect(response.statusCode, 200);
      expect(response.body, '{"ok":true}');
      expect(response.headers['content-type'], 'application/json');
    });

    test('POST 把 body 流式透传到 adapter', () async {
      final adapter = _RecordingAdapter((_, __) async {
        return ResponseBody.fromString('{}', 201,
            headers: {}, statusMessage: 'Created');
      });
      final client = DioBackedHttpClient(adapter);

      await client.post(
        Uri.parse('https://api.example.com/v1/x'),
        headers: {'Content-Type': 'application/json'},
        body: '{"q":"hi"}',
      );

      expect(adapter.lastOptions!.method, 'POST');
      expect(utf8.decode(adapter.lastBody!), '{"q":"hi"}');
    });

    test('流式响应（SSE 风格）按 chunk 透传，不在桥接层缓冲', () async {
      final controller = StreamController<Uint8List>();
      final adapter = _RecordingAdapter((_, __) async {
        return ResponseBody(
          controller.stream,
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      });
      final client = DioBackedHttpClient(adapter);

      final responseFuture = client.send(
        http.Request('POST', Uri.parse('https://api.example.com/v1/stream'))
          ..body = '',
      );

      final response = await responseFuture;
      final received = <List<int>>[];
      final sub = response.stream.listen(received.add);

      controller
        ..add(Uint8List.fromList(utf8.encode('data: chunk1\n\n')))
        ..add(Uint8List.fromList(utf8.encode('data: chunk2\n\n')));
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 2);
      expect(utf8.decode(received[0]), 'data: chunk1\n\n');
      expect(utf8.decode(received[1]), 'data: chunk2\n\n');

      await controller.close();
      await sub.cancel();
    });

    test('4xx 不抛错，状态码原样返回', () async {
      final adapter = _RecordingAdapter((_, __) async {
        return ResponseBody.fromString('unauthorized', 401,
            headers: {}, statusMessage: 'Unauthorized');
      });
      final client = DioBackedHttpClient(adapter);

      final response = await client.get(Uri.parse('https://api.example.com/x'));
      expect(response.statusCode, 401);
      expect(response.reasonPhrase, 'Unauthorized');
      expect(response.body, 'unauthorized');
    });

    test('多值响应头按逗号合并', () async {
      final adapter = _RecordingAdapter((_, __) async {
        return ResponseBody.fromString('ok', 200, headers: {
          'set-cookie': ['a=1', 'b=2'],
        });
      });
      final client = DioBackedHttpClient(adapter);

      final response = await client.get(Uri.parse('https://api.example.com/x'));
      expect(response.headers['set-cookie'], 'a=1, b=2');
    });

    test('DioException 转为 http.ClientException', () async {
      final adapter = _RecordingAdapter((options, _) async {
        throw DioException(
          requestOptions: options,
          message: 'connection refused',
          type: DioExceptionType.connectionError,
        );
      });
      final client = DioBackedHttpClient(adapter);

      expect(
        () => client.get(Uri.parse('https://api.example.com/x')),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('close() 后再发请求抛 ClientException', () async {
      final adapter = _RecordingAdapter((_, __) async {
        return ResponseBody.fromString('', 200, headers: {});
      });
      final client = DioBackedHttpClient(adapter);
      client.close();

      expect(
        () => client.get(Uri.parse('https://api.example.com/x')),
        throwsA(isA<http.ClientException>()),
      );
      expect(adapter.closed, isTrue);
    });
  });

  group('取消与关闭（审查第 5 批）', () {
    test('close 先取消进行中的请求：读流的一方收到 RequestAbortedException，close 不抛', () async {
      final body = StreamController<Uint8List>();
      final adapter = _CupertinoLikeAdapter(body.stream);
      final client = DioBackedHttpClient(adapter);
      final response = await client.send(
        http.Request('POST', Uri.parse('https://api.example.com/v1/x'))..body = 'x',
      );
      final errors = <Object>[];
      final done = Completer<void>();
      response.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
      body.add(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);

      // 模拟 CupertinoClient：有请求在进行时 close 抛 StateError；这里不能抛出来
      expect(client.close, returnsNormally);
      await done.future.timeout(const Duration(seconds: 2));
      expect(errors.single, isA<http.RequestAbortedException>());
      expect(adapter.cancelFutureFired, isTrue);
    });

    test('Abortable 请求：abortTrigger 触发后流被打断（适配器自己不会中断）', () async {
      final body = StreamController<Uint8List>();
      final adapter = _CupertinoLikeAdapter(body.stream);
      final client = DioBackedHttpClient(adapter);
      final abort = Completer<void>();
      final response = await client.send(
        http.AbortableRequest('POST', Uri.parse('https://api.example.com/v1/x'), abortTrigger: abort.future)
          ..body = 'x',
      );
      final errors = <Object>[];
      final done = Completer<void>();
      response.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
      abort.complete();
      await done.future.timeout(const Duration(seconds: 2));
      expect(errors.single, isA<http.RequestAbortedException>());
    });
  });
}
