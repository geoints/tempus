package io.github.geoints.tempus

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal object FilmProcessor {
    fun develop(input: File, output: File, profile: List<Double>, strength: Double) {
        require(profile.size == 8)
        val bitmap = decode(input)
        try {
            applyLook(bitmap, profile, strength.coerceIn(0.0, 1.0).toFloat())
            output.outputStream().buffered().use { stream ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 96, stream))
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun decode(file: File): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, _, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.isMutableRequired = true
                decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            }
        }

        val original = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inMutable = true
        }) ?: throw IOException("Unsupported image")
        val orientation = ExifInterface(file.path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return original
        }
        val oriented = Bitmap.createBitmap(original, 0, 0, original.width, original.height, matrix, true)
        if (oriented !== original) original.recycle()
        if (oriented.isMutable) return oriented
        return requireNotNull(oriented.copy(Bitmap.Config.ARGB_8888, true)).also { oriented.recycle() }
    }

    private fun applyLook(bitmap: Bitmap, profile: List<Double>, strength: Float) {
        val (saturation, warmth, contrast, fade) = profile.map(Double::toFloat)
        val grain = profile[4].toFloat() * strength
        val vignette = profile[5].toFloat() * strength
        val highlight = profile[6].toFloat() * strength
        val shadow = profile[7].toFloat() * strength
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width)
        val average = sampleBrightness(bitmap, pixels)
        val lift = max(0f, (115f - average) * .10f)
        val tone = FloatArray(256) { sample ->
            val level = sample / 255f
            val midtones = 4 * level * (1 - level)
            val darkMidtones = midtones * (1 - level)
            sample +
                lift * darkMidtones * strength +
                (sample - 127.5f) * contrast * midtones * strength +
                fade * (1 - level) * (1 - level) * strength +
                shadow * darkMidtones -
                highlight * level * level
        }
        val xDistance = FloatArray(width) { x ->
            val normalized = (x / max(1f, width - 1f)) * 2 - 1
            normalized * normalized
        }
        val sat = 1 + (saturation - 1) * strength
        val warm = warmth * strength
        var random = 13579
        for (y in 0 until height) {
            bitmap.getPixels(pixels, 0, width, 0, y, width, 1)
            val dy = (y / max(1f, height - 1f)) * 2 - 1
            for (x in 0 until width) {
                val pixel = pixels[x]
                val red = (pixel shr 16) and 255
                val green = (pixel shr 8) and 255
                val blue = pixel and 255
                val luminance = (red * 54 + green * 183 + blue * 19) shr 8
                val base = tone[luminance]
                random = random * 1664525 + 1013904223
                val noise = (((random ushr 24) - 127) / 128f) * grain
                val edges = max(0f, (xDistance[x] + dy * dy - .35f) * .60f)
                val shading = 1 - vignette * min(1f, edges)
                val tint = 1 - (luminance / 255f) * .58f
                val r = byte((base + (red - luminance) * sat + warm * tint + noise) * shading)
                val g = byte((base + (green - luminance) * sat + warm * .23f * tint + noise) * shading)
                val b = byte((base + (blue - luminance) * sat - warm * .88f * tint + noise) * shading)
                pixels[x] = (255 shl 24) or (r shl 16) or (g shl 8) or b
            }
            bitmap.setPixels(pixels, 0, width, 0, y, width, 1)
        }
    }

    private fun sampleBrightness(bitmap: Bitmap, pixels: IntArray): Float {
        var sum = 0L
        var count = 0
        for (y in 0 until bitmap.height step max(1, bitmap.height / 64)) {
            bitmap.getPixels(pixels, 0, bitmap.width, 0, y, bitmap.width, 1)
            for (x in pixels.indices step max(1, pixels.size / 64)) {
                val pixel = pixels[x]
                sum += (((pixel shr 16) and 255) * 54 +
                    ((pixel shr 8) and 255) * 183 + (pixel and 255) * 19) shr 8
                count++
            }
        }
        return sum.toFloat() / count
    }

    private fun byte(value: Float) = value.roundToInt().coerceIn(0, 255)
}
