import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// 出力相当の合成画像を全画面表示するオーバーレイ。
/// タップ or 閉じるボタンで onClose が呼ばれる。
class PreviewOverlay extends StatelessWidget {
  final Uint8List imageBytes;
  final VoidCallback onClose;

  /// 注釈ラベル（例: 「動画は現在フレーム」）
  final String? caption;

  const PreviewOverlay({
    super.key,
    required this.imageBytes,
    required this.onClose,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景タップで閉じる
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black.withValues(alpha: 0.92),
            ),
          ),
        ),
        // 合成画像
        Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
            ),
          ),
        ),
        // 上部にラベル
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated.withValues(alpha: 0.85),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(
                          color: AppTheme.borderLight
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility_rounded,
                          size: 14,
                          color: AppTheme.accentBright,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '出力プレビュー',
                          style: AppTheme.textBodyStrong.copyWith(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 下部にキャプション
        if (caption != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Text(
                      caption!,
                      style: AppTheme.textCaption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
