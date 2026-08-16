import 'dart:ui';

enum MosaicType {
  pixelate,
  blur,
  fill, // 単色塗りつぶし（旧 blackout/whiteout を統合、色は MosaicLayer.fillColor）
  noise,
  bars, // 黒のり風ストライプ。色は fillColor、密度は intensity、角度は barAngle
}

enum MosaicShape {
  rectangle,
  ellipse,
  triangle,
  heart,
}

/// 経路キーフレーム。モザイクの移動経路（位置）だけを持つ
class PathPoint {
  final Duration time;
  Offset position;

  PathPoint({required this.time, required this.position});

  Map<String, dynamic> toJson() => {
        'timeMs': time.inMilliseconds,
        'posX': position.dx,
        'posY': position.dy,
      };

  static PathPoint fromJson(Map<String, dynamic> json) => PathPoint(
        time: Duration(milliseconds: (json['timeMs'] as num).toInt()),
        position: Offset(
            (json['posX'] as num).toDouble(), (json['posY'] as num).toDouble()),
      );
}

/// 基準キーフレーム。サイズ・回転・強度を持ち、経路とは独立して補間される
class StylePoint {
  final Duration time;
  Size size;
  double rotation;
  double intensity;

  StylePoint({
    required this.time,
    required this.size,
    this.rotation = 0.0,
    this.intensity = 20.0,
  });

  Map<String, dynamic> toJson() => {
        'timeMs': time.inMilliseconds,
        'sizeW': size.width,
        'sizeH': size.height,
        'rotation': rotation,
        'intensity': intensity,
      };

  static StylePoint fromJson(Map<String, dynamic> json) => StylePoint(
        time: Duration(milliseconds: (json['timeMs'] as num).toInt()),
        size: Size(
            (json['sizeW'] as num).toDouble(), (json['sizeH'] as num).toDouble()),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
        intensity: (json['intensity'] as num?)?.toDouble() ?? 20.0,
      );
}

/// 指定時刻における経路・基準の補間結果
class LayerState {
  final Offset position;
  final Size size;
  final double rotation;
  final double intensity;

  const LayerState({
    required this.position,
    required this.size,
    required this.rotation,
    required this.intensity,
  });
}

class MosaicLayer {
  String id;
  String name;
  MosaicType type;
  MosaicShape shape;
  bool visible;

  /// true の場合、矩形の外側にエフェクトが適用される（内外反転）
  bool inverted;

  /// true の場合、キャンバス上での選択・移動・リサイズができない
  /// （レイヤーパネルからのプロパティ変更は可能）
  bool locked;

  /// fill エフェクトで使用する色（ARGB値）。デフォルトは黒。
  /// bars エフェクトでも色の指定として共用する。
  int fillColor;

  /// bars エフェクト用、ストライプの角度（ラジアン）。
  /// レイヤー形状の回転とは独立して、ストライプだけを傾ける。
  /// 0 = 水平ストライプ、π/2 = 垂直ストライプ。
  double barAngle;

  /// レイヤーが表示され始める時刻（動画専用、画像では未使用）
  Duration startTime;

  /// レイヤーが非表示になる時刻（動画専用、画像では未使用）
  /// デフォルトは非常に大きな値で事実上無制限
  Duration endTime;

  /// 移動経路（位置のキーフレーム列）
  List<PathPoint> pathKeyframes;

  /// 基準（サイズ・回転・強度のキーフレーム列）。経路とは独立
  List<StylePoint> styleKeyframes;

  MosaicLayer({
    required this.id,
    required this.name,
    this.type = MosaicType.pixelate,
    this.shape = MosaicShape.rectangle,
    this.visible = true,
    this.inverted = false,
    this.locked = false,
    this.fillColor = 0xFF000000,
    this.barAngle = 0.0,
    this.startTime = Duration.zero,
    this.endTime = const Duration(days: 1),
    List<PathPoint>? pathKeyframes,
    List<StylePoint>? styleKeyframes,
  })  : pathKeyframes = pathKeyframes ?? [],
        styleKeyframes = styleKeyframes ?? [];

  /// 描画に必要なキーフレームが揃っているか
  bool get hasContent => pathKeyframes.isNotEmpty && styleKeyframes.isNotEmpty;

  /// 指定時刻でレイヤーがアクティブ（表示対象）かどうか
  bool isActiveAt(Duration time) {
    return time >= startTime && time <= endTime;
  }

  /// 指定時刻の位置（経路の線形補間）
  Offset positionAt(Duration time) {
    if (pathKeyframes.isEmpty) return Offset.zero;
    final t = _segment(pathKeyframes.map((p) => p.time).toList(), time);
    if (t == null) {
      return time <= pathKeyframes.first.time
          ? pathKeyframes.first.position
          : pathKeyframes.last.position;
    }
    final a = pathKeyframes[t.$1];
    final b = pathKeyframes[t.$1 + 1];
    return Offset.lerp(a.position, b.position, t.$2)!;
  }

  /// 指定時刻のサイズ・回転・強度（基準の線形補間）
  LayerState getStateAt(Duration time) {
    Size size = const Size(100, 100);
    double rotation = 0.0;
    double intensity = 20.0;
    if (styleKeyframes.isNotEmpty) {
      final t = _segment(styleKeyframes.map((s) => s.time).toList(), time);
      if (t == null) {
        final s = time <= styleKeyframes.first.time
            ? styleKeyframes.first
            : styleKeyframes.last;
        size = s.size;
        rotation = s.rotation;
        intensity = s.intensity;
      } else {
        final a = styleKeyframes[t.$1];
        final b = styleKeyframes[t.$1 + 1];
        size = Size.lerp(a.size, b.size, t.$2)!;
        rotation = a.rotation + (b.rotation - a.rotation) * t.$2;
        intensity = a.intensity + (b.intensity - a.intensity) * t.$2;
      }
    }
    return LayerState(
      position: positionAt(time),
      size: size,
      rotation: rotation,
      intensity: intensity,
    );
  }

  /// [times]（昇順）の中で time を挟む区間 (index, 補間率) を返す。
  /// 範囲外・単一要素の場合は null
  (int, double)? _segment(List<Duration> times, Duration time) {
    if (times.length < 2) return null;
    if (time <= times.first || time >= times.last) return null;
    for (int i = 0; i < times.length - 1; i++) {
      if (time >= times[i] && time <= times[i + 1]) {
        final range = (times[i + 1] - times[i]).inMilliseconds;
        if (range == 0) return (i, 0.0);
        return (i, (time - times[i]).inMilliseconds / range);
      }
    }
    return null;
  }

  void addPathKeyframe(PathPoint point) {
    pathKeyframes.add(point);
    pathKeyframes.sort((a, b) => a.time.compareTo(b.time));
  }

  void removePathKeyframeAt(int index) {
    if (index >= 0 && index < pathKeyframes.length) {
      pathKeyframes.removeAt(index);
    }
  }

  void addStyleKeyframe(StylePoint point) {
    styleKeyframes.add(point);
    styleKeyframes.sort((a, b) => a.time.compareTo(b.time));
  }

  void removeStyleKeyframeAt(int index) {
    if (index >= 0 && index < styleKeyframes.length) {
      styleKeyframes.removeAt(index);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'shape': shape.name,
        'visible': visible,
        'inverted': inverted,
        'locked': locked,
        'fillColor': fillColor,
        'barAngle': barAngle,
        'startTimeMs': startTime.inMilliseconds,
        'endTimeMs': endTime.inMilliseconds,
        'pathKeyframes': pathKeyframes.map((p) => p.toJson()).toList(),
        'styleKeyframes': styleKeyframes.map((s) => s.toJson()).toList(),
      };

  static MosaicLayer fromJson(Map<String, dynamic> json) {
    // 旧形式の blackout / whiteout を fill に自動移行
    final rawType = json['type'] as String?;
    MosaicType type;
    int fillColor = (json['fillColor'] as num?)?.toInt() ?? 0xFF000000;
    switch (rawType) {
      case 'blackout':
        type = MosaicType.fill;
        fillColor = 0xFF000000;
        break;
      case 'whiteout':
        type = MosaicType.fill;
        fillColor = 0xFFFFFFFF;
        break;
      default:
        type = MosaicType.values.firstWhere(
          (t) => t.name == rawType,
          orElse: () => MosaicType.pixelate,
        );
    }
    // 経路・基準の読み込み。旧形式（keyframes に全プロパティ同居）は
    // 位置→経路、サイズ等→基準へ分解して移行する（描画結果は同一）
    List<PathPoint> path;
    List<StylePoint> styles;
    if (json['pathKeyframes'] != null) {
      path = (json['pathKeyframes'] as List<dynamic>)
          .map((p) => PathPoint.fromJson(p as Map<String, dynamic>))
          .toList();
      styles = (json['styleKeyframes'] as List<dynamic>? ?? [])
          .map((s) => StylePoint.fromJson(s as Map<String, dynamic>))
          .toList();
    } else {
      final legacy = (json['keyframes'] as List<dynamic>? ?? [])
          .map((k) => k as Map<String, dynamic>)
          .toList();
      path = legacy.map(PathPoint.fromJson).toList();
      styles = legacy.map(StylePoint.fromJson).toList();
      // 旧仕様ではサイズ・強度が全キーフレーム共通のことが多いため、
      // 全て同一値なら基準1つに集約する（描画結果は変わらない）
      if (styles.length > 1) {
        final first = styles.first;
        final uniform = styles.every((s) =>
            s.size == first.size &&
            s.rotation == first.rotation &&
            s.intensity == first.intensity);
        if (uniform) styles = [first];
      }
    }

    return MosaicLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      type: type,
      shape: MosaicShape.values.firstWhere(
        (s) => s.name == json['shape'],
        orElse: () => MosaicShape.rectangle,
      ),
      visible: json['visible'] as bool? ?? true,
      inverted: json['inverted'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      fillColor: fillColor,
      barAngle: (json['barAngle'] as num?)?.toDouble() ?? 0.0,
      startTime: Duration(
          milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      endTime: Duration(
          milliseconds: (json['endTimeMs'] as num?)?.toInt() ??
              const Duration(days: 1).inMilliseconds),
      pathKeyframes: path,
      styleKeyframes: styles,
    );
  }
}
