import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// Android ネイティブ (Kotlin + MediaCodec + OpenGL) でモザイクを焼き込んだ動画を出力
class VideoExporter {
  static const _channel =
      MethodChannel('com.easyblur.easy_blur_app/video_processor');

  static final _progressController = StreamController<double>.broadcast();
  static bool _listenerRegistered = false;

  static void _registerListener() {
    if (_listenerRegistered) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final v = (call.arguments as num).toDouble();
        _progressController.add(v);
      }
    });
    _listenerRegistered = true;
  }

  /// 動画書き出しを実行
  /// [videoSize] は表示座標系（回転補正後）のサイズ
  /// 返り値は出力ファイルパス
  static Future<String> export({
    required EditorProject project,
    required Size videoSize,
    required int rotationDegrees,
    ValueChanged<double>? onProgress,
  }) async {
    _registerListener();
    if (!project.isVideo) {
      throw Exception('動画ではありません');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(tempDir.path, 'easy_blur_$timestamp.mp4');
    // 既存削除
    final outFile = File(outPath);
    if (await outFile.exists()) await outFile.delete();

    // レイヤー情報をJSON化（表示座標系、ピクセル単位）
    final layersJson = _buildLayersJson(project.layers, videoSize);

    StreamSubscription<double>? sub;
    if (onProgress != null) {
      sub = _progressController.stream.listen(onProgress);
    }

    try {
      final result = await _channel.invokeMethod<String>('processVideo', {
        'inputPath': project.mediaPath,
        'outputPath': outPath,
        'layersJson': layersJson,
        'videoWidth': videoSize.width.round(),
        'videoHeight': videoSize.height.round(),
        'rotationDegrees': rotationDegrees,
      });
      if (result == null || !await File(result).exists()) {
        throw Exception('出力ファイルが生成されませんでした');
      }
      return result;
    } finally {
      await sub?.cancel();
    }
  }

  static String _buildLayersJson(
      List<MosaicLayer> layers, Size videoSize) {
    final list = <Map<String, dynamic>>[];
    for (final l in layers) {
      if (!l.visible || l.keyframes.isEmpty) continue;

      final keyframes = l.keyframes
          .map((kf) => {
                'timeMs': kf.time.inMilliseconds,
                'cx': kf.position.dx,
                'cy': kf.position.dy,
                'w': kf.size.width,
                'h': kf.size.height,
                'intensity': kf.intensity,
              })
          .toList();

      list.add({
        'type': l.type.name,
        'shape': l.shape.name,
        'startMs': l.startTime.inMilliseconds,
        'endMs': l.endTime.inMilliseconds,
        'keyframes': keyframes,
      });
    }
    return jsonEncode(list);
  }
}
