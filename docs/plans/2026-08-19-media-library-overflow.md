# 媒体库卡片溢出修复计划

**Goal：** 修复媒体库内容网格在小屏和大字体缩放下出现黄黑溢出条纹的问题。

**Architecture：** 保留现有三列媒体卡片和卡片内部结构，仅将网格固定比例高度改为依据可用列宽、标题两行和年份行动态计算的 `mainAxisExtent`。卡片文本样式显式设置行高，使网格高度计算与实际布局一致。

**Tech Stack：** Flutter 3.x、Dart、flutter_test。

**Spec：** 用户反馈：媒体库仍出现黄黑相间的布局溢出线。

---

## Task 1: 媒体库网格布局

**Files：**
- Modify: `lib/screens/servers/media_library_screen.dart:572-591`
- Modify: `lib/screens/servers/media_library_screen.dart:638-655`
- Create: `test/media_library_overflow_test.dart`

- [x] 写失败测试：320x568 逻辑像素、3.0 设备像素比、2.0 字体缩放、长标题和年份下渲染 `LibraryItemsScreen`，断言没有 `RenderFlex overflowed`。
- [x] 运行测试确认当前固定 `childAspectRatio` 实现失败。
- [x] 将网格改为动态 `mainAxisExtent`，并为标题和年份设置显式行高。
- [x] 运行回归测试确认通过。
- [x] 运行全量测试、`flutter analyze` 和 Android debug 构建。

---

## 计划自查

- [x] 根因已由 Flutter 渲染错误定位到 `Column` 和固定网格高度。
- [x] 修改范围限定在媒体库网格和对应回归测试。
- [x] 不修改网络、数据、导航和其他页面逻辑。
