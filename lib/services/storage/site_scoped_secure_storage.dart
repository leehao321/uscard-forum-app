import '../site_context.dart';
import 'resilient_secure_storage.dart';

/// 当前站点专属的安全存储：用户名、CSRF、User API Key、保存的账密都走这里，
/// 否则换站后会把 A 站的凭证发给 B 站。
///
/// AI 供应商的 API Key 这类和站点无关的凭证继续用 [ResilientSecureStorage]。
class SiteScopedSecureStorage extends ResilientSecureStorage {
  SiteScopedSecureStorage({super.secureStorage});

  @override
  Future<String?> read({required String key}) =>
      super.read(key: SiteContext.scopedKey(key));

  @override
  Future<void> write({required String key, required String value}) =>
      super.write(key: SiteContext.scopedKey(key), value: value);

  @override
  Future<void> delete({required String key}) =>
      super.delete(key: SiteContext.scopedKey(key));
}
