# 演员图片失败误删修复实施计划

**Goal：** 修复详情页演员图片请求失败后演员卡片全部消失的问题，并阻止空 `PrimaryImageTag` 生成无效图片 URL。

**Architecture：** 保留详情页现有“无图片不展示”的筛选逻辑，但将图片加载错误分为“服务器明确返回资源不存在”和“认证、网络、缓存或服务端暂时异常”。只有 `HttpExceptionWithStatus` 的 404/410 才加入 `_failedCreditImages`；其他错误保留演员卡片，不再未经确认地永久过滤。Emby/Jellyfin 解析演员图片时只接受非空 `PrimaryImageTag`，并对人员 ID、Token 和 Tag 做 URL 编码。

**Tech Stack：** Flutter、Dart、`cached_network_image`、`flutter_cache_manager`、Dio、Flutter widget test。

**Spec：** 用户提供的详情页演员图片加载问题与既有详情页回归测试。

## Global Constraints

- 只修改演员图片失败确认、Emby/Jellyfin 演员图片 URL 解析及对应测试。
- 不回退工作区中用户已有的其他改动。
- 代码添加中文注释。
- 测试运行前清空 HTTP 代理变量。

---

## Task 1: 演员图片失败确认策略

**Files：**
- Create: `lib/screens/detail/credit_image_failure.dart`
- Modify: `lib/screens/detail/detail_screen.dart:1840-1848`
- Test: `test/credit_image_failure_test.dart`

**Interfaces：**
- Produces: `bool shouldHideCreditImageAfterError(Object error)`，仅对 `HttpExceptionWithStatus` 的 404/410 返回 `true`。

- [ ] **Step 1: 写失败测试**
  测试 404/410 返回 `true`，401/403/500 和普通异常返回 `false`。
- [ ] **Step 2: 跑测试确认失败**
  命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; D:\Android\flutter\bin\flutter.bat test test/credit_image_failure_test.dart`
  期望：FAIL，报 `credit_image_failure.dart` 中函数未定义或文件不存在。
- [ ] **Step 3: 写最小实现**
  使用 `HttpExceptionWithStatus.statusCode`，只接受 404 和 410；未知错误不隐藏。
- [ ] **Step 4: 跑测试确认通过**
  使用同一命令，期望全部通过。
- [ ] **Step 5: 接入详情页并提交**
  `errorWidget` 只在策略返回 `true` 时加入 `_failedCreditImages`，其他错误只保留当前演员卡片，不调用 `setState` 过滤。

## Task 2: 修正 Emby/Jellyfin 演员图片 URL

**Files：**
- Modify: `lib/services/media_server_service.dart:1253-1259`
- Modify: `test/media_server_auth_cache_test.dart`

**Interfaces：**
- Existing: `EmbyService.getItemDetails(String itemId)` 返回 `MediaItem.people`。
- Existing: `EmbyService.imageHeaders` 和 `JellyfinService.imageHeaders` 返回图片请求认证头。

- [ ] **Step 1: 写失败测试**
  通过 Dio `HttpClientAdapter` 返回包含空 `PrimaryImageTag` 和带特殊字符 Tag 的 People 数据，断言空 Tag 不生成 `ImageUrl`，有效 Tag 生成 `/Persons/{id}/Images/Primary` 并保留 URL 查询参数；断言 Emby/Jellyfin 图片头包含对应 Token。
- [ ] **Step 2: 跑测试确认失败**
  命令：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; D:\Android\flutter\bin\flutter.bat test test/media_server_auth_cache_test.dart`
  期望：空 Tag 断言失败，证明当前解析会生成无效 URL。
- [ ] **Step 3: 写最小实现**
  对 `PrimaryImageTag` 调用 `trim()`，非空时才构造 URL；使用 `Uri.encodeComponent` 编码人员 ID、Token 和 Tag。
- [ ] **Step 4: 跑测试确认通过**
  使用同一命令，期望全部通过。
- [ ] **Step 5: 提交**
  `git add lib/services/media_server_service.dart test/media_server_auth_cache_test.dart && git commit -m "fix: 防止演员图片认证失败时被误删"`

## Task 3: 全量验证

**Files：**
- Verify: `lib/screens/detail/detail_screen.dart`
- Verify: `lib/screens/detail/credit_image_failure.dart`
- Verify: `lib/services/media_server_service.dart`
- Verify: `test/credit_image_failure_test.dart`
- Verify: `test/media_server_auth_cache_test.dart`

- [ ] **Step 1: 运行定向详情测试**
  `D:\Android\flutter\bin\flutter.bat test test/detail_screen_test.dart`
- [ ] **Step 2: 运行全量测试**
  `$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; D:\Android\flutter\bin\flutter.bat test`
- [ ] **Step 3: 运行静态检查**
  `$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'; D:\Android\flutter\bin\flutter.bat analyze`
- [ ] **Step 4: 核对 diff**
  确认只包含演员图片策略、URL 解析、测试和本计划文件。

## 计划自查

- [x] spec 每条需求都能指向一个任务。
- [x] 全文无占位符。
- [x] 后置任务引用的函数名和文件路径与前置任务一致。
