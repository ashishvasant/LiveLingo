package com.example.talking_learning

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import kotlin.math.max

class LiveAudioStreamHandler(
    private val context: Context
) : EventChannel.StreamHandler {
    private val tag = "LiveAudioStream"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var emittedChunkCount = 0L

    @Volatile
    private var isRecording = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.d(tag, "EventChannel listener attached.")
    }

    override fun onCancel(arguments: Any?) {
        Log.d(tag, "EventChannel listener cancelled.")
        dispose()
    }

    fun startRecording(result: MethodChannel.Result) {
        if (isRecording) {
            Log.d(tag, "startRecording ignored because recording is already active.")
            result.success(null)
            return
        }
        if (
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(tag, "Microphone permission missing when startRecording was called.")
            result.error("permission_denied", "Microphone permission not granted.", null)
            return
        }
        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufferSize <= 0) {
            Log.e(tag, "AudioRecord min buffer size was invalid: $minBufferSize")
            result.error("audio_config", "Unable to initialize AudioRecord buffer.", null)
            return
        }
        val targetFrameBytes = FRAME_SAMPLES * BYTES_PER_SAMPLE
        val bufferSize = max(minBufferSize, targetFrameBytes * 4)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            Log.e(tag, "AudioRecord failed to initialize.")
            result.error("audio_init", "AudioRecord failed to initialize.", null)
            return
        }
        audioRecord = recorder
        isRecording = true
        emittedChunkCount = 0L
        Log.d(tag, "AudioRecord starting with bufferSize=$bufferSize frameBytes=$targetFrameBytes")
        recorder.startRecording()
        recordingThread = thread(
            start = true,
            isDaemon = true,
            name = "live-audio-stream"
        ) {
            streamAudio(recorder, targetFrameBytes)
        }
        result.success(null)
    }

    fun stopRecording(result: MethodChannel.Result) {
        Log.d(tag, "stopRecording called from Flutter.")
        stopInternal()
        result.success(null)
    }

    private fun streamAudio(recorder: AudioRecord, frameBytes: Int) {
        val buffer = ByteArray(frameBytes)
        try {
            while (isRecording) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read > 0) {
                    val payload = if (read == buffer.size) {
                        buffer.clone()
                    } else {
                        buffer.copyOf(read)
                    }
                    emittedChunkCount += 1
                    if (emittedChunkCount == 1L || emittedChunkCount % 25L == 0L) {
                        Log.d(tag, "Read mic chunk #$emittedChunkCount size=$read eventSink=${eventSink != null}")
                    }
                    mainHandler.post {
                        val sink = eventSink ?: return@post
                        if (!isRecording) {
                            return@post
                        }
                        sink.success(payload)
                    }
                    continue
                }
                if (read == 0) {
                    continue
                }
                mainHandler.post {
                    eventSink?.error(
                        "audio_read_error",
                        "AudioRecord read failed with code $read",
                        null
                    )
                }
                break
            }
        } catch (error: Exception) {
            mainHandler.post {
                eventSink?.error(
                    "audio_stream_error",
                    error.message ?: "Audio streaming failed.",
                    null
                )
            }
        } finally {
            Log.d(tag, "Audio streaming loop finished.")
            stopInternal()
        }
    }

    fun dispose() {
        Log.d(tag, "Disposing LiveAudioStreamHandler.")
        eventSink = null
        mainHandler.removeCallbacksAndMessages(null)
        stopInternal()
    }

    private fun stopInternal() {
        if (!isRecording && audioRecord == null && recordingThread == null) {
            return
        }
        Log.d(tag, "Stopping audio capture. emittedChunkCount=$emittedChunkCount")
        isRecording = false
        val recorder = audioRecord
        audioRecord = null
        try {
            recorder?.stop()
        } catch (_: IllegalStateException) {
        }
        recorder?.release()
        recordingThread?.interrupt()
        recordingThread = null
    }

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val FRAME_SAMPLES = 1600
        private const val BYTES_PER_SAMPLE = 2
    }
}
