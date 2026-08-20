# 首页服务器控件与认证缓存修复计划

**Goal：** 移除首页左上角服务器名称对内容的遮挡，并避免 Emby/Jellyfin 服务实例重建后重复登录。

**Architecture：** 首页复用现有 `ServerSelectorChip` 菜单，但提供图标紧凑显示模式，服务器名称只在下拉菜单中展示。媒体服务在同一地址、账号和密码配置下共享成功认证结果；401 仍通过现有重新认证流程刷新 token。

**Tech Stack：** Flutter 3.x、Dart、Dio、flutter_test。

---

## Task 1: 首页服务器控件

**Files：** `lib/widgets/server_selector_chip.dart`、`lib/screens/home/home_screen.dart`、`test/server_selector_chip_overflow_test.dart`

- [x] 写紧凑控件测试并确认当前构造参数缺失导致测试失败。
- [x] 增加紧凑图标模式，首页使用该模式，保留下拉切换能力。
- [x] 运行控件测试和首页相关测试。

## Task 2: Emby/Jellyfin 认证缓存

**Files：** `lib/services/media_server_service.dart`、`test/media_server_auth_cache_test.dart`

- [x] 写服务实例重建后的重复登录测试并确认当前测试失败。
- [x] 缓存认证成功后的 token 和 userId，构造新服务时复用缓存。
- [x] 保持 401 强制重新认证行为，并运行认证和全量测试。

## Task 3: 交付验证

- [x] `flutter analyze` 无新增 error。
- [x] `flutter build apk --debug` 成功。
- [x] 安装并启动默认设备 `iPA2375`。
