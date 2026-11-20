package com.manhua.manhua_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "manhua/saf"
    private val pickDirectoryRequest = 7281
    private var pendingPick: MethodChannel.Result? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        }
        result.success(uri.toString())
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
                if (!lower.endsWith(".pdf") && !lower.endsWith(".mobi")) continue
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
        ioExecutor.shutdown()
        super.onDestroy()
    }
}
