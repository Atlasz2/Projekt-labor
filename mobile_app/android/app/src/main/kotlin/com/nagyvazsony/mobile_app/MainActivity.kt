package com.nagyvazsony.mobile_app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Fájl mentése a nyilvános Letöltések mappába (MediaStore, Android 10+:
        // engedély nélkül), illetve a mentett fájl megnyitása.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nagyvazsony/downloads")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            val name = call.argument<String>("name")!!
                            val mime = call.argument<String>("mime")!!
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val resolver = applicationContext.contentResolver
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, name)
                                put(MediaStore.Downloads.MIME_TYPE, mime)
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = resolver.insert(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                            ) ?: throw IllegalStateException("MediaStore insert failed")
                            resolver.openOutputStream(uri)!!.use { it.write(bytes) }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                    "open" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    Uri.parse(call.argument<String>("uri")!!),
                                    call.argument<String>("mime")!!
                                )
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
