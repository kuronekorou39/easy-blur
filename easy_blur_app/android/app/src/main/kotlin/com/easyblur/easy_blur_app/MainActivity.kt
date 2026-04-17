package com.easyblur.easy_blur_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.easyblur.easy_blur_app/video_processor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "processVideo" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as Map<String, Any>
                    val inputPath = args["inputPath"] as String
                    val outputPath = args["outputPath"] as String
                    val layersJson = args["layersJson"] as String
                    val videoWidth = (args["videoWidth"] as Number).toInt()
                    val videoHeight = (args["videoHeight"] as Number).toInt()
                    val rotationDegrees =
                        (args["rotationDegrees"] as Number).toInt()

                    Thread {
                        try {
                            val processor = VideoMosaicProcessor()
                            processor.process(
                                inputPath = inputPath,
                                outputPath = outputPath,
                                layersJson = layersJson,
                                videoWidth = videoWidth,
                                videoHeight = videoHeight,
                                rotationDegrees = rotationDegrees,
                                onProgress = { progress ->
                                    runOnUiThread {
                                        channel.invokeMethod(
                                            "onProgress",
                                            progress
                                        )
                                    }
                                }
                            )
                            runOnUiThread { result.success(outputPath) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error(
                                    "PROCESS_ERROR",
                                    e.message ?: "不明なエラー",
                                    e.stackTraceToString()
                                )
                            }
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }
    }
}
