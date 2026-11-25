package com.perol.pixez.plugin

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Keeps the actual document URI, including providers whose document IDs are opaque. */
class OriginalImagePlugin(private val activity: FlutterActivity) {
    private val resolver get() = activity.contentResolver
    private val index = activity.getSharedPreferences("saved_original_images", Context.MODE_PRIVATE)
    private val settings = activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private val folderLock = Any()

    fun bindChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.perol.dev/original")
            .setMethodCallHandler { call, result ->
                activity.lifecycleScope.launch {
                    try {
                        val value = withContext(Dispatchers.IO) {
                            when (call.method) {
                                "find" -> find(
                                    call.argument<String>("url")!!,
                                    call.argument<List<String>>("names") ?: emptyList(),
                                    call.argument<Int>("save_mode") ?: 0
                                )
                                "read" -> resolver.openInputStream(Uri.parse(call.argument<String>("location")!!))
                                    ?.use { it.readBytes() }
                                "save" -> save(
                                    call.argument<String>("url")!!,
                                    File(call.argument<String>("source_path")!!),
                                    call.argument<String>("name")!!,
                                    call.argument<Int>("save_mode") ?: 0,
                                    call.argument<Boolean>("clear_old") ?: false
                                )
                                else -> null
                            }
                        }
                        result.success(value)
                    } catch (e: Exception) {
                        result.error("ORIGINAL_IMAGE", e.message, null)
                    }
                }
            }
    }

    private fun readable(uri: Uri): Boolean = try {
        resolver.openAssetFileDescriptor(uri, "r")?.use { it.length != 0L } ?: false
    } catch (_: Exception) { false }

    private fun rootFile(mode: Int): File = if (mode == 2) {
        File(settings.getString("flutter.store_path", null)
            ?: "/storage/emulated/0/Pictures/pixez")
    } else {
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "pixez")
    }

    private fun trees() = resolver.persistedUriPermissions
        .filter { it.isReadPermission }
        .mapNotNull { DocumentFile.fromTreeUri(activity, it.uri) }

    private fun find(url: String, names: List<String>, mode: Int): String? {
        index.getString(url, null)?.let { if (readable(Uri.parse(it))) return it }
        if (names.isEmpty()) return null
        // Old downloads predate the index. Search their recorded/custom names without
        // walking the entire card, and keep the URI so future setting changes are safe.
        for (name in names.distinct()) {
            for (root in listOf(rootFile(mode), rootFile(0)).distinct()) {
                val uri = Uri.fromFile(File(root, name))
                if (readable(uri)) {
                    index.edit().putString(url, uri.toString()).commit()
                    return uri.toString()
                }
            }
        }
        for (tree in trees()) {
            // One listing per candidate parent, rather than one full directory
            // scan per possible filename on large TF/SD cards.
            for ((parent, candidates) in names.distinct().groupBy { it.substringBeforeLast('/', "") }) {
                var folder: DocumentFile? = tree
                if (parent.isNotEmpty()) for (part in parent.split('/')) folder = folder?.findFile(part)
                val parentUri = folder?.uri ?: continue
                val wanted = candidates.map { it.substringAfterLast('/') }.toSet()
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                    tree.uri, DocumentsContract.getDocumentId(parentUri)
                )
                resolver.query(children, arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME),
                    null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        if (cursor.getString(1) !in wanted) continue
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree.uri, cursor.getString(0))
                        if (readable(uri)) {
                            index.edit().putString(url, uri.toString()).commit()
                            return uri.toString()
                        }
                    }
                }
            }
        }
        return null
    }

    private fun save(url: String, source: File, name: String, mode: Int, clearOld: Boolean): String {
        var previousFormat: DocumentFile? = null
        val uri = if (mode == 1) {
            val permission = resolver.persistedUriPermissions.firstOrNull {
                it.isReadPermission && it.isWritePermission
            } ?: error("请先授权下载目录")
            synchronized(folderLock) {
                var folder = DocumentFile.fromTreeUri(activity, permission.uri)!!
                val parts = name.split('/')
                for (part in parts.dropLast(1)) {
                    folder = folder.findFile(part) ?: folder.createDirectory(part)
                        ?: error("无法创建下载目录")
                }
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(File(name).extension)
                    ?: "application/octet-stream"
                if (clearOld && parts.last().contains("_p0")) {
                    previousFormat = folder.findFile(parts.last().replace("_p0", ""))
                }
                (folder.findFile(parts.last()) ?: folder.createFile(mime, parts.last()))?.uri
                    ?: error("无法创建下载文件")
            }
        } else {
            val target = File(rootFile(mode), name)
            target.parentFile?.mkdirs()
            Uri.fromFile(target)
        }
        try {
            val output = resolver.openOutputStream(uri, "wt") ?: error("无法打开下载文件")
            output.use { sink -> source.inputStream().use { it.copyTo(sink, 1024 * 1024) } }
            resolver.openAssetFileDescriptor(uri, "r")?.use {
                check(it.length < 0 || it.length == source.length()) { "下载文件大小不符" }
            } ?: error("下载文件无法读取")
        } catch (e: Exception) {
            if (uri.scheme == "file") File(uri.path!!).delete()
            else DocumentsContract.deleteDocument(resolver, uri)
            throw e
        }
        check(index.edit().putString(url, uri.toString()).commit()) { "无法记录原图位置" }
        try { previousFormat?.delete() } catch (_: Exception) { /* Keep the new save valid. */ }
        if (uri.scheme == "file") {
            if (clearOld && name.contains("_p0")) File(rootFile(mode), name.replace("_p0", "")).delete()
            MediaScannerConnection.scanFile(activity, arrayOf(uri.path), null, null)
        }
        return uri.toString()
    }
}
