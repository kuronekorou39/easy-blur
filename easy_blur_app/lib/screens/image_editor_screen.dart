import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../painters/mosaic_painter.dart';
import '../utils/theme.dart';
import '../widgets/editor_bottom_sheet.dart';
import '../widgets/floating_action_button_row.dart';
import '../widgets/mosaic_effect_layer.dart';
import '../widgets/mosaic_overlay.dart';

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
  String? _loadError;
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _loadImage();
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(_project.mediaPath);
      if (!await file.exists()) {
        throw Exception('ファイルが見つかりません: ${_project.mediaPath}');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('ファイルが空です');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();

      if (!mounted) {
        frame.image.dispose();
        return;
      }

      setState(() {
        _uiImage = frame.image;
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  // --- レイヤー管理 ---

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      layer.addKeyframe(Keyframe(
        time: Duration.zero,
        position: Offset(_imageSize.width / 2, _imageSize.height / 2),
        size: Size(_imageSize.width * 0.35, _imageSize.height * 0.22),
        intensity: 20,
      ));
    });
  }

  Future<void> _deleteLayer(int index) async {
    final layer = _project.layers[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'レイヤーを削除',
        message: '"${layer.name}" を削除します。\nこの操作は元に戻せません。',
        confirmLabel: '削除',
        confirmColor: AppTheme.danger,
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _project.removeLayer(index));
    }
  }

  void _selectLayer(int index) {
    setState(() => _project.selectedLayerIndex = index);
  }

  void _deselectLayer() {
    if (_project.selectedLayerIndex >= 0) {
      setState(() => _project.selectedLayerIndex = -1);
    }
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

  void _onInvertedChanged(bool inverted) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.inverted = inverted);
  }

  void _onIntensityChanged(double value) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.keyframes.isEmpty) return;
    setState(() => layer.keyframes.first.intensity = value);
  }

  // --- 座標変換 ---

  double _fitScale(Size canvasSize) {
    if (_imageSize.isEmpty) return 1.0;
    final sx = canvasSize.width / _imageSize.width;
    final sy = canvasSize.height / _imageSize.height;
    return sx < sy ? sx : sy;
  }

  /// キャンバス座標系での画像描画矩形
  Rect _imageRect(Size canvasSize) {
    final scale = _fitScale(canvasSize);
    final imgW = _imageSize.width * scale;
    final imgH = _imageSize.height * scale;
    final left = (canvasSize.width - imgW) / 2;
    final top = (canvasSize.height - imgH) / 2;
    return Rect.fromLTWH(left, top, imgW, imgH);
  }

  /// 画像座標のレイヤー矩形をキャンバス座標に変換
  Rect _layerCanvasRect(MosaicLayer layer, Rect imageRect, double scale) {
    if (layer.keyframes.isEmpty) return Rect.zero;
    final kf = layer.keyframes.first;
    final cx = imageRect.left + kf.position.dx * scale;
    final cy = imageRect.top + kf.position.dy * scale;
    final w = kf.size.width * scale;
    final h = kf.size.height * scale;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  // --- レイヤー操作（オーバーレイから呼ばれる）---

  void _moveLayer(int index, Offset canvasDelta, double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.keyframes.isEmpty) return;
    final kf = layer.keyframes.first;
    setState(() {
      kf.position = Offset(
        (kf.position.dx + canvasDelta.dx / scale)
            .clamp(0, _imageSize.width),
        (kf.position.dy + canvasDelta.dy / scale)
            .clamp(0, _imageSize.height),
      );
    });
  }

  void _resizeLayer(int index, Offset canvasDelta, HandleCorner corner,
      double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.keyframes.isEmpty) return;
    final kf = layer.keyframes.first;

    // 画像座標系でのデルタ
    final imgDx = canvasDelta.dx / scale;
    final imgDy = canvasDelta.dy / scale;

    // 各コーナーの挙動（反対側の角が固定）
    double widthSign = 0, heightSign = 0;
    switch (corner) {
      case HandleCorner.topLeft:
        widthSign = -1;
        heightSign = -1;
        break;
      case HandleCorner.topRight:
        widthSign = 1;
        heightSign = -1;
        break;
      case HandleCorner.bottomLeft:
        widthSign = -1;
        heightSign = 1;
        break;
      case HandleCorner.bottomRight:
        widthSign = 1;
        heightSign = 1;
        break;
    }

    setState(() {
      final newW = (kf.size.width + imgDx * widthSign)
          .clamp(20.0, _imageSize.width);
      final newH = (kf.size.height + imgDy * heightSign)
          .clamp(20.0, _imageSize.height);
      // 実際のサイズ変化量（clamp 後）
      final actualDw = newW - kf.size.width;
      final actualDh = newH - kf.size.height;
      kf.size = Size(newW, newH);
      // 中心は固定側の反対方向に半分ずつ移動
      kf.position = Offset(
        kf.position.dx + (actualDw * widthSign) / 2,
        kf.position.dy + (actualDh * heightSign) / 2,
      );
    });
  }

  // --- 保存 ---

  Future<void> _saveImage() async {
    if (_uiImage == null) return;
    setState(() => _saving = true);

    try {
      // 1. 描画→PNGエンコード
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = MosaicPainter(
        mediaImage: _uiImage,
        layers: _project.layers,
        currentTime: Duration.zero,
        mediaSize: _imageSize,
        selectedLayerIndex: null,
        isPreview: false,
      );
      painter.paint(canvas, _imageSize);

      final picture = recorder.endRecording();
      final img = await picture.toImage(
        _imageSize.width.round(),
        _imageSize.height.round(),
      );
      picture.dispose();
      final byteData =
          await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (byteData == null) throw Exception('PNGエンコード失敗');

      // 2. ギャラリーへの書き込み権限を確認
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw Exception('ギャラリーへのアクセスが許可されていません');
        }
      }

      // 3. ギャラリーへ保存（Android: 写真アプリ / iOS: 写真Appの"Easy Blur"アルバム）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = p.basenameWithoutExtension(_project.mediaPath);
      final filename = '${originalName}_mosaic_$timestamp';

      await Gal.putImageBytes(
        byteData.buffer.asUint8List(),
        album: 'Easy Blur',
        name: filename,
      );

      if (mounted) {
        _showSnack(
          icon: Icons.check_circle_rounded,
          message: '保存しました',
          detail: '写真アプリの「Easy Blur」アルバム',
          color: AppTheme.success,
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        _showSnack(
          icon: Icons.error_outline_rounded,
          message: '保存に失敗しました',
          detail: e.type.message,
          color: AppTheme.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          icon: Icons.error_outline_rounded,
          message: '保存に失敗しました',
          detail: e.toString(),
          color: AppTheme.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack({
    required IconData icon,
    required String message,
    String? detail,
    required Color color,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message,
                        style: AppTheme.textBodyStrong.copyWith(
                            color: AppTheme.textPrimary)),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.textCaption,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.bgElevated,
          elevation: 8,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).size.height * 0.12,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleBack() async {
    if (_project.layers.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ConfirmDialog(
        title: '編集を破棄',
        message: '現在の編集内容は失われます。\nホームに戻りますか？',
        confirmLabel: '破棄して戻る',
        confirmColor: AppTheme.danger,
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // --- ビルド ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: _loading
          ? const _LoadingView()
          : _loadError != null
              ? _ErrorView(
                  error: _loadError!,
                  onBack: () => Navigator.of(context).pop(),
                )
              : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    final topInset = MediaQuery.of(context).padding.top;
    // 上部余白: SafeArea + フローティングボタン高 + 余白
    final topMargin = topInset + 60;
    return Stack(
      children: [
        Column(
          children: [
            SizedBox(height: topMargin),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildCanvas(),
              ),
            ),
            EditorBottomSheet(
              selectedLayer: _project.selectedLayer,
              layers: _project.layers,
              selectedIndex: _project.selectedLayerIndex,
              onTypeChanged: _onTypeChanged,
              onShapeChanged: _onShapeChanged,
              onInvertedChanged: _onInvertedChanged,
              onIntensityChanged: _onIntensityChanged,
              onSelectLayer: _selectLayer,
              onAddLayer: _addLayer,
              onDeleteLayer: _deleteLayer,
              onToggleVisibility: _toggleVisibility,
              onReorderLayers: _reorderLayers,
            ),
          ],
        ),
        // フローティング戻る/保存ボタン
        FloatingActionButtonRow(
          onBack: _handleBack,
          onSave: _saveImage,
          isSaving: _saving,
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        final scale = _fitScale(canvasSize);
        final imageRect = _imageRect(canvasSize);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _deselectLayer, // 画像の空白領域タップで選択解除
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 画像本体のみ描画（モザイクは別レイヤーで重ねる）
              if (_uiImage != null)
                Positioned.fromRect(
                  rect: imageRect,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: RawImage(
                      image: _uiImage,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              // 各レイヤーのモザイク効果（BackdropFilter で実画像にフィルター）
              for (int i = 0; i < _project.layers.length; i++)
                if (_project.layers[i].visible &&
                    _project.layers[i].keyframes.isNotEmpty)
                  MosaicEffectLayer(
                    key: ValueKey('effect_${_project.layers[i].id}'),
                    canvasRect: _layerCanvasRect(
                        _project.layers[i], imageRect, scale),
                    type: _project.layers[i].type,
                    shape: _project.layers[i].shape,
                    inverted: _project.layers[i].inverted,
                    intensity:
                        _project.layers[i].keyframes.first.intensity,
                  ),
              // 各レイヤーのオーバーレイ（選択枠・ハンドル）
              for (int i = 0; i < _project.layers.length; i++)
                if (_project.layers[i].visible &&
                    _project.layers[i].keyframes.isNotEmpty)
                  MosaicOverlay(
                    key: ValueKey('overlay_${_project.layers[i].id}'),
                    layer: _project.layers[i],
                    canvasRect: _layerCanvasRect(
                        _project.layers[i], imageRect, scale),
                    isSelected: i == _project.selectedLayerIndex,
                    onTap: () => _selectLayer(i),
                    onMove: (delta) => _moveLayer(i, delta, scale),
                    onResize: (delta, corner) =>
                        _resizeLayer(i, delta, corner, scale),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 20),
          Text('画像を読み込んでいます…', style: AppTheme.textBody),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onBack;

  const _ErrorView({required this.error, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceXl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 36,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Text('画像を読み込めませんでした', style: AppTheme.textTitle),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                error,
                style: AppTheme.textBody,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppTheme.spaceXl),
              FilledButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                label: const Text('戻る'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.textHeader),
            const SizedBox(height: AppTheme.spaceSm),
            Text(message, style: AppTheme.textBody),
            const SizedBox(height: AppTheme.spaceXl),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: AppTheme.spaceSm),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
