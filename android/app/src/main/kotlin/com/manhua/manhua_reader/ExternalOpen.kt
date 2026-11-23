package com.manhua.manhua_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executor

internal class ExternalOpen(
    private val activity: Activity,
    private val executor: Executor,
) {
    private val queue = ArrayDeque<Map<String, Any>>()
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "manhua/external_open").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeNext" -> result.success(queue.removeFirstOrNull())
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        queue.forEach { request -> (request["path"] as? String)?.let { File(it).delete() } }
        queue.clear()
    }

    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "content" && uri.scheme != "file") return
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val mime = intent.type

        // Stage granted content while the Android activity can still read it.
        // 在 Android Activity 仍持有读取授权时暂存内容。
        executor.execute {
            val request = stage(uri, mime)
            activity.runOnUiThread {
                if (activity.isDestroyed || channel == null) {
                    (request["path"] as? String)?.let { File(it).delete() }
                } else {
                    queue.addLast(request)
                    channel?.invokeMethod("filesAvailable", null)
                }
            }
        }
    }

    private fun stage(uri: Uri, mime: String?): Map<String, Any> {
        val resolver = activity.contentResolver
        var name = uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "打开的文件"
        var staged: File? = null
        try {
            if (uri.scheme == "content") {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            name = cursor.getString(0)?.substringAfterLast('/')
                                ?.substringAfterLast('\\')?.takeIf { it.isNotBlank() } ?: name
                        }
                    }
            }
            var extension = name.substringAfterLast('.', "").lowercase()
            if (extension !in supportedExtensions) {
                extension = mimeExtensions[mime] ?: mimeExtensions[resolver.getType(uri)]
                    ?: return mapOf("name" to name, "error" to "仅支持 PDF、MOBI、CBZ 格式")
                name += ".$extension"
            }

            val directory = File(activity.cacheDir, "external_open").apply { mkdirs() }
            val target = File.createTempFile("book-", ".$extension", directory)
            staged = target
            val input = resolver.openInputStream(uri)
                ?: throw IllegalStateException("Cannot open document")
            input.use { source -> target.outputStream().use { source.copyTo(it) } }
            return mapOf("name" to name, "path" to target.absolutePath, "temporary" to true)
        } catch (_: Exception) {
            staged?.delete()
            return mapOf("name" to name, "error" to "无法读取文件，请重新选择")
        }
    }

    companion object {
        private val supportedExtensions = setOf("pdf", "mobi", "cbz")
        private val mimeExtensions = mapOf(
            "application/pdf" to "pdf",
            "application/x-mobipocket-ebook" to "mobi",
            "application/x-mobi" to "mobi",
            "application/vnd.comicbook+zip" to "cbz",
            "application/x-cbz" to "cbz",
        )
    }
}
