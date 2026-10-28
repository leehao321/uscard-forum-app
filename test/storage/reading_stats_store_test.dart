import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/storage/reading_stats_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReadingStatsStore.instance.resetForTest();
  });

  test('按天累加阅读时间和话题，单次最多算 5 秒，保存后可重新读取', () async {
    final store = ReadingStatsStore.instance;
    store.addReading(10, 1000);
    store.addReading(10, 60 * 1000); // 记作 5 秒
    store.addReading(11, 2000);
    await store.flush();

    final days = await store.recent(7);
    expect(days, hasLength(7));
    final today = days.last;
    expect(today.millis, 8000);
    expect(today.topics, {10, 11});
    expect(today.day, ReadingStatsStore.dayKey(DateTime.now()));

    store.resetForTest();
    final reloaded = (await store.recent(1)).single;
    expect(reloaded.millis, 8000);
    expect(reloaded.topics, {10, 11});
  });

  test('连续阅读天数：今天不足 1 分钟时从昨天算', () async {
    final now = DateTime.now();
    String key(int daysAgo) => ReadingStatsStore.dayKey(
      DateTime(now.year, now.month, now.day - daysAgo),
    );
    SharedPreferences.setMockInitialValues({
      'reading_stats_v1':
          '{"${key(1)}":{"ms":120000,"t":[1]},"${key(2)}":{"ms":90000,"t":[2]},'
          '"${key(4)}":{"ms":600000,"t":[3]}}',
    });
    ReadingStatsStore.instance.resetForTest();
    expect(await ReadingStatsStore.instance.streak(), 2);
  });
}
