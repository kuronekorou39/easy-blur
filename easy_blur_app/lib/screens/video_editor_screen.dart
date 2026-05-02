import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/models.dart';
import '../painters/mosaic_painter.dart';
import '../utils/project_history.dart';
import '../utils/project_storage.dart';
import '../utils/theme.dart';
import '../utils/video_exporter.dart';
import '../widgets/compact_playback_bar.dart';
import '../widgets/editor_bottom_sheet.dart';
import '../widgets/floating_action_button_row.dart';
import '../widgets/mosaic_effect_layer.dart';
import '../widgets/mosaic_overlay.dart';
import '../widgets/preview_overlay.dart';
import '../widgets/view_mode_toggle.dart';

class VideoEditorScreen extends StatefulWidget {
  final EditorProject project;

  const VideoEditorScreen({super.key, required this.project});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  late EditorProject _project;
  VideoPlayerController? _videoController;
  bool _loading = true;
  String? _loadError;
  bool _playing = false;
  bool _saving = false;
  double _saveProgress = 0.0;
  Duration _currentTime = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _positionTimer;
  Size _videoSize = Size.zero;
  int _rotationDegrees = 0;

  // 表示モード: 縮小/固定
  VideoViewMode _viewMode = VideoViewMode.shrink;
  VerticalAnchor _anchor = VerticalAnchor.center;

  // シーク処理の重複防止・最新値のみ反映
  bool _seeking = false;
  Duration? _pendingSeek;

  // 再生開始のバッファリング表示
  bool _playLoading = false;
  Duration _playStartPos = Duration.zero;
  Timer? _playLoadingTimeout;

  // 編集履歴（Undo/Redo）
  final ProjectHistory _history = ProjectHistory();
  Timer? _historyPushTimer;

  // プレビュー
  Uint8List? _previewBytes;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _history.push(_project);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final file = File(_project.mediaPath);
      if (!await file.exists()) {
        throw Exception('ファイルが見つかりません: ${_project.mediaPath}');
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      // 表示サイズは aspectRatio から逆算（rotationCorrection の挙動が
      // 動画ごとに不安定なため、より信頼できる aspectRatio を使う）
      final rawSize = controller.value.size;
      final rotation = controller.value.rotationCorrection;
      final aspect = controller.value.aspectRatio;
      final maxSide = math.max(rawSize.width, rawSize.height);
      final minSide = math.min(rawSize.width, rawSize.height);
      final displaySize = aspect >= 1
          ? Size(maxSide, minSide) // 横長: 長辺=幅
          : Size(minSide, maxSide); // 縦長: 長辺=高さ

      setState(() {
        _videoController = controller;
        _totalDuration = controller.value.duration;
        _project.videoDuration = _totalDuration;
        _videoSize = displaySize;
        _rotationDegrees = rotation;
        _loading = false;
        _loadError = null;
      });

      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (!mounted) return;
          if (_seeking || _pendingSeek != null) return;
          final ctrl = _videoController;
          if (ctrl == null) return;
          final pos = ctrl.value.position;
          final nowPlaying = ctrl.value.isPlaying;

          // 再生ローディング解除条件（いずれか）:
          //   - isPlaying が true になった
          //   - position が開始位置より進んだ
          // isBuffering は環境によって常に true のケースがあるため使わない
          bool newPlayLoading = _playLoading;
          if (_playLoading) {
            final progressed = pos.inMilliseconds >
                _playStartPos.inMilliseconds + 30;
            if (nowPlaying || progressed) {
              newPlayLoading = false;
            }
          }

          if (pos != _currentTime ||
              nowPlaying != _playing ||
              newPlayLoading != _playLoading) {
            setState(() {
              _currentTime = pos;
              _playing = nowPlaying;
              _playLoading = newPlayLoading;
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    ProjectStorage.flush(_project);
    _historyPushTimer?.cancel();
    _positionTimer?.cancel();
    _playLoadingTimeout?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    ProjectStorage.requestSave(_project);
    _historyPushTimer?.cancel();
    _historyPushTimer = Timer(const Duration(milliseconds: 400), () {
      _history.push(_project);
      if (mounted) setState(() {});
    });
  }

  void _undo() {
    if (_historyPushTimer?.isActive == true) {
      _historyPushTimer?.cancel();
      _history.push(_project);
    }
    final restored = _history.undo();
    if (restored == null) return;
    setState(() => _project = restored);
    ProjectStorage.requestSave(_project);
  }

  void _redo() {
    final restored = _history.redo();
    if (restored == null) return;
    setState(() => _project = restored);
    ProjectStorage.requestSave(_project);
  }

  // --- 再生制御 ---

  void _togglePlayPause() {
    final ctrl = _videoController;
    if (ctrl == null) return;
    _playLoadingTimeout?.cancel();
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() {
        _playing = false;
        _playLoading = false;
      });
    } else {
      setState(() {
        _playing = true;
        _playLoading = true;
        _playStartPos = _currentTime;
      });
      ctrl.play();
      // 1.5秒たってもローディングが解けなかったら強制解除
      _playLoadingTimeout = Timer(
        const Duration(milliseconds: 1500),
        () {
          if (!mounted) return;
          if (_playLoading) {
            setState(() => _playLoading = false);
          }
        },
      );
    }
  }

  void _seekTo(Duration time) {
    final ctrl = _videoController;
    if (ctrl == null) return;
    // UI の時刻表示は即座に更新
    final clamped = Duration(
      milliseconds:
          time.inMilliseconds.clamp(0, _totalDuration.inMilliseconds),
    );
    setState(() => _currentTime = clamped);
    // 実際のシークはキューを畳み込み、最新値のみ反映
    _pendingSeek = clamped;
    _drainSeek();
  }

  Future<void> _drainSeek() async {
    if (_seeking) return; // 既に処理中。終わったら最新値を拾う
    _seeking = true;
    final ctrl = _videoController;
    try {
      while (_pendingSeek != null && ctrl != null) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        await ctrl.seekTo(next);
      }
    } finally {
      _seeking = false;
    }
  }

  // --- レイヤー管理 ---

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      // 時間範囲：現在時刻から動画の終端まで
      layer.startTime = _currentTime;
      layer.endTime = _totalDuration > Duration.zero
          ? _totalDuration
          : const Duration(days: 1);
      layer.addKeyframe(Keyframe(
        time: _currentTime,
        position: Offset(_videoSize.width / 2, _videoSize.height / 2),
        size: Size(_videoSize.width * 0.35, _videoSize.height * 0.22),
        intensity: 20,
      ));
    });
    _scheduleSave();
  }

  void _setLayerStart(int index) {
    if (index < 0 || index >= _project.layers.length) return;
    setState(() {
      final layer = _project.layers[index];
      layer.startTime = _currentTime;
      // 開始が終了を越えたら終了を引き上げる
      if (layer.startTime > layer.endTime) {
        layer.endTime = layer.startTime;
      }
    });
    _scheduleSave();
  }

  void _setLayerEnd(int index) {
    if (index < 0 || index >= _project.layers.length) return;
    setState(() {
      final layer = _project.layers[index];
      layer.endTime = _currentTime;
      if (layer.endTime < layer.startTime) {
        layer.startTime = layer.endTime;
      }
    });
    _scheduleSave();
  }

  /// 現在時刻にキーフレームを追加（既にある場合は何もしない）
  void _addKeyframeAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.keyframes.isEmpty) return;
    // 既に近い時刻にキーフレームがあれば何もしない
    const toleranceMs = 100;
    for (final kf in layer.keyframes) {
      if ((kf.time.inMilliseconds - _currentTime.inMilliseconds).abs() <=
          toleranceMs) {
        return;
      }
    }
    setState(() {
      final state = layer.getStateAt(_currentTime);
      layer.addKeyframe(Keyframe(
        time: _currentTime,
        position: state.position,
        size: state.size,
        rotation: state.rotation,
        intensity: state.intensity,
      ));
    });
    _scheduleSave();
  }

  /// 指定したキーフレームを削除（ただし最後の1つは削除できない）
  void _deleteKeyframe(int layerIndex, int keyframeIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (keyframeIndex < 0 || keyframeIndex >= layer.keyframes.length) return;
    if (layer.keyframes.length <= 1) return; // 最後の1つは消せない
    setState(() {
      layer.removeKeyframeAt(keyframeIndex);
    });
    _scheduleSave();
  }

  /// 現在時刻のキーフレームを削除
  void _deleteKeyframeAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.keyframes.length <= 1) return;
    const toleranceMs = 150;
    for (int i = 0; i < layer.keyframes.length; i++) {
      if ((layer.keyframes[i].time.inMilliseconds -
                  _currentTime.inMilliseconds)
              .abs() <=
          toleranceMs) {
        setState(() => layer.removeKeyframeAt(i));
        _scheduleSave();
        return;
      }
    }
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
      _scheduleSave();
    }
  }

  void _selectLayer(int index) {
    setState(() => _project.selectedLayerIndex = index);
    _scheduleSave();
  }

  void _deselectLayer() {
    if (_project.selectedLayerIndex >= 0) {
      setState(() => _project.selectedLayerIndex = -1);
      _scheduleSave();
    }
  }

  void _toggleVisibility(int index) {
    setState(() {
      _project.layers[index].visible = !_project.layers[index].visible;
    });
    _scheduleSave();
  }

  void _toggleLocked(int index) {
    setState(() {
      _project.layers[index].locked = !_project.layers[index].locked;
    });
    _scheduleSave();
  }

  void _reorderLayers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _project.reorderLayer(oldIndex, newIndex);
    });
    _scheduleSave();
  }

  void _onTypeChanged(MosaicType type) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.type = type);
    _scheduleSave();
  }

  void _onShapeChanged(MosaicShape shape) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.shape = shape);
    _scheduleSave();
  }

  void _onInvertedChanged(bool inverted) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.inverted = inverted);
    _scheduleSave();
  }

  void _onFillColorChanged(int color) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.fillColor = color);
    _scheduleSave();
  }

  void _onIntensityChanged(double value) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    // 全キーフレームに適用（動画全体で強度は統一）
    setState(() {
      for (final kf in layer.keyframes) {
        kf.intensity = value;
      }
      if (layer.keyframes.isEmpty) {
        layer.addKeyframe(Keyframe(
          time: _currentTime,
          position: Offset(_videoSize.width / 2, _videoSize.height / 2),
          size: Size(_videoSize.width * 0.35, _videoSize.height * 0.22),
          intensity: value,
        ));
      }
    });
    _scheduleSave();
  }

  void _onRotationChanged(double radians) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    // 全キーフレームに適用（動画全体で回転は統一）
    setState(() {
      for (final kf in layer.keyframes) {
        kf.rotation = radians;
      }
    });
    _scheduleSave();
  }

  // --- 座標変換 ---

  double _fitScale(Size canvasSize) {
    if (_videoSize.isEmpty) return 1.0;
    final sx = canvasSize.width / _videoSize.width;
    final sy = canvasSize.height / _videoSize.height;
    return sx < sy ? sx : sy;
  }

  Rect _videoRect(Size canvasSize) {
    final scale = _fitScale(canvasSize);
    final imgW = _videoSize.width * scale;
    final imgH = _videoSize.height * scale;
    final left = (canvasSize.width - imgW) / 2;
    final top = (canvasSize.height - imgH) / 2;
    return Rect.fromLTWH(left, top, imgW, imgH);
  }

  Rect _layerCanvasRect(MosaicLayer layer, Rect videoRect, double scale) {
    if (layer.keyframes.isEmpty) return Rect.zero;
    final state = layer.getStateAt(_currentTime);
    final cx = videoRect.left + state.position.dx * scale;
    final cy = videoRect.top + state.position.dy * scale;
    final w = state.size.width * scale;
    final h = state.size.height * scale;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// 現在時刻に対応するキーフレームを取得または作成
  Keyframe _getOrCreateKeyframeAt(MosaicLayer layer, Duration time) {
    const toleranceMs = 200; // この時間内のキーフレームを同一とみなす
    for (final kf in layer.keyframes) {
      if ((kf.time.inMilliseconds - time.inMilliseconds).abs() <=
          toleranceMs) {
        return kf;
      }
    }
    // 新規作成
    final state = layer.getStateAt(time);
    final newKf = Keyframe(
      time: time,
      position: state.position,
      size: state.size,
      rotation: state.rotation,
      intensity: state.intensity,
    );
    layer.addKeyframe(newKf);
    return newKf;
  }

  void _moveLayer(int index, Offset canvasDelta, double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.locked || layer.keyframes.isEmpty) return;
    setState(() {
      final kf = _getOrCreateKeyframeAt(layer, _currentTime);
      kf.position = Offset(
        (kf.position.dx + canvasDelta.dx / scale)
            .clamp(0, _videoSize.width),
        (kf.position.dy + canvasDelta.dy / scale)
            .clamp(0, _videoSize.height),
      );
    });
    _scheduleSave();
  }

  void _resizeLayer(
      int index, Offset canvasDelta, HandleCorner corner, double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.locked || layer.keyframes.isEmpty) return;

    final imgDx = canvasDelta.dx / scale;
    final imgDy = canvasDelta.dy / scale;

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
      final kf = _getOrCreateKeyframeAt(layer, _currentTime);
      final newW = (kf.size.width + imgDx * widthSign)
          .clamp(20.0, _videoSize.width);
      final newH = (kf.size.height + imgDy * heightSign)
          .clamp(20.0, _videoSize.height);
      final actualDw = newW - kf.size.width;
      final actualDh = newH - kf.size.height;
      kf.size = Size(newW, newH);
      kf.position = Offset(
        kf.position.dx + (actualDw * widthSign) / 2,
        kf.position.dy + (actualDh * heightSign) / 2,
      );
    });
    _scheduleSave();
  }

  // --- プレビュー（現在フレーム + 出力相当の合成画像） ---

  Future<void> _showPreview() async {
    if (_videoController == null || _previewLoading) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
      setState(() => _playing = false);
    }
    setState(() => _previewLoading = true);
    try {
      final thumbBytes = await VideoThumbnail.thumbnailData(
        video: _project.mediaPath,
        timeMs: _currentTime.inMilliseconds,
        imageFormat: ImageFormat.PNG,
        quality: 100,
      );
      if (thumbBytes == null || thumbBytes.isEmpty) {
        throw Exception('フレーム取得失敗');
      }
      final codec = await ui.instantiateImageCodec(thumbBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final frameImage = frame.image;
      try {
        final frameSize = Size(
          frameImage.width.toDouble(),
          frameImage.height.toDouble(),
        );
        final sx = frameSize.width / _videoSize.width;
        final sy = frameSize.height / _videoSize.height;
        final scale = (sx + sy) / 2;

        // レイヤーをフレーム座標系にスケール
        final scaledLayers = <MosaicLayer>[];
        for (final l in _project.layers) {
          if (!l.isActiveAt(_currentTime) ||
              l.keyframes.isEmpty ||
              !l.visible) {
            continue;
          }
          scaledLayers.add(MosaicLayer(
            id: l.id,
            name: l.name,
            type: l.type,
            shape: l.shape,
            visible: l.visible,
            inverted: l.inverted,
            locked: l.locked,
            fillColor: l.fillColor,
            startTime: l.startTime,
            endTime: l.endTime,
            keyframes: l.keyframes
                .map((kf) => Keyframe(
                      time: kf.time,
                      position: Offset(
                          kf.position.dx * sx, kf.position.dy * sy),
                      size: Size(
                          kf.size.width * sx, kf.size.height * sy),
                      rotation: kf.rotation,
                      intensity: kf.intensity * scale,
                    ))
                .toList(),
          ));
        }

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = MosaicPainter(
          mediaImage: frameImage,
          layers: scaledLayers,
          currentTime: _currentTime,
          mediaSize: frameSize,
          selectedLayerIndex: null,
          isPreview: false,
        );
        painter.paint(canvas, frameSize);
        final picture = recorder.endRecording();
        final saved = await picture.toImage(
          frameSize.width.round(),
          frameSize.height.round(),
        );
        picture.dispose();
        final byteData =
            await saved.toByteData(format: ui.ImageByteFormat.png);
        saved.dispose();
        if (byteData == null) throw Exception('プレビュー生成失敗');
        if (!mounted) return;
        setState(() => _previewBytes = byteData.buffer.asUint8List());
      } finally {
        frameImage.dispose();
      }
    } catch (_) {
      // 失敗時は無視
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  void _closePreview() {
    setState(() => _previewBytes = null);
  }

  // --- 動画保存（ネイティブ Kotlin + MediaCodec でモザイクを焼き込み）---

  Future<void> _saveVideo() async {
    if (_videoController == null || _saving) return;

    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
      setState(() => _playing = false);
    }

    setState(() {
      _saving = true;
      _saveProgress = 0.0;
    });

    try {
      final outPath = await VideoExporter.export(
        project: _project,
        videoSize: _videoSize,
        rotationDegrees: _rotationDegrees,
        onProgress: (p) {
          if (mounted) setState(() => _saveProgress = p);
        },
      );

      // ギャラリーへ保存
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw Exception('ギャラリーへのアクセスが許可されていません');
        }
      }
      await Gal.putVideo(outPath, album: 'Easy Blur');

      // 一時ファイル削除
      try {
        await File(outPath).delete();
      } catch (_) {}

      if (mounted) {
        _showSnack(
          icon: Icons.check_circle_rounded,
          message: '動画を保存しました',
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
      if (mounted) {
        setState(() {
          _saving = false;
          _saveProgress = 0.0;
        });
      }
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

  void _handleBack() {
    // 自動保存されているので確認なしで戻る
    Navigator.of(context).pop();
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
    final topMargin = topInset + 60;

    final playbackBar = CompactPlaybackBar(
      isPlaying: _playing,
      isLoading: _playLoading,
      currentTime: _currentTime,
      totalDuration: _totalDuration,
      onTogglePlay: _togglePlayPause,
      onSeek: _seekTo,
    );

    final bottomSheet = EditorBottomSheet(
      selectedLayer: _project.selectedLayer,
      layers: _project.layers,
      selectedIndex: _project.selectedLayerIndex,
      onTypeChanged: _onTypeChanged,
      onShapeChanged: _onShapeChanged,
      onInvertedChanged: _onInvertedChanged,
      onFillColorChanged: _onFillColorChanged,
      onIntensityChanged: _onIntensityChanged,
      onRotationChanged: _onRotationChanged,
      onSelectLayer: _selectLayer,
      onAddLayer: _addLayer,
      onDeleteLayer: _deleteLayer,
      onToggleVisibility: _toggleVisibility,
      onToggleLocked: _toggleLocked,
      onReorderLayers: _reorderLayers,
      showTimeRange: true,
      currentTime: _currentTime,
      totalDuration: _totalDuration,
      onSetStart: _setLayerStart,
      onSetEnd: _setLayerEnd,
      onSeekTo: _seekTo,
      onAddKeyframeAtCurrent: _addKeyframeAtCurrent,
      onDeleteKeyframeAtCurrent: _deleteKeyframeAtCurrent,
      onDeleteKeyframe: _deleteKeyframe,
    );

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
            // 縮小モード：通常のカラム配置（キャンバスが圧迫される）
            if (_viewMode == VideoViewMode.shrink) ...[
              playbackBar,
              bottomSheet,
            ],
          ],
        ),
        // 固定モード：再生バー + ボトムシートをキャンバスに被せる
        if (_viewMode == VideoViewMode.fixed)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [playbackBar, bottomSheet],
              ),
            ),
          ),
        // FAB
        FloatingActionButtonRow(
          onBack: _handleBack,
          onSave: _saveVideo,
          isSaving: _saving,
          onUndo: _undo,
          onRedo: _redo,
          canUndo: _history.canUndo,
          canRedo: _history.canRedo,
          onPreview: _showPreview,
          isPreviewLoading: _previewLoading,
        ),
        if (_previewBytes != null)
          PreviewOverlay(
            imageBytes: _previewBytes!,
            onClose: _closePreview,
            caption: '動画は現在フレームを合成（実際の出力は時間軸で適用）',
          ),
        // モード切替ボタン（FABの下）
        Positioned(
          top: topInset + 60,
          left: 0,
          right: 0,
          child: ViewModeToggle(
            mode: _viewMode,
            anchor: _anchor,
            onModeChanged: (m) => setState(() => _viewMode = m),
            onAnchorChanged: (a) => setState(() => _anchor = a),
          ),
        ),
      ],
    );
  }

  /// 固定モード時、キャンバスを縦方向にシフトする量（-は上、+は下）
  double _verticalShift(double canvasHeight) {
    if (_viewMode == VideoViewMode.shrink) return 0;
    switch (_anchor) {
      case VerticalAnchor.top:
        // 動画の上部を可視領域に：シフト 0（元の位置で上が見える）
        return 0;
      case VerticalAnchor.center:
        // 動画を上に 25% 移動して中央を可視領域に
        return -canvasHeight * 0.22;
      case VerticalAnchor.bottom:
        // 動画を上に 45% 移動して下部を可視領域に
        return -canvasHeight * 0.42;
    }
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        final scale = _fitScale(canvasSize);
        final videoRect = _videoRect(canvasSize);
        final ctrl = _videoController;
        final shiftY = _verticalShift(canvasSize.height);

        return Transform.translate(
          offset: Offset(0, shiftY),
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _deselectLayer,
          onPanUpdate: (d) {
            // 選択中レイヤーがあれば、矩形外ドラッグでも相対移動できる
            final idx = _project.selectedLayerIndex;
            if (idx < 0) return;
            _moveLayer(idx, d.delta, scale);
          },
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (ctrl != null)
                Positioned.fromRect(
                  rect: videoRect,
                  child: VideoPlayer(ctrl),
                ),
              // モザイク効果（BackdropFilter で実フレームにフィルター適用）
              for (int i = 0; i < _project.layers.length; i++)
                if (_project.layers[i].visible &&
                    _project.layers[i].keyframes.isNotEmpty &&
                    _project.layers[i].isActiveAt(_currentTime))
                  MosaicEffectLayer(
                    key: ValueKey(
                        'effect_${_project.layers[i].id}'),
                    canvasRect: _layerCanvasRect(
                        _project.layers[i], videoRect, scale),
                    type: _project.layers[i].type,
                    shape: _project.layers[i].shape,
                    inverted: _project.layers[i].inverted,
                    fillColor: _project.layers[i].fillColor,
                    intensity: _project.layers[i]
                        .getStateAt(_currentTime)
                        .intensity,
                    rotation: _project.layers[i]
                        .getStateAt(_currentTime)
                        .rotation,
                  ),
              if (!_saving)
                for (int i = 0; i < _project.layers.length; i++)
                  if (_project.layers[i].visible &&
                      _project.layers[i].keyframes.isNotEmpty &&
                      _project.layers[i].isActiveAt(_currentTime))
                    MosaicOverlay(
                      key: ValueKey(
                          'overlay_${_project.layers[i].id}'),
                      layer: _project.layers[i],
                      canvasRect: _layerCanvasRect(
                          _project.layers[i], videoRect, scale),
                      isSelected: i == _project.selectedLayerIndex,
                      onTap: () => _selectLayer(i),
                      onMove: (delta) => _moveLayer(i, delta, scale),
                      onResize: (delta, corner) =>
                          _resizeLayer(i, delta, corner, scale),
                    ),
              if (_saving)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Center(
                      child: SizedBox(
                        width: 240,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('動画を書き出し中',
                                style: AppTheme.textHeader),
                            const SizedBox(height: 6),
                            Text(
                              '${(_saveProgress * 100).toStringAsFixed(0)}%',
                              style: AppTheme.textBody.copyWith(
                                color: AppTheme.accentBright,
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: _saveProgress > 0
                                    ? _saveProgress
                                    : null,
                                backgroundColor: AppTheme.bgHover,
                                color: AppTheme.accent,
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'モザイクを焼き込んだ動画を\n生成しています',
                              style: AppTheme.textCaption,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
          Text('動画を読み込んでいます…', style: AppTheme.textBody),
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
                  Icons.videocam_off_outlined,
                  size: 36,
                  color: AppTheme.danger,
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Text('動画を読み込めませんでした', style: AppTheme.textTitle),
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
