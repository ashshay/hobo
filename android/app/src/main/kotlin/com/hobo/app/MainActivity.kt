package com.hobo.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 登录 WebView 与 App 共用系统 CookieManager，所以登录态的真源是它：
 * 登录完成后把整表读出来落盘，之后每次新建 WebView 再把本地那份补回去。
 * 对应 Kotlin 版 CookieVault.readDomains / inject / plant。
 *
 * 另外挂三条通道：
 *  - `hobo/media`：把图片 / 视频写进系统相册（MediaStore），Android 10 起不需要权限；
 *  - `hobo/icon`：切换桌面图标形状。两套图标是已经画好形状的位图，分别挂在
 *    `.IconRounded` / `.IconCircle` 两个 activity-alias 上，这里只负责开关它们；
 *  - `hobo/browser`：把网址交给系统浏览器（`Intent.ACTION_VIEW`），给内置网页的
 *    「用浏览器打开」按钮用。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "hobo/cookies"
    private val mediaChannelName = "hobo/media"
    private val iconChannelName = "hobo/icon"
    private val browserChannelName = "hobo/browser"
    private val storageRequestCode = 0x4d44

    /** 形状 → activity-alias 后缀；`.IconRounded` 是 AndroidManifest 里的默认入口。 */
    private val iconAliases = listOf(
        "rounded" to ".IconRounded",
        "circle" to ".IconCircle",
    )

    private var pendingSave: (() -> Unit)? = null
    private var pendingSaveFailure: ((String) -> Unit)? = null

    private val cookieUrls = linkedMapOf(
        "https://m.weibo.cn" to ".weibo.cn",
        "https://weibo.com" to ".weibo.com",
        "https://passport.weibo.cn" to "passport.weibo.cn",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "read" -> result.success(readCookies())
                        "inject" -> {
                            @Suppress("UNCHECKED_CAST")
                            val cookies = call.argument<Map<String, String>>("cookies").orEmpty()
                            plant(cookies)
                            result.success(null)
                        }
                        "clear" -> {
                            val manager = CookieManager.getInstance()
                            manager.removeAllCookies(null)
                            manager.flush()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("cookie_failed", t.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: defaultName("jpg")
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("save_failed", "图片内容为空", null)
                            return@setMethodCallHandler
                        }
                        saveToGallery(result) { insertImage(bytes, name) }
                    }
                    "saveVideo" -> {
                        val path = call.argument<String>("path").orEmpty()
                        val name = call.argument<String>("name") ?: defaultName("mp4")
                        val mime = call.argument<String>("mime") ?: "video/mp4"
                        if (path.isEmpty()) {
                            result.error("save_failed", "视频路径为空", null)
                            return@setMethodCallHandler
                        }
                        saveToGallery(result) { insertVideo(File(path), name, mime) }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "currentShape" -> result.success(currentIconShape())
                        "applyShape" -> {
                            val shape = call.argument<String>("shape") ?: "rounded"
                            result.success(applyIconShape(shape))
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("icon_failed", t.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, browserChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url").orEmpty()
                        result.success(openInBrowser(url))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 交给系统浏览器。
     *
     * 只填 action + data，不 setPackage：默认浏览器可以是任何一个第三方浏览器，
     * 写死包名反而会在没装那个 App 的机器上失败。系统没有能处理 http/https 的应用时
     * `startActivity` 会抛 `ActivityNotFoundException`，这里当成「打不开」返回 false，
     * 由界面提示，而不是让 App 崩掉。
     */
    private fun openInBrowser(url: String): Boolean {
        if (url.isBlank()) return false
        val uri = try {
            Uri.parse(url)
        } catch (e: Exception) {
            return false
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return false
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            // 从 Activity 起 Intent 本来不需要 NEW_TASK，但部分 ROM 的 chooser 会把
            // 目标放进新任务；显式加上更稳，也不会把当前 WebView 任务带过去。
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * 现在生效的形状。两个 alias 在没被改过时都是 COMPONENT_ENABLED_STATE_DEFAULT，
     * 这时按 AndroidManifest 里的默认值算（只有 `.IconRounded` 带 enabled="true"）。
     */
    private fun currentIconShape(): String {
        val pm = packageManager
        fun enabled(suffix: String, manifestDefault: Boolean): Boolean =
            when (pm.getComponentEnabledSetting(ComponentName(this, packageName + suffix))) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                else -> manifestDefault
            }

        val rounded = enabled(".IconRounded", manifestDefault = true)
        val circle = enabled(".IconCircle", manifestDefault = false)
        return if (circle && !rounded) "circle" else "rounded"
    }

    /**
     * 只留一个 alias 带 MAIN/LAUNCHER，桌面才会只有一枚图标。
     * DONT_KILL_APP：切图标不该把正在用的 App 杀掉（当前任务还挂着被关掉的那个 alias）。
     */
    private fun applyIconShape(shape: String): String {
        val target = if (shape == "circle") "circle" else "rounded"
        val pm = packageManager
        for ((key, suffix) in iconAliases) {
            val component = ComponentName(this, packageName + suffix)
            val wantEnabled = key == target
            val want = if (wantEnabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val current = pm.getComponentEnabledSetting(component)
            if (current == want) continue
            // 首次安装时是 DEFAULT：默认启用的那个不用动，省得无谓地惊动桌面。
            if (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT &&
                wantEnabled == (key == "rounded")
            ) {
                continue
            }
            pm.setComponentEnabledSetting(component, want, PackageManager.DONT_KILL_APP)
        }
        return target
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != storageRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val save = pendingSave
        val failure = pendingSaveFailure
        pendingSave = null
        pendingSaveFailure = null
        if (granted) save?.invoke() else failure?.invoke("没有存储权限，无法保存到相册")
    }

    /** 后台线程写相册，结果回到主线程再交给 Flutter。 */
    private fun saveToGallery(result: MethodChannel.Result, write: () -> String) {
        withStoragePermission(
            onGranted = {
                Thread {
                    try {
                        val uri = write()
                        runOnUiThread { result.success(uri) }
                    } catch (t: Throwable) {
                        runOnUiThread {
                            result.error("save_failed", t.message ?: "保存失败", null)
                        }
                    }
                }.start()
            },
            onDenied = { message -> result.error("save_failed", message, null) },
        )
    }

    private fun withStoragePermission(onGranted: () -> Unit, onDenied: (String) -> Unit) {
        val granted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            onGranted()
            return
        }
        pendingSave = onGranted
        pendingSaveFailure = onDenied
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            storageRequestCode,
        )
    }

    private fun insertImage(bytes: ByteArray, name: String): String {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mimeOf(name))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/Hobo",
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("无法创建相册文件")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: error("无法写入相册文件")
        } catch (t: Throwable) {
            resolver.delete(uri, null, null)
            throw t
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri.toString()
    }

    private fun insertVideo(source: File, name: String, mime: String): String {
        if (!source.isFile || source.length() <= 0L) error("视频文件为空")
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Video.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MOVIES + "/Hobo",
                )
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("无法创建相册文件")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { input -> input.copyTo(out) }
            } ?: error("无法写入相册文件")
        } catch (t: Throwable) {
            resolver.delete(uri, null, null)
            throw t
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return uri.toString()
    }

    private fun defaultName(ext: String): String =
        "hobo_${System.currentTimeMillis()}.$ext"

    private fun mimeOf(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        else -> "image/jpeg"
    }

    private fun parseHeader(header: String): List<String> =
        header.split(';').map { it.trim() }.filter { it.contains('=') }

    private fun readCookies(): Map<String, String> {
        val manager = CookieManager.getInstance()
        manager.setAcceptCookie(true)
        val out = LinkedHashMap<String, String>()
        for ((url, domain) in cookieUrls) {
            val lines = parseHeader(manager.getCookie(url).orEmpty())
            if (lines.isNotEmpty()) out[domain] = lines.joinToString("\n")
        }
        return out
    }

    private fun plant(cookies: Map<String, String>) {
        if (cookies.isEmpty()) return
        val manager = CookieManager.getInstance()
        manager.setAcceptCookie(true)
        for ((domain, value) in cookies) {
            val lines = value.split('\n').filter { it.isNotBlank() }
            if (lines.isEmpty()) {
                manager.setCookie(domain, value)
            } else {
                for (line in lines) manager.setCookie(domain, line)
            }
        }
        manager.flush()
    }
}
