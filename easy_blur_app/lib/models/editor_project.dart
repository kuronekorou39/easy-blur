import 'mosaic_layer.dart';

enum MediaType {
  image,
  video,
}

class EditorProject {
  final String mediaPath;
  final MediaType mediaType;
  final List<MosaicLayer> layers;
  int selectedLayerIndex;
  Duration? videoDuration;

  EditorProject({
    required this.mediaPath,
    required this.mediaType,
    List<MosaicLayer>? layers,
    this.selectedLayerIndex = -1,
    this.videoDuration,
  }) : layers = layers ?? [];

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
}
