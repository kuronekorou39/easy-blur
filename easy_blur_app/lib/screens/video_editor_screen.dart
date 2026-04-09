import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import '../widgets/layer_panel.dart';
import '../widgets/property_panel.dart';
import '../widgets/timeline_panel.dart';

class VideoEditorScreen extends StatefulWidget {
  final EditorProject project;

  const VideoEditorScreen({super.key, required this.project});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  late EditorProject _project;
  late VideoPlayerController _videoController;
  bool _loading = true;
  bool _playing = false;
  Duration _currentTime = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _positionTimer;
  Size _videoSize = Size.zero;

  // Gesture state
  Offset? _panStart;
  Size? _resizeStart;
  Offset? _posStart;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.file(File(_project.mediaPath));
    await _videoController.initialize();

    setState(() {
      _totalDuration = _videoController.value.duration;
      _project.videoDuration = _totalDuration;
      _videoSize = Size(
        _videoController.value.size.width,
        _videoController.value.size.height,
      );
      _loading = false;
    });

    // Poll position
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        if (!mounted) return;
        final pos = _videoController.value.position;
        if (pos != _currentTime) {
          setState(() => _currentTime = pos);
        }
      },
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _videoController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_playing) {
        _videoController.pause();
      } else {
        _videoController.play();
      }
      _playing = !_playing;
    });
  }

  void _seekTo(Duration time) {
    _videoController.seekTo(time);
    setState(() => _currentTime = time);
  }

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      // Add initial keyframe at current time
      layer.addKeyframe(Keyframe(
        time: _currentTime,
        position: Offset(_videoSize.width / 2, _videoSize.height / 2),
        size: Size(_videoSize.width * 0.25, _videoSize.height * 0.2),
        intensity: 20,
      ));
    });
  }

  void _deleteLayer(int index) {
    setState(() => _project.removeLayer(index));
  }

  void _selectLayer(int index) {
    setState(() => _project.selectedLayerIndex = index);
  }

  void _toggleVisibility(int index) {
    setState(() {
      _project.layers[index].visible = !_project.layers[index].visible;
    });
  }

  void _reorderLayers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _project.reorderLayer(oldIndex, newIndex);
    });
  }

  void _onTypeChanged(MosaicType type) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.type = type);
  }

  void _onShapeChanged(MosaicShape shape) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.shape = shape);
  }

  void _onIntensityChanged(double value) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.keyframes.isEmpty) return;
    // Update the keyframe closest to current time
    Keyframe? closest;
    int closestDist = 999999999;
    for (final kf in layer.keyframes) {
      final dist = (kf.time.inMilliseconds - _currentTime.inMilliseconds).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closest = kf;
      }
    }
    if (closest != null) {
      setState(() => closest!.intensity = value);
    }
  }

  void _addKeyframeToLayer(int layerIndex) {
    final layer = _project.layers[layerIndex];
    // Get current interpolated state and add as new keyframe
    final current = layer.getStateAt(_currentTime);
    setState(() {
      layer.addKeyframe(Keyframe(
        time: _currentTime,
        position: current.position,
        size: current.size,
        rotation: current.rotation,
        intensity: current.intensity,
      ));
    });
  }

  void _selectKeyframe(int layerIndex, int keyframeIndex) {
    _selectLayer(layerIndex);
    final kf = _project.layers[layerIndex].keyframes[keyframeIndex];
    _seekTo(kf.time);
  }

  void _deleteKeyframe(int layerIndex, int keyframeIndex) {
    setState(() {
      _project.layers[layerIndex].removeKeyframeAt(keyframeIndex);
    });
  }

  Offset _toVideoCoords(Offset localPos, Size canvasSize) {
    return Offset(
      localPos.dx / canvasSize.width * _videoSize.width,
      localPos.dy / canvasSize.height * _videoSize.height,
    );
  }

  int _hitTestLayers(Offset vidPos) {
    for (int i = _project.layers.length - 1; i >= 0; i--) {
      final layer = _project.layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;
      final st = layer.getStateAt(_currentTime);
      final dx = (vidPos.dx - st.position.dx).abs();
      final dy = (vidPos.dy - st.position.dy).abs();
      if (dx < st.size.width / 2 + 20 && dy < st.size.height / 2 + 20) {
        return i;
      }
    }
    return -1;
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    final vidPos = _toVideoCoords(details.localPosition, canvasSize);

    final hitIndex = _hitTestLayers(vidPos);
    if (hitIndex < 0) return;

    setState(() => _project.selectedLayerIndex = hitIndex);
    final state = _project.layers[hitIndex].getStateAt(_currentTime);

    final corners = [
      Offset(state.position.dx + state.size.width / 2, state.position.dy + state.size.height / 2),
      Offset(state.position.dx - state.size.width / 2, state.position.dy - state.size.height / 2),
      Offset(state.position.dx + state.size.width / 2, state.position.dy - state.size.height / 2),
      Offset(state.position.dx - state.size.width / 2, state.position.dy + state.size.height / 2),
    ];
    final threshold = _videoSize.width * 0.05;
    bool nearCorner = corners.any((c) => (vidPos - c).distance < threshold);

    if (nearCorner) {
      _resizeStart = state.size;
      _posStart = state.position;
      _panStart = vidPos;
    } else {
      _panStart = vidPos;
      _posStart = state.position;
      _resizeStart = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.keyframes.isEmpty || _panStart == null) return;

    // Find or create keyframe at current time
    Keyframe? kf;
    for (final k in layer.keyframes) {
      if ((k.time.inMilliseconds - _currentTime.inMilliseconds).abs() < 100) {
        kf = k;
        break;
      }
    }
    if (kf == null) {
      // Auto-create keyframe at current time
      kf = layer.getStateAt(_currentTime).copyWith(time: _currentTime);
      layer.addKeyframe(kf);
    }

    final vidPos = _toVideoCoords(details.localPosition, canvasSize);

    setState(() {
      if (_resizeStart != null) {
        final delta = vidPos - _panStart!;
        kf!.size = Size(
          (_resizeStart!.width + delta.dx * 2).clamp(20, _videoSize.width),
          (_resizeStart!.height + delta.dy * 2).clamp(20, _videoSize.height),
        );
      } else {
        final delta = vidPos - _panStart!;
        kf!.position = _posStart! + delta;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _panStart = null;
    _resizeStart = null;
    _posStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('動画エディタ', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            tooltip: '動画を書き出し',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('動画書き出し機能は開発中です'),
                  backgroundColor: AppTheme.accent,
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Video canvas area
                Expanded(
                  child: Container(
                    color: AppTheme.bgPrimary,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _videoSize.width / _videoSize.height,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            return GestureDetector(
                              onPanStart: (d) => _onPanStart(d, canvasSize),
                              onPanUpdate: (d) => _onPanUpdate(d, canvasSize),
                              onPanEnd: _onPanEnd,
                              child: Stack(
                                children: [
                                  // Video player
                                  VideoPlayer(_videoController),
                                  // Mosaic overlay
                                  CustomPaint(
                                    size: canvasSize,
                                    painter: _VideoMosaicOverlayPainter(
                                      layers: _project.layers,
                                      currentTime: _currentTime,
                                      mediaSize: _videoSize,
                                      selectedLayerIndex: _project.selectedLayerIndex,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Playback controls
                Container(
                  color: AppTheme.bgSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppTheme.textPrimary,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      Text(
                        '${_formatDuration(_currentTime)} / ${_formatDuration(_totalDuration)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),

                // Timeline
                TimelinePanel(
                  layers: _project.layers,
                  selectedLayerIndex: _project.selectedLayerIndex,
                  currentTime: _currentTime,
                  totalDuration: _totalDuration,
                  onSeek: _seekTo,
                  onAddKeyframe: _addKeyframeToLayer,
                  onSelectKeyframe: _selectKeyframe,
                  onDeleteKeyframe: _deleteKeyframe,
                ),

                // Property panel
                PropertyPanel(
                  layer: _project.selectedLayer,
                  onTypeChanged: _onTypeChanged,
                  onShapeChanged: _onShapeChanged,
                  onIntensityChanged: _onIntensityChanged,
                ),

                // Layer panel
                LayerPanel(
                  layers: _project.layers,
                  selectedIndex: _project.selectedLayerIndex,
                  onSelect: _selectLayer,
                  onAdd: _addLayer,
                  onDelete: _deleteLayer,
                  onToggleVisibility: _toggleVisibility,
                  onReorder: _reorderLayers,
                ),
              ],
            ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Overlay painter for video mode - draws mosaic regions without the base image
/// (since VideoPlayer widget handles that).
class _VideoMosaicOverlayPainter extends CustomPainter {
  final List<MosaicLayer> layers;
  final Duration currentTime;
  final Size mediaSize;
  final int? selectedLayerIndex;

  _VideoMosaicOverlayPainter({
    required this.layers,
    required this.currentTime,
    required this.mediaSize,
    this.selectedLayerIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / mediaSize.width;
    final scaleY = size.height / mediaSize.height;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;

      final state = layer.getStateAt(currentTime);
      _drawMosaicOverlay(canvas, layer, state, scaleX, scaleY, i == selectedLayerIndex);
    }
  }

  void _drawMosaicOverlay(
    Canvas canvas, MosaicLayer layer, Keyframe state,
    double scaleX, double scaleY, bool isSelected,
  ) {
    final cx = state.position.dx * scaleX;
    final cy = state.position.dy * scaleY;
    final w = state.size.width * scaleX;
    final h = state.size.height * scaleY;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    // Clip to shape
    final path = Path();
    if (layer.shape == MosaicShape.ellipse) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    }
    canvas.clipPath(path);

    // Draw effect
    switch (layer.type) {
      case MosaicType.pixelate:
        final blockSize = (state.intensity * scaleX * 0.5).clamp(2.0, 100.0);
        final paint = Paint();
        for (double y = rect.top; y < rect.bottom; y += blockSize) {
          for (double x = rect.left; x < rect.right; x += blockSize) {
            final bw = (rect.right - x).clamp(0.0, blockSize);
            final bh = (rect.bottom - y).clamp(0.0, blockSize);
            final hash = (x ~/ blockSize * 17 + y ~/ blockSize * 31) % 255;
            paint.color = Color.fromARGB(180, hash ~/ 2, hash ~/ 2, hash ~/ 2);
            canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
          }
        }
        break;
      case MosaicType.blur:
        canvas.saveLayer(rect, Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: state.intensity * 0.8,
            sigmaY: state.intensity * 0.8,
          ));
        canvas.drawRect(rect, Paint()..color = Colors.grey.withAlpha(100));
        canvas.restore();
        break;
      case MosaicType.blackout:
        canvas.drawRect(rect, Paint()..color = Colors.black);
        break;
    }

    canvas.restore();

    // Selection border
    if (isSelected) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(state.rotation);
      canvas.translate(-cx, -cy);

      final borderPaint = Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect.inflate(2), borderPaint);

      final handlePaint = Paint()..color = Colors.white;
      for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
        canvas.drawRect(
          Rect.fromCenter(center: corner, width: 8, height: 8),
          handlePaint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: corner, width: 8, height: 8),
          borderPaint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VideoMosaicOverlayPainter old) {
    return old.currentTime != currentTime ||
        old.layers != layers ||
        old.selectedLayerIndex != selectedLayerIndex;
  }
}
