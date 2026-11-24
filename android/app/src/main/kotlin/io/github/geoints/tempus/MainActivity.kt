package io.github.geoints.tempus

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger, "tempus/photography", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "develop" -> {
                        val input = File(requireNotNull(call.argument<String>("source")))
                        val profile = requireNotNull(call.argument<List<Double>>("profile"))
                        val strength = requireNotNull(call.argument<Double>("strength"))
                        val output = File.createTempFile("tempus-film-", ".jpg", cacheDir)
                        try {
                            FilmProcessor.develop(input, output, profile, strength)
                            result.success(output.path)
                        } catch (error: Exception) {
                            output.delete()
                            throw error
                        } catch (error: OutOfMemoryError) {
                            output.delete()
                            throw error
                        }
                    }
                    "saveToGallery" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(false)
                        } else {
                            saveToGallery(
                                requireNotNull(call.argument<String>("name")),
                                requireNotNull(call.argument<ByteArray>("image")),
                            )
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("TEMPUS_PHOTO", error.javaClass.simpleName, null)
            } catch (error: OutOfMemoryError) {
                result.error("TEMPUS_PHOTO_MEMORY", "Image processing ran out of memory", null)
            }
        }
    }

    private fun saveToGallery(name: String, image: ByteArray) {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/TEMPUS")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not open the photo library")
        try {
            val output = contentResolver.openOutputStream(uri) ?: throw IOException("Could not open image")
            output.use { it.write(image) }
            val published = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            contentResolver.update(uri, published, null, null)
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }
}
