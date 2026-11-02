import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/sites/linuxdo.dart';
import 'package:fluxdo/constants.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/plugins/plugin_registry.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final other = SiteProfile(baseUrl: 'https://example.com/forum', title: 'Example');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SiteContext.debugReset();
  });

  tearDown(SiteContext.debugReset);

  Future<SiteRegistryService> load() async {
    final service = SiteRegistryService();
    await service.init(await SharedPreferences.getInstance());
    return service;
  }

  group('SiteRegistryService', () {
    test('首次启动没有站点，不设置 SiteContext', () async {
      final service = await load();
      expect(service.sites, isEmpty);
      expect(service.current, isNull);
      expect(SiteContext.isConfigured, isFalse);
    });

    test('addAndActivate 立即生效，重启后恢复', () async {
      final service = await load();
      await service.addAndActivate(SitePresets.uscard);
      expect(SiteContext.current.baseUrl, SitePresets.uscard.baseUrl);

      SiteContext.debugReset();
      final restarted = await load();
      expect(restarted.sites.single.id, SitePresets.uscard.id);
      expect(SiteContext.isConfigured, isTrue);
      expect(SiteContext.current.baseUrl, SitePresets.uscard.baseUrl);
      expect(SiteContext.current.featurePack, SiteFeaturePack.uscard);
    });

    test('setCurrent 只改持久化，重启后才切换', () async {
      final service = await load();
      await service.addAndActivate(SitePresets.linuxdo);
      await service.addOrUpdate(other);
      await service.setCurrent(other.id);

      expect(service.current!.id, other.id);
      expect(SiteContext.current.id, SitePresets.linuxdo.id);

      SiteContext.debugReset();
      await load();
      expect(SiteContext.current.id, other.id);
    });

    test('同一地址重复添加时覆盖，不产生重复项', () async {
      final service = await load();
      await service.addOrUpdate(other);
      await service.addOrUpdate(
        SiteProfile(baseUrl: other.baseUrl, title: 'Renamed'),
      );
      expect(service.sites.single.title, 'Renamed');
    });

    test('不能删除当前站，也不能切到未注册的站', () async {
      final service = await load();
      await service.addAndActivate(SitePresets.linuxdo);
      await service.addOrUpdate(other);

      expect(() => service.remove(SitePresets.linuxdo.id), throwsStateError);
      expect(() => service.setCurrent('nope.example.com'), throwsArgumentError);

      await service.remove(other.id);
      expect(service.sites.map((s) => s.id), [SitePresets.linuxdo.id]);
    });

    test('列表损坏时回到未选站状态', () async {
      SharedPreferences.setMockInitialValues({
        SiteRegistryService.sitesKey: 'not json',
        SiteRegistryService.currentKey: 'linux.do',
      });
      final service = await load();
      expect(service.sites, isEmpty);
      expect(SiteContext.isConfigured, isFalse);
    });

    test('跳过列表里的坏条目，保留好的', () async {
      SharedPreferences.setMockInitialValues({
        SiteRegistryService.sitesKey: jsonEncode([
          {'baseUrl': 'not a domain'},
          other.toJson(),
        ]),
        SiteRegistryService.currentKey: other.id,
      });
      final service = await load();
      expect(service.sites.single.id, other.id);
      expect(SiteContext.current.id, other.id);
    });

    test('站点列表不进数据备份', () {
      expect(
        DataBackupService.debugShouldBackup(SiteRegistryService.sitesKey),
        isFalse,
      );
      expect(
        DataBackupService.debugShouldBackup(SiteRegistryService.currentKey),
        isFalse,
      );
    });
  });

  group('AppConstants 跟随当前站点', () {
    test('未选站时回落到 linux.do', () {
      expect(AppConstants.baseUrl, 'https://linux.do');
      expect(AppConstants.siteOrigin, 'https://linux.do');
    });

    test('子路径站点的 baseUrl 与 origin 分开', () {
      SiteContext.activate(other);
      expect(AppConstants.baseUrl, 'https://example.com/forum');
      expect(AppConstants.siteOrigin, 'https://example.com');
    });

    test('linux.do 用专属配置和插件', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(AppConstants.siteCustomization, same(linuxdoCustomization));
      expect(PluginRegistry.plugins, isNotEmpty);
    });

    test('其他站没有社区插件，当前站算内部链接，换站后不残留', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(PluginRegistry.plugins, isNotEmpty);

      SiteContext.activate(other);
      final customization = AppConstants.siteCustomization;
      expect(PluginRegistry.plugins, isEmpty);
      expect(customization.avatarGlowRules, isEmpty);
      expect(
        customization.linkSecurityConfig!.internalDomains,
        containsAll(['example.com', '*.example.com']),
      );

      SiteContext.activate(SitePresets.uscard);
      expect(PluginRegistry.plugins, isEmpty);
      expect(
        AppConstants.siteCustomization.linkSecurityConfig!.internalDomains,
        containsAll(['uscardforum.com', '*.uscardforum.com']),
      );
    });
  });
}
