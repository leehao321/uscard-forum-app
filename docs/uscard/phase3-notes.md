# 阶段 3 笔记：美卡适配、AI 总结、看过就存

## 新增功能
- **AI 总结**（`lib/services/ai_topic_summary_service.dart`、`lib/widgets/ai/ai_topic_summary_sheet.dart`、`lib/providers/ai_topic_summary_provider.dart`）
  话题页「更多」菜单新增「AI 总结」。只总结 App 里已加载的楼层（单层最多 2500 字、总计 24000 字，超出截断并提示），
  用设置里配置的 AI 服务商与默认文本模型（`ai_model_manager`），请求直接发给用户自己的 API，**不向论坛发任何额外请求**，
  不依赖论坛的 discourse-ai（美卡 404）。结果不持久化。
- **看过就存**（`lib/storage/saved_topic_store.dart`、`lib/pages/saved_topics_page.dart`）
  话题详情加载稳定 3 秒后，把已加载的楼层（cooked HTML、作者、时间）存到应用私有目录 `saved_topics/`（每话题一个 JSON + `index.json`）。
  再次浏览按楼层号合并；私信不保存；纯本地写文件，不联网、不批量抓取。
  个人页「已存帖子」入口：开关（默认开）、标题/正文搜索、离线阅读（纯文本）、左滑删除、清空。
  单元测试：`test/storage/saved_topic_store_test.dart`（3 项，通过）。
  已知限制：不区分账号（多账号共用同一份）；离线页只显示纯文本，不渲染图片和格式。

## 适配与清理
- `SiteCustomization.allowAutoExcerptFetch`（美卡为 false）：列表卡片不再为每个话题自动请求首帖做摘要，设置页对应开关隐藏。
- 界面文案、User API Key 的应用名、通知名、关于页等里的 “FluxDO” 全部改为 “USCard Forum”（多语言 ARB 里只改文案，**不要改键名**，如 `profile_aboutFluxDO`）。
- **占位图标**：深蓝底 + 银行卡轮廓 + “US”，已替换 iOS（AppIcon / ModernIcon）、macOS、Android 位图回退、Windows `.ico`、设置页图标预览。
  **未替换**：Android 自适应图标的矢量前景（`drawable/ic_launcher*_foreground.xml`）、`assets/logo*.svg`（欢迎页那个条纹圆标）、flatpak / altstore 图标。

## 验证
- `flutter analyze lib` 无 error / warning；Windows debug 编译通过。
- **未启动 App 做运行验证**：现在 `baseUrl` 已是 uscardforum.com，启动会自动请求首页，所以留给用户手动首次启动。AI 总结、已存帖子的界面效果都还没人看过。

## 留给阶段 4 / 之后
- iOS 打包（GitHub Actions 打 IPA）、真机验收；App Link / URL scheme / Info.plist 的 linux.do 残留（Android 清单里的 App Link 仍是 linux.do）。
- 聊天（美卡关闭）、discourse-ai 相关入口、LDC/CDK/追觅残留死代码清理。
- 正式图标与欢迎页 logo。
