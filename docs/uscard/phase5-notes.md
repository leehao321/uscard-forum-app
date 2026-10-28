# 阶段 5 笔记：本机功能与加密出包

## 本机功能（只存在本机，不请求论坛）

- **我的笔记**（`lib/storage/topic_note_store.dart`、`lib/widgets/notes/topic_note_sheet.dart`、`lib/pages/notes_page.dart`）
  话题页「更多 → 笔记」：自由文字加摘录。摘录的做法是在帖子里选中文字点「复制」，回到笔记点「粘贴为摘录」
  （帖子渲染包的选区菜单没有改，避免动渲染包和四处调用点）。个人页「我的笔记」可搜索、长按删除。
- **阅读统计**（`lib/storage/reading_stats_store.dart`、`lib/pages/reading_stats_page.dart`）
  挂在已有的 `ScreenTrack` 计时上，每秒一格累加到本机（单格最多 5 秒），按天保存最近 120 天：
  今天时长和话题数、连续阅读天数（每天至少 1 分钟）、7 天柱状图、30 天合计。
- **应用锁**（`lib/services/app_lock_service.dart`、`lib/widgets/app_lock_gate.dart`、`lib/pages/app_lock_settings_page.dart`）
  依赖 `local_auth ^3.0.2`（用户同意新增）。设置 →「应用锁」：冷启动或离开超过设定时间（立即 / 1 / 5 / 15 分钟）后
  用 Face ID / Touch ID / 设备密码解锁；开关都要先验证。iOS、macOS 加了 `NSFaceIDUsageDescription`。
  **Android 不开放**：local_auth 要求 `FlutterFragmentActivity`，现有 `MainActivity` 是 `FlutterActivity`，暂不改。
- **朗读（TTS）**：用户决定先不做（不加 `flutter_tts`）。
- **稍后读**：上游已有，未重复做。

## 加密出包（镜像功能）

镜像相关代码只在本地分支 `uscard-mirror`，不以明文进 GitHub。`tool/mirror_patch.sh`：

1. `keygen`：生成密钥，存在仓库外的 `~/.uscard-mirror/patch.key`，再设成仓库 Secret `MIRROR_PATCH_KEY`。
2. `export`：把 `uscard-mirror` 相对 `uscard` 的改动加密成 `private/mirror.patch.enc`（AES-256-CBC，PBKDF2 20 万次）。
3. `check`：在临时工作区解密并试合入。
4. 手动触发 iOS 构建时勾选「带镜像功能」：构建机解密补丁合入，IPA 加密成 `.ipa.enc` 后才上传（公开仓库的产物其他 GitHub 用户也能下载）。
5. `decrypt-ipa <文件>`：本机解密下载的 IPA。

每次出带镜像的包前，`uscard-mirror` 要先 `git rebase uscard`，再 `export`。
