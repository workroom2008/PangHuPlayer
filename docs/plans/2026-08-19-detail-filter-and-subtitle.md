# 详情页与筛选改造实施计划

> **执行者须知**：按任务逐条执行，步骤用 `- [ ]` 勾选跟踪。
> 每个任务独立完成自己的测试循环；不要跳步骤、不要「顺手优化」。

**Goal：** 规范媒体库筛选面板，增加文件夹/列表布局，并按参考图收敛详情页结构，支持音频/字幕选择和 Emby/Jellyfin 原生字幕搜索下载，同时移除预告片入口并保留下载、已观看、收藏、删除能力。

**Architecture：** 媒体库页面继续使用 `MediaLibraryFilter` 和 `MediaLibraryQuery`，新增明确的布局枚举和按父目录分组的纯查询函数，页面只负责渲染与状态切换。详情页继续复用现有 `TrackSelectorSheet`，在 `MediaServerService` 抽象中增加统一的服务器字幕搜索/下载接口，Emby/Jellyfin 共用 `/Items/{id}/RemoteSearch/Subtitles`、`/Items/{id}/RemoteSearch/Subtitles/{subtitleId}` 协议，下载结果写入播放器可读取的本地字幕文件。播放入口携带选中的语言偏好和轨道索引，播放器已有语言偏好逻辑继续负责最终切轨。

**Tech Stack：** Flutter 3.x、Dart、flutter_test、Dio、flutter_riverpod、现有 `TrackSelectorSheet` 和 `PlayerScreen`。

**Spec：** 用户在当前对话中确认的“规范筛选 + 参考图详情页 + 音频/字幕选择 + Emby/Jellyfin 字幕搜索下载 + 移除预告片且保留下载/已观看/收藏/删除”设计。

## Global Constraints

- 仅修改本次需求涉及的媒体库、详情页、媒体服务、播放器入口和测试文件。
- 不新增第三方依赖；复用现有 Dio、Riverpod、轨道选择器和字幕缓存逻辑。
- 服务器字幕接口失败时显示错误提示，不阻塞已有本地字幕轨和 OpenSubtitles 播放器功能。
- 所有测试命令清除代理变量：`HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test`。
- 完成前运行全量 Flutter 测试、`flutter analyze`、`git diff --check`，并构建 debug APK 安装到已连接平板。

---

## Task 1: 媒体库布局与筛选查询模型

**Files：**
- Modify: `lib/screens/media_library/media_library_query.dart`
- Modify: `lib/screens/media_library/media_library_items_screen.dart`
- Test: `test/media_library_query_test.dart`
- Test: `test/media_library_items_screen_test.dart`

**Interfaces：**
- Consumes: 现有 `MediaItem`、`MediaLibraryFilter`、`MediaLibraryQuery.apply`。
- Produces: `enum MediaLibraryLayout { grid, folder, list }`、`MediaLibraryQuery.folderGroups(List<MediaItem>) -> Map<String, List<MediaItem>>`；页面使用布局状态并渲染网格、文件夹分组和列表三种视图。

- [ ] **Step 1: 写失败测试**

```dart
test('文件夹布局按父目录分组且未分类单独成组', () {
  final groups = MediaLibraryQuery.folderGroups(items);
  expect(groups.keys, ['Beta', 'Alpha', '未分类']);
  expect(groups['Beta']!.single.id, 'a');
});

testWidgets('布局面板提供网格、文件夹和列表三种模式', (tester) async {
  await tester.pumpWidget(buildScreen());
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('布局'));
  await tester.pumpAndSettle();
  expect(find.text('网格'), findsOneWidget);
  expect(find.text('文件夹'), findsOneWidget);
  expect(find.text('列表'), findsOneWidget);
});

testWidgets('选择列表布局后显示媒体列表', (tester) async {
  await tester.pumpWidget(buildScreen());
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('布局'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('列表'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('media-list')), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/media_library_query_test.dart test/media_library_items_screen_test.dart`

期望：FAIL，报 `folderGroups` 未定义或找不到“文件夹/列表”布局入口，失败原因必须是功能缺失而非测试拼写错误。

- [ ] **Step 3: 写最小实现**

在查询类中按 `MediaLibraryQuery._folderFor` 生成有序分组；在页面中将 `_isPortrait` 替换为 `MediaLibraryLayout _layout = MediaLibraryLayout.grid`，保留网格列数规则，新增文件夹分组 Sliver 和列表 Sliver。筛选面板改为每个分组使用 `Wrap` 横向选项块，选中项只显示蓝色背景与文字，底部按钮固定，避免当前一个选项一个 ListTile 的长列表。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令。期望：新增测试和原有媒体库测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/media_library/media_library_query.dart lib/screens/media_library/media_library_items_screen.dart test/media_library_query_test.dart test/media_library_items_screen_test.dart
git commit -m "feat: 规范媒体库筛选并增加文件夹列表布局"
```

---

## Task 2: Emby/Jellyfin 原生字幕搜索与下载接口

**Files：**
- Modify: `lib/services/media_server_service.dart`
- Create: `lib/services/server_subtitle_service.dart`
- Test: `test/server_subtitle_service_test.dart`

**Interfaces：**
- Consumes: `MediaServerService` 的认证 Dio、`authHeaders`、`imageHeaders` 和媒体 ID。
- Produces: `class ServerSubtitleResult`（`id`、`language`、`displayTitle`、`provider`、`format`）、`Future<List<ServerSubtitleResult>> MediaServerService.searchSubtitles(String itemId, {String? language})`、`Future<String> MediaServerService.downloadSubtitle(String itemId, String subtitleId)`。

- [ ] **Step 1: 写失败测试**

```dart
test('服务器字幕结果解析语言、标题、提供方和格式', () {
  final result = ServerSubtitleResult.fromJson({
    'Id': 'sub-1',
    'Language': 'chi',
    'Name': '简体中文',
    'ProviderName': 'OpenSubtitles',
    'Format': 'srt',
  });
  expect(result.id, 'sub-1');
  expect(result.language, 'chi');
  expect(result.displayTitle, '简体中文');
  expect(result.provider, 'OpenSubtitles');
  expect(result.format, 'srt');
});

test('服务器字幕下载返回本地字幕文件内容', () async {
  final service = FakeServerSubtitleService();
  final path = await service.downloadSubtitle('item-1', 'sub-1');
  expect(path, '/tmp/sub-1.srt');
});
```

- [ ] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/server_subtitle_service_test.dart`

期望：FAIL，报统一接口或结果模型不存在，失败原因必须是功能缺失而非测试拼写错误。

- [ ] **Step 3: 写最小实现**

在 `media_server_service.dart` 抽象增加两个方法的默认实现，并实现 Emby/Jellyfin 共用 REST 路径：先 `GET /Items/{itemId}/RemoteSearch/Subtitles`，按 `Language`、`Name`、`ProviderName`、`Format` 解析；下载使用 `GET /Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}`，读取响应中的 `Path` 或 `Content`，写入应用支持目录的 `subtitle_cache/server_{itemId}_{subtitleId}.{format}`，返回绝对路径。未配置或接口返回空时返回空列表；下载无内容时抛出带中文错误信息的 `MediaServerSubtitleException`。

- [ ] **Step 4: 跑测试确认通过**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/server_subtitle_service_test.dart`

期望：PASS，并运行媒体服务相关既有测试确认没有认证回归。

- [ ] **Step 5: 提交**

```bash
git add lib/services/media_server_service.dart lib/services/server_subtitle_service.dart test/server_subtitle_service_test.dart
git commit -m "feat: 增加Emby和Jellyfin原生字幕搜索下载"
```

---

## Task 3: 详情页结构、轨道选择与操作入口

**Files：**
- Modify: `lib/screens/detail/detail_screen.dart`
- Modify: `lib/router/app_router.dart`
- Modify: `lib/screens/player/player_screen.dart`
- Test: `test/detail_screen_test.dart`

**Interfaces：**
- Consumes: Task 1 的布局无关查询、Task 2 的服务器字幕接口、现有 `TrackSelectorSheet`。
- Produces: 详情页首屏稳定 key：`detail-hero`、`detail-track-controls`、`detail-actions`；播放路由额外接收 `subtitleLanguage`、`audioLanguage`；不再渲染“预告片”文本或 `Icons.movie_filter` 入口。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('详情页不显示预告片但保留下载已观看收藏删除入口', (tester) async {
  await tester.pumpWidget(buildDetailScreen());
  await tester.pumpAndSettle();
  expect(find.text('预告片'), findsNothing);
  expect(find.byTooltip('下载'), findsOneWidget);
  expect(find.byTooltip('已观看'), findsOneWidget);
  expect(find.byTooltip('收藏'), findsOneWidget);
  expect(find.byTooltip('删除'), findsOneWidget);
});

testWidgets('详情页提供字幕和音频选择入口', (tester) async {
  await tester.pumpWidget(buildDetailScreen(withTracks: true));
  await tester.pumpAndSettle();
  expect(find.byTooltip('选择字幕'), findsOneWidget);
  expect(find.byTooltip('选择音频'), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/detail_screen_test.dart`

期望：FAIL，现有详情页仍有“预告片”或缺少目标操作按钮，失败原因必须是行为未实现而非测试拼写错误。

- [ ] **Step 3: 写最小实现**

重排详情页首屏为参考图的海报、标题元数据、轨道选择行、主播放/订阅按钮和操作按钮；删除预告片按钮及其回调，保留现有下载、已观看、收藏、删除回调并为按钮加稳定 tooltip。选择轨道时保存具体语言到播放器设置，并在播放路由 extra 传入语言偏好；播放器启动前恢复这些偏好，不改变现有 OpenSubtitles 在线搜索和服务端轨道下载逻辑。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令，并运行现有播放器相关测试。期望：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/detail/detail_screen.dart lib/router/app_router.dart lib/screens/player/player_screen.dart test/detail_screen_test.dart
git commit -m "feat: 重排媒体详情页并保留媒体操作"
```

---

## Task 4: 详情页服务器字幕搜索交互

**Files：**
- Modify: `lib/screens/detail/detail_screen.dart`
- Create: `lib/widgets/server_subtitle_search_sheet.dart`
- Test: `test/server_subtitle_search_sheet_test.dart`

**Interfaces：**
- Consumes: `MediaServerService.searchSubtitles`、`MediaServerService.downloadSubtitle`、`ServerSubtitleResult`。
- Produces: `ServerSubtitleSearchSheet.show(BuildContext, {required MediaServerService service, required String itemId, required String query}) -> Future<String?>`，返回已下载字幕本地路径。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('服务器字幕搜索面板显示结果并可下载', (tester) async {
  await tester.pumpWidget(buildSubtitleSheet());
  await tester.tap(find.byTooltip('搜索字幕'));
  await tester.pumpAndSettle();
  expect(find.text('简体中文'), findsOneWidget);
  await tester.tap(find.text('下载'));
  await tester.pumpAndSettle();
  expect(find.text('字幕已下载'), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/server_subtitle_search_sheet_test.dart`

期望：FAIL，面板、入口或搜索字幕按钮不存在，失败原因必须是功能缺失而非测试拼写错误。

- [ ] **Step 3: 写最小实现**

创建深色底部面板：顶部标题和关闭按钮、中间搜索框、结果列表、每行显示语言/来源/格式、右侧下载按钮；下载成功返回路径并在详情页提示“字幕已下载，播放时可在字幕面板启用”，失败显示服务端错误。详情页将服务器字幕搜索入口放在字幕选择面板的“搜索字幕”操作中，OpenSubtitles 入口保持播放器已有功能。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令，并运行完整 Flutter 测试。期望：PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/detail/detail_screen.dart lib/widgets/server_subtitle_search_sheet.dart test/server_subtitle_search_sheet_test.dart
git commit -m "feat: 在详情页支持服务器字幕搜索下载"
```

---

## Task 5: 全量验证与平板安装

**Files：**
- No production file changes expected.

- [ ] **Step 1: 运行全量测试**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test`

- [ ] **Step 2: 运行分析和差异检查**

命令：`flutter analyze`；`git diff --check`。记录 error 数量，不将既有 warning/info 误报为本次回归。

- [ ] **Step 3: 构建 debug APK**

命令：`flutter build apk --debug`。期望：生成 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 4: 安装并启动平板应用**

命令：`& 'C:\Users\hongbo\AppData\Local\Android\Sdk\platform-tools\adb.exe' -s 400DB303XH00000 install -r 'build\app\outputs\flutter-apk\app-debug.apk'`；随后启动 `com.panghuplayer`，检查前台 Activity、进程和最近日志无崩溃。

- [ ] **Step 5: 提交验证结果**

```bash
git status --short
```

在交付中报告测试数量、分析遗留 warning/info、APK 路径和设备端启动检查结果。

---

## 计划自查

- [x] 用户确认的筛选、布局、详情页、字幕和预告片范围均有对应任务。
- [x] 无 TBD、TODO、handle edge cases 或“类似 Task N”等占位符。
- [x] 后置任务使用的 `MediaLibraryLayout`、`ServerSubtitleResult`、`searchSubtitles`、`downloadSubtitle` 和 `ServerSubtitleSearchSheet.show` 已在前置任务中定义。
