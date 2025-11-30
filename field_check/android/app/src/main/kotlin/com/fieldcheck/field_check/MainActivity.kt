package com.fieldcheck.field_check

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Environment
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fieldcheck.field_check/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDownloadsDirectory" -> {
                        try {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            )
                            if (downloadsDir != null && !downloadsDir.exists()) {
                                downloadsDir.mkdirs()
                            }
                            result.success(downloadsDir?.absolutePath)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "Downloads directory not available", e.message)
                        }
                    }
                    "saveFile" -> {
                        try {
                            val fileName = call.argument<String>("fileName")
                            val fileBytes = call.argument<ByteArray>("fileBytes")
                            
                            if (fileName == null || fileBytes == null) {
                                result.error("INVALID_ARGS", "fileName and fileBytes are required", null)
                                return@setMethodCallHandler
                            }

                            val downloadsDir = Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            )
                            if (downloadsDir != null && !downloadsDir.exists()) {
                                downloadsDir.mkdirs()
                            }

                            val file = File(downloadsDir, fileName)
                            file.writeBytes(fileBytes)
                            
                            result.success(mapOf(
                                "path" to file.absolutePath,
                                "size" to file.length()
                            ))
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", "Failed to save file", e.message)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
