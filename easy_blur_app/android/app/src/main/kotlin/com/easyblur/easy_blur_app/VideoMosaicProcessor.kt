package com.easyblur.easy_blur_app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer

/**
 * 動画にモザイクを焼き込んで出力する。
 *
 * 処理フロー:
 *   1. MediaExtractor で入力動画のビデオトラックと音声トラックを取得
 *   2. ビデオデコーダー (MediaCodec) → SurfaceTexture (OES)
 *   3. OpenGL ES で動画フレーム + モザイクを合成描画
 *   4. エンコーダー (MediaCodec) の InputSurface に描画 → H.264 出力
 *   5. 音声トラックは MediaExtractor → MediaMuxer にそのままコピー
 */
class VideoMosaicProcessor {
    companion object {
        private const val TAG = "VideoMosaicProcessor"
        const val MIME_VIDEO = "video/avc"
    }

    fun process(
        inputPath: String,
        outputPath: String,
        layersJson: String,
        videoWidth: Int,
        videoHeight: Int,
        rotationDegrees: Int,
        onProgress: (Double) -> Unit,
    ) {
        // 出力ファイルがあれば削除
        File(outputPath).takeIf { it.exists() }?.delete()

        // レイヤー情報をパース
        val layers = parseLayers(layersJson)
        Log.d(TAG, "Parsed ${layers.size} layers")

        // 処理本体
        val helper = ProcessHelper(
            inputPath = inputPath,
            outputPath = outputPath,
            layers = layers,
            outputWidth = videoWidth,
            outputHeight = videoHeight,
            rotationDegrees = rotationDegrees,
            onProgress = onProgress,
        )
        helper.run()
    }

    private fun parseLayers(json: String): List<LayerParam> {
        val arr = JSONArray(json)
        val out = mutableListOf<LayerParam>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val type = when (obj.getString("type")) {
                "pixelate" -> MosaicType.PIXELATE
                "blur" -> MosaicType.BLUR
                "blackout" -> MosaicType.BLACKOUT
                "whiteout" -> MosaicType.WHITEOUT
                "noise" -> MosaicType.NOISE
                else -> MosaicType.PIXELATE
            }
            val shape = when (obj.getString("shape")) {
                "ellipse" -> MosaicShape.ELLIPSE
                else -> MosaicShape.RECTANGLE
            }
            val kfArr = obj.getJSONArray("keyframes")
            val kfs = mutableListOf<KeyframeParam>()
            for (j in 0 until kfArr.length()) {
                val k = kfArr.getJSONObject(j)
                kfs.add(
                    KeyframeParam(
                        timeMs = k.getLong("timeMs"),
                        cx = k.getDouble("cx").toFloat(),
                        cy = k.getDouble("cy").toFloat(),
                        w = k.getDouble("w").toFloat(),
                        h = k.getDouble("h").toFloat(),
                        intensity = k.getDouble("intensity").toFloat(),
                    )
                )
            }
            out.add(
                LayerParam(
                    type = type,
                    shape = shape,
                    inverted = obj.optBoolean("inverted", false),
                    startMs = obj.getLong("startMs"),
                    endMs = obj.getLong("endMs"),
                    keyframes = kfs,
                )
            )
        }
        return out
    }
}

enum class MosaicType { PIXELATE, BLUR, BLACKOUT, WHITEOUT, NOISE }
enum class MosaicShape { RECTANGLE, ELLIPSE }

data class KeyframeParam(
    val timeMs: Long,
    val cx: Float,
    val cy: Float,
    val w: Float,
    val h: Float,
    val intensity: Float,
)

data class LayerParam(
    val type: MosaicType,
    val shape: MosaicShape,
    val inverted: Boolean,
    val startMs: Long,
    val endMs: Long,
    val keyframes: List<KeyframeParam>,
) {
    fun isActiveAt(timeUs: Long): Boolean {
        val ms = timeUs / 1000
        return ms in startMs..endMs
    }

    /**
     * 指定時刻（μs）での補間状態を返す。
     * キーフレームが1つならそれを返す。
     * 範囲内なら前後キーフレームから線形補間。
     */
    fun getStateAt(timeUs: Long): KeyframeParam {
        require(keyframes.isNotEmpty())
        if (keyframes.size == 1) return keyframes[0]
        val ms = timeUs / 1000
        if (ms <= keyframes.first().timeMs) return keyframes.first()
        if (ms >= keyframes.last().timeMs) return keyframes.last()
        for (i in 0 until keyframes.size - 1) {
            val a = keyframes[i]
            val b = keyframes[i + 1]
            if (ms in a.timeMs..b.timeMs) {
                val range = (b.timeMs - a.timeMs).toFloat()
                if (range == 0f) return a
                val t = (ms - a.timeMs).toFloat() / range
                return KeyframeParam(
                    timeMs = ms,
                    cx = a.cx + (b.cx - a.cx) * t,
                    cy = a.cy + (b.cy - a.cy) * t,
                    w = a.w + (b.w - a.w) * t,
                    h = a.h + (b.h - a.h) * t,
                    intensity = a.intensity + (b.intensity - a.intensity) * t,
                )
            }
        }
        return keyframes.last()
    }
}

/**
 * 実処理のヘルパー。入出力・エンコーダー・デコーダー・GLのライフサイクルを管理。
 */
private class ProcessHelper(
    private val inputPath: String,
    private val outputPath: String,
    private val layers: List<LayerParam>,
    private val outputWidth: Int,
    private val outputHeight: Int,
    private val rotationDegrees: Int,
    private val onProgress: (Double) -> Unit,
) {
    companion object {
        private const val TAG = "ProcessHelper"
        private const val TIMEOUT_US = 10_000L
        private const val FRAME_RATE = 30
        private const val I_FRAME_INTERVAL = 1
        private const val BIT_RATE_PER_PIXEL = 0.15f
    }

    fun run() {
        val videoExtractor = MediaExtractor().apply { setDataSource(inputPath) }
        val audioExtractor = MediaExtractor().apply { setDataSource(inputPath) }

        val videoTrackIndex = selectTrack(videoExtractor, "video/")
        if (videoTrackIndex < 0) throw RuntimeException("ビデオトラックが見つかりません")
        videoExtractor.selectTrack(videoTrackIndex)
        val inputVideoFormat =
            videoExtractor.getTrackFormat(videoTrackIndex)

        val audioTrackIndex = selectTrack(audioExtractor, "audio/")
        if (audioTrackIndex >= 0) {
            audioExtractor.selectTrack(audioTrackIndex)
        }
        val inputAudioFormat = if (audioTrackIndex >= 0) {
            audioExtractor.getTrackFormat(audioTrackIndex)
        } else null

        val totalDurationUs =
            inputVideoFormat.getLong(MediaFormat.KEY_DURATION, 0L)

        // エンコーダー設定
        val bitRate =
            (outputWidth * outputHeight * FRAME_RATE * BIT_RATE_PER_PIXEL).toInt()
                .coerceAtLeast(2_000_000)
        val outputFormat =
            MediaFormat.createVideoFormat(
                VideoMosaicProcessor.MIME_VIDEO,
                outputWidth,
                outputHeight
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
                setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
                setInteger(
                    MediaFormat.KEY_I_FRAME_INTERVAL,
                    I_FRAME_INTERVAL
                )
            }

        val encoder =
            MediaCodec.createEncoderByType(VideoMosaicProcessor.MIME_VIDEO)
        encoder.configure(
            outputFormat,
            null,
            null,
            MediaCodec.CONFIGURE_FLAG_ENCODE
        )
        val inputSurface = InputSurface(encoder.createInputSurface())
        inputSurface.makeCurrent()
        encoder.start()

        // GL レンダラーの初期化
        val renderer = MosaicRenderer(outputWidth, outputHeight)
        renderer.setup()

        // デコーダー設定（SurfaceTexture 出力）
        val decoder = MediaCodec.createDecoderByType(
            inputVideoFormat.getString(MediaFormat.KEY_MIME)!!
        )
        // デコーダーは回転前のサイズで動く
        val outputSurface = OutputSurface(renderer.oesTextureId)
        decoder.configure(inputVideoFormat, outputSurface.surface, null, 0)
        decoder.start()

        // MediaMuxer
        val muxer = MediaMuxer(
            outputPath,
            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
        )
        var videoMuxerTrack = -1
        var audioMuxerTrack = -1
        var muxerStarted = false

        // 音声トラックの先行追加（エンコード開始後に format が確定してから）
        val pendingAudioSamples = mutableListOf<AudioSample>()

        // デコード → 変換 → エンコード ループ
        var decoderDone = false
        var encoderDone = false
        val bufferInfo = MediaCodec.BufferInfo()

        try {
            while (!encoderDone) {
                // 1) 入力サンプルをデコーダーに供給
                if (!decoderDone) {
                    val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuf = decoder.getInputBuffer(inputIndex)!!
                        val sampleSize =
                            videoExtractor.readSampleData(inputBuf, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            decoderDone = true
                        } else {
                            val ptsUs = videoExtractor.sampleTime
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                sampleSize,
                                ptsUs,
                                videoExtractor.sampleFlags
                            )
                            videoExtractor.advance()
                        }
                    }
                }

                // 2) デコーダー出力を SurfaceTexture に渡す
                val decodeInfo = MediaCodec.BufferInfo()
                val outIndex = decoder.dequeueOutputBuffer(decodeInfo, TIMEOUT_US)
                if (outIndex >= 0) {
                    val doRender = decodeInfo.size > 0
                    decoder.releaseOutputBuffer(outIndex, doRender)
                    if (doRender) {
                        outputSurface.awaitNewImage()
                        outputSurface.drawImage()

                        // SurfaceTextureのtransformMatrix を使って
                        // Y軸反転/回転補正を適用しつつモザイクを描画
                        renderer.drawMosaics(
                            layers,
                            decodeInfo.presentationTimeUs,
                            outputSurface.getTransformMatrix()
                        )

                        inputSurface.setPresentationTime(
                            decodeInfo.presentationTimeUs * 1000
                        )
                        inputSurface.swapBuffers()
                    }

                    if ((decodeInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        encoder.signalEndOfInputStream()
                    }
                }

                // 3) エンコーダー出力を Muxer へ
                while (true) {
                    val encIndex =
                        encoder.dequeueOutputBuffer(bufferInfo, 0)
                    if (encIndex == MediaCodec.INFO_TRY_AGAIN_LATER) break
                    if (encIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) {
                            throw RuntimeException("format changed twice")
                        }
                        val newFormat = encoder.outputFormat
                        videoMuxerTrack = muxer.addTrack(newFormat)
                        inputAudioFormat?.let {
                            audioMuxerTrack = muxer.addTrack(it)
                        }
                        muxer.start()
                        muxerStarted = true

                        // 保留音声を書き出し
                        if (audioMuxerTrack >= 0) {
                            for (s in pendingAudioSamples) {
                                muxer.writeSampleData(
                                    audioMuxerTrack,
                                    s.buffer,
                                    s.info
                                )
                            }
                            pendingAudioSamples.clear()
                        }
                        continue
                    }
                    if (encIndex < 0) continue

                    val encodedBuffer = encoder.getOutputBuffer(encIndex)!!
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        bufferInfo.size = 0
                    }
                    if (bufferInfo.size > 0) {
                        encodedBuffer.position(bufferInfo.offset)
                        encodedBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        if (muxerStarted) {
                            muxer.writeSampleData(
                                videoMuxerTrack,
                                encodedBuffer,
                                bufferInfo
                            )
                        }
                        // 進捗
                        if (totalDurationUs > 0) {
                            val pct =
                                (bufferInfo.presentationTimeUs.toDouble() /
                                    totalDurationUs).coerceIn(0.0, 1.0)
                            onProgress(pct * 0.85) // 最後の15%は音声muxとクローズ
                        }
                    }
                    encoder.releaseOutputBuffer(encIndex, false)

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        encoderDone = true
                        break
                    }
                }
            }

            // 4) 音声トラックのコピー
            if (audioMuxerTrack >= 0 && inputAudioFormat != null) {
                val audioBuf = ByteBuffer.allocate(256 * 1024)
                val info = MediaCodec.BufferInfo()
                while (true) {
                    info.offset = 0
                    info.size = audioExtractor.readSampleData(audioBuf, 0)
                    if (info.size < 0) break
                    info.presentationTimeUs = audioExtractor.sampleTime
                    info.flags = audioExtractor.sampleFlags
                    muxer.writeSampleData(audioMuxerTrack, audioBuf, info)
                    audioExtractor.advance()
                    if (totalDurationUs > 0) {
                        val pct = 0.85 + (info.presentationTimeUs.toDouble() /
                            totalDurationUs).coerceIn(0.0, 1.0) * 0.15
                        onProgress(pct)
                    }
                }
            }

            onProgress(1.0)
        } finally {
            try {
                muxer.stop()
            } catch (_: Exception) {
            }
            try {
                muxer.release()
            } catch (_: Exception) {
            }
            try {
                encoder.stop()
            } catch (_: Exception) {
            }
            encoder.release()
            try {
                decoder.stop()
            } catch (_: Exception) {
            }
            decoder.release()
            inputSurface.release()
            outputSurface.release()
            renderer.release()
            videoExtractor.release()
            audioExtractor.release()
        }
    }

    private fun selectTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) return i
        }
        return -1
    }

    private data class AudioSample(
        val buffer: ByteBuffer,
        val info: MediaCodec.BufferInfo,
    )
}
