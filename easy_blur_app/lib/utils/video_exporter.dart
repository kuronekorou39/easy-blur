import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// Video export pipeline.
///
/// Flow:
/// 1. Extract frames from video using VideoPlayerController
/// 2. For each frame, render mosaic layers via Canvas
/// 3. Save as PNG sequence
/// 4. Reassemble with FFmpeg (ffmpeg_kit_flutter)
///
/// Note: ffmpeg_kit_flutter is not yet added to dependencies.
/// This class provides the structure for when it is integrated.
class VideoExporter {
  final EditorProject project;
  final ValueChanged<double>? onProgress;

  VideoExporter({required this.project, this.onProgress});

  Future<String?> export() async {
    if (!project.isVideo || project.videoDuration == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(dir.path, 'mosaic_$timestamp.mp4');

    // TODO: Integrate ffmpeg_kit_flutter for actual frame-by-frame processing
    //
    // The approach:
    //
    // 1. Use FFmpegKit to extract frames:
    //    ffmpeg -i input.mp4 -vf fps=30 frames/%04d.png
    //
    // 2. For each frame image:
    //    a. Load as ui.Image
    //    b. Create Canvas + PictureRecorder
    //    c. Draw the frame image
    //    d. For each visible layer, call getStateAt(frameTime)
    //       to get interpolated position/size/rotation/intensity
    //    e. Apply mosaic effect to the clipped region
    //    f. Save composited frame as PNG
    //
    // 3. Reassemble with FFmpeg:
    //    ffmpeg -framerate 30 -i frames/%04d.png -i input.mp4
    //           -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p output.mp4
    //
    // 4. Clean up temp frames

    return outPath;
  }

  /// Render a single frame with mosaic layers applied.
  Future<ui.Image> renderFrame(
    ui.Image frameImage,
    Size frameSize,
    Duration time,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw base frame
    canvas.drawImage(frameImage, Offset.zero, Paint());

    // Draw each mosaic layer at interpolated state
    for (final layer in project.layers) {
      if (!layer.visible || layer.keyframes.isEmpty) continue;

      final state = layer.getStateAt(time);

      // Check if this time is within the layer's active range
      if (time < layer.keyframes.first.time) continue;
      if (time > layer.keyframes.last.time) continue;

      _applyMosaic(canvas, frameSize, layer, state);
    }

    final picture = recorder.endRecording();
    return picture.toImage(frameSize.width.round(), frameSize.height.round());
  }

  void _applyMosaic(
    Canvas canvas, Size frameSize, MosaicLayer layer, Keyframe state,
  ) {
    final cx = state.position.dx;
    final cy = state.position.dy;
    final w = state.size.width;
    final h = state.size.height;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    final path = Path();
    if (layer.shape == MosaicShape.ellipse) {
      path.addOval(rect);
    } else {
      path.addRect(rect);
    }
    canvas.clipPath(path);

    switch (layer.type) {
      case MosaicType.pixelate:
        // For production: read pixel data from the frame image,
        // average blocks, and draw colored rectangles
        final blockSize = state.intensity.clamp(2.0, 100.0);
        final paint = Paint();
        for (double y = rect.top; y < rect.bottom; y += blockSize) {
          for (double x = rect.left; x < rect.right; x += blockSize) {
            final bw = (rect.right - x).clamp(0.0, blockSize);
            final bh = (rect.bottom - y).clamp(0.0, blockSize);
            // In production, sample actual pixel colors here
            paint.color = const Color.fromARGB(200, 128, 128, 128);
            canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
          }
        }
        break;
      case MosaicType.blur:
        canvas.saveLayer(rect, Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: state.intensity,
            sigmaY: state.intensity,
          ));
        canvas.drawRect(rect, Paint()..color = Colors.transparent);
        canvas.restore();
        break;
      case MosaicType.blackout:
        canvas.drawRect(rect, Paint()..color = Colors.black);
        break;
    }

    canvas.restore();
  }
}
