package com.fieldcheck.field_check

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Environment
import android.content.ContentValues
import android.provider.MediaStore
import android.os.Build
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fieldcheck.field_check/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        try {
                            val fileName = call.argument<String>("fileName")
                            val fileBytes = call.argument<ByteArray>("fileBytes")
                            
                            if (fileName == null || fileBytes == null) {
                                result.error("INVALID_ARGS", "fileName and fileBytes are required", null)
                                return@setMethodCallHandler
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                // Use MediaStore for Android 10+
                                saveFileViaMediaStore(fileName, fileBytes, result)
                            } else {
                                // Use direct file write for older Android versions
                                saveFileDirectly(fileName, fileBytes, result)
                            }
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", "Failed to save file", e.message)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveFileViaMediaStore(fileName: String, fileBytes: ByteArray, result: MethodChannel.Result) {
        try {
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, getMimeType(fileName))
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)

            if (uri != null) {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    outputStream.write(fileBytes)
                    outputStream.flush()
                }

                contentValues.clear()
                contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, contentValues, null, null)

                // Get the actual file path for display
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val filePath = File(downloadsDir, fileName).absolutePath

                result.success(mapOf(
                    "path" to filePath,
                    "size" to fileBytes.size.toLong()
                ))
            } else {
                result.error("SAVE_ERROR", "Failed to create file in MediaStore", null)
            }
        } catch (e: Exception) {
            result.error("SAVE_ERROR", "MediaStore save failed: ${e.message}", null)
        }
    }

    private fun saveFileDirectly(fileName: String, fileBytes: ByteArray, result: MethodChannel.Result) {
        try {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }

            val file = File(downloadsDir, fileName)
            file.writeBytes(fileBytes)

            result.success(mapOf(
                "path" to file.absolutePath,
                "size" to file.length()
            ))
        } catch (e: Exception) {
            result.error("SAVE_ERROR", "Direct save failed: ${e.message}", null)
        }
    }

    private fun getMimeType(fileName: String): String {
        return when {
            fileName.endsWith(".pdf") -> "application/pdf"
            fileName.endsWith(".xlsx") -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            fileName.endsWith(".csv") -> "text/csv"
            else -> "application/octet-stream"
        }
    }
}
