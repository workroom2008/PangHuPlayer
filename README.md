# LAN Player

一个基于 Flutter 的个人媒体播放器，支持 **手机（Android）** 与 **Android TV** 双端，接入 Emby / Jellyfin / 飞牛（FnOS）等媒体服务器，本地网络内直接播放你的影视资源。

> 纯局域网直连播放，无中转、无云同步——你的媒体只属于你自己的服务器。

## ✨ 功能特性

### 媒体服务器
- 支持 **Emby / Jellyfin / 飞牛 FnOS** 三套协议（飞牛走官方 API 签名，自动降级到 Jellyfin 认证）
- **合集（BoxSet）**：点开合集直接列出内部影视，不再误入详情页
- **分页拉全量**：大媒体库（几百部）不再只显示第一页 50 条
- **剧集排序修正**：按（季, 集）排序，乱序的服务器也不会把"第 1 集"播成"第 13 集"
- 搜索、收藏、日历视图、资源发现（MoviePilot 订阅 / 资源搜索）

### 播放内核
- **ExoPlayer（Media3）**：HLS / DASH / 直连流，4K HDR10 直通，FFmpeg 音频软解兜底
- **MPV（media_kit）**：高性能内核，支持杜比视界 / HDR 元数据
- 播放中一键切换内核（Exo ⇄ MPV）
- 自动连播下一集、片头/片尾跳过（带脏数据防御，异常章节直接丢弃）

### 字幕
- **内嵌字幕原生渲染**：ExoPlayer / MPV 直接从视频流读取，不依赖服务器按需提取（慢 NAS 也能秒出）
- **服务端外挂字幕**：下载到本地缓存、超时自动重试、播放启动即后台预取"默认 + 中文 + 英文"三条，切换秒开
- **在线字幕搜索**（OpenSubtitles 等）
- **libass 渲染**：ASS 特效字幕（位置、样式、动画）完整支持
- 编码兼容：GBK / GB18030 中文字幕（`fast_gbk`），SRT / SSA / VTT 解析
- 字幕样式自定义：字号、颜色、描边、阴影、位置实时预览

### 播放体验
- 音量 / 亮度 **与系统联动**（应用内调的就是系统媒体音量，硬件按键与 HUD 完全对应）并持久化记忆
- 双击左/右快进快退、双击中间播放/暂停、上下滑动调音量/亮度
- 防误触：面板打开时隐藏控制簇、锁定按钮原地锁定/解锁
- 毛玻璃 UI：右侧滑入面板、弹幕徽章、倍速步进等

### 弹幕
- 弹幕加载与渲染（文件名匹配第三方弹幕源），支持开关、样式

### Android TV
- Leanback 界面自动识别，手机 / TV 双入口同一 APK
- 遥控器焦点导航、二维码扫码配对、局域网配对服务器

## 🚀 构建

前置要求：

- Flutter SDK ≥ 3.0（含 Dart 3）
- Android SDK + **NDK / CMake**（`android/app/src/main/cpp` 原生构建）
- JDK 17

```bash
# 1. 安装依赖
flutter pub get

# 2. 构建 APK
flutter build apk --release

# 产物
# build/app/outputs/flutter-apk/app-release.apk   （手机 + TV 双端，自动识别设备类型）
```

> 说明：`android/build.gradle.kts` 会将 APK 重命名为 `tv-{type}.apk` 以区分构建来源；原生依赖（libass、libdartjni）已预编译进 `jniLibs`，一般无需自行编译。

## 📁 目录结构（简）

```
lib/
├── main.dart                 # 入口（自动识别 TV / 手机）
├── screens/                  # 手机端页面（首页/发现/库/播放器/设置…）
├── tv/                       # Android TV 端
├── player/                   # 播放内核抽象 + Exo/MPV 实现 + 弹幕 + 字幕
├── services/                 # 服务器/字幕/弹幕/TMDB/MoviePilot 服务
├── widgets/                  # 通用组件（毛玻璃/右滑面板/涟漪…）
├── models/  providers/  router/  database/  theme/  utils/
android/
└── app/src/main/
    ├── kotlin/…              # ExoPlayer 原生层（SurfaceView HDR、字幕叠加、FFmpeg 音频）
    └── cpp/                  # libass JNI 桥（lanplayer_jni）
```

## 📸 截图

截图待补充（可放入 `docs/screenshots/` 后在此引用）。

## ⚠️ 说明

- 本项目仅面向**个人 / 家庭局域网**使用，请勿用于公开传播他人版权内容。
- 代码中保留了飞牛官方 App 的 API 签名密钥（开源客户端通用做法），如在意可自行改为运行时注入。
