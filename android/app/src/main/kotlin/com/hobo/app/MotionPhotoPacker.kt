package com.hobo.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.nio.ByteBuffer

/**
 * 将「静图 + 实况视频（.mov / .mp4）」封装为 Android 通用 Motion Photo（动态照片）：
 *  1. 静图统一为标准 JPEG（剥离旧 XMP 与 EOI 之后的尾随数据）；
 *  2. 微博实况视频多为 QuickTime `.mov`，通过系统 MediaExtractor + MediaMuxer 无损重封装为
 *     标准 `.mp4`（只保留 video/audio 轨道、保留旋转信息），兼容 Google 相册与主流国产相册；
 *  3. 注入同时包含 Motion Photo V1（GCamera:MotionPhoto + Container:Directory）与
 *     Legacy MicroVideo（GCamera:MicroVideo + MicroVideoOffset）的 XMP APP1 段；
 *  4. 紧贴 JPEG EOI (`FF D9`) 追加完整 MP4 字节流。
 */
object MotionPhotoPacker {
    private val xmpHeader = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)
    private val mp4Brands = setOf("isom", "iso2", "iso5", "iso6", "mp41", "mp42", "M4V ", "avc1")

    /**
     * 将 [imageBytes] 与 [videoFile] 合并写出为 Android Motion Photo 到 [output]。
     * 临时重封装文件会在结束时自动清理。
     */
    fun pack(
        imageBytes: ByteArray,
        videoFile: File,
        cacheDir: File,
        output: OutputStream,
    ) {
        val jpeg = ensureJpeg(imageBytes)
        val (mp4File, shouldDelete) = ensureMp4(videoFile, cacheDir)
        try {
            val videoLength = mp4File.length()
            if (videoLength <= 0L) error("实况视频文件为空")
            val xmpXml = buildMotionPhotoXmp(videoLength)
            val patchedJpeg = injectXmpIntoJpeg(jpeg, xmpXml)
            output.write(patchedJpeg)
            mp4File.inputStream().use { input ->
                input.copyTo(output, bufferSize = 64 * 1024)
            }
            output.flush()
        } finally {
            if (shouldDelete && mp4File.exists()) {
                mp4File.delete()
            }
        }
    }

    /** 确保静图是有效 JPEG，非 JPEG（如 WebP/PNG）先解码再转存为高质量 JPEG。 */
    fun ensureJpeg(bytes: ByteArray): ByteArray {
        if (bytes.size >= 4 &&
            (bytes[0].toInt() and 0xFF) == 0xFF &&
            (bytes[1].toInt() and 0xFF) == 0xD8
        ) {
            return trimAfterEoi(bytes)
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: error("无法解码实况静图")
        return try {
            ByteArrayOutputStream().use { baos ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, baos)) {
                    error("无法编码实况静图")
                }
                baos.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * 确保视频为标准 MP4 容器。微博实况视频常为 QuickTime `.mov` (`ftypqt  `)，
     * 部分系统相册只认 MP4，这里无损重封装一次；重封装失败时回退原文件。
     */
    fun ensureMp4(source: File, cacheDir: File): Pair<File, Boolean> {
        if (!source.isFile || source.length() <= 0L) error("实况视频文件为空")
        if (isAlreadyMp4(source)) return source to false
        val out = File(cacheDir, "hobo_mp_${System.nanoTime()}.mp4")
        return try {
            remuxToMp4(source, out)
            if (out.isFile && out.length() > 0L) {
                out to true
            } else {
                out.delete()
                source to false
            }
        } catch (_: Throwable) {
            out.delete()
            source to false
        }
    }

    private fun isAlreadyMp4(file: File): Boolean {
        val header = ByteArray(12)
        val read = file.inputStream().use { it.read(header) }
        if (read < 12) return false
        val box = String(header, 4, 4, Charsets.US_ASCII)
        val brand = String(header, 8, 4, Charsets.US_ASCII)
        return box == "ftyp" && brand in mp4Brands
    }

    private fun remuxToMp4(input: File, output: File) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(input.absolutePath)
            val trackCount = extractor.trackCount
            if (trackCount <= 0) error("视频不含有效轨道")

            val trackMap = LinkedHashMap<Int, Int>()
            // 部分 4K/HEVC 实况图单帧关键帧可能超过 256 KB，默认给足 2 MB 避免 readSampleData 溢出。
            var maxBufferSize = 2 * 1024 * 1024
            var rotation = 0
            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) {
                    // 跳过 QuickTime 元数据轨道（如 meta / timed metadata），否则 MediaMuxer 会抛异常。
                    continue
                }
                if (mime.startsWith("video/") && format.containsKey(MediaFormat.KEY_ROTATION)) {
                    rotation = format.getInteger(MediaFormat.KEY_ROTATION)
                }
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    val size = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                    if (size > maxBufferSize) maxBufferSize = size
                }
                val dstTrack = muxer.addTrack(format)
                trackMap[i] = dstTrack
                extractor.selectTrack(i)
            }
            if (trackMap.isEmpty()) error("未找到可封装的音视频轨道")
            if (rotation != 0) muxer.setOrientationHint(rotation)

            muxer.start()
            muxerStarted = true

            val buffer = ByteBuffer.allocate(maxBufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                info.offset = 0
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size < 0) break
                val srcTrack = extractor.sampleTrackIndex
                val dstTrack = trackMap[srcTrack]
                if (dstTrack != null) {
                    info.presentationTimeUs = extractor.sampleTime.coerceAtLeast(0L)
                    val sampleFlags = extractor.sampleFlags
                    var codecFlags = 0
                    if ((sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) {
                        codecFlags = codecFlags or MediaCodec.BUFFER_FLAG_KEY_FRAME
                    }
                    if ((sampleFlags and MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME) != 0) {
                        codecFlags = codecFlags or MediaCodec.BUFFER_FLAG_PARTIAL_FRAME
                    }
                    info.flags = codecFlags
                    muxer.writeSampleData(dstTrack, buffer, info)
                }
                if (!extractor.advance()) break
            }
        } finally {
            try {
                if (muxerStarted) muxer?.stop()
            } catch (_: Throwable) {
            }
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
            try {
                extractor.release()
            } catch (_: Throwable) {
            }
        }
    }

    /** 生成兼顾 Motion Photo V1 与 Legacy MicroVideo 的 XMP 元数据。 */
    fun buildMotionPhotoXmp(videoLength: Long): String = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                xmlns:Container="http://ns.google.com/photos/1.0/container/"
                xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
                GCamera:MotionPhoto="1"
                GCamera:MotionPhotoVersion="1"
                GCamera:MotionPhotoPresentationTimestampUs="0"
                GCamera:MicroVideo="1"
                GCamera:MicroVideoVersion="1"
                GCamera:MicroVideoOffset="$videoLength"
                GCamera:MicroVideoPresentationTimestampUs="0">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item
                        Item:Mime="image/jpeg"
                        Item:Semantic="Primary"
                        Item:Length="0"
                        Item:Padding="0"/>
                  </rdf:li>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item
                        Item:Mime="video/mp4"
                        Item:Semantic="MotionPhoto"
                        Item:Length="$videoLength"
                        Item:Padding="0"/>
                  </rdf:li>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
    """.trimIndent()

    /**
     * 在 JPEG 头部（APP0/EXIF 之后、SOS 之前）插入 XMP APP1 段，同时移除已有 XMP 段避免冲突。
     */
    fun injectXmpIntoJpeg(jpeg: ByteArray, xmpXml: String): ByteArray {
        val xmpBytes = xmpXml.toByteArray(Charsets.UTF_8)
        val payloadLength = 2 + xmpHeader.size + xmpBytes.size
        if (payloadLength > 0xFFFF) error("XMP 元数据超出长度上限")

        val out = ByteArrayOutputStream(jpeg.size + payloadLength + 4)
        // 写入 SOI (FF D8)
        out.write(0xFF)
        out.write(0xD8)

        var pos = 2
        var xmpInserted = false

        fun writeXmpSegment() {
            if (xmpInserted) return
            out.write(0xFF)
            out.write(0xE1)
            out.write((payloadLength shr 8) and 0xFF)
            out.write(payloadLength and 0xFF)
            out.write(xmpHeader)
            out.write(xmpBytes)
            xmpInserted = true
        }

        while (pos + 1 < jpeg.size) {
            if ((jpeg[pos].toInt() and 0xFF) != 0xFF) break
            // 跳过填充 0xFF
            var markerPos = pos + 1
            while (markerPos < jpeg.size && (jpeg[markerPos].toInt() and 0xFF) == 0xFF) {
                markerPos++
            }
            if (markerPos >= jpeg.size) break
            val marker = jpeg[markerPos].toInt() and 0xFF

            // SOS (FF DA) 或 EOI (FF D9)：先写 XMP，再把剩余压缩流完整写出。
            if (marker == 0xDA || marker == 0xD9) {
                writeXmpSegment()
                out.write(jpeg, pos, jpeg.size - pos)
                return out.toByteArray()
            }

            // 独立标记（无长度字段）：TEM(01) / RST0..7(D0..D7)
            if (marker == 0x01 || marker in 0xD0..0xD7) {
                out.write(jpeg, pos, markerPos + 1 - pos)
                pos = markerPos + 1
                continue
            }

            if (markerPos + 2 >= jpeg.size) break
            val segLen = ((jpeg[markerPos + 1].toInt() and 0xFF) shl 8) or
                (jpeg[markerPos + 2].toInt() and 0xFF)
            val segEnd = markerPos + 1 + segLen
            if (segLen < 2 || segEnd > jpeg.size) break

            val isExistingXmp = marker == 0xE1 &&
                segLen >= 2 + xmpHeader.size &&
                matchesPrefix(jpeg, markerPos + 3, xmpHeader)

            // 在 APP0(E0) 和 EXIF APP1(E1) 之后、首个非 APP0/APP1 段之前写入 XMP，
            // 保证 XMP 靠近文件头，各类相册快速扫描都能第一时间识别。
            if (!xmpInserted && marker != 0xE0 && marker != 0xE1) {
                writeXmpSegment()
            }

            if (!isExistingXmp) {
                out.write(jpeg, pos, segEnd - pos)
            }
            pos = segEnd
        }

        if (!xmpInserted) writeXmpSegment()
        if (pos < jpeg.size) out.write(jpeg, pos, jpeg.size - pos)
        return out.toByteArray()
    }

    /** 去掉最后一个 EOI (`FF D9`) 之后的尾随数据，确保视频紧贴 JPEG 末尾。 */
    private fun trimAfterEoi(jpeg: ByteArray): ByteArray {
        var i = jpeg.size - 2
        while (i >= 2) {
            if ((jpeg[i].toInt() and 0xFF) == 0xFF && (jpeg[i + 1].toInt() and 0xFF) == 0xD9) {
                return if (i + 2 == jpeg.size) jpeg else jpeg.copyOf(i + 2)
            }
            i--
        }
        return jpeg
    }

    private fun matchesPrefix(data: ByteArray, offset: Int, prefix: ByteArray): Boolean {
        if (offset + prefix.size > data.size) return false
        for (i in prefix.indices) {
            if (data[offset + i] != prefix[i]) return false
        }
        return true
    }
}
