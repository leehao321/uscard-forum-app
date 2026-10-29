import 'package:flutter/material.dart';
import '../models/topic.dart';
import '../plugins/site_plugin.dart';

/// 链接风险等级
enum LinkRiskLevel {
  /// 内部链接，无需拦截
  internal,

  /// 信任链接，无需拦截
  trusted,

  /// 普通外部链接，显示确认
  normal,

  /// 风险链接（如短链接服务），显示警告
  risky,

  /// 危险链接（如推广链接），显示强烈警告
  dangerous,

  /// 阻止链接，不允许访问
  blocked,
}

/// 链接安全配置
class LinkSecurityConfig {
  /// 是否启用外部链接确认
  final bool enableExitConfirmation;

  /// 内部域名（不拦截）
  final List<String> internalDomains;

  /// 信任域名（不拦截）
  final List<String> trustedDomains;

  /// 风险域名（显示警告）
  final List<String> riskyDomains;

  /// 危险域名（显示强烈警告）
  final List<String> dangerousDomains;

  /// 阻止域名（禁止访问）
  final List<String> blockedDomains;

  const LinkSecurityConfig({
    this.enableExitConfirmation = true,
    this.internalDomains = const [],
    this.trustedDomains = const [],
    this.riskyDomains = const [],
    this.dangerousDomains = const [],
    this.blockedDomains = const [],
  });
}

/// 头像光晕匹配规则
class AvatarGlowRule {
  /// 按群组匹配
  final String? primaryGroupName;

  /// 按用户名匹配
  final String? username;

  /// 光晕颜色
  final Color glowColor;

  const AvatarGlowRule({
    this.primaryGroupName,
    this.username,
    required this.glowColor,
  });
}

/// 用户头衔特殊样式规则
class UserTitleStyleRule {
  /// 匹配的头衔文本
  final String title;

  /// 自定义 widget builder
  final Widget Function(String title, double fontSize) builder;

  const UserTitleStyleRule({
    required this.title,
    required this.builder,
  });
}

/// 站点自定义配置
class SiteCustomization {
  /// 头像光晕规则列表
  final List<AvatarGlowRule> avatarGlowRules;

  /// 用户头衔特殊渲染规则列表
  final List<UserTitleStyleRule> userTitleStyleRules;

  /// 链接安全配置
  final LinkSecurityConfig? linkSecurityConfig;

  /// 站点插件列表
  ///
  /// 对应该社区自建的 Discourse 插件（非标准能力），
  /// 由 [PluginRegistry] 在对应钩子处按顺序执行。
  final List<SitePlugin> plugins;

  /// 登录时是否需要先过 hCaptcha 人机验证（站点没启用 hCaptcha 插件时设为 false）
  final bool requiresHcaptcha;

  /// 是否允许列表卡片为每个话题自动请求首帖做摘要/配图（逐条后台请求，默认开放给用户选择）
  final bool allowAutoExcerptFetch;

  /// 音视频是否改名成 `.xz` 上传。linux.do 的扩展名白名单不含音视频，社区
  /// 「媒体上传」脚本约定这样绕过；其他站点不绕白名单，按原文件名上传，
  /// 扩展名不在站点允许列表里就直接提示。默认关闭，linux.do 配置里打开。
  final bool mediaUploadAsXz;

  /// 站点是否装了树形回复插件（提供 `/n/topic/...` 接口）。没装时隐藏树形视图的
  /// 所有入口，也不按「默认树形」去请求（否则每个话题先 404 再回落平铺）。
  final bool supportsNestedView;

  /// 站点是否靠插件脚本在 WebView 里产生额外会话 cookie（linux.do 的
  /// fingerprint 插件上报后才下发 `_rt`）。没有这类插件时不跑会话 bootstrap：
  /// 否则每次都找不到插件，反复起无头 WebView 拉首页和插件 JS，登录也会白等。
  final bool hasSessionBootstrapPlugin;

  const SiteCustomization({
    this.avatarGlowRules = const [],
    this.userTitleStyleRules = const [],
    this.linkSecurityConfig,
    this.plugins = const [],
    this.requiresHcaptcha = true,
    this.allowAutoExcerptFetch = true,
    this.mediaUploadAsXz = false,
    this.supportsNestedView = true,
    this.hasSessionBootstrapPlugin = true,
  });

  /// 匹配头像光晕（返回光晕颜色，null 表示无光晕）
  Color? matchAvatarGlow(Post post) {
    for (final rule in avatarGlowRules) {
      if (rule.primaryGroupName != null &&
          post.primaryGroupName == rule.primaryGroupName) {
        return rule.glowColor;
      }
      if (rule.username != null && post.username == rule.username) {
        return rule.glowColor;
      }
    }
    return null;
  }

  /// 匹配用户头衔特殊样式（返回 widget builder，null 表示使用默认样式）
  Widget Function(String title, double fontSize)? matchTitleStyle(Post post) {
    if (post.userTitle == null) return null;
    for (final rule in userTitleStyleRules) {
      if (post.userTitle == rule.title) {
        return rule.builder;
      }
    }
    return null;
  }
}
