# 媒体库内容页统一设计

## 目标

统一首页媒体库分类和服务器入口进入后的媒体库内容页，按参考图提供紧凑的媒体网格、排序、布局和筛选操作，并修复文件夹视图没有内容、点击后看不到结果的问题。

## 现状与范围

当前项目存在两套同名 `LibraryItemsScreen`：

- `lib/screens/home/home_screen.dart` 中的页面包含类型/文件夹 Tab、排序菜单和大图卡片。
- `lib/screens/servers/media_library_screen.dart` 中的页面只有固定三列海报，没有工具栏。

本次新增共享页面 `lib/screens/media_library/media_library_items_screen.dart`，两个旧入口只负责导出和跳转到该页面。`MediaLibraryScreen` 的服务器媒体库卡片页保留，只有进入库后的内容页统一。

## 交互设计

### 页面结构

内容页采用深色媒体库布局，结构从上到下为：

1. 返回按钮、当前媒体库标题、搜索按钮。
2. 工具行：当前排序字段、升降序图标、结果数量；右侧为布局按钮和筛选按钮。
3. 媒体网格。

删除旧页面的“类型” Tab。文件夹不再作为顶部 Tab，而是在筛选面板中作为可选的文件夹条件；选择文件夹后，工具行显示当前文件夹条件，内容区只显示该文件夹的媒体。清除条件后恢复全部内容。

### 响应式网格

- 逻辑宽度小于 `900` 时使用 3 列。
- 逻辑宽度大于等于 `900` 时使用 6 列。
- 列间距为 `12`，左右内边距为 `20`；卡片宽度由 `LayoutBuilder` 计算。
- 竖幅布局海报比例为 `2 / 3`，横幅布局比例为 `16 / 10`。
- 网格使用 `mainAxisExtent` 根据卡片宽度、文字缩放、标题两行和年份行计算，不能使用固定 `childAspectRatio` 裁剪文字。
- 默认布局为竖幅；布局面板提供“横幅”和“竖幅”两个互斥选项。

### 排序

排序面板提供：加入日期、标题、公众评分、出品年份、首映日期、播放状态。默认“加入日期 + 降序”，点击当前排序字段切换升降序，切换字段恢复降序。当前数据已经由服务端按加入日期返回，因此没有日期字段时保留原顺序作为稳定排序。

### 筛选

筛选面板使用底部弹层，提供“分类”“类型”“年份”“观看状态”“文件夹”五组条件：

- 分类：全部、电影、电视节目，根据 `MediaType` 映射。
- 类型：从 `MediaItem.genres` 去重生成。
- 年份：全部、今年、2020s、2010s、2000s，以及当前数据中存在的其他十年分组。
- 观看状态：全部、已观看、未观看。
- 文件夹：从 `filePath` 提取父目录名称并去重生成；没有路径的媒体归入“未分类”，保证筛选入口始终有可见结果。

筛选面板底部提供“重置”和“确定”。重置清空所有条件但不关闭面板，确定应用条件并关闭面板。多个条件在客户端按 AND 关系组合；同一组只保留一个值。

### 文件夹进入

服务端返回的 `filePath` 是文件级路径。页面在加载后按父目录分组生成文件夹选项，点击文件夹选项等价于进入该文件夹，结果区只展示该目录下的媒体；顶部显示可清除的文件夹条件。不能把没有路径的媒体静默丢弃，必须放入“未分类”选项。

### 内容卡片

卡片保留现有 Hero 海报、评分、已观看标记、标题和年份。点击合集（`isBoxSet`）进入同一个共享内容页并将合集作为新的父级；点击普通媒体进入详情页。文件夹筛选不会改变普通媒体的详情导航。

## 数据与接口

新增共享页面公开接口保持现有调用兼容：

```dart
class LibraryItemsScreen extends ConsumerStatefulWidget {
  const LibraryItemsScreen({
    super.key,
    required MediaServer server,
    required MediaServerService serverService,
    required MediaItem library,
  });
}
```

媒体服务继续使用 `getAllLibraryItems`，本次不新增服务端查询参数，不引入新的网络依赖。Emby/Jellyfin 的媒体列表查询继续请求 `MediaSources`，FnOS 继续使用现有文件路径字段。共享页面只对内存中的 `List<MediaItem>` 做排序、筛选和文件夹分组。

为保证测试可覆盖，新增纯 Dart 逻辑类 `MediaLibraryQuery`，接口如下：

```dart
enum MediaLibrarySortField {
  addedDate,
  title,
  rating,
  year,
  releaseDate,
  watched,
}

class MediaLibraryFilter {
  final String? category;
  final String? genre;
  final int? year;
  final int? decade;
  final bool? watched;
  final String? folder;
}

class MediaLibraryQuery {
  static List<MediaItem> apply({
    required List<MediaItem> items,
    required MediaLibrarySortField sortField,
    required bool descending,
    required MediaLibraryFilter filter,
  });

  static List<String> folders(List<MediaItem> items);
}
```

`MediaLibraryQuery` 的文件夹提取只使用跨平台分隔符正则 `[\\/]`；没有有效父目录时返回 `未分类`。所有排序字段都必须保持稳定：相同值按原列表索引顺序排列。

## 错误与空状态

- 加载中显示与目标列数一致的骨架网格。
- 网络错误显示“加载失败”和重试按钮，重试沿用现有 service 调用。
- 当前筛选条件没有结果时显示“没有符合条件的内容”和清除筛选操作。
- 原始媒体库为空时显示现有“暂无内容”状态。

## 测试契约

新增 `test/media_library_query_test.dart` 覆盖：默认排序、标题升降序、评分排序、类型/年份/观看状态组合筛选、文件夹提取和无路径媒体归入“未分类”。

新增或调整 Widget 测试覆盖：

- 逻辑宽度 `390` 时渲染 3 列，逻辑宽度 `1440` 时渲染 6 列。
- 页面不再出现“类型” Tab，工具行包含排序、布局、筛选入口。
- 选择文件夹后能显示该文件夹媒体，清除后恢复全部媒体。
- 大字体和长标题下没有 `RenderFlex overflowed`。

必须运行：

```bash
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test
flutter analyze
```
