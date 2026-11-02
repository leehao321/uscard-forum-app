import '../site_customization.dart';

/// 没有专属配置的站点：无头像光晕、无头衔特效、无社区插件。
/// 外链确认保持开启，当前站（含不带 www 的根域）及其子域算内部链接；
/// 常见短链接和推广链接仍然提醒。
SiteCustomization genericCustomization(
  String rootHost, {
  int? greatTopicBadgeId,
  int? funnyTopicBadgeId,
}) => SiteCustomization(
  greatTopicBadgeId: greatTopicBadgeId,
  funnyTopicBadgeId: funnyTopicBadgeId,
  linkSecurityConfig: LinkSecurityConfig(
    enableExitConfirmation: true,
    internalDomains: [
      rootHost,
      '*.$rootHost',
      'localhost',
      '*.local',
      // 普通字符串里要写 \\ 才是正则的 \（单个 \d 会被 Dart 当成字母 d）
      '^127(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
      '^10(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
      '^169\\.254(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
      '^192\\.168(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
      '^172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
    ],
    riskyDomains: const [
      'bit.ly',
      'tinyurl.com',
      't.co',
      'goo.gl',
      'ow.ly',
      'buff.ly',
      'adf.ly',
      'short.link',
      '*.short.link',
      'tiny.cc',
      'is.gd',
      'cutt.us',
      'v.gd',
      'j.mp',
      'bitly.com',
      'lnkd.in',
      'link.zip',
    ],
    dangerousDomains: const ['**aff='],
  ),
);
