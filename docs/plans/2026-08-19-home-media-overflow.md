# 首页媒体卡片溢出修复计划

**Goal：** 修复首页媒体横向列表在大屏设备上因固定高度不足产生的黄黑溢出条纹。

**Architecture：** 保留首页现有横向媒体列表和卡片结构，将列表视口高度改为依据
`ScreenAdapter` 卡片尺寸、两行标题、年份行和系统文字缩放动态计算。正式卡片与加载骨架共用同一高度函数，避免加载态和内容态发生布局跳变。

**Tech Stack：** Flutter 3.x、Dart、flutter_test、Riverpod。

**Spec：** 用户反馈：首页媒体溢出，疑似文字长度导致黄黑相间的线仍然存在。

---

## Task 1: 首页媒体横向列表

**Files：**
- Modify: `lib/screens/home/home_screen.dart:1104-1121`
- Modify: `lib/screens/home/home_screen.dart:1280-1320`
- Modify: `lib/screens/home/home_screen.dart:1609-1622`
- Test: `test/home_media_overflow_test.dart`

**Interfaces：**
- Consumes：`ScreenAdapter.of(BuildContext context)`、`MediaQuery.textScalerOf(BuildContext context)`。
- Produces：`_MediaLibraryContentState._categoryItemsHeight(BuildContext, {required bool hasYear}) -> double`。

- [x] 写大屏尺寸和长标题回归测试，断言首页媒体卡片列表高度超过旧固定值 `220`，并收集 Flutter 溢出错误。
- [x] 运行测试确认修复前列表仍为固定 `220` 高度。
- [x] 使用卡片图片高度、标题两行、年份行和安全间距计算动态高度；为标题和年份设置显式行高。
- [x] 运行回归测试确认通过。
- [x] 运行全量测试、`flutter analyze`、Android debug 构建并安装到 `iPA2375`。

---

## 计划自查

- [x] 根因已定位到首页横向列表固定高度与大屏卡片内容高度不匹配。
- [x] 修改范围限定在首页媒体列表、卡片文字行高和对应回归测试。
- [x] 加载骨架与正式内容使用同一动态高度规则。
