import '../site_customization.dart';

/// 美卡论坛（www.uscardforum.com）站点自定义配置
///
/// 站点未启用 hCaptcha，也没有 linux.do 专属插件（回复扣积分 / warden / 字数补丁），
/// 因此不挂任何站点插件；头像光晕与头衔特效规则暂时为空，阶段 3 再按需补充。
final uscardCustomization = SiteCustomization(
  requiresHcaptcha: false,
  enableLinuxdoServices: false,
  // 论坛条款禁止程序自动批量访问：列表卡片不为每个话题自动拉首帖
  allowAutoExcerptFetch: false,
  // 没装树形回复插件：真机日志里 `/n/topic/<id>.json` 返回 404
  supportsNestedView: false,
  // 没有 linux.do 的 fingerprint 插件，也不下发 `_rt`，不跑 WebView 会话 bootstrap
  hasSessionBootstrapPlugin: false,
  linkSecurityConfig: _uscardLinkSecurityConfig,
);

/// 美卡论坛链接安全配置
///
/// 内部域名不拦截，其他外部链接保持确认；风险/危险域名沿用通用的短链接与推广链接规则。
const _uscardLinkSecurityConfig = LinkSecurityConfig(
  enableExitConfirmation: true,
  internalDomains: [
    'uscardforum.com',
    '*.uscardforum.com',
    'localhost',
    '*.local',
    // 普通字符串里要写 \\ 才是正则的 \（单个 \d 会被 Dart 当成字母 d）
    '^127(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
    '^10(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
    '^169\\.254(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
    '^192\\.168(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
    '^172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
  ],
  riskyDomains: [
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'buff.ly',
    'adf.ly', 'short.link', '*.short.link', 'tiny.cc', 'is.gd',
    'cutt.us', 'v.gd', 'j.mp', 'bitly.com', 'lnkd.in', 'link.zip',
  ],
  dangerousDomains: [
    '**aff=',
  ],
);
