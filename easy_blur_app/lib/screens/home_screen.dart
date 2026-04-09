import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'image_editor_screen.dart';
import 'video_editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickMedia(BuildContext context, {required bool video}) async {
    final picker = ImagePicker();
    final XFile? file;

    if (video) {
      file = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
    }

    if (file == null || !context.mounted) return;

    final project = EditorProject(
      mediaPath: file.path,
      mediaType: video ? MediaType.video : MediaType.image,
    );

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => video
            ? VideoEditorScreen(project: project)
            : ImageEditorScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppTheme.accent, Color(0xFFa78bfa)],
                  ).createShader(bounds),
                  child: const Text(
                    'Easy Blur',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'モザイク & ぼかしエディター',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 56),
                _MediaPickButton(
                  icon: Icons.image_outlined,
                  label: '画像を編集',
                  sublabel: 'PNG, JPG, WebP',
                  onTap: () => _pickMedia(context, video: false),
                ),
                const SizedBox(height: 16),
                _MediaPickButton(
                  icon: Icons.videocam_outlined,
                  label: '動画を編集',
                  sublabel: 'MP4, MOV',
                  onTap: () => _pickMedia(context, video: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _MediaPickButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgSecondary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.accent, size: 28),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
