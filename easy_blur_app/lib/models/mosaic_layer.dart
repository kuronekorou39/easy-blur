import 'dart:ui';

enum MosaicType {
  pixelate,
  blur,
  fill, // 単色塗りつぶし（旧 blackout/whiteout を統合、色は MosaicLayer.fillColor）
  noise,
}

enum MosaicShape {
  rectangle,
  ellipse,
  triangle,
  heart,
}

class Keyframe {
  final Duration time;
  Offset position;
  Size size;
  double rotation;
  double intensity;

  Keyframe({
    required this.time,
    required this.position,
    required this.size,
    this.rotation = 0.0,
    this.intensity = 20.0,
  });

  Keyframe copyWith({
    Duration? time,
    Offset? position,
    Size? size,
    double? rotation,
    double? intensity,
  }) {
    return Keyframe(
      time: time ?? this.time,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      intensity: intensity ?? this.intensity,
    );
  }

  static Keyframe lerp(Keyframe a, Keyframe b, double t) {
    return Keyframe(
      time: Duration(
        milliseconds:
            (a.time.inMilliseconds + (b.time.inMilliseconds - a.time.inMilliseconds) * t).round(),
      ),
      position: Offset.lerp(a.position, b.position, t)!,
      size: Size.lerp(a.size, b.size, t)!,
      rotation: a.rotation + (b.rotation - a.rotation) * t,
      intensity: a.intensity + (b.intensity - a.intensity) * t,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeMs': time.inMilliseconds,
        'posX': position.dx,
        'posY': position.dy,
        'sizeW': size.width,
        'sizeH': size.height,
        'rotation': rotation,
        'intensity': intensity,
      };

  static Keyframe fromJson(Map<String, dynamic> json) => Keyframe(
        time: Duration(milliseconds: (json['timeMs'] as num).toInt()),
        position: Offset(
            (json['posX'] as num).toDouble(), (json['posY'] as num).toDouble()),
        size: Size(
            (json['sizeW'] as num).toDouble(), (json['sizeH'] as num).toDouble()),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
        intensity: (json['intensity'] as num?)?.toDouble() ?? 20.0,
      );
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
  int fillColor;

  /// レイヤーが表示され始める時刻（動画専用、画像では未使用）
  Duration startTime;

  /// レイヤーが非表示になる時刻（動画専用、画像では未使用）
  /// デフォルトは非常に大きな値で事実上無制限
  Duration endTime;

  List<Keyframe> keyframes;

  MosaicLayer({
    required this.id,
    required this.name,
    this.type = MosaicType.pixelate,
    this.shape = MosaicShape.rectangle,
    this.visible = true,
    this.inverted = false,
    this.locked = false,
    this.fillColor = 0xFF000000,
    this.startTime = Duration.zero,
    this.endTime = const Duration(days: 1),
    List<Keyframe>? keyframes,
  }) : keyframes = keyframes ?? [];

  /// 指定時刻でレイヤーがアクティブ（表示対象）かどうか
  bool isActiveAt(Duration time) {
    return time >= startTime && time <= endTime;
  }

  /// Get interpolated keyframe at a given time.
  /// For image mode, returns the first keyframe (or a default).
  Keyframe getStateAt(Duration time) {
    if (keyframes.isEmpty) {
      return Keyframe(
        time: Duration.zero,
        position: Offset.zero,
        size: const Size(100, 100),
      );
    }

    if (keyframes.length == 1) return keyframes.first;

    // Before first keyframe
    if (time <= keyframes.first.time) return keyframes.first;

    // After last keyframe
    if (time >= keyframes.last.time) return keyframes.last;

    // Find the two surrounding keyframes and lerp
    for (int i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (time >= a.time && time <= b.time) {
        final range = (b.time - a.time).inMilliseconds;
        if (range == 0) return a;
        final t = (time - a.time).inMilliseconds / range;
        return Keyframe.lerp(a, b, t);
      }
    }

    return keyframes.last;
  }

  void addKeyframe(Keyframe kf) {
    keyframes.add(kf);
    keyframes.sort((a, b) => a.time.compareTo(b.time));
  }

  void removeKeyframeAt(int index) {
    if (index >= 0 && index < keyframes.length) {
      keyframes.removeAt(index);
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
        'startTimeMs': startTime.inMilliseconds,
        'endTimeMs': endTime.inMilliseconds,
        'keyframes': keyframes.map((k) => k.toJson()).toList(),
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
      startTime: Duration(
          milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      endTime: Duration(
          milliseconds: (json['endTimeMs'] as num?)?.toInt() ??
              const Duration(days: 1).inMilliseconds),
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
