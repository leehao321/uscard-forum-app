import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_profile.dart';
import 'site_context.dart';

/// 站点列表与当前站的持久化。
///
/// 数据模型按多站建；运行时只连一个站，[setCurrent] 只改持久化，重启后生效。
class SiteRegistryService {
  SiteRegistryService();

  static final SiteRegistryService instance = SiteRegistryService();

  @visibleForTesting
  static const sitesKey = 'site_registry_sites';
  @visibleForTesting
  static const currentKey = 'site_registry_current';

  late SharedPreferences _prefs;
  List<SiteProfile> _sites = const [];
  String? _currentId;

  /// 读取持久化；已选过站时把它设为本次运行的站点。
  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _sites = _readSites(prefs);
    _currentId = prefs.getString(currentKey);
    final current = this.current;
    if (current != null) {
      SiteContext.activate(current);
    }
  }

  List<SiteProfile> get sites => List.unmodifiable(_sites);

  /// 持久化的当前站；[setCurrent] 之后到重启之前，可能和 [SiteContext.current] 不同。
  SiteProfile? get current {
    for (final site in _sites) {
      if (site.id == _currentId) return site;
    }
    return null;
  }

  /// 新增站点；同一地址已存在时用新信息覆盖。
  Future<void> addOrUpdate(SiteProfile site) async {
    final index = _sites.indexWhere((s) => s.id == site.id);
    _sites = [
      for (var i = 0; i < _sites.length; i++)
        if (i == index) site else _sites[i],
      if (index < 0) site,
    ];
    await _writeSites();
  }

  /// 不能删除当前站：它的登录态和数据还在用。
  Future<void> remove(String id) async {
    if (id == _currentId) {
      throw StateError('不能删除当前站点');
    }
    _sites = _sites.where((s) => s.id != id).toList(growable: false);
    await _writeSites();
  }

  Future<void> setCurrent(String id) async {
    if (!_sites.any((s) => s.id == id)) {
      throw ArgumentError.value(id, 'id', '站点未注册');
    }
    _currentId = id;
    await _prefs.setString(currentKey, id);
  }

  /// 首次启动选站：加入列表、设为当前站，并立即作为本次运行的站点。
  Future<void> addAndActivate(SiteProfile site) async {
    await addOrUpdate(site);
    await setCurrent(site.id);
    SiteContext.activate(site);
  }

  Future<void> _writeSites() async {
    await _prefs.setString(
      sitesKey,
      jsonEncode(_sites.map((s) => s.toJson()).toList(growable: false)),
    );
  }

  static List<SiteProfile> _readSites(SharedPreferences prefs) {
    final raw = prefs.getString(sitesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(SiteProfile.tryFromJson)
          .whereType<SiteProfile>()
          .toList(growable: false);
    } on FormatException catch (e) {
      debugPrint('[SiteRegistry] 站点列表损坏: $e');
      return const [];
    }
  }
}
