import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/pages/first_run_site_picker.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(SiteContext.debugReset);

  testWidgets('选好站才返回，选中的站立即生效并已持久化', (tester) async {
    SharedPreferences.setMockInitialValues({});
    SiteContext.debugReset();
    await tester.runAsync(() async {
      await SiteRegistryService.instance.init(
        await SharedPreferences.getInstance(),
      );
    });
    expect(SiteContext.isConfigured, isFalse);

    var returned = false;
    unawaited(runFirstRunSitePicker().then((_) => returned = true));
    await tester.pumpAndSettle();

    expect(returned, isFalse);
    expect(find.text('USCard Forum'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();

    expect(returned, isTrue);
    expect(SiteContext.current.featurePack, SiteFeaturePack.uscard);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SiteRegistryService.currentKey),
      SitePresets.uscard.id,
    );
  });
}
