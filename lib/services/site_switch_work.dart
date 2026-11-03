import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:fluxdo_render/fluxdo_render.dart'
    show FlattenCache, ParagraphLayoutCache;

import '../models/pending_post.dart';
import '../models/site_profile.dart';
import '../plugins/topic_plugin_data.dart';
import '../storage/reading_stats_store.dart';
import '../widgets/content/discourse_html_content/image_utils.dart';
import '../widgets/post/post_item/render_parse_cache.dart';
import 'auth_issue_notice_service.dart';
import 'auth_session.dart';
import 'background/background_notification_service.dart';
import 'browser_trust_coordinator.dart';
import 'cf_challenge_service.dart';
import 'cf_clearance_authority.dart';
import 'cf_clearance_refresh_service.dart';
import 'discourse/discourse_service.dart';
import 'discourse_cook_service.dart';
import 'emoji_alias_service.dart';
import 'emoji_handler.dart';
import 'local_notification_service.dart';
import 'message_bus_service.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/cookie/cookie_store_observer.dart';
import 'network/cookie/csrf_token_service.dart';
import 'network/cookie/session_cookie_sentinel.dart';
import 'network/cookie/webview_cookie_priming.dart';
import 'network/doh/network_settings_service.dart';
import 'network/webview/webview_adapter_settings_service.dart';
import 'preloaded_data_service.dart';
import 'site_context.dart';
import 'site_registry_service.dart';
import 'site_switch_service.dart';
import 'topic_excerpt_service.dart';
import 'topic_preview_preloader.dart';
import 'user_api_key_service.dart';
import 'webview_session_cookie_refresh_service.dart';

/// 切站时对 App 里各单例做的事。
///
/// `logout()` 不能拿来用：它会删掉当前站保存的用户名和 Cookie，切站要的是只清内存，
/// A 站的登录还要留着，切回来不用重新登录。
class DeviceSiteSwitchWork implements SiteSwitchWork {
  DeviceSiteSwitchWork({required SiteRegistryService registry})
    : _registry = registry;

  final SiteRegistryService _registry;

  static const _drainTimeout = Duration(seconds: 5);

  @override
  void stopWork() {
    AuthSession().advance();
    MessageBusService().stopAll();
  }

  @override
  Future<void> waitForUnmount() async {
    // 第一帧建占位页并卸载旧树（帧末销毁），第二帧确保销毁时发起的回调都跑完。
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  Future<void> drainWork() async {
    await _bestEffort('阅读统计', ReadingStatsStore.instance.flush);
    await _bestEffort(
      'Cookie 同步',
      SessionCookieSentinel.instance.cancelAllSweeps,
    );
    await _bestEffort('CF 续期', CfClearanceRefreshService().stop);
    await _bestEffort('后台通知', BackgroundNotificationService().disable);
  }

  @override
  Future<Object?> prepareSite(SiteProfile site) async {
    final jar = await CookieJarService().openJarFor(site);
    await _registry.addOrUpdate(site);
    await _registry.setCurrent(site.id);
    return jar;
  }

  @override
  void commitSite(SiteProfile site, Object? prepared) {
    // 这段不能有 await。前面几行是凭证相关的，出错就让切站失败，不继续。
    SiteContext.activate(site);
    AiChatStorageService.keyScope = site.scopePrefix;
    CookieJarService().useJar(prepared! as CookieJar);
    DiscourseService().resetForSiteSwitch();
    CsrfTokenService().resetForSiteSwitch();
    MessageBusService().resetForSiteSwitch();
    PreloadedDataService().resetForSiteSwitch();
    BrowserTrustCoordinator.instance.resetForSiteSwitch();
    // 响应晚于上面的清理回来，也不能写进新站。
    AuthSession().advance();

    final resets = <String, VoidCallback>{
      '其他模块': SiteContext.notifySwitched,
      '阅读统计': () => ReadingStatsStore.instance.resetForSiteSwitch(),
      '自定义表情': () => EmojiHandler().reset(),
      '表情别名': () => EmojiAliasService().resetForSiteSwitch(),
      '编辑器预览': () => DiscourseCookService().resetForSiteSwitch(),
      '话题摘要': () => TopicExcerptService().resetForSiteSwitch(),
      '话题预览': () => TopicPreviewPreloader.clear(),
      '上传短链': () => DiscourseImageUtils.clearUploadCaches(),
      '待审回复': () => PendingReplyTargetRegistry.clear(),
      '话题扩展字段': () => TopicPluginData.clear(),
      'WebView Cookie 预灌': () => WebViewCookiePriming.instance.invalidate(),
      'WebView Cookie 观察': () => CookieStoreObserver.instance.clearKnownUrls(),
      'Cookie 同步节流': () => SessionCookieSentinel.instance.resetForSiteSwitch(),
      '会话引导': () => WebViewSessionCookieRefreshService.instance.resetForSiteSwitch(),
      'CF 续期': () => CfClearanceRefreshService().clearSitekey(),
      'CF 验证冷却': () => CfChallengeService().resetForSiteSwitch(),
      'CF 撞盾记录': () => CfClearanceAuthority.instance.reset(),
      'WebView 适配器': () => WebViewAdapterSettingsService.instance.resetForSiteSwitch(),
      '登录问题提示': () => AuthIssueNoticeService.instance.resetForSiteSwitch(),
      '自愈冷却': () => UserApiKeyService().resetForSiteSwitch(),
      '解析缓存': () => RenderParseCache.clear(),
      '布局缓存': () => FlattenCache.evictAll(),
      '段落缓存': () => ParagraphLayoutCache.evictAll(),
      '图片内存缓存': () => PaintingBinding.instance.imageCache.clear(),
    };
    resets.forEach((name, reset) {
      try {
        reset();
      } catch (e) {
        debugPrint('[SiteSwitch] 清理 $name 失败(继续): $e');
      }
    });
    // A 站的通知点开会按话题 ID 进 B 站的同号话题。
    unawaited(_bestEffort('系统通知', LocalNotificationService().cancelAll));
  }

  @override
  Future<void> restartWork() async {
    await _bestEffort('Cookie 迁移', CookieJarService().migrateCurrentJar);
    await _bestEffort('CSRF', CsrfTokenService().init);
    await _bestEffort('ECH', NetworkSettingsService.instance.reapplyEchForCurrentSite);
    await _bestEffort('后台通知', BackgroundNotificationService().initialize);
    BrowserTrustCoordinator.instance.prepareStartup(reason: 'site_switch');
    unawaited(
      BrowserTrustCoordinator.instance
          .ensurePreloaded(reason: 'site_switch')
          .catchError((Object _) {}),
    );
  }

  /// 这些失败不影响站点隔离，记一下继续，别因为收尾卡住整个切换。
  static Future<void> _bestEffort(
    String name,
    Future<void> Function() action,
  ) async {
    try {
      await action().timeout(_drainTimeout);
    } catch (e) {
      debugPrint('[SiteSwitch] $name 失败(继续): $e');
    }
  }
}
