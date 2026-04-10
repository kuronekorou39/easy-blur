import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import '../widgets/top_toolbar.dart';
import '../widgets/video_editor_bottom_sheet.dart';

class VideoEditorScreen extends StatefulWidget {
  final EditorProject project;

  const VideoEditorScreen({super.key, required this.project});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    with TickerProviderStateMixin {
  late EditorProject _project;
  late VideoPlayerController _videoController;
  bool _loading = true;
  bool _playing = false;
  Duration _currentTime = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _positionTimer;
  Size _videoSize = Size.zero;

  // Viewport state
  Offset _viewOffset = Offset.zero;
  double _viewScale = 1.0;
  Offset _scaleStartFocal = Offset.zero;
  double _scaleStartScale = 1.0;
  Offset _scaleStartOffset = Offset.zero;

  // Gesture state
  _GestureMode _gestureMode = _GestureMode.none;
  Offset _lastFocal = Offset.zero;
  Size? _resizeStartSize;
  int _activeLayerIndex = -1;

  // Double-tap reset
  late final AnimationController _resetCtrl;
  late Animation<double> _resetScale;
  late Animation<Offset> _resetOffset;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _resetCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _resetCtrl.addListener(() {
      setState(() {
        _viewScale = _resetScale.value;
        _viewOffset = _resetOffset.value;
      });
    });
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoController =
        VideoPlayerController.file(File(_project.mediaPath));
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
    _resetCtrl.dispose();
    super.dispose();
  }

  // --- Playback ---

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

  // --- Layer management ---

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
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
    Keyframe? closest;
    int closestDist = 999999999;
    for (final kf in layer.keyframes) {
      final dist =
          (kf.time.inMilliseconds - _currentTime.inMilliseconds).abs();
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

  // --- Coordinate conversion ---

  Offset _screenToVideo(Offset screenPos, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final adjusted = (screenPos - center - _viewOffset) / _viewScale + center;
    return Offset(
      adjusted.dx / canvasSize.width * _videoSize.width,
      adjusted.dy / canvasSize.height * _videoSize.height,
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

  bool _isNearCorner(Offset vidPos, Keyframe state) {
    final corners = [
      Offset(state.position.dx + state.size.width / 2,
          state.position.dy + state.size.height / 2),
      Offset(state.position.dx - state.size.width / 2,
          state.position.dy - state.size.height / 2),
      Offset(state.position.dx + state.size.width / 2,
          state.position.dy - state.size.height / 2),
      Offset(state.position.dx - state.size.width / 2,
          state.position.dy + state.size.height / 2),
    ];
    final threshold = _videoSize.shortestSide * 0.06;
    return corners.any((c) => (vidPos - c).distance < threshold);
  }

  // --- Gesture handlers ---

  void _onScaleStart(ScaleStartDetails details, Size canvasSize) {
    _scaleStartFocal = details.focalPoint;
    _scaleStartScale = _viewScale;
    _scaleStartOffset = _viewOffset;
    _lastFocal = details.focalPoint;

    if (details.pointerCount >= 2) {
      _gestureMode = _GestureMode.viewportZoom;
      return;
    }

    final localPos = details.localFocalPoint;
    final vidPos = _screenToVideo(localPos, canvasSize);
    final hitIndex = _hitTestLayers(vidPos);

    if (hitIndex >= 0) {
      _activeLayerIndex = hitIndex;
      setState(() => _project.selectedLayerIndex = hitIndex);
      final state = _project.layers[hitIndex].getStateAt(_currentTime);

      if (_isNearCorner(vidPos, state)) {
        _gestureMode = _GestureMode.resizeObject;
        _resizeStartSize = state.size;
      } else {
        _gestureMode = _GestureMode.moveObject;
      }
    } else {
      _gestureMode = _GestureMode.viewportPan;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size canvasSize) {
    switch (_gestureMode) {
      case _GestureMode.viewportZoom:
        setState(() {
          _viewScale =
              (_scaleStartScale * details.scale).clamp(0.5, 5.0);
          _viewOffset = _scaleStartOffset +
              (details.focalPoint - _scaleStartFocal);
        });
        break;

      case _GestureMode.viewportPan:
        setState(() {
          _viewOffset += details.focalPoint - _lastFocal;
        });
        break;

      case _GestureMode.moveObject:
        final layer = _project.layers[_activeLayerIndex];
        if (layer.keyframes.isEmpty) break;

        // Find or create keyframe at current time
        Keyframe? kf;
        for (final k in layer.keyframes) {
          if ((k.time.inMilliseconds - _currentTime.inMilliseconds)
                  .abs() <
              100) {
            kf = k;
            break;
          }
        }
        if (kf == null) {
          kf = layer.getStateAt(_currentTime).copyWith(time: _currentTime);
          layer.addKeyframe(kf);
        }

        final delta = details.focalPoint - _lastFocal;
        final canvasScale = canvasSize.width / _videoSize.width;
        final vidDelta = Offset(
          delta.dx / (canvasScale * _viewScale),
          delta.dy / (canvasScale * _viewScale),
        );
        setState(() {
          kf!.position = Offset(
            kf.position.dx + vidDelta.dx,
            kf.position.dy + vidDelta.dy,
          );
        });
        break;

      case _GestureMode.resizeObject:
        final layer = _project.layers[_activeLayerIndex];
        if (layer.keyframes.isEmpty || _resizeStartSize == null) break;

        Keyframe? kf;
        for (final k in layer.keyframes) {
          if ((k.time.inMilliseconds - _currentTime.inMilliseconds)
                  .abs() <
              100) {
            kf = k;
            break;
          }
        }
        if (kf == null) {
          kf = layer.getStateAt(_currentTime).copyWith(time: _currentTime);
          layer.addKeyframe(kf);
        }

        final totalDelta = details.focalPoint - _scaleStartFocal;
        final canvasScale2 = canvasSize.width / _videoSize.width;
        final vidDelta2 = Offset(
          totalDelta.dx / (canvasScale2 * _viewScale),
          totalDelta.dy / (canvasScale2 * _viewScale),
        );
        setState(() {
          kf!.size = Size(
            (_resizeStartSize!.width + vidDelta2.dx * 2)
                .clamp(20, _videoSize.width),
            (_resizeStartSize!.height + vidDelta2.dy * 2)
                .clamp(20, _videoSize.height),
          );
        });
        break;

      case _GestureMode.none:
        break;
    }
    _lastFocal = details.focalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureMode = _GestureMode.none;
    _activeLayerIndex = -1;
    _resizeStartSize = null;
  }

  void _onDoubleTap() {
    _resetScale =
        Tween(begin: _viewScale, end: 1.0).animate(CurvedAnimation(
      parent: _resetCtrl,
      curve: Curves.easeOutCubic,
    ));
    _resetOffset =
        Tween(begin: _viewOffset, end: Offset.zero).animate(CurvedAnimation(
      parent: _resetCtrl,
      curve: Curves.easeOutCubic,
    ));
    _resetCtrl.forward(from: 0);
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Full-screen video canvas
                Positioned.fill(
                  child: Container(
                    color: AppTheme.bgPrimary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvasSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: (d) =>
                              _onScaleStart(d, canvasSize),
                          onScaleUpdate: (d) =>
                              _onScaleUpdate(d, canvasSize),
                          onScaleEnd: _onScaleEnd,
                          onDoubleTap: _onDoubleTap,
                          child: Center(
                            child: Transform(
                              transform: Matrix4.identity()
                                ..translateByDouble(
                                    _viewOffset.dx, _viewOffset.dy, 0, 0)
                                ..scaleByDouble(
                                    _viewScale, _viewScale, 1, 0),
                              alignment: Alignment.center,
                              child: AspectRatio(
                                aspectRatio:
                                    _videoSize.width / _videoSize.height,
                                child: Stack(
                                  children: [
                                    VideoPlayer(_videoController),
                                    CustomPaint(
                                      size: canvasSize,
                                      painter:
                                          _VideoMosaicOverlayPainter(
                                        layers: _project.layers,
                                        currentTime: _currentTime,
                                        mediaSize: _videoSize,
                                        selectedLayerIndex:
                                            _project.selectedLayerIndex,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Top toolbar
                Positioned(
                  top: topPad + 6,
                  left: 12,
                  right: 12,
                  child: TopToolbar(
                    title: '動画エディタ',
                    onBack: () => Navigator.of(context).pop(),
                    onAddLayer: _addLayer,
                  ),
                ),

                // Bottom sheet
                VideoEditorBottomSheet(
                  isPlaying: _playing,
                  currentTime: _currentTime,
                  totalDuration: _totalDuration,
                  onTogglePlay: _togglePlayPause,
                  onSeek: _seekTo,
                  onAddKeyframe: _addKeyframeToLayer,
                  onSelectKeyframe: _selectKeyframe,
                  onDeleteKeyframe: _deleteKeyframe,
                  selectedLayer: _project.selectedLayer,
                  onTypeChanged: _onTypeChanged,
                  onShapeChanged: _onShapeChanged,
                  onIntensityChanged: _onIntensityChanged,
                  layers: _project.layers,
                  selectedIndex: _project.selectedLayerIndex,
                  onSelectLayer: _selectLayer,
                  onAddLayer: _addLayer,
                  onDeleteLayer: _deleteLayer,
                  onToggleVisibility: _toggleVisibility,
                  onReorderLayers: _reorderLayers,
                ),
              ],
            ),
    );
  }
}

enum _GestureMode {
  none,
  viewportPan,
  viewportZoom,
  moveObject,
  resizeObject,
}

/// Overlay painter for video mode
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
      _drawMosaicOverlay(
          canvas, size, layer, state, scaleX, scaleY, i == selectedLayerIndex);
    }
  }

  void _drawMosaicOverlay(
    Canvas canvas,
    Size canvasSize,
    MosaicLayer layer,
    Keyframe state,
    double scaleX,
    double scaleY,
    bool isSelected,
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

    final path = Path();
    if (layer.shape == MosaicShape.ellipse) {
      path.addOval(rect);
    } else {
      path.addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    }
    canvas.clipPath(path);

    switch (layer.type) {
      case MosaicType.pixelate:
        final blockSize =
            (state.intensity * scaleX * 0.5).clamp(2.0, 100.0);
        final paint = Paint();
        for (double y = rect.top; y < rect.bottom; y += blockSize) {
          for (double x = rect.left; x < rect.right; x += blockSize) {
            final bw = (rect.right - x).clamp(0.0, blockSize);
            final bh = (rect.bottom - y).clamp(0.0, blockSize);
            final hash =
                (x ~/ blockSize * 17 + y ~/ blockSize * 31) % 255;
            paint.color =
                Color.fromARGB(180, hash ~/ 2, hash ~/ 2, hash ~/ 2);
            canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
          }
        }
        break;
      case MosaicType.blur:
        canvas.saveLayer(
            rect,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: state.intensity * 0.8,
                sigmaY: state.intensity * 0.8,
              ));
        canvas.drawRect(
            rect, Paint()..color = Colors.grey.withAlpha(100));
        canvas.restore();
        break;
      case MosaicType.blackout:
        canvas.drawRect(rect, Paint()..color = Colors.black);
        break;
    }

    canvas.restore();

    // Selection
    if (isSelected) {
      _drawSelection(canvas, rect, state, cx, cy);
    }
  }

  void _drawSelection(
      Canvas canvas, Rect rect, Keyframe state, double cx, double cy) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    const accentColor = Color(0xFF6c5ce7);
    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final inflated = rect.inflate(2);

    // Dashed border
    _drawDashedRect(canvas, inflated, borderPaint);

    // Corner handles
    const handleRadius = 7.0;
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final corner in [
      inflated.topLeft,
      inflated.topRight,
      inflated.bottomLeft,
      inflated.bottomRight,
    ]) {
      canvas.drawCircle(corner, handleRadius, handleFill);
      canvas.drawCircle(corner, handleRadius, handleStroke);
    }

    canvas.restore();
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    const total = dash + gap;
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, total, dash);
    _drawDashedLine(
        canvas, rect.topRight, rect.bottomRight, paint, total, dash);
    _drawDashedLine(
        canvas, rect.bottomRight, rect.bottomLeft, paint, total, dash);
    _drawDashedLine(
        canvas, rect.bottomLeft, rect.topLeft, paint, total, dash);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      double totalDash, double dashLength) {
    final delta = end - start;
    final length = delta.distance;
    if (length == 0) return;
    final dir = Offset(delta.dx / length, delta.dy / length);
    double drawn = 0;
    while (drawn < length) {
      final segEnd =
          drawn + dashLength > length ? length : drawn + dashLength;
      canvas.drawLine(
        Offset(start.dx + dir.dx * drawn, start.dy + dir.dy * drawn),
        Offset(start.dx + dir.dx * segEnd, start.dy + dir.dy * segEnd),
        paint,
      );
      drawn += totalDash;
    }
  }

  @override
  bool shouldRepaint(covariant _VideoMosaicOverlayPainter old) {
    return old.currentTime != currentTime ||
        old.layers != layers ||
        old.selectedLayerIndex != selectedLayerIndex;
  }
}
