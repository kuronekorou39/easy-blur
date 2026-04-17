package com.easyblur.easy_blur_app

import android.graphics.SurfaceTexture
import android.view.Surface

/**
 * デコーダーの出力先となる Surface/SurfaceTexture。
 * SurfaceTexture の更新を同期的に待つ awaitNewImage() を提供。
 */
class OutputSurface(textureId: Int) :
    SurfaceTexture.OnFrameAvailableListener {

    private val surfaceTexture: SurfaceTexture
    val surface: Surface
    private val frameSyncLock = Object()
    private var frameAvailable = false
    private val transformMatrix = FloatArray(16)

    init {
        surfaceTexture = SurfaceTexture(textureId)
        surfaceTexture.setOnFrameAvailableListener(this)
        surface = Surface(surfaceTexture)
    }

    fun awaitNewImage() {
        synchronized(frameSyncLock) {
            var waited = 0L
            while (!frameAvailable) {
                frameSyncLock.wait(500)
                if (!frameAvailable) {
                    waited += 500
                    if (waited > 2500) {
                        throw RuntimeException(
                            "Frame wait timed out"
                        )
                    }
                }
            }
            frameAvailable = false
        }
        surfaceTexture.updateTexImage()
    }

    fun drawImage() {
        // 実際の描画は MosaicRenderer 内で行うため、ここでは transform を取得のみ
        surfaceTexture.getTransformMatrix(transformMatrix)
    }

    fun getTransformMatrix(): FloatArray = transformMatrix

    override fun onFrameAvailable(st: SurfaceTexture?) {
        synchronized(frameSyncLock) {
            frameAvailable = true
            frameSyncLock.notifyAll()
        }
    }

    fun release() {
        surface.release()
        surfaceTexture.release()
    }
}
