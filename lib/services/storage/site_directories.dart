import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/site_profile.dart';
import '../site_context.dart';

/// 当前站点的数据目录（ApplicationSupport 下），按需创建。
Future<Directory> siteSupportDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(siteDataDirectory(base.path, SiteContext.current));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

String siteDataDirectory(String supportPath, SiteProfile site) =>
    p.join(supportPath, 'sites', site.storageId);
