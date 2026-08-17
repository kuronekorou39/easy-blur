import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../utils/project_history.dart';
import '../utils/project_storage.dart';
import '../utils/theme.dart';
import '../utils/video_exporter.dart';
import '../widgets/compact_playback_bar.dart';
import '../widgets/editor_bottom_sheet.dart';
import '../widgets/floating_action_button_row.dart';
import '../widgets/mosaic_effect_layer.dart';
import '../widgets/mosaic_overlay.dart';
import '../widgets/path_edit_overlay.dart';
import '../widgets/video_preview_overlay.dart';
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

  // スクラブ（スライダードラッグ）中は一時停止し、離したら再開する
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;

  // 直近のシーク所要時間（ms）。重い動画ではドラッグ中の中間シークを省く
  int _lastSeekCostMs = 0;
  Duration? _scrubSkippedTarget;

  // 再生速度
  double _playbackSpeed = 1.0;

  // ミュート
  bool _muted = false;

  // 再生開始のバッファリング表示
  bool _playLoading = false;
  Duration _playStartPos = Duration.zero;
  Timer? _playLoadingTimeout;

  // 編集履歴（Undo/Redo）
  final ProjectHistory _history = ProjectHistory();
  Timer? _historyPushTimer;

  // 出力プレビュー（モザイク適用済みのまま再生）表示中か
  bool _showingPreview = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _playbackSpeed = _project.playbackSpeed;
    _muted = _project.muted;
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

      // 前回の編集時に使っていた再生速度・ミュートを復元
      if (_playbackSpeed != 1.0) {
        await controller.setPlaybackSpeed(_playbackSpeed);
      }
      if (_muted) {
        await controller.setVolume(0);
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
    _resumeAfterScrub = false; // 手動操作が最優先
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() {
        _playing = false;
        _playLoading = false;
      });
    } else {
      // 末尾で停止している場合は自前で先頭へ戻してから再生する。
      // video_player 内部の「終端で play すると自動で 0 へシーク」は
      // 完了を検知できず、長時間固まって見えるため使わない
      final atEnd = _totalDuration > Duration.zero &&
          _currentTime >=
              _totalDuration - const Duration(milliseconds: 200);
      setState(() {
        _playing = true;
        _playLoading = true;
        _playStartPos = atEnd ? Duration.zero : _currentTime;
      });
      if (atEnd) {
        _resumeAfterScrub = true; // 巻き戻し完了後に play する
        _seekTo(Duration.zero);
      } else if (_seeking || _pendingSeek != null) {
        // シーク処理が残っている間は、完了してから再生を開始する
        _resumeAfterScrub = true;
      } else {
        ctrl.play();
      }
      _schedulePlayLoadingClear();
    }
  }

  /// 再生ローディング表示の強制解除タイマー。
  /// シーク処理が続いている間は解除せず、スピナーで「処理中」を伝える
  void _schedulePlayLoadingClear() {
    _playLoadingTimeout = Timer(
      const Duration(milliseconds: 1500),
      () {
        if (!mounted) return;
        if (_seeking || _pendingSeek != null || _resumeAfterScrub) {
          _schedulePlayLoadingClear();
          return;
        }
        if (_playLoading) {
          setState(() => _playLoading = false);
        }
      },
    );
  }

  void _setPlaybackSpeed(double speed) {
    final ctrl = _videoController;
    if (ctrl == null) return;
    setState(() => _playbackSpeed = speed);
    ctrl.setPlaybackSpeed(speed);
    // 次回開いたとき復元できるよう保存（履歴には積まない）
    _project.playbackSpeed = speed;
    ProjectStorage.requestSave(_project);
  }

  void _toggleMute() {
    final ctrl = _videoController;
    if (ctrl == null) return;
    setState(() => _muted = !_muted);
    ctrl.setVolume(_muted ? 0 : 1);
    // 次回開いたとき復元できるよう保存（履歴には積まない）
    _project.muted = _muted;
    ProjectStorage.requestSave(_project);
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
    // シークが重い動画（キーフレームが疎）では、ドラッグ中の
    // 中間シークを省略し、指を離したときに1回だけシークする
    if (_scrubbing && _lastSeekCostMs > 350) {
      _scrubSkippedTarget = clamped;
      return;
    }
    _scrubSkippedTarget = null;
    // 実際のシークはキューを畳み込み、最新値のみ反映
    _pendingSeek = clamped;
    _drainSeek();
  }

  Future<void> _drainSeek() async {
    if (_seeking) return; // 既に処理中。終わったら最新値を拾う
    _seeking = true;
    final ctrl = _videoController;
    try {
      final sw = Stopwatch();
      while (_pendingSeek != null && ctrl != null) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        sw
          ..reset()
          ..start();
        await ctrl.seekTo(next);
        _lastSeekCostMs = sw.elapsedMilliseconds;
      }
    } finally {
      _seeking = false;
      _maybeResumeAfterScrub();
    }
  }

  /// スクラブ開始: 再生中なら一時停止（重いシークと再生の競合を防ぐ）
  void _onScrubStart() {
    _scrubbing = true;
    final ctrl = _videoController;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      _resumeAfterScrub = true;
      ctrl.pause();
      setState(() => _playing = false);
    }
  }

  /// スクラブ終了: 残っているシークが完了してから再生を再開する
  void _onScrubEnd() {
    _scrubbing = false;
    // ドラッグ中に省略していた最終位置へ確定シーク
    if (_scrubSkippedTarget != null) {
      _pendingSeek = _scrubSkippedTarget;
      _scrubSkippedTarget = null;
      _drainSeek();
    }
    _maybeResumeAfterScrub();
  }

  void _maybeResumeAfterScrub() {
    if (!_resumeAfterScrub || _scrubbing) return;
    if (_seeking || _pendingSeek != null) return;
    _resumeAfterScrub = false;
    final ctrl = _videoController;
    if (ctrl == null || !mounted) return;
    ctrl.play();
    setState(() => _playing = true);
  }

  // --- レイヤー管理 ---

  void _addLayer() {
    setState(() {
      final layer = _project.addLayer();
      // 時間範囲：デフォルトは動画全体。
      // 途中で追加したレイヤーが他の時間帯で「反映されない」ように
      // 見える混乱を避けるため、範囲の限定はタイムタブで明示的に行う。
      layer.startTime = Duration.zero;
      layer.endTime = _totalDuration > Duration.zero
          ? _totalDuration
          : const Duration(days: 1);
      layer.addPathKeyframe(PathPoint(
        time: _currentTime,
        position: Offset(_videoSize.width / 2, _videoSize.height / 2),
      ));
      layer.addStyleKeyframe(StylePoint(
        time: _currentTime,
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

  /// 現在時刻に経路キーフレームを追加（既にある場合は何もしない）
  void _addKeyframeAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.pathKeyframes.isEmpty) return;
    // 既に近い時刻にキーフレームがあれば何もしない
    const toleranceMs = 100;
    for (final kf in layer.pathKeyframes) {
      if ((kf.time.inMilliseconds - _currentTime.inMilliseconds).abs() <=
          toleranceMs) {
        return;
      }
    }
    setState(() {
      layer.addPathKeyframe(PathPoint(
        time: _currentTime,
        position: layer.positionAt(_currentTime),
      ));
    });
    _scheduleSave();
  }

  /// 指定した経路キーフレームを削除（ただし最後の1つは削除できない）
  void _deleteKeyframe(int layerIndex, int keyframeIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (keyframeIndex < 0 ||
        keyframeIndex >= layer.pathKeyframes.length) {
      return;
    }
    if (layer.pathKeyframes.length <= 1) return; // 最後の1つは消せない
    setState(() {
      layer.removePathKeyframeAt(keyframeIndex);
    });
    _scheduleSave();
  }

  /// 現在時刻の経路キーフレームを削除
  void _deleteKeyframeAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.pathKeyframes.length <= 1) return;
    const toleranceMs = 150;
    for (int i = 0; i < layer.pathKeyframes.length; i++) {
      if ((layer.pathKeyframes[i].time.inMilliseconds -
                  _currentTime.inMilliseconds)
              .abs() <=
          toleranceMs) {
        setState(() => layer.removePathKeyframeAt(i));
        _scheduleSave();
        return;
      }
    }
  }

  /// 現在時刻に基準（サイズ・強度・回転）を追加（既にある場合は何もしない）
  void _addStylePointAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.styleKeyframes.isEmpty) return;
    const toleranceMs = 100;
    for (final s in layer.styleKeyframes) {
      if ((s.time.inMilliseconds - _currentTime.inMilliseconds).abs() <=
          toleranceMs) {
        return;
      }
    }
    setState(() {
      final state = layer.getStateAt(_currentTime);
      layer.addStyleKeyframe(StylePoint(
        time: _currentTime,
        size: state.size,
        rotation: state.rotation,
        intensity: state.intensity,
      ));
    });
    _scheduleSave();
  }

  /// 指定した基準を削除（最後の1つは削除できない）
  void _deleteStylePoint(int layerIndex, int styleIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (styleIndex < 0 || styleIndex >= layer.styleKeyframes.length) {
      return;
    }
    if (layer.styleKeyframes.length <= 1) return;
    setState(() {
      layer.removeStyleKeyframeAt(styleIndex);
    });
    _scheduleSave();
  }

  /// 現在時刻の基準を削除
  void _deleteStylePointAtCurrent(int layerIndex) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.styleKeyframes.length <= 1) return;
    const toleranceMs = 150;
    for (int i = 0; i < layer.styleKeyframes.length; i++) {
      if ((layer.styleKeyframes[i].time.inMilliseconds -
                  _currentTime.inMilliseconds)
              .abs() <=
          toleranceMs) {
        setState(() => layer.removeStyleKeyframeAt(i));
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

  void _onBarAngleChanged(double radians) {
    final layer = _project.selectedLayer;
    if (layer == null) return;
    setState(() => layer.barAngle = radians);
    _scheduleSave();
  }

  void _onIntensityChanged(double value) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.styleKeyframes.isEmpty) return;
    setState(() {
      _getOrCreateStylePointAt(layer, _currentTime).intensity = value;
    });
    _scheduleSave();
  }

  void _onRotationChanged(double radians) {
    final layer = _project.selectedLayer;
    if (layer == null || layer.styleKeyframes.isEmpty) return;
    setState(() {
      _getOrCreateStylePointAt(layer, _currentTime).rotation = radians;
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

  /// 経路表示の対象レイヤー（選択中・表示中・経路が2点以上）
  MosaicLayer? get _selectedPathLayer {
    final idx = _project.selectedLayerIndex;
    if (idx < 0 || idx >= _project.layers.length) return null;
    final layer = _project.layers[idx];
    if (!layer.visible || layer.pathKeyframes.length < 2) return null;
    return layer;
  }

  Rect _layerCanvasRect(MosaicLayer layer, Rect videoRect, double scale) {
    if (!layer.hasContent) return Rect.zero;
    final state = layer.getStateAt(_currentTime);
    final cx = videoRect.left + state.position.dx * scale;
    final cy = videoRect.top + state.position.dy * scale;
    final w = state.size.width * scale;
    final h = state.size.height * scale;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// 現在時刻に対応する経路キーフレームを取得または作成
  PathPoint _getOrCreatePathPointAt(MosaicLayer layer, Duration time) {
    const toleranceMs = 200; // この時間内のキーフレームを同一とみなす
    for (final kf in layer.pathKeyframes) {
      if ((kf.time.inMilliseconds - time.inMilliseconds).abs() <=
          toleranceMs) {
        return kf;
      }
    }
    final newKf = PathPoint(time: time, position: layer.positionAt(time));
    layer.addPathKeyframe(newKf);
    return newKf;
  }

  /// 現在時刻に対応する基準を取得または作成。
  /// 基準が1つだけのときは常にそれを編集する（レイヤー全体で共通の扱い）。
  /// 基準を時間変化させたい場合はタイムタブから明示的に追加する
  StylePoint _getOrCreateStylePointAt(MosaicLayer layer, Duration time) {
    if (layer.styleKeyframes.length <= 1) {
      if (layer.styleKeyframes.isEmpty) {
        layer.addStyleKeyframe(StylePoint(
          time: time,
          size: Size(_videoSize.width * 0.35, _videoSize.height * 0.22),
        ));
      }
      return layer.styleKeyframes.first;
    }
    const toleranceMs = 200;
    for (final s in layer.styleKeyframes) {
      if ((s.time.inMilliseconds - time.inMilliseconds).abs() <=
          toleranceMs) {
        return s;
      }
    }
    final state = layer.getStateAt(time);
    final newPoint = StylePoint(
      time: time,
      size: state.size,
      rotation: state.rotation,
      intensity: state.intensity,
    );
    layer.addStyleKeyframe(newPoint);
    return newPoint;
  }

  void _moveLayer(int index, Offset canvasDelta, double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.locked || layer.pathKeyframes.isEmpty) return;
    setState(() {
      final kf = _getOrCreatePathPointAt(layer, _currentTime);
      kf.position = Offset(
        (kf.position.dx + canvasDelta.dx / scale)
            .clamp(0, _videoSize.width),
        (kf.position.dy + canvasDelta.dy / scale)
            .clamp(0, _videoSize.height),
      );
    });
    _scheduleSave();
  }

  /// 指定した経路キーフレームを直接動かす（経路編集オーバーレイから）
  void _movePathPoint(
      int layerIndex, int pointIndex, Offset canvasDelta, double scale) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.locked) return;
    if (pointIndex < 0 || pointIndex >= layer.pathKeyframes.length) return;
    setState(() {
      final kf = layer.pathKeyframes[pointIndex];
      kf.position = Offset(
        (kf.position.dx + canvasDelta.dx / scale)
            .clamp(0, _videoSize.width),
        (kf.position.dy + canvasDelta.dy / scale)
            .clamp(0, _videoSize.height),
      );
    });
    _scheduleSave();
  }

  /// 経路キーフレームの位置を絶対座標で設定（経路点一覧の手動調整から）
  void _setPathPointPosition(
      int layerIndex, int pointIndex, Offset position) {
    if (layerIndex < 0 || layerIndex >= _project.layers.length) return;
    final layer = _project.layers[layerIndex];
    if (layer.locked) return;
    if (pointIndex < 0 || pointIndex >= layer.pathKeyframes.length) {
      return;
    }
    setState(() {
      layer.pathKeyframes[pointIndex].position = Offset(
        position.dx.clamp(0, _videoSize.width),
        position.dy.clamp(0, _videoSize.height),
      );
    });
    _scheduleSave();
  }

  /// リサイズは基準（サイズ）のみを編集し、経路には触れない。
  /// 中心固定で拡大縮小されるため、追跡済みの経路が崩れない
  void _resizeLayer(
      int index, Offset canvasDelta, HandleCorner corner, double scale) {
    if (index < 0 || index >= _project.layers.length) return;
    final layer = _project.layers[index];
    if (layer.locked || !layer.hasContent) return;

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
      final style = _getOrCreateStylePointAt(layer, _currentTime);
      // 中心固定なのでドラッグ量は2倍でサイズに反映（ハンドル追従）
      final newW = (style.size.width + imgDx * widthSign * 2)
          .clamp(20.0, _videoSize.width);
      final newH = (style.size.height + imgDy * heightSign * 2)
          .clamp(20.0, _videoSize.height);
      style.size = Size(newW, newH);
    });
    _scheduleSave();
  }

  // --- 出力プレビュー（モザイク適用済みのまま再生できる全画面表示） ---

  void _showPreview() {
    if (_videoController == null) return;
    setState(() => _showingPreview = true);
  }

  void _closePreview() {
    setState(() => _showingPreview = false);
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
      playbackSpeed: _playbackSpeed,
      onSpeedChanged: _setPlaybackSpeed,
      isMuted: _muted,
      onToggleMute: _toggleMute,
      onScrubStart: _onScrubStart,
      onScrubEnd: _onScrubEnd,
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
      onBarAngleChanged: _onBarAngleChanged,
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
      onAddStylePointAtCurrent: _addStylePointAtCurrent,
      onDeleteStylePointAtCurrent: _deleteStylePointAtCurrent,
      onDeleteStylePoint: _deleteStylePoint,
      onSetPathPointPosition: _setPathPointPosition,
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
          isPreviewLoading: false,
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
        // 出力プレビューは全UIの最前面に重ねる
        if (_showingPreview && _videoController != null)
          VideoPreviewOverlay(
            controller: _videoController!,
            layers: _project.layers,
            videoSize: _videoSize,
            currentTime: _currentTime,
            totalDuration: _totalDuration,
            isPlaying: _playing,
            isLoading: _playLoading,
            playbackSpeed: _playbackSpeed,
            onTogglePlay: _togglePlayPause,
            onSeek: _seekTo,
            onSpeedChanged: _setPlaybackSpeed,
            isMuted: _muted,
            onToggleMute: _toggleMute,
            onScrubStart: _onScrubStart,
            onScrubEnd: _onScrubEnd,
            onClose: _closePreview,
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
                    _project.layers[i].hasContent &&
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
                    barAngle: _project.layers[i].barAngle,
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
                      _project.layers[i].hasContent &&
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
              // 選択中レイヤーの移動経路（前後の経路を表示・点をドラッグで修正）
              if (!_saving && _selectedPathLayer != null)
                PathEditOverlay(
                  key: ValueKey('path_${_selectedPathLayer!.id}'),
                  pathKeyframes: _selectedPathLayer!.pathKeyframes,
                  videoRect: videoRect,
                  scale: scale,
                  currentTime: _currentTime,
                  enabled: !_selectedPathLayer!.locked,
                  onMovePoint: (i, delta) => _movePathPoint(
                      _project.selectedLayerIndex, i, delta, scale),
                  onTapPoint: (i) => _seekTo(
                      _selectedPathLayer!.pathKeyframes[i].time),
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
