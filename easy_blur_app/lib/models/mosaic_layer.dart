import 'dart:ui';

enum MosaicType {
  pixelate,
  blur,
  blackout,
}

enum MosaicShape {
  rectangle,
  ellipse,
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
}

class MosaicLayer {
  String id;
  String name;
  MosaicType type;
  MosaicShape shape;
  bool visible;

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
}
