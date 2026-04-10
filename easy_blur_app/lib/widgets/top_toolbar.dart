import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class TopToolbar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final VoidCallback? onAddLayer;
  final bool isSaving;
  final String title;

  const TopToolbar({
    super.key,
    required this.onBack,
    this.onSave,
    this.onAddLayer,
    this.isSaving = false,
    this.title = '',
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.toolbarRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(AppTheme.toolbarRadius),
            border: Border.all(color: AppTheme.borderColor.withValues(alpha:0.6)),
          ),
          child: Row(
            children: [
              _ToolbarBtn(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (onAddLayer != null)
                _ToolbarBtn(
                  icon: Icons.add_rounded,
                  onTap: onAddLayer!,
                ),
              if (onSave != null)
                isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        ),
                      )
                    : _ToolbarBtn(
                        icon: Icons.save_rounded,
                        onTap: onSave!,
                      ),
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

  const _ToolbarBtn({required this.icon, required this.onTap});

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
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween(begin: 1.0, end: 0.85).animate(
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
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.bgHover.withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, size: 20, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}
