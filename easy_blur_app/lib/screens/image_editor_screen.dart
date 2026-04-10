import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../painters/mosaic_painter.dart';
import '../utils/theme.dart';
import '../widgets/editor_bottom_sheet.dart';
import '../widgets/top_toolbar.dart';

class ImageEditorScreen extends StatefulWidget {
  final EditorProject project;

  const ImageEditorScreen({super.key, required this.project});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen>
    with TickerProviderStateMixin {
  late EditorProject _project;
  ui.Image? _uiImage;
  Size _imageSize = Size.zero;
  bool _loading = true;
  bool _saving = false;
  final GlobalKey _canvasKey = GlobalKey();

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

  // Double-tap reset animation
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
    _loadImage();
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final file = File(_project.mediaPath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _uiImage = frame.image;
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      _loading = false;
    });
  }

  // --- Layer management ---

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      layer.addKeyframe(Keyframe(
        time: Duration.zero,
        position: Offset(_imageSize.width / 2, _imageSize.height / 2),
        size: Size(_imageSize.width * 0.25, _imageSize.height * 0.2),
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
    setState(() => layer.keyframes.first.intensity = value);
  }

  // --- Coordinate conversion ---

  Offset _screenToImage(Offset screenPos, Size canvasSize) {
    // Reverse viewport transform, then map to image coords
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final adjusted = (screenPos - center - _viewOffset) / _viewScale + center;
    return Offset(
      adjusted.dx / canvasSize.width * _imageSize.width,
      adjusted.dy / canvasSize.height * _imageSize.height,
    );
  }

  int _hitTestLayers(Offset imgPos) {
    for (int i = _project.layers.length - 1; i >= 0; i--) {
      final layer = _project.layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;
      final kf = layer.keyframes.first;
      final dx = (imgPos.dx - kf.position.dx).abs();
      final dy = (imgPos.dy - kf.position.dy).abs();
      if (dx < kf.size.width / 2 + 20 && dy < kf.size.height / 2 + 20) {
        return i;
      }
    }
    return -1;
  }

  bool _isNearCorner(Offset imgPos, Keyframe kf) {
    final corners = [
      Offset(kf.position.dx + kf.size.width / 2,
          kf.position.dy + kf.size.height / 2),
      Offset(kf.position.dx - kf.size.width / 2,
          kf.position.dy - kf.size.height / 2),
      Offset(kf.position.dx + kf.size.width / 2,
          kf.position.dy - kf.size.height / 2),
      Offset(kf.position.dx - kf.size.width / 2,
          kf.position.dy + kf.size.height / 2),
    ];
    final threshold = _imageSize.shortestSide * 0.06;
    return corners.any((c) => (imgPos - c).distance < threshold);
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

    // Single finger: try to hit a layer
    final localPos = details.localFocalPoint;
    final imgPos = _screenToImage(localPos, canvasSize);
    final hitIndex = _hitTestLayers(imgPos);

    if (hitIndex >= 0) {
      _activeLayerIndex = hitIndex;
      setState(() => _project.selectedLayerIndex = hitIndex);
      final kf = _project.layers[hitIndex].keyframes.first;

      if (_isNearCorner(imgPos, kf)) {
        _gestureMode = _GestureMode.resizeObject;
        _resizeStartSize = kf.size;
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
          _viewScale = (_scaleStartScale * details.scale).clamp(0.5, 5.0);
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
        final kf = layer.keyframes.first;
        // Relative movement: delta in image coordinates
        final delta = details.focalPoint - _lastFocal;
        final canvasScale =
            canvasSize.width / _imageSize.width;
        final imgDelta = Offset(
          delta.dx / (canvasScale * _viewScale),
          delta.dy / (canvasScale * _viewScale),
        );
        setState(() {
          kf.position = Offset(
            kf.position.dx + imgDelta.dx,
            kf.position.dy + imgDelta.dy,
          );
        });
        break;

      case _GestureMode.resizeObject:
        final layer = _project.layers[_activeLayerIndex];
        if (layer.keyframes.isEmpty || _resizeStartSize == null) break;
        final kf = layer.keyframes.first;
        final totalDelta = details.focalPoint - _scaleStartFocal;
        final canvasScale = canvasSize.width / _imageSize.width;
        final imgDelta = Offset(
          totalDelta.dx / (canvasScale * _viewScale),
          totalDelta.dy / (canvasScale * _viewScale),
        );
        setState(() {
          kf.size = Size(
            (_resizeStartSize!.width + imgDelta.dx * 2)
                .clamp(20, _imageSize.width),
            (_resizeStartSize!.height + imgDelta.dy * 2)
                .clamp(20, _imageSize.height),
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

  // --- Save ---

  Future<void> _saveImage() async {
    if (_uiImage == null) return;
    setState(() => _saving = true);

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = MosaicPainter(
        mediaImage: _uiImage,
        layers: _project.layers,
        currentTime: Duration.zero,
        mediaSize: _imageSize,
        selectedLayerIndex: null,
      );
      painter.paint(canvas, _imageSize);

      final picture = recorder.endRecording();
      final img = await picture.toImage(
        _imageSize.width.round(),
        _imageSize.height.round(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName =
          p.basenameWithoutExtension(_project.mediaPath);
      final outPath =
          p.join(dir.path, '${originalName}_mosaic_$timestamp.png');
      final outFile = File(outPath);
      await outFile.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存完了: ${p.basename(outPath)}'),
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失敗: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                // Full-screen canvas
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
                                ..scaleByDouble(_viewScale, _viewScale, 1, 0),
                              alignment: Alignment.center,
                              child: AspectRatio(
                                aspectRatio:
                                    _imageSize.width / _imageSize.height,
                                child: RepaintBoundary(
                                  key: _canvasKey,
                                  child: CustomPaint(
                                    size: canvasSize,
                                    painter: MosaicPainter(
                                      mediaImage: _uiImage,
                                      layers: _project.layers,
                                      currentTime: Duration.zero,
                                      mediaSize: _imageSize,
                                      selectedLayerIndex:
                                          _project.selectedLayerIndex,
                                    ),
                                  ),
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
                    title: '画像エディタ',
                    onBack: () => Navigator.of(context).pop(),
                    onAddLayer: _addLayer,
                    onSave: _saveImage,
                    isSaving: _saving,
                  ),
                ),

                // Bottom sheet
                EditorBottomSheet(
                  selectedLayer: _project.selectedLayer,
                  layers: _project.layers,
                  selectedIndex: _project.selectedLayerIndex,
                  onTypeChanged: _onTypeChanged,
                  onShapeChanged: _onShapeChanged,
                  onIntensityChanged: _onIntensityChanged,
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
