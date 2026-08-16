package com.lanplayer

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lanplayer/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册 ExoPlayer + FFmpeg 音频扩展插件
        flutterEngine.plugins.add(ExoFFmpegPlugin())
        // 注册 libass ASS/SSA 字幕渲染插件
        flutterEngine.plugins.add(LibassPlugin())

        // 注册设备类型检测 Channel（TV/手机）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getUiMode" -> result.success(getUiMode())
                    "getApplicationDocumentsDirectory" -> result.success(getApplicationDocumentsDirectory())
                    else -> result.notImplemented()
                }
            }
    }

    /// 获取当前设备的 UI Mode
    /// 返回值：leanback（TV）/ normal / undefined
    private fun getUiMode(): String {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager
        val currentModeType = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return when {
            // 系统判定为 TV 类型（插入到 Leanback 设备）
            currentModeType == Configuration.UI_MODE_TYPE_TELEVISION -> "leanback"
            // UiModeManager 显式进入 TV 模式
            uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION -> "leanback"
            else -> "normal"
        }
    }

    /// 获取应用文档目录路径（绕过 path_provider 的 jni 依赖）
    private fun getApplicationDocumentsDirectory(): String {
        return filesDir.absolutePath
    }
}
