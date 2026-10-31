import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 0.4.0 M3：底栏偏好迁移（计划 §10.3）——最多 4 项，首页最前、我的最后，
// 通知变成页面、缺了就补，旧偏好不丢项。

void main() {
  group('normalizeBottomNavIds', () {
    test('旧默认 [首页, 我的] → 补上通知', () {
      expect(normalizeBottomNavIds(['home', 'profile']), [
        'home',
        'notifications',
        'profile',
      ]);
    });

    test('空偏好 → 默认三项', () {
      expect(normalizeBottomNavIds(const []), [
        'home',
        'notifications',
        'profile',
      ]);
    });

    test('超过 4 项：截掉中间靠后的，首尾固定', () {
      expect(
        normalizeBottomNavIds([
          'home',
          'bookmarks',
          'history',
          'drafts',
          'messages',
          'profile',
        ]),
        ['home', 'notifications', 'bookmarks', 'profile'],
      );
    });

    test('已有通知时保持用户顺序，首页 / 我的被挪到两端', () {
      expect(
        normalizeBottomNavIds([
          'profile',
          'bookmarks',
          'notifications',
          'home',
        ]),
        ['home', 'bookmarks', 'notifications', 'profile'],
      );
    });

    test('去重、丢掉未注册的 id', () {
      expect(
        normalizeBottomNavIds([
          'home',
          'home',
          'ghost',
          'notifications',
          'notifications',
          'profile',
        ]),
        ['home', 'notifications', 'profile'],
      );
    });

    test('幂等', () {
      final once = normalizeBottomNavIds([
        'home',
        'history',
        'drafts',
        'profile',
      ]);
      expect(normalizeBottomNavIds(once), once);
      expect(once.length, lessThanOrEqualTo(kMaxBottomNavItems));
    });
  });

  test('读取偏好时迁移，不改写旧键', () async {
    SharedPreferences.setMockInitialValues({
      'pref_bottom_nav_ids': [
        'home',
        'bookmarks',
        'history',
        'drafts',
        'profile',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(preferencesProvider).bottomNavIds, [
      'home',
      'notifications',
      'bookmarks',
      'profile',
    ]);
    // 旧键原样保留（降级回旧版还能用）
    expect(prefs.getStringList('pref_bottom_nav_ids'), [
      'home',
      'bookmarks',
      'history',
      'drafts',
      'profile',
    ]);
  });
}
