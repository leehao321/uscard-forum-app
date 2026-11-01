import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/download_list_page.dart';
import 'package:fluxdo/pages/my_browser_page.dart';
import 'package:fluxdo/pages/notion_settings_page.dart';
import 'package:fluxdo/pages/open_source_licenses_page.dart';
import 'package:fluxdo/pages/preferences_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/secret_store_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:fluxdo/services/storage/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 第 11 批 · 补充稿 43–55 出图（设了 SHOTS_DIR 才落盘，没设时只检查不溢出、无异常）。
// 对照 Figma「补充 · AI 快捷词与网页浏览空态」「w5」「设置 · Notion 同步与开源许可」。
// 全部本地假数据，不联网。

const _variants = [
  UiVariant(Brightness.light, 1, UiDevice.pro),
  UiVariant(Brightness.dark, 1, UiDevice.pro),
];

String _suffix(UiVariant v) =>
    v.brightness == Brightness.dark ? 'dark' : 'light';

const _builtIns = [
  PromptPreset(
    id: 'b_text_summary',
    type: PromptType.text,
    name: '总结这个话题',
    iconRaw: 'summarize_outlined',
    promptTemplate: 'a',
    builtIn: true,
    sortOrder: 1,
  ),
  PromptPreset(
    id: 'b_text_translate',
    type: PromptType.text,
    name: '翻译主帖',
    iconRaw: 'translate_outlined',
    promptTemplate: 'b',
    builtIn: true,
    sortOrder: 2,
  ),
  PromptPreset(
    id: 'b_text_points',
    type: PromptType.text,
    name: '列出主要观点',
    iconRaw: 'question_answer_outlined',
    promptTemplate: 'c',
    builtIn: true,
    sortOrder: 3,
  ),
  PromptPreset(
    id: 'b_text_notice',
    type: PromptType.text,
    name: '有什么值得关注的',
    iconRaw: 'lightbulb_outlined',
    promptTemplate: 'd',
    builtIn: true,
    sortOrder: 4,
  ),
];

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    builtInPresetsProvider.overrideWithValue(_builtIns),
    currentUserProvider.overrideWith(_FakeUser.new),
    currentUsernameProvider.overrideWith((ref) async => 'tester'),
    secretStoreProvider.overrideWithValue(InMemorySecretStore()),
  ];
}

Future<void> _shot(WidgetTester tester, String name, UiVariant v) async {
  await tester.pumpAndSettle();
  expectNoUiException(tester);
  await uiShot(tester, '${name}_${_suffix(v)}');
}

/// 开源许可假数据（包名、许可数取自稿）
List<PackageLicenses> _packages() {
  PackageLicenses pkg(String name, int n) => PackageLicenses(name, [
    for (var i = 0; i < n; i++)
      [LicenseParagraph('Copyright $name license ${i + 1}', 0)],
  ]);
  return [
    pkg('_fe_analyzer_shared', 1),
    pkg('abseil-cpp', 2),
    pkg('accessibility', 16),
    pkg('aFileChooser', 1),
    pkg('ai', 3),
    pkg('analyzer', 1),
    pkg('angle', 58),
    pkg('ansi_styles', 1),
    pkg('anthropic_sdk_dart', 1),
    pkg('app_links', 1),
    pkg('archive', 1),
  ];
}

PackageLicenses _aiPackage() => PackageLicenses('ai', [
  [
    LicenseParagraph('Copyright 2025, the Dart project authors.', 0),
    LicenseParagraph(
      'Redistribution and use in source and binary forms, with or without '
      'modification, are permitted provided that the following conditions '
      'are met:',
      0,
    ),
    LicenseParagraph(
      '· Redistributions of source code must retain the above copyright '
      'notice, this list of conditions and the following disclaimer.',
      1,
    ),
    LicenseParagraph(
      '· Redistributions in binary form must reproduce the above copyright '
      'notice, this list of conditions and the following disclaimer in the '
      'documentation and/or other materials provided with the distribution.',
      1,
    ),
    LicenseParagraph(
      '· Neither the name of Google LLC nor the names of its contributors '
      'may be used to endorse or promote products derived from this software '
      'without specific prior written permission.',
      1,
    ),
    LicenseParagraph(
      'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS '
      '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT '
      'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS '
      'FOR A PARTICULAR PURPOSE ARE DISCLAIMED.',
      0,
    ),
  ],
  [
    LicenseParagraph(
      'Copyright (c) 2025, the Dart project authors. Please see the AUTHORS '
      'file for details. All rights reserved. Use of this source code is '
      'governed by a BSD-style license that can be found in the LICENSE file.',
      0,
    ),
  ],
  [LicenseParagraph('Third license text.', 0)],
]);

void main() {
  setUpAll(loadUiFonts);

  for (final v in _variants) {
    testUi('43 快捷词管理 · 更多菜单（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const PromptPresetsPage(initialType: PromptType.text),
        variant: v,
        overrides: await _overrides(),
      );
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await _shot(tester, '43_快捷词管理更多菜单', v);
    });

    testUi('44 新建快捷词（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const PromptPresetEditPage(initialType: PromptType.text),
        variant: v,
        overrides: await _overrides(),
      );
      await _shot(tester, '44_新建快捷词', v);
    });

    testUi('45 新建快捷词 · 搜索图标（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const PromptPresetEditPage(initialType: PromptType.text),
        variant: v,
        overrides: await _overrides(),
      );
      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'heart');
      // 稿里选中的是第一个（heart）
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppPressable && w.semanticLabel == 'heart',
        ),
      );
      await _shot(tester, '45_新建快捷词搜索图标', v);
    });

    testUi('46 网页浏览 · 收藏 · 空（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const MyBrowserPage(),
        variant: v,
        overrides: await _overrides(),
      );
      await tester.tap(find.text('收藏'));
      await _shot(tester, '46_网页浏览收藏空', v);
    });

    testUi('47 网页浏览 · 浏览历史 · 空（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const MyBrowserPage(),
        variant: v,
        overrides: await _overrides(),
      );
      await tester.tap(find.text('浏览历史'));
      await _shot(tester, '47_网页浏览浏览历史空', v);
    });

    testUi('48 功能 · 编辑器 / AI / 加解密工具箱（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const PreferencesPage(),
        variant: v,
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      // 加高视口，让编辑器 / AI / 加解密工具箱三组同屏（稿里也是合成一屏）
      tester.view.physicalSize = const Size(393, 1500) * 3;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('编辑器'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('编辑器')),
        alignment: 0,
      );
      await _shot(tester, '48_功能表情包数据源与加解密工具箱', v);
    });

    testUi('49 功能 · 表情包数据源 · 对话框（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const PreferencesPage(),
        variant: v,
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.scrollUntilVisible(
        find.text('表情包数据源'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('表情包数据源')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('表情包数据源'));
      await _shot(tester, '49_功能表情包数据源对话框', v);
    });

    testUi('50 网页浏览 · 下载管理 · 空（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const DownloadListPage(),
        variant: v,
        overrides: await _overrides(),
      );
      await _shot(tester, '50_网页浏览下载管理空', v);
    });

    testUi('51 网页浏览 · 添加收藏（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const MyBrowserPage(),
        variant: v,
        overrides: await _overrides(),
      );
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(AppIcons.add));
      await _shot(tester, '51_网页浏览添加收藏', v);
    });

    testUi('52 Notion 同步 · 配置步骤（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const NotionSettingsPage(),
        variant: v,
        overrides: await _overrides(),
      );
      await _shot(tester, '52_Notion同步配置步骤', v);
    });

    testUi('53 Notion 同步 · 底部说明（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        const NotionSettingsPage(),
        variant: v,
        overrides: await _overrides(),
      );
      // Token 聚焦并填好（遮挡显示）
      final token = find.byType(TextField).first;
      await tester.tap(token);
      await tester.enterText(token, 'secret_abcdefghijklmnopqrstuvwxyz0123');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await _shot(tester, '53_Notion同步底部说明', v);
    });

    testUi('54 开源许可 · 列表（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        OpenSourceLicensesPage(
          appName: 'USCard Forum',
          appVersion: '0.3.1',
          loader: () async => _packages(),
        ),
        variant: v,
      );
      await _shot(tester, '54_开源许可列表', v);
    });

    testUi('55 开源许可 · 单个包详情（${v.label}）', (tester) async {
      await pumpUi(
        tester,
        PackageLicensePage(package: _aiPackage()),
        variant: v,
      );
      await _shot(tester, '55_开源许可单个包详情', v);
    });
  }
}
