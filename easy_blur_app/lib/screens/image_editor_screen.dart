import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../painters/mosaic_painter.dart';
import '../utils/theme.dart';
import '../widgets/layer_panel.dart';
import '../widgets/property_panel.dart';

class ImageEditorScreen extends StatefulWidget {
  final EditorProject project;

  const ImageEditorScreen({super.key, required this.project});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late EditorProject _project;
  ui.Image? _uiImage;
  Size _imageSize = Size.zero;
  bool _loading = true;
  bool _saving = false;
  final GlobalKey _canvasKey = GlobalKey();

  // Gesture state
  Offset? _panStart;
  Size? _resizeStart;
  Offset? _posStart;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _loadImage();
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

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      // Add a default keyframe at center
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

  // Canvas coordinate conversion
  Offset _toImageCoords(Offset localPos, Size canvasSize) {
    return Offset(
      localPos.dx / canvasSize.width * _imageSize.width,
      localPos.dy / canvasSize.height * _imageSize.height,
    );
  }

  /// Hit-test all layers top-down and return the index of the hit layer, or -1.
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

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    final imgPos = _toImageCoords(details.localPosition, canvasSize);

    // Auto-select layer under finger
    final hitIndex = _hitTestLayers(imgPos);
    if (hitIndex < 0) return;

    setState(() => _project.selectedLayerIndex = hitIndex);
    final kf = _project.layers[hitIndex].keyframes.first;

    // Check if near corner for resize
    final corners = [
      Offset(kf.position.dx + kf.size.width / 2, kf.position.dy + kf.size.height / 2),
      Offset(kf.position.dx - kf.size.width / 2, kf.position.dy - kf.size.height / 2),
      Offset(kf.position.dx + kf.size.width / 2, kf.position.dy - kf.size.height / 2),
      Offset(kf.position.dx - kf.size.width / 2, kf.position.dy + kf.size.height / 2),
    ];
    final threshold = _imageSize.width * 0.05;
    bool nearCorner = corners.any((c) => (imgPos - c).distance < threshold);

    if (nearCorner) {
      _resizeStart = kf.size;
      _posStart = kf.position;
      _panStart = imgPos;
    } else {
      _panStart = imgPos;
      _posStart = kf.position;
      _resizeStart = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.keyframes.isEmpty || _panStart == null) return;
    final kf = layer.keyframes.first;
    final imgPos = _toImageCoords(details.localPosition, canvasSize);

    setState(() {
      if (_resizeStart != null) {
        // Resize
        final delta = imgPos - _panStart!;
        kf.size = Size(
          (_resizeStart!.width + delta.dx * 2).clamp(20, _imageSize.width),
          (_resizeStart!.height + delta.dy * 2).clamp(20, _imageSize.height),
        );
      } else {
        // Move
        final delta = imgPos - _panStart!;
        kf.position = _posStart! + delta;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _panStart = null;
    _resizeStart = null;
    _posStart = null;
  }

  Future<void> _saveImage() async {
    if (_uiImage == null) return;
    setState(() => _saving = true);

    try {
      // Render at original resolution
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
      final originalName = p.basenameWithoutExtension(_project.mediaPath);
      final outPath = p.join(dir.path, '${originalName}_mosaic_$timestamp.png');
      final outFile = File(outPath);
      await outFile.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存完了: ${p.basename(outPath)}'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失敗: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('画像エディタ', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            tooltip: 'PNG保存',
            onPressed: _saving ? null : _saveImage,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Canvas area
                Expanded(
                  child: Container(
                    color: AppTheme.bgPrimary,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _imageSize.width / _imageSize.height,
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
                              child: RepaintBoundary(
                                key: _canvasKey,
                                child: CustomPaint(
                                  size: canvasSize,
                                  painter: MosaicPainter(
                                    mediaImage: _uiImage,
                                    layers: _project.layers,
                                    currentTime: Duration.zero,
                                    mediaSize: _imageSize,
                                    selectedLayerIndex: _project.selectedLayerIndex,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
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

      // Saving overlay
      floatingActionButton: _saving
          ? Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          : null,
    );
  }
}
