import '../site_customization.dart';

/// 没有专属配置的站点：无头像光晕、无头衔特效、无社区插件。
/// 外链确认保持开启，当前站及其子域算内部链接。
SiteCustomization genericCustomization(String host) => SiteCustomization(
  linkSecurityConfig: LinkSecurityConfig(
    enableExitConfirmation: true,
    internalDomains: [host, '*.$host'],
  ),
);
