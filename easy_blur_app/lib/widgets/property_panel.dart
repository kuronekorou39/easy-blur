import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// プロ仕様のプロパティパネル
/// - 大きなチップ（タッチ領域確保）
/// - 明確なセクション見出し
/// - スライダーに数値値表示、値調整時のハプティック的な視覚効果
class PropertyPanel extends StatelessWidget {
  final MosaicLayer? layer;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<double> onIntensityChanged;

  const PropertyPanel({
    super.key,
    required this.layer,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onIntensityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        if (layer == null) {
          return bounded
              ? _buildEmptyState()
              : SizedBox(height: 180, child: _buildEmptyState());
        }
        final kf =
            layer!.keyframes.isNotEmpty ? layer!.keyframes.first : null;
        final content = _buildContent(kf);
        if (bounded) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }

  Widget _buildContent(Keyframe? kf) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceLg, 4, AppTheme.spaceLg, AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== モザイク種類 =====
          _SectionLabel(label: '効果'),
          const SizedBox(height: AppTheme.spaceSm),
          Row(
            children: MosaicType.values.map((type) {
              final isSelected = layer!.type == type;
              final isLast = type == MosaicType.values.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: _OptionChip(
                    label: _typeLabel(type),
                    icon: _typeIcon(type),
                    isSelected: isSelected,
                    onTap: () => onTypeChanged(type),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.spaceLg),

          // ===== 形状 =====
          _SectionLabel(label: '形状'),
          const SizedBox(height: AppTheme.spaceSm),
          Row(
            children: MosaicShape.values.map((shape) {
              final isSelected = layer!.shape == shape;
              final isLast = shape == MosaicShape.values.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: _OptionChip(
                    label: _shapeLabel(shape),
                    icon: _shapeIcon(shape),
                    isSelected: isSelected,
                    onTap: () => onShapeChanged(shape),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.spaceLg),

          // ===== 強度 =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SectionLabel(label: '強度'),
              const Spacer(),
              _ValueChip(value: (kf?.intensity ?? 20).round().toString()),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _SliderButton(
                icon: Icons.remove_rounded,
                onTap: () {
                  final cur = kf?.intensity ?? 20;
                  onIntensityChanged((cur - 2).clamp(2, 60));
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Slider(
                  value: (kf?.intensity ?? 20).clamp(2, 60),
                  min: 2,
                  max: 60,
                  onChanged: onIntensityChanged,
                ),
              ),
              const SizedBox(width: 6),
              _SliderButton(
                icon: Icons.add_rounded,
                onTap: () {
                  final cur = kf?.intensity ?? 20;
                  onIntensityChanged((cur + 2).clamp(2, 60));
                },
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSm),

          // ===== ヒント =====
          Container(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                  color: AppTheme.borderColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 14,
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'キャンバスでドラッグして移動、角で拡縮、2本指でズーム',
                    style: AppTheme.textCaption.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 30,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          Text(
            'レイヤーが未選択',
            style: AppTheme.textBodyStrong,
          ),
          const SizedBox(height: 4),
          Text(
            'レイヤータブから選択するか新規追加',
            style: AppTheme.textCaption,
          ),
        ],
      ),
    );
  }

  String _typeLabel(MosaicType type) {
    switch (type) {
      case MosaicType.pixelate:
        return 'モザイク';
      case MosaicType.blur:
        return 'ぼかし';
      case MosaicType.fill:
        return 'バケツ';
      case MosaicType.noise:
        return 'ノイズ';
    }
  }

  IconData _typeIcon(MosaicType type) {
    switch (type) {
      case MosaicType.pixelate:
        return Icons.grid_on_rounded;
      case MosaicType.blur:
        return Icons.blur_on_rounded;
      case MosaicType.fill:
        return Icons.format_color_fill_rounded;
      case MosaicType.noise:
        return Icons.grain_rounded;
    }
  }

  String _shapeLabel(MosaicShape shape) {
    switch (shape) {
      case MosaicShape.rectangle:
        return '矩形';
      case MosaicShape.ellipse:
        return '楕円';
      case MosaicShape.triangle:
        return '三角';
      case MosaicShape.heart:
        return 'ハート';
    }
  }

  IconData _shapeIcon(MosaicShape shape) {
    switch (shape) {
      case MosaicShape.rectangle:
        return Icons.crop_square_rounded;
      case MosaicShape.ellipse:
        return Icons.circle_outlined;
      case MosaicShape.triangle:
        return Icons.change_history_rounded;
      case MosaicShape.heart:
        return Icons.favorite_outline_rounded;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppTheme.textLabel);
  }
}

class _ValueChip extends StatelessWidget {
  final String value;
  const _ValueChip({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.accentBright,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SliderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SliderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.bgTertiary,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
              color: AppTheme.borderColor.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 18, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.2)
              : AppTheme.bgTertiary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: isSelected
                ? AppTheme.accent
                : AppTheme.borderColor.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color:
                  isSelected ? AppTheme.accentBright : AppTheme.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
