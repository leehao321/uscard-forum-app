import '../constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connect_stats.dart';
import '../services/network/discourse_dio.dart';
import 'core_providers.dart';

/// connect.linux.do 统计 Provider
final connectStatsProvider = FutureProvider<ConnectStats?>((ref) async {
  final user = ref.watch(
    currentUserProvider.select((value) => value.value),
  );
  if (user == null) return null;
  // connect.linux.do 是 linux.do 生态服务，其他站点不请求
  if (!AppConstants.siteCustomization.enableLinuxdoServices) return null;

  final dio = DiscourseDio.create();
  final response = await dio.get('https://connect.linux.do/');
  if (response.statusCode == 200) {
    return ConnectStats.fromHtml(response.data);
  }
  return null;
});
