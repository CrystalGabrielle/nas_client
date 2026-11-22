package com.nasclient.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Handles the `com.nasclient.app/download` method channel.
///
/// All writes go through the Storage Access Framework using a persisted URI
/// grant, so the app can save into the public Downloads folder on Android 11+
/// without requesting broad storage permissions or adding third-party deps.
class DownloadLocationChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.nasclient.app/download"
        const val REQUEST_PICK_DIR = 4242
    }

    private var pendingResult: MethodChannel.Result? = null

    fun configure(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "writeFile" -> writeFile(call, result)
            "hasPermission" -> hasPermission(call, result)
            "releaseDirectory" -> releaseDirectory(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "A directory picker is already open", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            flags = (Intent.FLAG_GRANT_READ_URI_PERMISSION
                    or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    or (Intent.FLAG_GRANT_PREFIX_URI_PERMISSION))
            putExtra(DocumentsContract.EXTRA_INITIAL_URI, downloadsTreeUri())
        }
        activity.startActivityForResult(intent, REQUEST_PICK_DIR)
    }

    /// Called from MainActivity.onActivityResult.
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_DIR) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        val takeFlags = (Intent.FLAG_GRANT_READ_URI_PERMISSION
                or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (_: SecurityException) {
            // Some providers do not allow persisting; the grant still works for
            // this session, but it will need re-approval after a reboot.
        }
        val displayName = displayNameFor(uri)
        result.success(mapOf("uri" to uri.toString(), "displayName" to displayName))
    }

    private fun writeFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val sourcePath = call.argument<String>("source")
        val displayName = call.argument<String>("displayName")
        if (uriString == null || sourcePath == null || displayName.isNullOrEmpty()) {
            result.error("invalid_args", "uri, source and displayName are required", null)
            return
        }
        try {
            val treeUri = Uri.parse(uriString)
            val directory = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
            val mime = mimeFor(displayName)
            val created = DocumentsContract.createDocument(
                activity.contentResolver,
                directory,
                mime,
                displayName,
            ) ?: run {
                result.error("create_failed", "Could not create the document", null)
                return
            }
            val source = File(sourcePath)
            activity.contentResolver.openOutputStream(created).use { output ->
                if (output == null) {
                    result.error("open_failed", "Could not open the document for writing", null)
                    return
                }
                source.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
            }
            result.success(resolvePath(created) ?: created.toString())
        } catch (e: Exception) {
            result.error("write_failed", e.message ?: "Write failed", null)
        }
    }

    private fun hasPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrEmpty()) {
            result.success(false)
            return
        }
        val granted = activity.contentResolver.persistedUriPermissions.any { permission ->
            permission.uri.toString() == uriString && permission.isWritePermission
        }
        result.success(granted)
    }

    private fun releaseDirectory(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (!uriString.isNullOrEmpty()) {
            try {
                val uri = Uri.parse(uriString)
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                activity.contentResolver.releasePersistableUriPermission(uri, flags)
            } catch (_: Exception) {
            }
        }
        result.success(null)
    }

    private fun downloadsTreeUri(): Uri? = try {
        DocumentsContract.buildTreeDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Download",
        )
    } catch (_: Exception) {
        null
    }

    private fun displayNameFor(uri: Uri): String {
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (_: Exception) {
            return "下载文件夹"
        }
        return docId.substringAfterLast(':', docId).ifEmpty { "下载文件夹" }
    }

    private fun mimeFor(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }

    /// Best-effort human/Flutter-visible path. Returns null for virtual files.
    private fun resolvePath(uri: Uri): String? {
        val docId = try {
            DocumentsContract.getDocumentId(uri)
        } catch (_: Exception) {
            return null
        }
        if (!docId.startsWith("primary:")) return null
        val relative = docId.substringAfter(':').replace(':', '/')
        val root = android.os.Environment.getExternalStorageDirectory()
        return File(root, relative).absolutePath
    }
}
