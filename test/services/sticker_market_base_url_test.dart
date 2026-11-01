import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/sticker_market_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 表情包数据源改了之后要存得住：
// 旧实现先存地址，再清掉所有以 sticker_market_ 开头的键，而地址的键
// sticker_market_base_url 也以它开头，所以刚存的地址又被清掉了。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SharedPreferences, StickerMarketService)> open([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return (prefs, StickerMarketService(prefs));
  }

  test('改了数据源：地址存得住，重新打开（新实例读同一份存储）读到的还是新地址', () async {
    final (prefs, service) = await open();
    expect(service.baseUrl, StickerMarketService.defaultBaseUrl);

    await service.setBaseUrl('https://stickers.example.com/');

    expect(service.baseUrl, 'https://stickers.example.com');
    expect(StickerMarketService(prefs).baseUrl, 'https://stickers.example.com');
    expect(prefs.getString('sticker_market_base_url'), 'https://stickers.example.com');
  });

  test('改了数据源：旧站点的市场缓存全部作废，订阅和最近使用不受影响', () async {
    final (prefs, service) = await open({
      'sticker_market_topics': '{"cached":true}',
      'sticker_market_page_1': '{"cached":true}',
      'sticker_subscribed_groups': '["group-1"]',
      'sticker_recent_items': '[]',
    });

    await service.setBaseUrl('https://stickers.example.com');

    expect(prefs.containsKey('sticker_market_topics'), isFalse);
    expect(prefs.containsKey('sticker_market_page_1'), isFalse);
    expect(prefs.getString('sticker_subscribed_groups'), '["group-1"]');
    expect(prefs.containsKey('sticker_recent_items'), isTrue);
  });

  test('恢复默认：地址回到默认值，缓存同样清掉', () async {
    final (prefs, service) = await open({
      'sticker_market_base_url': 'https://stickers.example.com',
      'sticker_market_topics': '{"cached":true}',
    });
    expect(service.baseUrl, 'https://stickers.example.com');

    await service.resetBaseUrl();

    expect(service.baseUrl, StickerMarketService.defaultBaseUrl);
    expect(prefs.containsKey('sticker_market_base_url'), isFalse);
    expect(prefs.containsKey('sticker_market_topics'), isFalse);
  });
}
