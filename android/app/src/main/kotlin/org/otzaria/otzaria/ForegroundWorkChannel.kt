package org.otzaria.otzaria

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** הפעלה ועצירה של [ForegroundWorkService] מ-Dart (`lib/core/foreground_work.dart`). */
class ForegroundWorkChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        ForegroundWorkService.timeoutListener = {
            mainHandler.post { channel.invokeMethod("timeout", null) }
        }
        ForegroundWorkService.startFailedListener = { reason ->
            mainHandler.post { channel.invokeMethod("startFailed", reason) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = ForegroundWorkService.intent(context)
                        .putExtra(ForegroundWorkService.EXTRA_TITLE, call.argument<String>("title"))
                        .putExtra(ForegroundWorkService.EXTRA_TEXT, call.argument<String>("text"))
                        .putExtra(
                            ForegroundWorkService.EXTRA_CHANNEL_NAME,
                            call.argument<String>("channelName"),
                        )
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(intent)
                        } else {
                            context.startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        // מרקע אסור להפעיל שירות חזית (API 31+).
                        result.error("start_failed", e.toString(), null)
                    }
                }

                "stop" -> {
                    requestStop()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    /** המנוע נסגר ⇒ העבודה ב-Dart מתה איתו, ואין טעם להשאיר את השירות. */
    fun dispose() {
        channel.setMethodCallHandler(null)
        ForegroundWorkService.timeoutListener = null
        ForegroundWorkService.startFailedListener = null
        requestStop()
    }

    private fun requestStop() {
        val stop = ForegroundWorkService.intent(context).setAction(ForegroundWorkService.ACTION_STOP)
        try {
            context.startService(stop)
        } catch (e: IllegalStateException) {
            // מרקע startService נחסם, ואז השירות כבר לא בחזית — עצירה ישירה בטוחה.
            context.stopService(ForegroundWorkService.intent(context))
        }
    }

    companion object {
        private const val CHANNEL = "otzaria/foreground_work"
    }
}
