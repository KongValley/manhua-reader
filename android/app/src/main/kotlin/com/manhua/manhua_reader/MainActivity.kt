package com.manhua.manhua_reader

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private companion object {
        const val STATE_OPEN_KEY = "manhua.openKey"
    }

    private val channelName = "manhua/saf"
    private val pickDirectoryRequest = 7281
    private var pendingPick: MethodChannel.Result? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val externalOpen = ExternalOpen(this, ioExecutor)
    private var readerChannel: MethodChannel? = null
    private var volumeKeysEnabled = false
    private var handledOpenKey: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handledOpenKey = savedInstanceState?.getString(STATE_OPEN_KEY)
        val key = openKey(intent)
        // A restored activity can still receive a brand-new VIEW intent after
        // the process was killed; only skip intents this activity already saw.
        // 被系统重建的 Activity 仍可能收到全新的 VIEW Intent；只跳过已经处理过的
        // 同一个 Intent。
        if (key != null && key != handledOpenKey) {
            externalOpen.receive(intent)
            handledOpenKey = key
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        externalOpen.receive(intent)
        handledOpenKey = openKey(intent) ?: handledOpenKey
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        handledOpenKey?.let { outState.putString(STATE_OPEN_KEY, it) }
    }

    private fun openKey(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW) {
            intent.toUri(Intent.URI_INTENT_SCHEME)
        } else {
            null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        externalOpen.attach(messenger)
        PdfPasswordStore.register(applicationContext, messenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> pickDirectory(result)
                    "listBooks" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing directory uri", null)
                        } else {
                            listBooks(Uri.parse(uri), result)
                        }
                    }
                    "directoryName" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing directory uri", null)
                        } else {
                            directoryName(Uri.parse(uri), result)
                        }
                    }
                    "listImages" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing directory uri", null)
                        } else {
                            listImages(Uri.parse(uri), result)
                        }
                    }
                    "readDocument" -> {
                        val uri = call.argument<String>("uri")
                        val maxBytes = call.argument<Int>("maxBytes")
                            ?: 64 * 1024 * 1024
                        if (uri == null) {
                            result.error("bad_args", "Missing document uri", null)
                        } else {
                            readDocument(Uri.parse(uri), maxBytes, result)
                        }
                    }
                    "readDocumentPrefix" -> {
                        val uri = call.argument<String>("uri")
                        val maxBytes = call.argument<Int>("maxBytes")
                            ?: 128 * 1024
                        if (uri == null) {
                            result.error("bad_args", "Missing document uri", null)
                        } else {
                            readDocumentPrefix(Uri.parse(uri), maxBytes, result)
                        }
                    }
                    "releaseTree" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing directory uri", null)
                        } else {
                            releaseTree(Uri.parse(uri), result)
                        }
                    }
                    "copyToCache" -> {
                        val uri = call.argument<String>("uri")
                        val name = call.argument<String>("name") ?: "book"
                        if (uri == null) {
                            result.error("bad_args", "Missing document uri", null)
                        } else {
                            copyToCache(Uri.parse(uri), name, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "manhua/screen")
            .setMethodCallHandler { call, result ->
                if (call.method != "setKeepScreenOn") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val enabled = call.arguments as? Boolean ?: false
                runOnUiThread {
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
            }

        readerChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "manhua/reader").also {
                it.setMethodCallHandler { call, result ->
                    if (call.method == "setVolumeKeysEnabled") {
                        volumeKeysEnabled = call.arguments as? Boolean ?: false
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeysEnabled &&
            event.action == KeyEvent.ACTION_DOWN &&
            event.repeatCount == 0 &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_UP)
        ) {
            val method = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                "nextPage"
            } else {
                "previousPage"
            }
            readerChannel?.invokeMethod(method, null)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A directory picker is already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, pickDirectoryRequest)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickDirectoryRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // Some providers only grant access for the current session.
            // 部分文件提供方只授予当前会话的访问权限。
        }
        result.success(uri.toString())
    }

    private fun directoryName(treeUri: Uri, result: MethodChannel.Result) {
        ioExecutor.execute {
            var name = "导入的文件夹"
            try {
                val rootId = DocumentsContract.getTreeDocumentId(treeUri)
                val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
                contentResolver.query(
                    rootUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        name = cursor.getString(0)?.takeIf { it.isNotBlank() } ?: name
                    }
                }
                runOnUiThread { result.success(name) }
            } catch (error: Exception) {
                runOnUiThread { result.success(name) }
            }
        }
    }

    private fun listImages(treeUri: Uri, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val rootId = DocumentsContract.getTreeDocumentId(treeUri)
                val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
                val images = mutableListOf<Map<String, Any?>>()
                walkImages(treeUri, rootUri, "", 0, images)
                runOnUiThread { result.success(images) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "saf_images_failed",
                        error.message ?: "Cannot list images",
                        null,
                    )
                }
            }
        }
    }

    private fun walkImages(
        treeUri: Uri,
        documentUri: Uri,
        relativeDir: String,
        depth: Int,
        out: MutableList<Map<String, Any?>>,
    ) {
        if (depth > 24 || out.size >= 2000) return
        val documentId = DocumentsContract.getDocumentId(documentUri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext() && out.size < 2000) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                if (name.startsWith(".") || name.equals("__MACOSX", ignoreCase = true)) {
                    continue
                }
                val mime = cursor.getString(2) ?: ""
                val relativePath =
                    if (relativeDir.isEmpty()) name else "$relativeDir/$name"
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val childUri =
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    walkImages(treeUri, childUri, relativePath, depth + 1, out)
                    continue
                }
                if (!isImageName(name)) continue
                val size = if (cursor.isNull(3)) null else cursor.getLong(3)
                val childUri =
                    DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                try {
                    contentResolver.openInputStream(childUri)?.use { stream ->
                        BitmapFactory.decodeStream(stream, null, options)
                    }
                } catch (_: Exception) {
                    // Dimensions are optional; the reader falls back to an
                    // aspect ratio and decodes the page later.
                    // 尺寸仅用于排版，读取失败时阅读器会回退比例并稍后解码。
                }
                out.add(
                    mapOf(
                        "uri" to childUri.toString(),
                        "relativePath" to relativePath,
                        "name" to name,
                        "size" to size,
                        "width" to options.outWidth,
                        "height" to options.outHeight,
                        "lastModified" to if (cursor.isNull(4)) {
                            null
                        } else {
                            cursor.getLong(4)
                        },
                    ),
                )
            }
        }
    }

    private fun isImageName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") ||
            lower.endsWith(".jpeg") ||
            lower.endsWith(".png") ||
            lower.endsWith(".webp") ||
            lower.endsWith(".gif") ||
            lower.endsWith(".bmp")
    }

    private fun readDocument(
        uri: Uri,
        maxBytes: Int,
        result: MethodChannel.Result,
    ) {
        ioExecutor.execute {
            try {
                val output = java.io.ByteArrayOutputStream()
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Cannot open document")
                input.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > maxBytes) {
                            throw IllegalStateException("Image is too large")
                        }
                        output.write(buffer, 0, count)
                    }
                }
                runOnUiThread { result.success(output.toByteArray()) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "saf_read_failed",
                        error.message ?: "Cannot read document",
                        null,
                    )
                }
            }
        }
    }

    private fun readDocumentPrefix(
        uri: Uri,
        maxBytes: Int,
        result: MethodChannel.Result,
    ) {
        ioExecutor.execute {
            try {
                val output = java.io.ByteArrayOutputStream()
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Cannot open document")
                input.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    var remaining = maxBytes
                    while (remaining > 0) {
                        val count = stream.read(
                            buffer,
                            0,
                            minOf(buffer.size, remaining),
                        )
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        remaining -= count
                    }
                }
                runOnUiThread { result.success(output.toByteArray()) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "saf_read_failed",
                        error.message ?: "Cannot read document prefix",
                        null,
                    )
                }
            }
        }
    }

    private fun releaseTree(uri: Uri, result: MethodChannel.Result) {
        try {
            contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // The provider may not have granted a persistable permission.
            // 提供方可能没有授予持久化权限。
        }
        result.success(null)
    }

    private fun listBooks(treeUri: Uri, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val rootId = DocumentsContract.getTreeDocumentId(treeUri)
                val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
                val books = mutableListOf<Map<String, Any?>>()
                walkTree(treeUri, rootUri, books, 0)
                runOnUiThread { result.success(books) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("saf_list_failed", error.message ?: "Cannot list folder", null)
                }
            }
        }
    }

    private fun walkTree(
        treeUri: Uri,
        documentUri: Uri,
        out: MutableList<Map<String, Any?>>,
        depth: Int,
    ) {
        if (depth > 24 || out.size >= 1000) return
        val documentId = DocumentsContract.getDocumentId(documentUri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext() && out.size < 1000) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2) ?: ""
                val size = if (cursor.isNull(3)) null else cursor.getLong(3)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    walkTree(treeUri, childUri, out, depth + 1)
                    continue
                }
                val lower = name.lowercase()
                if (!lower.endsWith(".pdf") &&
                    !lower.endsWith(".mobi") &&
                    !lower.endsWith(".cbz")
                ) continue
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                out.add(
                    mapOf(
                        "uri" to childUri.toString(),
                        "name" to name,
                        "size" to size,
                    ),
                )
            }
        }
    }

    private fun copyToCache(uri: Uri, name: String, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val directory = File(cacheDir, "saf_import").apply { mkdirs() }
                val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80)
                val target = File(directory, "${UUID.randomUUID()}_$safeName")
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Cannot open document")
                input.use { source ->
                    target.outputStream().use { destination ->
                        source.copyTo(destination)
                    }
                }
                runOnUiThread { result.success(target.absolutePath) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("saf_copy_failed", error.message ?: "Cannot copy document", null)
                }
            }
        }
    }

    override fun onDestroy() {
        externalOpen.detach()
        ioExecutor.shutdown()
        super.onDestroy()
    }
}
