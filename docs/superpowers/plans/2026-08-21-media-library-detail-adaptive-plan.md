# 媒体库与详情页自适应优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复演员头像加载，并让媒体库、手机详情页和 TV 详情页在不同宽度下稳定自适应，同时保持 Android 5/6 可运行。

**Architecture:** 抽取纯 Dart 的演员头像 URL 解析器和媒体库列数计算器；详情页继续使用现有服务请求和 `ServerImage`，只统一字段解析、认证请求头和 TMDB 回退。TV 详情页复用同一套演员列表组件，避免两套加载逻辑继续分叉。

**Tech Stack:** Flutter 3.x、Dart、Riverpod、CachedNetworkImage、Flutter test。

**Spec:** 本次对话中已确认的详情页参考图、演员头像修复、自适应布局和 Android 5/6 兼容要求。

## Global Constraints

- 默认项目路径为 `D:\LAN-Player`。
- 所有新增代码添加中文注释。
- 不引入 Android 7+ API，不修改现有 minSdk/targetSdk 约束。
- 保留现有路由、播放、收藏和媒体库数据流。

---

### Task 1: 演员头像 URL 解析器

**Files:**
- Create: `lib/utils/credit_image_url.dart`
- Test: `test/credit_image_url_test.dart`

- [ ] 写测试覆盖服务端 ImageUrl、大小写字段、TMDB profile_path 和空值。
- [ ] 运行测试确认先失败。
- [ ] 实现纯函数 `resolveCreditImageUrl`。
- [ ] 运行测试确认通过。

### Task 2: 媒体库自适应列数

**Files:**
- Create: `lib/utils/adaptive_layout.dart`
- Modify: `lib/screens/media_library/media_library_items_screen.dart`
- Test: `test/adaptive_layout_test.dart`

- [ ] 写最小列数计算测试并确认失败。
- [ ] 实现按最小卡片宽度计算、限制 2 到 8 列的函数。
- [ ] 替换媒体库网格和文件夹布局中的固定 3/6 列。
- [ ] 更新现有布局断言并运行测试。

### Task 3: 手机/TV 详情页演员显示

**Files:**
- Create: `lib/widgets/credit_list.dart`
- Modify: `lib/screens/detail/detail_screen.dart`
- Modify: `lib/tv/screens/detail/tv_detail_screen.dart`

- [ ] 新增带中文注释的通用横向演员组件，头像失败时保留姓名和角色。
- [ ] 手机详情页接入统一解析器和组件。
- [ ] TV 详情页接入服务端 People 与 TMDB credits 合并结果。
- [ ] 保持 Android 5/6 使用的基础 Flutter API。

### Task 4: 验证

**Files:**
- No new files.

- [ ] 运行演员、媒体库、详情页相关 Flutter 测试。
- [ ] 运行 `flutter analyze`。
- [ ] 检查 Android 构建配置未被修改。

