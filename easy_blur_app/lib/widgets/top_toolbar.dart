import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class TopToolbar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final VoidCallback? onAddLayer;
  final bool isSaving;
  final String title;
  final int layerCount;

  const TopToolbar({
    super.key,
    required this.onBack,
    this.onSave,
    this.onAddLayer,
    this.isSaving = false,
    this.title = '',
    this.layerCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.toolbarRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(AppTheme.toolbarRadius),
            border: Border.all(
                color: AppTheme.borderColor.withValues(alpha: 0.8)),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Row(
            children: [
              _ToolbarBtn(
                icon: Icons.arrow_back_rounded,
                tooltip: '戻る',
                onTap: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (layerCount > 0) ...[
                      const SizedBox(height: 1),
                      Text(
                        '$layerCount レイヤー',
                        style: AppTheme.textCaption.copyWith(fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (onAddLayer != null)
                _ToolbarBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'レイヤーを追加',
                  onTap: onAddLayer!,
                ),
              if (onSave != null) ...[
                const SizedBox(width: 4),
                isSaving
                    ? Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppTheme.accent,
                          ),
                        ),
                      )
                    : _ToolbarBtn(
                        icon: Icons.download_rounded,
                        tooltip: '保存',
                        onTap: onSave!,
                        highlighted: true,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool highlighted;

  const _ToolbarBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.highlighted = false,
  });

  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends State<_ToolbarBtn>
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
    _scale = Tween(begin: 1.0, end: 0.9).animate(
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
    final btn = GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.highlighted
                ? AppTheme.accent
                : AppTheme.bgHover.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: widget.highlighted ? AppTheme.shadowGlow : null,
          ),
          child: Icon(
            widget.icon,
            size: 21,
            color: widget.highlighted
                ? Colors.white
                : AppTheme.textPrimary,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}
