import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// キャンバス上にフローティング配置される丸型アクションボタン。
/// ツールバーを撤廃し、戻る/保存ボタンを画面の角に浮かせることでキャンバス領域を最大化する。
class FloatingActionButtonRow extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool isSaving;

  /// Undo/Redo コールバック。null なら非表示
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;

  /// プレビューコールバック（出力相当の合成画像を全画面表示）。null なら非表示。
  final VoidCallback? onPreview;
  final bool isPreviewLoading;

  const FloatingActionButtonRow({
    super.key,
    required this.onBack,
    this.onSave,
    this.isSaving = false,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.onPreview,
    this.isPreviewLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasHistory = onUndo != null && onRedo != null;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            _CircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '戻る',
              onTap: onBack,
            ),
            if (hasHistory) ...[
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.undo_rounded,
                tooltip: '元に戻す',
                onTap: canUndo ? onUndo! : null,
                enabled: canUndo,
              ),
              const SizedBox(width: 4),
              _CircleButton(
                icon: Icons.redo_rounded,
                tooltip: 'やり直す',
                onTap: canRedo ? onRedo! : null,
                enabled: canRedo,
              ),
            ],
            const Spacer(),
            if (onPreview != null) ...[
              _CircleButton(
                icon: Icons.visibility_rounded,
                tooltip: '出力プレビュー',
                onTap: onPreview!,
                loading: isPreviewLoading,
              ),
              const SizedBox(width: 8),
            ],
            if (onSave != null)
              _CircleButton(
                icon: Icons.download_rounded,
                tooltip: '保存',
                onTap: onSave!,
                highlighted: true,
                loading: isSaving,
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool loading;
  final bool enabled;

  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
    this.loading = false,
    this.enabled = true,
  });

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final bg = widget.highlighted
        ? AppTheme.accent
        : Colors.black.withValues(alpha: 0.5);
    final iconColor = Colors.white;

    final disabled = !widget.enabled || widget.onTap == null;
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown:
            widget.loading || disabled ? null : (_) => _ctrl.forward(),
        onTapUp: widget.loading || disabled
            ? null
            : (_) {
                _ctrl.reverse();
                widget.onTap?.call();
              },
        onTapCancel:
            widget.loading || disabled ? null : () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Opacity(
                opacity: disabled ? 0.35 : 1.0,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.highlighted
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                    boxShadow: disabled
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                            if (widget.highlighted)
                              BoxShadow(
                                color: AppTheme.accent
                                    .withValues(alpha: 0.45),
                                blurRadius: 16,
                                spreadRadius: -2,
                              ),
                          ],
                  ),
                  child: Center(
                    child: widget.loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: iconColor,
                            ),
                          )
                        : Icon(widget.icon, size: 20, color: iconColor),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
