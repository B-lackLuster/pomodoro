package com.tomatoclock.pomodoro

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        // 前台服务通过静态引用回传按钮点击（单 Activity 应用安全）
        @JvmStatic
        var channel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pomodoro/android_service"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService", "updateNotification", "stopService" -> {
                        try {
                            val svc = Intent(this@MainActivity, TimerForegroundService::class.java)
                            when (call.method) {
                                "startService" -> {
                                    svc.action = TimerForegroundService.ACTION_START
                                    svc.putExtra(TimerForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                                    svc.putExtra(TimerForegroundService.EXTRA_TEXT, call.argument<String>("text"))
                                    svc.putExtra(TimerForegroundService.EXTRA_RUNNING, call.argument<Boolean>("running") ?: true)
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        startForegroundService(svc)
                                    } else {
                                        startService(svc)
                                    }
                                }
                                "updateNotification" -> {
                                    svc.action = TimerForegroundService.ACTION_UPDATE
                                    svc.putExtra(TimerForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                                    svc.putExtra(TimerForegroundService.EXTRA_TEXT, call.argument<String>("text"))
                                    svc.putExtra(TimerForegroundService.EXTRA_RUNNING, call.argument<Boolean>("running") ?: true)
                                    startService(svc)
                                }
                                "stopService" -> {
                                    svc.action = TimerForegroundService.ACTION_STOP
                                    startService(svc)
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 从通知点击回到应用
        setIntent(intent)
    }
}
