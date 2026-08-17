import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// プロジェクトカード用のメディアサムネイル。
/// 画像はファイルを直接縮小表示、動画は先頭フレームを取得して
/// メモリキャッシュする（ホームに戻るたびの再生成を避ける）。
class ProjectThumbnail extends StatefulWidget {
  final EditorProject project;

  const ProjectThumbnail({super.key, required this.project});

  @override
  State<ProjectThumbnail> createState() => _ProjectThumbnailState();
}

class _ProjectThumbnailState extends State<ProjectThumbnail> {
  /// 動画サムネイルのメモリキャッシュ（メディアパス → PNGバイト列）
  static final Map<String, Uint8List?> _videoThumbCache = {};

  Uint8List? _videoThumb;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.project.isVideo) {
      _loadVideoThumb();
    }
  }

  Future<void> _loadVideoThumb() async {
    final path = widget.project.mediaPath;
    if (_videoThumbCache.containsKey(path)) {
      _videoThumb = _videoThumbCache[path];
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 70,
      );
      _videoThumbCache[path] = bytes;
      if (mounted) setState(() => _videoThumb = bytes);
    } catch (_) {
      _videoThumbCache[path] = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.isImage) {
      final file = File(widget.project.mediaPath);
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 320,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    if (_videoThumb != null) {
      return Image.memory(
        _videoThumb!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback(loading: _loading);
  }

  Widget _fallback({bool loading = false}) {
    return Container(
      color: AppTheme.bgTertiary,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.textMuted,
              ),
            )
          : Icon(
              widget.project.isVideo
                  ? Icons.videocam_rounded
                  : Icons.image_rounded,
              size: 28,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
    );
  }
}
