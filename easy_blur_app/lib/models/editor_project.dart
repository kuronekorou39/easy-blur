import 'mosaic_layer.dart';

enum MediaType {
  image,
  video,
}

class EditorProject {
  /// プロジェクトの一意ID。保存時はこれを使ってファイル名を決める。
  final String id;
  final String mediaPath;
  final MediaType mediaType;
  final List<MosaicLayer> layers;
  int selectedLayerIndex;
  Duration? videoDuration;

  /// 最終更新日時
  DateTime updatedAt;

  EditorProject({
    String? id,
    required this.mediaPath,
    required this.mediaType,
    List<MosaicLayer>? layers,
    this.selectedLayerIndex = -1,
    this.videoDuration,
    DateTime? updatedAt,
  })  : id = id ?? 'proj_${DateTime.now().microsecondsSinceEpoch}',
        layers = layers ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  MosaicLayer? get selectedLayer {
    if (selectedLayerIndex < 0 || selectedLayerIndex >= layers.length) {
      return null;
    }
    return layers[selectedLayerIndex];
  }

  bool get isVideo => mediaType == MediaType.video;
  bool get isImage => mediaType == MediaType.image;

  MosaicLayer addLayer({String? name}) {
    final layer = MosaicLayer(
      id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'レイヤー ${layers.length + 1}',
    );
    layers.add(layer);
    selectedLayerIndex = layers.length - 1;
    return layer;
  }

  void removeLayer(int index) {
    if (index < 0 || index >= layers.length) return;
    layers.removeAt(index);
    if (selectedLayerIndex >= layers.length) {
      selectedLayerIndex = layers.length - 1;
    }
  }

  void reorderLayer(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= layers.length) return;
    if (newIndex < 0 || newIndex >= layers.length) return;
    final layer = layers.removeAt(oldIndex);
    layers.insert(newIndex, layer);
    if (selectedLayerIndex == oldIndex) {
      selectedLayerIndex = newIndex;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaPath': mediaPath,
        'mediaType': mediaType.name,
        'videoDurationMs': videoDuration?.inMilliseconds,
        'selectedLayerIndex': selectedLayerIndex,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  static EditorProject fromJson(Map<String, dynamic> json) {
    return EditorProject(
      id: json['id'] as String,
      mediaPath: json['mediaPath'] as String,
      mediaType: MediaType.values.firstWhere(
        (m) => m.name == json['mediaType'],
        orElse: () => MediaType.image,
      ),
      videoDuration: json['videoDurationMs'] != null
          ? Duration(milliseconds: (json['videoDurationMs'] as num).toInt())
          : null,
      selectedLayerIndex: (json['selectedLayerIndex'] as num?)?.toInt() ?? -1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch),
      layers: (json['layers'] as List<dynamic>?)
              ?.map((l) => MosaicLayer.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
