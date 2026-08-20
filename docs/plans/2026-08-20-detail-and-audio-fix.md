# 详情页、演员头像与 4K 音频修复

## 目标

修正影视详情页布局，使海报、背景、元数据、操作按钮和演员区域符合参考图；修正 Emby/Jellyfin 演员图片的认证请求；确认 Android ExoPlayer 使用可用的 FFmpeg 音频渲染器，避免 4K 片源只有画面；完成测试、分析、APK 构建并安装到设备 `400DB303XH00000`。

## 实施步骤

1. 检查 `lib/screens/detail/detail_screen.dart`、`lib/widgets/server_image.dart`、`lib/services/media_server_service.dart` 的现有实现，确认演员图片 URL、请求头、缓存键和失败回调的实际行为；检查 `ExoFFmpegPlayer.kt`、`ExoFFmpegPlugin.kt`、`exo_ffmpeg_engine.dart`、Gradle 依赖和 `jniLibs`，确认音频 codec 与 FFmpeg renderer 的连接点。
2. 针对已确认的行为缺口添加最小回归测试：演员图片 URL/请求头保留认证信息且失败回调不误隐藏；音频播放器启用目标 renderer 或正确选择可播放音轨；详情页不输出歌曲语义。运行清代理后的定向测试，确认测试因缺少实现而失败。
3. 修改最少代码使新增测试通过：修正图片 URL 和 headers 传递/缓存处理；按现有 Media3 版本注册 FFmpeg 音频 renderer 或修正等价的音频解码配置；按参考图调整详情页结构和视觉文案，保留影视操作入口并移除下载、预告片和歌曲语义。
4. 运行定向测试和全量 `flutter test`，确认新增回归测试及存量测试全部通过；运行 `flutter analyze`，确认无新增 error。
5. 构建 debug APK，使用 `adb -s 400DB303XH00000 install -r` 安装到平板，并报告构建与安装结果。

## 验证命令

```powershell
$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'
& 'D:\Android\flutter\bin\flutter.bat' test
& 'D:\Android\flutter\bin\flutter.bat' analyze
& 'D:\Android\flutter\bin\flutter.bat' build apk --debug
& 'C:\Users\hongbo\AppData\Local\Android\Sdk\platform-tools\adb.exe' -s 400DB303XH00000 install -r 'D:\LAN-Player\build\app\outputs\flutter-apk\app-debug.apk'
```
