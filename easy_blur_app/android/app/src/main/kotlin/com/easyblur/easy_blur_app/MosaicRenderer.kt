package com.easyblur.easy_blur_app

import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * フレームに OES テクスチャを描画し、その上にモザイク効果レイヤーを重ねる GL レンダラー。
 *
 * - ベース動画: samplerExternalOES + フルスクリーンクアッド
 * - ピクセレート: UV 量子化
 * - ぼかし: 簡易ボックスブラー（9タップ）
 * - 黒塗り: 単色
 *
 * 出力サイズは encoder のサイズ (outputWidth x outputHeight) に合わせ、
 * デコーダーからの動画がその中に合うように描画する。
 */
class MosaicRenderer(
    private val outputWidth: Int,
    private val outputHeight: Int,
) {
    var oesTextureId: Int = 0
        private set

    private var baseProgram = 0
    private var mosaicProgram = 0

    private var aPosBase = 0
    private var aUvBase = 0
    private var uTexBase = 0
    private var uMvpBase = 0
    private var uStMatrixBase = 0

    private var aPosMosaic = 0
    private var aUvMosaic = 0
    private var uTexMosaic = 0
    private var uStMatrixMosaic = 0
    private var uSampleBoxMosaic = 0
    private var uEffectMosaic = 0
    private var uIntensityMosaic = 0
    private var uShapeMosaic = 0
    private var uInvertedMosaic = 0
    private var uFillColorMosaic = 0
    private var uRotationMosaic = 0

    private lateinit var vertexBuf: FloatBuffer
    private val mvpMatrix = FloatArray(16)

    fun setup() {
        // OES テクスチャ作成
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        oesTextureId = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE
        )

        // 頂点バッファ（フルスクリーンクアッド、位置+UV 交互格納）
        // NDC: (-1, -1) to (1, 1), UV: (0,0) to (1,1)
        val quad = floatArrayOf(
            -1f, -1f, 0f, 0f,
            1f, -1f, 1f, 0f,
            -1f, 1f, 0f, 1f,
            1f, 1f, 1f, 1f,
        )
        vertexBuf = ByteBuffer.allocateDirect(quad.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer().apply { put(quad); position(0) }

        // MVPはidentity。回転と Y 軸反転は SurfaceTexture の transformMatrix で扱う
        Matrix.setIdentityM(mvpMatrix, 0)

        // シェーダープログラム
        baseProgram = buildProgram(VS_BASE, FS_BASE)
        aPosBase = GLES20.glGetAttribLocation(baseProgram, "a_pos")
        aUvBase = GLES20.glGetAttribLocation(baseProgram, "a_uv")
        uTexBase = GLES20.glGetUniformLocation(baseProgram, "u_tex")
        uMvpBase = GLES20.glGetUniformLocation(baseProgram, "u_mvp")
        uStMatrixBase = GLES20.glGetUniformLocation(baseProgram, "u_st_matrix")

        mosaicProgram = buildProgram(VS_MOSAIC, FS_MOSAIC)
        aPosMosaic = GLES20.glGetAttribLocation(mosaicProgram, "a_pos")
        aUvMosaic = GLES20.glGetAttribLocation(mosaicProgram, "a_uv")
        uTexMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_tex")
        uStMatrixMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_st_matrix")
        uSampleBoxMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_sample_box")
        uEffectMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_effect")
        uIntensityMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_intensity")
        uShapeMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_shape")
        uInvertedMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_inverted")
        uFillColorMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_fill_color")
        uRotationMosaic = GLES20.glGetUniformLocation(mosaicProgram, "u_rotation")
    }

    /**
     * 1フレーム分描画：
     * - ベース動画フレーム
     * - 各レイヤー（時間範囲内）のモザイク効果
     *
     * [stMatrix] は SurfaceTexture.getTransformMatrix の結果。
     * OES テクスチャの Y 軸反転・回転補正が含まれている。
     */
    fun drawMosaics(
        layers: List<LayerParam>,
        timeUs: Long,
        stMatrix: FloatArray,
    ) {
        // ビューポート
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        // ベース動画描画
        drawBaseFrame(stMatrix)

        // モザイク描画（表示座標系で位置指定）
        for (layer in layers) {
            if (!layer.isActiveAt(timeUs)) continue
            if (layer.keyframes.isEmpty()) continue
            val state = layer.getStateAt(timeUs)
            drawMosaicLayer(layer, state, stMatrix)
        }
    }

    private fun drawBaseFrame(stMatrix: FloatArray) {
        GLES20.glUseProgram(baseProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            oesTextureId
        )
        GLES20.glUniform1i(uTexBase, 0)
        GLES20.glUniformMatrix4fv(uMvpBase, 1, false, mvpMatrix, 0)
        GLES20.glUniformMatrix4fv(uStMatrixBase, 1, false, stMatrix, 0)

        vertexBuf.position(0)
        GLES20.glEnableVertexAttribArray(aPosBase)
        GLES20.glVertexAttribPointer(aPosBase, 2, GLES20.GL_FLOAT, false, 16, vertexBuf)
        vertexBuf.position(2)
        GLES20.glEnableVertexAttribArray(aUvBase)
        GLES20.glVertexAttribPointer(aUvBase, 2, GLES20.GL_FLOAT, false, 16, vertexBuf)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosBase)
        GLES20.glDisableVertexAttribArray(aUvBase)
    }

    /**
     * モザイクレイヤーを描画。
     * 画面座標系 (outputWidth, outputHeight) でレイヤーの矩形を求め、
     * その位置に矩形クアッドを描画する。シェーダー内で効果を適用。
     */
    private fun drawMosaicLayer(
        layer: LayerParam,
        kf: KeyframeParam,
        stMatrix: FloatArray,
    ) {
        GLES20.glUseProgram(mosaicProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            oesTextureId
        )
        GLES20.glUniform1i(uTexMosaic, 0)
        GLES20.glUniformMatrix4fv(uStMatrixMosaic, 1, false, stMatrix, 0)

        // レイヤー矩形のUV座標（u_sample_box に渡す、反転判定でも使う）
        val w = outputWidth.toFloat()
        val h = outputHeight.toFloat()
        val u0 = (kf.cx - kf.w / 2f) / w
        val u1 = (kf.cx + kf.w / 2f) / w
        val v0 = 1f - (kf.cy + kf.h / 2f) / h
        val v1 = 1f - (kf.cy - kf.h / 2f) / h

        // 反転モードは全画面クアッドで描画（シェーダーが矩形外のみエフェクト）
        val quad: FloatArray = if (layer.inverted) {
            floatArrayOf(
                -1f, -1f, 0f, 0f,
                1f, -1f, 1f, 0f,
                -1f, 1f, 0f, 1f,
                1f, 1f, 1f, 1f,
            )
        } else {
            val x0 = u0 * 2f - 1f
            val x1 = u1 * 2f - 1f
            val y0 = v0 * 2f - 1f
            val y1 = v1 * 2f - 1f
            floatArrayOf(
                x0, y0, u0, v0,
                x1, y0, u1, v0,
                x0, y1, u0, v1,
                x1, y1, u1, v1,
            )
        }
        val quadBuf = ByteBuffer.allocateDirect(quad.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer().apply { put(quad); position(0) }

        // レイヤー効果のuniform
        val effect = when (layer.type) {
            MosaicType.PIXELATE -> 0
            MosaicType.BLUR -> 1
            MosaicType.FILL -> 2
            MosaicType.NOISE -> 3
        }
        val shape = when (layer.shape) {
            MosaicShape.RECTANGLE -> 0
            MosaicShape.ELLIPSE -> 1
            MosaicShape.TRIANGLE -> 2
            MosaicShape.HEART -> 3
        }
        GLES20.glUniform1i(uEffectMosaic, effect)
        GLES20.glUniform1i(uShapeMosaic, shape)
        GLES20.glUniform1i(uInvertedMosaic, if (layer.inverted) 1 else 0)
        GLES20.glUniform1f(uIntensityMosaic, max(2f, kf.intensity))
        GLES20.glUniform4f(uSampleBoxMosaic, u0, v0, u1, v1)
        // ARGB int → RGBA float
        val a = ((layer.fillColor shr 24) and 0xFF) / 255f
        val r = ((layer.fillColor shr 16) and 0xFF) / 255f
        val g = ((layer.fillColor shr 8) and 0xFF) / 255f
        val b = (layer.fillColor and 0xFF) / 255f
        GLES20.glUniform4f(uFillColorMosaic, r, g, b, a)
        GLES20.glUniform1f(uRotationMosaic, kf.rotation)

        quadBuf.position(0)
        GLES20.glEnableVertexAttribArray(aPosMosaic)
        GLES20.glVertexAttribPointer(aPosMosaic, 2, GLES20.GL_FLOAT, false, 16, quadBuf)
        quadBuf.position(2)
        GLES20.glEnableVertexAttribArray(aUvMosaic)
        GLES20.glVertexAttribPointer(aUvMosaic, 2, GLES20.GL_FLOAT, false, 16, quadBuf)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPosMosaic)
        GLES20.glDisableVertexAttribArray(aUvMosaic)
    }

    fun release() {
        if (baseProgram != 0) GLES20.glDeleteProgram(baseProgram)
        if (mosaicProgram != 0) GLES20.glDeleteProgram(mosaicProgram)
        if (oesTextureId != 0) {
            val ids = intArrayOf(oesTextureId)
            GLES20.glDeleteTextures(1, ids, 0)
        }
    }

    companion object {
        private const val VS_BASE = """
            attribute vec4 a_pos;
            attribute vec2 a_uv;
            uniform mat4 u_mvp;
            uniform mat4 u_st_matrix;
            varying vec2 v_uv;
            void main() {
                gl_Position = u_mvp * a_pos;
                v_uv = (u_st_matrix * vec4(a_uv, 0.0, 1.0)).xy;
            }
        """

        private const val FS_BASE = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_uv;
            uniform samplerExternalOES u_tex;
            void main() {
                gl_FragColor = texture2D(u_tex, v_uv);
            }
        """

        private const val VS_MOSAIC = """
            attribute vec4 a_pos;
            attribute vec2 a_uv;
            uniform mat4 u_st_matrix;
            varying vec2 v_uv;
            varying vec2 v_local;
            void main() {
                gl_Position = a_pos;
                v_uv = (u_st_matrix * vec4(a_uv, 0.0, 1.0)).xy;
                // ローカル座標 (0,0)〜(1,1)
                v_local = a_uv;
            }
        """

        private const val FS_MOSAIC = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_uv;
            varying vec2 v_local;
            uniform samplerExternalOES u_tex;
            uniform vec4 u_sample_box;
            uniform int u_effect;
            uniform int u_shape;
            uniform int u_inverted;
            uniform vec4 u_fill_color;
            uniform float u_intensity;
            uniform float u_rotation;

            void main() {
                // 矩形ローカル座標 (0..1)
                vec2 boxSize = vec2(u_sample_box.z - u_sample_box.x,
                                    u_sample_box.w - u_sample_box.y);
                vec2 local = (v_uv - u_sample_box.xy) / boxSize;

                // レイヤーが回転していれば、形状判定用に逆回転を適用
                if (u_rotation != 0.0) {
                    vec2 centered = local - 0.5;
                    float cR = cos(-u_rotation);
                    float sR = sin(-u_rotation);
                    local = vec2(
                        centered.x * cR - centered.y * sR,
                        centered.x * sR + centered.y * cR
                    ) + 0.5;
                }

                // 形状内判定
                bool inBox = (local.x >= 0.0 && local.x <= 1.0
                           && local.y >= 0.0 && local.y <= 1.0);
                if (u_shape == 1) {
                    // 楕円
                    vec2 d = local - vec2(0.5);
                    float e = (d.x * d.x) / 0.25 + (d.y * d.y) / 0.25;
                    inBox = e <= 1.0;
                } else if (u_shape == 2) {
                    // 上向き三角形：頂点(0.5,0), 底辺(0,1)〜(1,1)
                    // 重心座標で内外判定
                    vec2 a = vec2(0.5, 0.0);
                    vec2 b = vec2(0.0, 1.0);
                    vec2 c = vec2(1.0, 1.0);
                    vec2 v0 = c - b;
                    vec2 v1 = a - b;
                    vec2 v2 = local - b;
                    float dot00 = dot(v0, v0);
                    float dot01 = dot(v0, v1);
                    float dot02 = dot(v0, v2);
                    float dot11 = dot(v1, v1);
                    float dot12 = dot(v1, v2);
                    float invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01);
                    float u = (dot11 * dot02 - dot01 * dot12) * invDenom;
                    float v = (dot00 * dot12 - dot01 * dot02) * invDenom;
                    inBox = (u >= 0.0) && (v >= 0.0) && (u + v <= 1.0);
                } else if (u_shape == 3) {
                    // ハート：(-1..1) に正規化、UV座標系の y 反転で上向きハート
                    // ハート方程式: (x² + y² - 1)³ - x²y³ ≤ 0
                    vec2 p = (local - 0.5) * 2.4; // 矩形に収まるよう少し縮小
                    float ry = -p.y; // y軸反転（数学座標→UV）
                    float t = p.x * p.x + ry * ry - 1.0;
                    inBox = (t * t * t - p.x * p.x * ry * ry * ry) <= 0.0;
                }
                // 反転モードでは内外判定を反転
                bool shouldApply = (u_inverted == 1) ? !inBox : inBox;
                if (!shouldApply) discard;

                if (u_effect == 2) {
                    // 単色塗り（バケツ）
                    gl_FragColor = u_fill_color;
                } else if (u_effect == 3) {
                    // ノイズ（決定論的疑似乱数）
                    float n = fract(sin(dot(v_uv * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
                    gl_FragColor = vec4(vec3(n), 1.0);
                } else if (u_effect == 0) {
                    // ピクセレート: サンプリングUVを量子化
                    float cellsX = u_intensity;
                    float cellsY = u_intensity;
                    vec2 boxSize = vec2(u_sample_box.z - u_sample_box.x,
                                        u_sample_box.w - u_sample_box.y);
                    // レイヤーローカル (0..1) で量子化
                    vec2 local = (v_uv - u_sample_box.xy) / boxSize;
                    vec2 quantized = floor(local * cellsX) / cellsX + 0.5 / cellsX;
                    vec2 sampleUv = u_sample_box.xy + quantized * boxSize;
                    gl_FragColor = texture2D(u_tex, sampleUv);
                } else {
                    // ブラー（9タップ ボックス平均）
                    float r = u_intensity * 0.002;
                    vec4 sum = vec4(0.0);
                    sum += texture2D(u_tex, v_uv + vec2(-r, -r));
                    sum += texture2D(u_tex, v_uv + vec2( 0.0, -r));
                    sum += texture2D(u_tex, v_uv + vec2( r, -r));
                    sum += texture2D(u_tex, v_uv + vec2(-r,  0.0));
                    sum += texture2D(u_tex, v_uv);
                    sum += texture2D(u_tex, v_uv + vec2( r,  0.0));
                    sum += texture2D(u_tex, v_uv + vec2(-r,  r));
                    sum += texture2D(u_tex, v_uv + vec2( 0.0,  r));
                    sum += texture2D(u_tex, v_uv + vec2( r,  r));
                    gl_FragColor = sum / 9.0;
                }
            }
        """

        private fun compileShader(type: Int, src: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, src)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] == 0) {
                val log = GLES20.glGetShaderInfoLog(shader)
                GLES20.glDeleteShader(shader)
                throw RuntimeException("Shader compile failed: $log")
            }
            return shader
        }

        private fun buildProgram(vsSrc: String, fsSrc: String): Int {
            val vs = compileShader(GLES20.GL_VERTEX_SHADER, vsSrc)
            val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, fsSrc)
            val program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vs)
            GLES20.glAttachShader(program, fs)
            GLES20.glLinkProgram(program)
            val status = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
            if (status[0] == 0) {
                val log = GLES20.glGetProgramInfoLog(program)
                GLES20.glDeleteProgram(program)
                throw RuntimeException("Program link failed: $log")
            }
            GLES20.glDeleteShader(vs)
            GLES20.glDeleteShader(fs)
            return program
        }

        // Suppress unused imports
        private val _unused = listOf(::cos, ::sin)
    }
}
