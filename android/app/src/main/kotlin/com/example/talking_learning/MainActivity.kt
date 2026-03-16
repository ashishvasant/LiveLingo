package com.example.talking_learning

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val foregroundChannel = "talking_learning/foreground_service"
    private val audioMethodChannel = "talking_learning/audio_stream"
    private val audioEventChannel = "talking_learning/audio_stream/events"
    private var liveAudioStreamHandler: LiveAudioStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liveAudioStreamHandler?.dispose()
        val handler = LiveAudioStreamHandler(this)
        liveAudioStreamHandler = handler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            foregroundChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val mode = call.argument<String>("mode") ?: "Guide"
                    val muted = call.argument<Boolean>("muted") ?: false
                    val intent = Intent(this, LiveForegroundService::class.java).apply {
                        action = LiveForegroundService.ACTION_START
                        putExtra(LiveForegroundService.EXTRA_MODE, mode)
                        putExtra(LiveForegroundService.EXTRA_MUTED, muted)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForeground" -> {
                    val intent = Intent(this, LiveForegroundService::class.java).apply {
                        action = LiveForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            audioMethodChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> handler.startRecording(result)
                "stopRecording" -> handler.stopRecording(result)
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            audioEventChannel
        ).setStreamHandler(handler)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        liveAudioStreamHandler?.dispose()
        liveAudioStreamHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        liveAudioStreamHandler?.dispose()
        liveAudioStreamHandler = null
        super.onDestroy()
    }
}
