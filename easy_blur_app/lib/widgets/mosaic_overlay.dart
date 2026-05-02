import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// モザイクレイヤーの選択枠と操作ハンドルを表示するWidget。
/// CustomPainter で手描きせず、通常のGestureDetectorで確実な操作を提供。
class MosaicOverlay extends StatelessWidget {
  final MosaicLayer layer;

  /// キャンバス座標系でのレイヤー矩形
  final Rect canvasRect;
  final bool isSelected;
  final VoidCallback onTap;

  /// キャンバス座標での移動デルタ
  final void Function(Offset delta) onMove;

  /// キャンバス座標での拡縮デルタ
  final void Function(Offset delta, HandleCorner corner) onResize;

  const MosaicOverlay({
    super.key,
    required this.layer,
    required this.canvasRect,
    required this.isSelected,
    required this.onTap,
    required this.onMove,
    required this.onResize,
  });

  bool get _locked => layer.locked;

  @override
  Widget build(BuildContext context) {
    // タッチ領域（見た目は _Handle 内で 14pt の円）。指で掴みやすいよう広めに。
    const handleSize = 36.0;
    final rect = canvasRect;

    return Positioned(
      left: rect.left - handleSize,
      top: rect.top - handleSize,
      width: rect.width + handleSize * 2,
      height: rect.height + handleSize * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 中央：移動用タップ＋ドラッグエリア（ロック中は完全に透過）
          Positioned(
            left: handleSize,
            top: handleSize,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              ignoring: _locked,
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onPanUpdate: (d) {
                if (!isSelected) onTap();
                onMove(d.delta);
              },
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: AppTheme.animFast,
                  decoration: BoxDecoration(
                    border: isSelected
                        ? Border.all(
                            color: AppTheme.accent,
                            width: 2,
                          )
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.35),
                              blurRadius: 8,
                              spreadRadius: -1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
            ),
          ),

          // 選択時のみ表示されるコーナーハンドル（ロック中は非表示）
          if (isSelected && !_locked) ...[
            _Handle(
              left: 0,
              top: 0,
              size: handleSize,
              onDrag: (d) => onResize(d, HandleCorner.topLeft),
            ),
            _Handle(
              left: rect.width + handleSize,
              top: 0,
              size: handleSize,
              onDrag: (d) => onResize(d, HandleCorner.topRight),
            ),
            _Handle(
              left: 0,
              top: rect.height + handleSize,
              size: handleSize,
              onDrag: (d) => onResize(d, HandleCorner.bottomLeft),
            ),
            _Handle(
              left: rect.width + handleSize,
              top: rect.height + handleSize,
              size: handleSize,
              onDrag: (d) => onResize(d, HandleCorner.bottomRight),
            ),
            // レイヤー名バッジ（矩形の外側、上部に添える）
            Positioned(
              left: handleSize,
              top: handleSize - 22,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    layer.name,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum HandleCorner { topLeft, topRight, bottomLeft, bottomRight }

class _Handle extends StatefulWidget {
  final double left;
  final double top;
  final double size;
  final void Function(Offset delta) onDrag;

  const _Handle({
    required this.left,
    required this.top,
    required this.size,
    required this.onDrag,
  });

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    const visualSize = 14.0;
    return Positioned(
      left: widget.left,
      top: widget.top,
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _active = true),
        onPanUpdate: (d) => widget.onDrag(d.delta),
        onPanEnd: (_) => setState(() => _active = false),
        onPanCancel: () => setState(() => _active = false),
        child: Center(
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            width: _active ? visualSize + 4 : visualSize,
            height: _active ? visualSize + 4 : visualSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accent,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: _active ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
