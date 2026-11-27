package com.gymapp.android.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Profile photos live in the app's private files directory. Only the file name
 * is stored on the profile row, matching the iOS PhotoStore contract.
 */
object ProfilePhotoStore {
    private const val DIRECTORY = "profile-photos"
    private const val MAX_EDGE = 1024

    private fun directory(context: Context): File =
        File(context.filesDir, DIRECTORY).apply { mkdirs() }

    fun file(context: Context, name: String): File = File(directory(context), name)

    fun load(context: Context, name: String?): Bitmap? {
        val fileName = name ?: return null
        val target = file(context, fileName)
        if (!target.exists()) return null
        return runCatching { BitmapFactory.decodeFile(target.absolutePath) }.getOrNull()
    }

    fun save(context: Context, uri: Uri, replacing: String?): String {
        val raw = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IOException("That image could not be read.")
        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size)
            ?: throw IOException("That image could not be read.")
        val longest = maxOf(decoded.width, decoded.height)
        val scaled = if (longest > MAX_EDGE) {
            val ratio = MAX_EDGE.toFloat() / longest.toFloat()
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * ratio).toInt().coerceAtLeast(1),
                (decoded.height * ratio).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            decoded
        }
        val name = "profile-${System.currentTimeMillis()}.jpg"
        FileOutputStream(file(context, name)).use { output ->
            if (!scaled.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                throw IOException("That image could not be saved.")
            }
        }
        if (scaled !== decoded) scaled.recycle()
        decoded.recycle()
        replacing?.takeIf { it != name }?.let { file(context, it).delete() }
        return name
    }

    fun delete(context: Context, name: String?) {
        name?.let { file(context, it).delete() }
    }
}
