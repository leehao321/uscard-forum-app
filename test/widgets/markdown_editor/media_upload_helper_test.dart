/// 媒体改名上传 helper:short-url 播放路径换算与标签生成。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/media_upload_helper.dart';

void main() {
  test('upload:// 短链 → /uploads/short-url/<b62>.xz(去原扩展)', () {
    expect(
      mediaShortUrlToXzPath('upload://lwDn83PDeB3xOUoEeZI9v77qGJa.mp4'),
      '/uploads/short-url/lwDn83PDeB3xOUoEeZI9v77qGJa.xz',
    );
    expect(
      mediaShortUrlToXzPath('upload://abc'),
      '/uploads/short-url/abc.xz',
    );
    // 非短链兜底:仅换扩展
    expect(
      mediaShortUrlToXzPath('/uploads/default/original/1X/a.mp3'),
      '/uploads/default/original/1X/a.xz',
    );
  });

  test('audio 标签形态(脚本 makeTag 同款)', () {
    expect(
      buildMediaTag(
        isAudio: true,
        srcPath: '/uploads/short-url/abc.xz',
        mime: 'audio/mpeg',
      ),
      '<audio controls>\n'
      '  <source src="/uploads/short-url/abc.xz" type="audio/mpeg">\n'
      '</audio>',
    );
  });

  test('语音消息包 [wrap=voice] 壳', () {
    final tag = buildMediaTag(
      isAudio: true,
      srcPath: '/uploads/short-url/abc.xz',
      mime: 'audio/mp4',
      voice: true,
    );
    expect(tag, startsWith('[wrap=voice]\n<audio controls>'));
    expect(tag, endsWith('[/wrap]'));
  });

  test('video 标签带默认宽高', () {
    final tag = buildMediaTag(
      isAudio: false,
      srcPath: '/uploads/short-url/xyz.xz',
      mime: 'video/mp4',
    );
    expect(tag, contains('<video width="640" height="360" controls>'));
    expect(tag,
        contains('<source src="/uploads/short-url/xyz.xz" type="video/mp4">'));
  });

  group('按站点上传音视频', () {
    test('美卡（不改名）：播放路径保留原扩展，linux.do 用 .xz', () {
      expect(
        mediaSrcPath('upload://abc.mp4', asXz: false),
        '/uploads/short-url/abc.mp4',
      );
      expect(mediaSrcPath('/uploads/a.mp3', asXz: false), '/uploads/a.mp3');
      expect(
        mediaSrcPath('upload://abc.mp4', asXz: true),
        '/uploads/short-url/abc.xz',
      );
    });

    test('扩展名在站点白名单里才放行，不在就给出提示，不设限时放行', () {
      expect(mediaExtensionRejection('/tmp/a.MP4', ['mp4', 'jpg']), isNull);
      expect(
        mediaExtensionRejection(r'C:	mpoice.m4a', ['jpg', 'png']),
        contains('.m4a'),
      );
      expect(mediaExtensionRejection('/tmp/noext', ['mp4']), isNotNull);
      expect(mediaExtensionRejection('/tmp/a.webm', null), isNull);
    });

    test('美卡上传不允许的扩展名时直接报错，不发请求', () async {
      await expectLater(
        uploadSiteMedia('/tmp/a.mov', asXz: false, allowedExtensions: ['jpg']),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains('.mov')),
        ),
      );
    });
  });
}
