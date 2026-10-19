package org.otzaria.otzaria

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.zip.GZIPInputStream

/**
 * סיבות יציאה קודמות של התהליך (API 30+), כדי לדווח על ANR בהפעלה הבאה.
 * קריאת ההיסטוריה של המערכת בלבד — אין כאן עלות בזמן ריצה.
 */
class AppExitInfoChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAnrExits" -> {
                    val sinceMs = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                    executor.execute {
                        val value = try {
                            readAnrExits(sinceMs)
                        } catch (e: Throwable) {
                            EMPTY
                        }
                        mainHandler.post { result.success(value) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun readAnrExits(sinceMs: Long): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return EMPTY
        return readAnrExitsApi30(sinceMs)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun readAnrExitsApi30(sinceMs: Long): Map<String, Any?> {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return EMPTY
        val records = manager.getHistoricalProcessExitReasons(context.packageName, 0, 0)
        val newestAny = records.maxOfOrNull { it.timestamp }
        val exits = records
            .filter { it.reason == ApplicationExitInfo.REASON_ANR && it.timestamp > sinceMs }
            .sortedByDescending { it.timestamp }
            .take(MAX_EXITS)
            .map { info ->
                mapOf(
                    "timestamp" to info.timestamp,
                    "pid" to info.pid,
                    "description" to info.description,
                    "importance" to info.importance,
                    "processName" to info.processName,
                    "mainThreadTrace" to runCatching { readMainThreadTrace(info) }.getOrNull(),
                )
            }
        return mapOf("exits" to exits, "newestAnyTimestamp" to newestAny)
    }

    /** קטע ה-"main" מקובץ ה-traces של ה-ANR: משורת `"main"` עד השורה הריקה הבאה. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun readMainThreadTrace(info: ApplicationExitInfo): String? {
        val raw = info.traceInputStream ?: return null
        return plainText(raw).bufferedReader().use { reader ->
            val section = StringBuilder()
            var inMain = false
            while (true) {
                val line = reader.readLine() ?: break
                if (!inMain) {
                    inMain = line.startsWith("\"main\"")
                    if (!inMain) continue
                } else if (line.isBlank()) {
                    break
                }
                if (section.length + line.length + 1 > MAX_TRACE_CHARS) break
                section.append(line).append('\n')
            }
            section.toString().ifEmpty { null }
        }
    }

    // המערכת כבר פורסת את ה-gzip, אבל אם יגיע דחוס — נפרוס כאן.
    private fun plainText(raw: InputStream): InputStream {
        val stream = BufferedInputStream(raw)
        stream.mark(2)
        val first = stream.read()
        val second = stream.read()
        stream.reset()
        return if (first == 0x1f && second == 0x8b) GZIPInputStream(stream) else stream
    }

    companion object {
        private const val CHANNEL = "otzaria/app_exit_info"
        private const val MAX_EXITS = 5
        private const val MAX_TRACE_CHARS = 32 * 1024
        private val EMPTY: Map<String, Any?> =
            mapOf("exits" to emptyList<Any>(), "newestAnyTimestamp" to null)
    }
}
