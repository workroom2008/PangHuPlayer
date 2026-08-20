# 详情页重新排版实施计划

> **执行者须知**：按任务逐条执行，步骤用 `- [ ]` 勾选跟踪。每个任务独立完成测试循环。

**Goal：** 按 `D:\ui\详情新.jpg` 和 `D:\ui\详情6.jpg` 重排媒体详情页，移除下载功能，合并重复控件，并确保海报、元数据和操作区不互相遮挡。

**Architecture：** 保留现有 `DetailScreen`、轨道选择器和服务器媒体接口，只重排详情页首屏布局。首屏改为响应式双列结构：海报独占左列，媒体信息、音频/字幕选择和操作区位于右列；窄屏自动改为上下结构。演员区继续使用 `ServerImage`，只渲染有可用图片 URL 的演员。

**Tech Stack：** Flutter 3.x、Dart、flutter_test、CachedNetworkImage、现有 Riverpod 和 Emby/Jellyfin 服务。

**Spec：** 用户确认的详情页改版需求与两张本地参考图。

## Global Constraints

- 不新增第三方依赖。
- 下载按钮、下载入口、下载回调和下载相关文案全部移除；订阅功能不改为下载按钮。
- 收藏、音频选择、字幕选择各只保留一个入口。
- 演员没有 `ImageUrl` 或 `profile_path` 时直接过滤，不显示失败占位卡片。
- 海报必须有独立布局区域，任何文字、按钮和背景叠层不得覆盖海报内容。
- 测试命令清除代理变量：`HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= NO_PROXY=127.0.0.1,localhost flutter test`。

## Task 1: 更新详情页行为测试

**Files：**
- Modify: `test/detail_screen_test.dart`

**Interfaces：**
- Consumes: 现有 `_FakeDetailService` 和 `DetailScreen`。
- Produces: 覆盖无下载、单收藏、单轨道入口、播放按钮尺寸和海报独立区域的回归测试。

- [x] **Step 1: 修改失败测试**

将测试名称改为“详情页只保留一组操作和轨道入口”，删除下载断言，增加：

```dart
expect(find.byTooltip('下载'), findsNothing);
expect(find.byTooltip('收藏'), findsOneWidget);
expect(find.byTooltip('选择音频'), findsOneWidget);
expect(find.byTooltip('选择字幕'), findsOneWidget);
expect(find.byKey(const ValueKey('detail-poster')), findsOneWidget);
expect(find.byKey(const ValueKey('detail-play-button')), findsOneWidget);
```

增加一个带 `people` 数据的测试，验证无图片演员被过滤，有 `ImageUrl` 演员仍显示。

- [x] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/detail_screen_test.dart`

期望：FAIL，原因是当前仍渲染下载按钮、轨道入口 tooltip 不统一或没有独立海报 key。

## Task 2: 重排详情页首屏并移除下载

**Files：**
- Modify: `lib/screens/detail/detail_screen.dart`

**Interfaces：**
- Consumes: 现有媒体详情加载、收藏、已观看、删除、音频/字幕选择和服务器字幕搜索方法。
- Produces: `detail-poster`、`detail-play-button`、`detail-track-controls` 稳定 key；首屏只渲染一组收藏和一组音频/字幕入口。

- [x] **Step 1: 写最小实现**

删除 `_actionIconRow` 中的下载按钮和 `_downloadItem` 方法；删除顶部重复收藏按钮；操作行保留收藏、已观看、删除。首屏轨道选择仅使用 `_detailTrackControls`，其按钮 tooltip 固定为“选择音频”和“选择字幕”。

将原 480px 叠层首屏替换为响应式布局：宽度大于 700 时使用 `Row`，左侧 `SizedBox` + `AspectRatio` 独立渲染海报，右侧渲染标题、评分、元数据、轨道控制、紧凑播放按钮和操作行；窄屏使用 `Column`，海报先独占一段，再渲染信息。背景图只作为独立背景层并降低透明度，不作为海报容器。

播放按钮固定 `ValueKey('detail-play-button')`，高度约 52px；主播放区域不再使用下载/订阅状态作为 CTA。保留已订阅状态区域，但文案使用“已订阅”，不出现下载文案。

- [x] **Step 2: 跑定向测试确认通过**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; flutter test test/detail_screen_test.dart`

期望：PASS，详情页无下载入口，收藏/音频/字幕入口各一个。

## Task 3: 过滤失败演员图片并验证布局

**Files：**
- Modify: `lib/screens/detail/detail_screen.dart`
- Modify: `test/detail_screen_test.dart`

**Interfaces：**
- Consumes: `_credits` 演员数据和现有 `ServerImage`。
- Produces: 只有可解析图片地址且姓名非空的演员进入 `_castSection`。

- [x] **Step 1: 写失败测试**

使用包含以下演员数据的详情对象：一条空图片、一条只有无效空 `ImageUrl`、一条有效 TMDB `profile_path`；断言演员区只显示有效演员。

- [x] **Step 2: 跑测试确认失败**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY=127.0.0.1,localhost; flutter test test/detail_screen_test.dart`

期望：FAIL，当前代码会把无图片演员渲染成默认头像占位。

- [x] **Step 3: 写最小实现**

在 `_castSection` 构建列表前过滤姓名为空或最终图片 URL 为空的条目；优先使用服务器 `ImageUrl`，其次使用 TMDB `profile_path`，图片继续通过带服务器 headers 的图片组件加载。移除默认头像分支，图片加载错误时不产生带失败头像的演员卡片。

- [x] **Step 4: 跑全量验证**

命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY=127.0.0.1,localhost; flutter test`；`flutter analyze`；`git diff --check`。

- [x] **Step 5: 构建并安装**

命令：`flutter build apk --debug`；`adb -s 400DB303XH00000 install -r build/app/outputs/flutter-apk/app-debug.apk`；启动 `com.panghuplayer` 并检查前台 Activity、进程和 `FATAL EXCEPTION`。

## 计划自查

- [x] 下载移除、重复入口合并、演员过滤、海报不遮挡和播放按钮收敛均有任务覆盖。
- [x] 未新增依赖或改变字幕/音频接口。
- [x] 无 TBD、TODO 或未定义接口占位符。
