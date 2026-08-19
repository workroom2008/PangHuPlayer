# 媒体库内容页统一实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** 统一首页分类和服务器入口进入后的媒体库内容页，按屏幕宽度显示 3/6 列网格，并提供可用的排序、布局、筛选和文件夹条件。

**Architecture:** 新增无状态查询逻辑 `MediaLibraryQuery`，负责稳定排序、条件筛选和文件夹提取；新增共享 `LibraryItemsScreen`，负责加载数据、工具栏、底部面板和响应式网格。首页与服务器入口删除各自重复的内容页实现，只导出共享页面以保持现有测试和外部调用的导入路径兼容。

**Tech Stack:** Flutter 3.x、Dart 3、flutter_riverpod、flutter_animate、cached_network_image、flutter_test。

**Spec:** `docs/superpowers/specs/2026-08-19-media-library-content-design.md`

## Global Constraints

- 逻辑宽度小于 `900` 时使用 3 列，大于等于 `900` 时使用 6 列。
- 竖幅布局比例为 `2 / 3`，横幅布局比例为 `16 / 10`。
- 默认排序为“加入日期 + 降序”，没有加入日期字段时保持服务端返回的稳定顺序。
- 文件夹条件从 `MediaItem.filePath` 提取父目录；无有效路径的媒体归入“未分类”。
- 删除“类型”顶部 Tab；文件夹条件放入筛选面板。
- 测试命令必须清除代理变量：`HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test`。
- 每个任务完成自己的 RED-GREEN-REFACTOR 循环后提交，提交信息使用约定式中文描述。

---

## Task 1: 媒体库查询逻辑

**Files:**
- Create: `lib/screens/media_library/media_library_query.dart`
- Test: `test/media_library_query_test.dart`

**Interfaces:**
- Consumes: `MediaItem` from `lib/models/media_models.dart`。
- Produces: `MediaLibrarySortField`、包含 `year` 精确年份字段的 `MediaLibraryFilter`、`MediaLibraryQuery.apply` 和 `MediaLibraryQuery.folders`，供共享页面和测试直接调用。

- [x] **Step 1: 写失败测试**

创建 `test/media_library_query_test.dart`，使用真实 `MediaItem` 列表，不使用 mock：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lanplayer/models/media_models.dart';
import 'package:lanplayer/screens/media_library/media_library_query.dart';

MediaItem item({
  required String id,
  required String title,
  MediaType type = MediaType.movie,
  int? year,
  double? rating,
  bool? watched,
  List<String> genres = const [],
  String? filePath,
}) => MediaItem(
      id: id,
      title: title,
      posterUrl: '',
      type: type,
      year: year,
      rating: rating,
      isWatched: watched,
      genres: genres,
      filePath: filePath,
    );

void main() {
  final items = [
    item(id: 'a', title: 'Beta', year: 2024, rating: 7.2,
        genres: ['剧情'], filePath: r'D:\Movies\Beta\beta.mkv'),
    item(id: 'b', title: 'Alpha', type: MediaType.series, year: 2012,
        rating: 9.1, watched: true, genres: ['动作'],
        filePath: r'D:\Shows\Alpha\alpha.mkv'),
    item(id: 'c', title: 'Gamma', year: 2020, rating: 7.2,
        watched: false, genres: ['剧情'], filePath: null),
  ];

  test('标题升序和降序都保持可预测顺序', () {
    final ascending = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.title,
      descending: false,
      filter: const MediaLibraryFilter(),
    );
    final descending = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.title,
      descending: true,
      filter: const MediaLibraryFilter(),
    );
    expect(ascending.map((i) => i.id), ['b', 'a', 'c']);
    expect(descending.map((i) => i.id), ['c', 'a', 'b']);
  });

  test('评分排序相同评分保留原始顺序', () {
    final result = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.rating,
      descending: true,
      filter: const MediaLibraryFilter(),
    );
    expect(result.map((i) => i.id), ['b', 'a', 'c']);
  });

  test('分类、类型、年份、观看状态和文件夹按 AND 关系筛选', () {
    final result = MediaLibraryQuery.apply(
      items: items,
      sortField: MediaLibrarySortField.addedDate,
      descending: true,
      filter: const MediaLibraryFilter(
        category: '电影',
        genre: '剧情',
        decade: 2020,
        watched: false,
        folder: '未分类',
      ),
    );
    expect(result.map((i) => i.id), ['c']);
  });

  test('文件夹列表提取父目录并包含未分类媒体', () {
    expect(MediaLibraryQuery.folders(items), ['Beta', 'Alpha', '未分类']);
  });
}
```

- [x] **Step 2: 跑测试确认失败**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_query_test.dart
```

期望：FAIL，原因是 `media_library_query.dart` 尚不存在；修正路径或测试语法错误后才可继续。

- [x] **Step 3: 写最小实现**

创建 `lib/screens/media_library/media_library_query.dart`，实现以下完整契约：

```dart
import '../../models/media_models.dart';

enum MediaLibrarySortField { addedDate, title, rating, year, releaseDate, watched }

class MediaLibraryFilter {
  final String? category;
  final String? genre;
  final int? year;
  final int? decade;
  final bool? watched;
  final String? folder;

  const MediaLibraryFilter({
    this.category,
    this.genre,
    this.year,
    this.decade,
    this.watched,
    this.folder,
  });

  MediaLibraryFilter copyWith({
    Object? category = _unset,
    Object? genre = _unset,
    Object? year = _unset,
    Object? decade = _unset,
    Object? watched = _unset,
    Object? folder = _unset,
  }) => MediaLibraryFilter(
        category: identical(category, _unset) ? this.category : category as String?,
        genre: identical(genre, _unset) ? this.genre : genre as String?,
        year: identical(year, _unset) ? this.year : year as int?,
        decade: identical(decade, _unset) ? this.decade : decade as int?,
        watched: identical(watched, _unset) ? this.watched : watched as bool?,
        folder: identical(folder, _unset) ? this.folder : folder as String?,
      );
}

const _unset = Object();

class MediaLibraryQuery {
  static List<MediaItem> apply({
    required List<MediaItem> items,
    required MediaLibrarySortField sortField,
    required bool descending,
    required MediaLibraryFilter filter,
  }) {
    final filtered = items.where((item) {
      final categoryMatches = filter.category == null ||
          filter.category == '全部' ||
          (filter.category == '电影' && item.type == MediaType.movie) ||
          (filter.category == '电视节目' && item.type != MediaType.movie);
      final genreMatches = filter.genre == null || item.genres.contains(filter.genre);
      final decadeMatches = filter.decade == null ||
          (item.year != null && item.year! >= filter.decade! && item.year! < filter.decade! + 10);
      final watchedMatches = filter.watched == null ||
          (filter.watched! ? item.isWatched == true : item.isWatched != true);
      final folderMatches = filter.folder == null || _folderFor(item) == filter.folder;
      return categoryMatches && genreMatches && decadeMatches && watchedMatches && folderMatches;
    }).toList();

    final indexed = filtered.indexed.toList();
    int compare((int, MediaItem) a, (int, MediaItem) b) {
      int result;
      switch (sortField) {
        case MediaLibrarySortField.title:
          result = a.$2.title.compareTo(b.$2.title);
        case MediaLibrarySortField.rating:
          result = (a.$2.rating ?? 0).compareTo(b.$2.rating ?? 0);
        case MediaLibrarySortField.year:
        case MediaLibrarySortField.releaseDate:
          result = (a.$2.year ?? 0).compareTo(b.$2.year ?? 0);
        case MediaLibrarySortField.watched:
          result = (a.$2.isWatched == true ? 1 : 0).compareTo(b.$2.isWatched == true ? 1 : 0);
        case MediaLibrarySortField.addedDate:
          result = 0;
      }
      if (result == 0) result = a.$1.compareTo(b.$1);
      return descending ? -result : result;
    }

    indexed.sort(compare);
    return indexed.map((entry) => entry.$2).toList();
  }

  static List<String> folders(List<MediaItem> items) {
    final result = <String>{};
    for (final item in items) result.add(_folderFor(item));
    return result.toList();
  }

  static String _folderFor(MediaItem item) {
    final path = item.filePath?.trim() ?? '';
    if (path.isEmpty) return '未分类';
    final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return '未分类';
    return parts[parts.length - 2];
  }
}
```

将 import 路径按文件实际位置修正为 `../../models/media_models.dart`，并保持 Dart 3 的 record 写法可编译。

- [x] **Step 4: 跑测试确认通过**

运行同一个测试命令，期望 4 个测试 PASS。随后运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_query_test.dart test/media_library_overflow_test.dart
```

期望无新增错误。

- [x] **Step 5: 提交**

```bash
git add test/media_library_query_test.dart lib/screens/media_library/media_library_query.dart
git commit -m "feat: 增加媒体库排序筛选查询逻辑"
```

## Task 2: 共享媒体库内容页

**Files:**
- Create: `lib/screens/media_library/media_library_items_screen.dart`
- Test: `test/media_library_items_screen_test.dart`

**Interfaces:**
- Consumes: `MediaLibraryQuery.apply`、`MediaLibraryQuery.folders`、`MediaServerService.getAllLibraryItems`。
- Produces: 公共 `LibraryItemsScreen`，构造函数签名为 `const LibraryItemsScreen({super.key, required MediaServer server, required MediaServerService serverService, required MediaItem library})`。

- [ ] **Step 1: 写失败 Widget 测试**

创建 `_FakeMediaService extends EmbyService`，只重写 `getAllLibraryItems`，避免网络调用并复用 `EmbyService` 已有的抽象方法实现：

```dart
class _FakeMediaService extends EmbyService {
  _FakeMediaService() : super(baseUrl: 'http://test', apiKey: 'test-token');

  @override
  Future<List<MediaItem>> getAllLibraryItems(
    String libraryId, {
    bool includeBoxSets = false,
  }) async {
    return [
      MediaItem(id: 'one', title: '第一文件夹影片', posterUrl: '', year: 2024,
          rating: 8.0, genres: ['剧情'], filePath: '/电影库/第一文件夹/one.mkv'),
      MediaItem(id: 'two', title: '第二文件夹影片', posterUrl: '', year: 2023,
          rating: 7.0, genres: ['动作'], filePath: '/电影库/第二文件夹/two.mkv'),
      MediaItem(id: 'three', title: '第三文件夹影片', posterUrl: '', year: 2022,
          rating: 6.0, genres: ['动画'], filePath: '/电影库/第三文件夹/three.mkv'),
      MediaItem(id: 'four', title: '长标题媒体四', posterUrl: '', year: 2021,
          rating: 8.1, type: MediaType.series,
          filePath: '/电视剧/第四文件夹/four.mkv'),
      MediaItem(id: 'five', title: '长标题媒体五', posterUrl: '', year: 2020,
          rating: 8.2, filePath: '/电影库/第五文件夹/five.mkv'),
      MediaItem(id: 'six', title: '长标题媒体六', posterUrl: '', year: 2019,
          rating: 8.3, filePath: '/电影库/第六文件夹/six.mkv'),
      MediaItem(id: 'seven', title: '没有路径的媒体七', posterUrl: '', year: 2018,
          rating: 8.4),
    ];
  }
}

Widget buildScreen() => MaterialApp(
      home: LibraryItemsScreen(
        server: MediaServer(
          id: 'server', name: '测试服务器', url: 'http://test', type: ServerType.emby,
        ),
        serverService: _FakeMediaService(),
        library: const MediaItem(id: 'library', title: '电影', posterUrl: ''),
      ),
    );
```

测试文件导入 `flutter/material.dart`、`flutter_test.dart`、`media_models.dart`、共享页面、`media_server_service.dart`。测试文件包含以下测试：

```dart
testWidgets('小屏使用三列且内容页提供排序布局筛选入口', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(buildScreen());
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('media-grid')), findsOneWidget);
  expect(find.byKey(const ValueKey('media-grid-3-columns')), findsOneWidget);
  expect(find.byTooltip('布局'), findsOneWidget);
  expect(find.byTooltip('筛选'), findsOneWidget);
  expect(find.text('类型'), findsNothing);
});

testWidgets('大屏使用六列', (tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(buildScreen());
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('media-grid-6-columns')), findsOneWidget);
});

testWidgets('筛选面板选择文件夹后只显示该文件夹媒体', (tester) async {
  await tester.pumpWidget(buildScreen());
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('筛选'));
  await tester.pumpAndSettle();
  expect(find.text('文件夹'), findsOneWidget);
  await tester.tap(find.text('第二文件夹'));
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();

  expect(find.text('第二文件夹影片'), findsOneWidget);
  expect(find.text('第一文件夹影片'), findsNothing);
});

testWidgets('大字体长标题不产生溢出', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final errors = <FlutterErrorDetails>[];
  final oldOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = oldOnError;
  }
  expect(errors.where((e) => e.exception.toString().contains('overflowed')), isEmpty);
});
```

测试通过 `ValueKey('media-grid')`、`ValueKey('media-grid-3-columns')` 和 `ValueKey('media-grid-6-columns')` 验证实际网格委托，不通过实现私有字段验证。

- [ ] **Step 2: 跑测试确认失败**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_items_screen_test.dart
```

期望：FAIL，原因是共享页面文件和 `LibraryItemsScreen` 尚不存在。

- [ ] **Step 3: 写最小实现**

创建共享页面并遵守以下实现边界：

1. `initState` 调用 `widget.serverService.getAllLibraryItems(widget.library.id, includeBoxSets: widget.library.collectionType == 'boxsets')`，不再使用只取第一页的 `getLibraryItems`。
2. `_itemsFuture` 完成后保存 `_allItems`，build 使用 `MediaLibraryQuery.apply` 生成内容；状态包含 `_sortField = MediaLibrarySortField.addedDate`、`_descending = true`、`_isPortrait = true` 和 `MediaLibraryFilter _filter = const MediaLibraryFilter()`。
3. 顶部使用 `SafeArea`、返回按钮、居中标题、搜索按钮；工具行使用排序字段文本、数量文本、`IconButton(tooltip: '布局')` 和 `IconButton(tooltip: '筛选')`。不创建类型 Tab。
4. 布局按钮弹出底部面板，提供 `横幅`、`竖幅` 两个单选项；选择后 setState 并关闭。
5. 筛选按钮弹出 `StatefulBuilder` 底部面板，按“分类/类型/年份/观看状态/文件夹”显示单选选项，底部固定“重置/确定”按钮；确定只更新 `_filter`，重置把临时值设为 null。文件夹选项来自 `MediaLibraryQuery.folders(_allItems)`。
6. 网格使用 `SliverGrid`。`crossAxisCount = MediaQuery.sizeOf(context).width < 900 ? 3 : 6`；左右 padding 为 `20`，gap 为 `12`；`itemWidth = (width - 40 - gap * (count - 1)) / count`；`mainAxisExtent` 使用海报高度、`textScaler.scale(12) * 1.2 * 2`、可选年份行和间距相加。网格和委托分别添加上述三个 ValueKey。
7. 海报卡片使用 `Hero(tag: 'media_${item.id}_poster')`、`ServerImage`、评分和观看标记；标题最多两行，年份最多一行；普通媒体调用 `DetailScreen`，合集递归 push 共享 `LibraryItemsScreen`。
8. 过滤无结果时显示“没有符合条件的内容”和“清除筛选”；加载错误沿用重试按钮；原始空列表显示“暂无内容”。

- [ ] **Step 4: 跑测试确认通过**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_items_screen_test.dart
```

期望 4 个 Widget 测试 PASS；若大字体测试出现 overflow，只调整 `mainAxisExtent` 计算或文字行高，不放宽断言。

- [ ] **Step 5: 提交**

```bash
git add test/media_library_items_screen_test.dart lib/screens/media_library/media_library_items_screen.dart
git commit -m "feat: 增加统一媒体库内容页"
```

## Task 3: 迁移两个入口并删除旧页面

**Files:**
- Modify: `lib/screens/home/home_screen.dart:1631-2721`
- Modify: `lib/screens/servers/media_library_screen.dart:360-683`
- Create: `test/media_library_entry_points_test.dart`
- Modify: `test/media_library_overflow_test.dart`
- Modify: `test/sort_menu_animation_test.dart`

**Interfaces:**
- Consumes: `lib/screens/media_library/media_library_items_screen.dart` 的公共 `LibraryItemsScreen`。
- Produces: 两个原入口继续可以通过原有 import 路径引用 `LibraryItemsScreen`，首页和服务器入口实际打开同一个共享 runtimeType。

- [ ] **Step 1: 写失败回归测试**

在 `test/media_library_entry_points_test.dart` 新增测试，分别 import：

```dart
import 'package:lanplayer/screens/home/home_screen.dart' as home;
import 'package:lanplayer/screens/servers/media_library_screen.dart' as servers;
import 'package:lanplayer/screens/media_library/media_library_items_screen.dart' as shared;
```

测试主体使用 `Type` 比较验证导出类型：

```dart
void main() {
  test('首页和服务器入口导出同一个媒体库内容页类型', () {
    expect(home.LibraryItemsScreen, same(shared.LibraryItemsScreen));
    expect(servers.LibraryItemsScreen, same(shared.LibraryItemsScreen));
  });
}
```

先运行该测试，确认迁移前因两个文件各自拥有独立 `LibraryItemsScreen` 而失败。

- [ ] **Step 2: 跑测试确认失败**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_entry_points_test.dart
```

期望：FAIL，原因是两个入口的 `LibraryItemsScreen` 不是共享类型。

- [ ] **Step 3: 写最小迁移实现**

在两个旧页面文件的 import 区加入：

```dart
import '../media_library/media_library_items_screen.dart';
export '../media_library/media_library_items_screen.dart';
```

服务器页面的相对路径为 `../media_library/media_library_items_screen.dart`；首页页面的相对路径同样为 `../media_library/media_library_items_screen.dart`。删除两个文件中旧的 `LibraryItemsScreen`、`_LibraryItemsScreenState`、`_MediaItemCard`、`_SenPlayerCard`、`_GenreCard`、`_FolderCard`、`_AnimatedMenuPanel` 和 `_SortMenuItem` 定义，只保留各自入口页面。删除后清理仅由这些旧类使用的 import，保留其他首页/服务器页面依赖。

- [ ] **Step 4: 跑测试确认通过**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test test/media_library_entry_points_test.dart test/media_library_overflow_test.dart test/sort_menu_animation_test.dart
```

期望入口回归通过，现有排序动画测试若依赖旧菜单则删除该旧测试中针对旧菜单的断言，并替换为共享页面排序面板行为断言；不得保留一个已经不属于产品行为的测试。

- [ ] **Step 5: 提交**

```bash
git add lib/screens/home/home_screen.dart lib/screens/servers/media_library_screen.dart test/media_library_entry_points_test.dart test/media_library_overflow_test.dart test/sort_menu_animation_test.dart
git commit -m "refactor: 统一两个入口的媒体库内容页"
```

## Task 4: 全量验证与收尾

**Files:**
- Modify: `docs/plans/2026-08-19-media-library-content.md`，勾选已完成步骤并记录实际验证结果。

**Interfaces:**
- Consumes: Task 1-3 的实现和测试。
- Produces: 全量测试和静态分析的可复现结果。

- [ ] **Step 1: 运行全量 Flutter 测试**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test
```

期望：退出码为 0，所有测试通过；输出中不得有新增 overflow、异常或未处理的测试错误。

- [ ] **Step 2: 运行静态分析**

运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter analyze
```

期望：无 error；既有 info 级 lint 可以与基线一致，但不得引入新的 error。

- [ ] **Step 3: 检查差异和工作区边界**

运行：

```bash
git diff --check
git status --short
git diff --stat HEAD~3..HEAD
```

确认只包含本功能的共享页面、查询逻辑、两个入口迁移、测试和计划文件，不修改用户已有的无关未提交文件。

- [ ] **Step 4: 提交计划验证记录**

```bash
git add docs/plans/2026-08-19-media-library-content.md
git commit -m "docs: 记录媒体库内容页验证结果"
```

完成后再使用 `verification-before-completion` 检查最新测试输出，最后使用 `finishing-a-development-branch` 决定本地提交的交付方式。

---

## 计划自查

- [x] spec 的响应式网格、排序、布局、筛选、文件夹、错误状态和测试要求均有任务覆盖。
- [x] 全文无 `TBD`、`TODO`、`handle edge cases` 或“类似 Task N”等占位表述。
- [x] 共享页面、查询逻辑、入口导出和测试中使用的文件路径、类名、枚举名和方法签名一致。
