import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../utils/project_storage.dart';
import '../utils/theme.dart';
import 'image_editor_screen.dart';
import 'video_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introCtrl;
  bool _picking = false;
  List<EditorProject> _projects = [];
  bool _loadingProjects = true;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _introCtrl.forward();
    });
    _loadProjects();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    await ProjectStorage.cleanupMissingMedia();
    final projects = await ProjectStorage.list();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _loadingProjects = false;
    });
  }

  Future<void> _pickMedia({required bool video}) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      String? path;

      if (video) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
        );
        if (result != null && result.files.isNotEmpty) {
          path = result.files.first.path;
        }
      } else {
        final picker = ImagePicker();
        final file = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 100,
        );
        if (file != null) path = file.path;
      }

      if (path == null || !mounted) return;

      final project = EditorProject(
        mediaPath: path,
        mediaType: video ? MediaType.video : MediaType.image,
      );
      // 作成時点で保存（最小限の内容で）
      await ProjectStorage.saveNow(project);

      if (!mounted) return;
      await _openEditor(project);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('読み込みエラー: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openEditor(EditorProject project) async {
    final page = project.isVideo
        ? VideoEditorScreen(project: project)
        : ImageEditorScreen(project: project);

    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (ctx, a, b) => page,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (ctx, anim, secondary, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: anim, curve: AppTheme.curveEmphasized)),
              child: child,
            ),
          );
        },
      ),
    );
    // 戻ってきたらプロジェクトリストを再取得
    if (mounted) _loadProjects();
  }

  Future<void> _deleteProject(EditorProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: const Text('プロジェクトを削除'),
        content: Text(
          '編集中のプロジェクトを削除します。\n元のメディアファイルは残ります。',
          style: AppTheme.textBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ProjectStorage.delete(project.id);
      if (mounted) _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.5),
                  radius: 1.3,
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.18),
                    AppTheme.bgPrimary,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DotGridPainter()),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceXl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 48),
                          _buildHeader(),
                          const SizedBox(height: 40),
                          _buildPickButtons(),
                          if (_projects.isNotEmpty || _loadingProjects) ...[
                            const SizedBox(height: 36),
                            _buildContinueSection(),
                          ],
                          const Spacer(),
                          const SizedBox(height: 24),
                          _buildFooter(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _introCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_introCtrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.accentBright, AppTheme.accentDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.blur_on_rounded,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: AppTheme.spaceXl),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppTheme.textPrimary, AppTheme.accentBright],
                  ).createShader(bounds),
                  child: const Text(
                    'Easy Blur',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.4,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  'プロ仕様のモザイク・ぼかしエディター',
                  style: AppTheme.textBody.copyWith(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickButtons() {
    return AnimatedBuilder(
      animation: _introCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic
            .transform(((_introCtrl.value - 0.2) / 0.8).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: Column(
              children: [
                _MediaPickButton(
                  icon: Icons.image_rounded,
                  label: '新しい画像を編集',
                  sublabel: 'PNG · JPG · WebP',
                  color: AppTheme.accent,
                  loading: _picking,
                  onTap: () => _pickMedia(video: false),
                ),
                const SizedBox(height: AppTheme.spaceMd),
                _MediaPickButton(
                  icon: Icons.videocam_rounded,
                  label: '新しい動画を編集',
                  sublabel: 'MP4 · MOV',
                  color: AppTheme.info,
                  loading: _picking,
                  onTap: () => _pickMedia(video: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContinueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded,
                size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text('続きから', style: AppTheme.textHeader),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.bgHover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_projects.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _projects.length,
            separatorBuilder: (ctx, i) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final p = _projects[i];
              return _ProjectCard(
                project: p,
                onTap: () => _openEditor(p),
                onDelete: () => _deleteProject(p),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return AnimatedBuilder(
      animation: _introCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic
            .transform(((_introCtrl.value - 0.5) / 0.5).clamp(0.0, 1.0));
        return Opacity(
          opacity: t * 0.7,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FeatureTag(icon: Icons.grid_on_rounded, label: 'モザイク'),
                  const SizedBox(width: 8),
                  _FeatureTag(icon: Icons.blur_on_rounded, label: 'ぼかし'),
                  const SizedBox(width: 8),
                  _FeatureTag(
                      icon: Icons.layers_rounded, label: 'レイヤー'),
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                'デバイス内で処理 · データは送信されません',
                style: AppTheme.textCaption.copyWith(fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final EditorProject project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  String _formatUpdatedAt(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inSeconds < 60) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = project.isVideo;
    final accent = isVideo ? AppTheme.info : AppTheme.accent;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: AppTheme.borderLight.withValues(alpha: 0.5),
          ),
          boxShadow: AppTheme.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.3),
                        accent.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    isVideo
                        ? Icons.videocam_rounded
                        : Icons.image_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.bgHover,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${project.layers.length}層',
                    style: AppTheme.textCaption.copyWith(fontSize: 10),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              _shortName(project.mediaPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.textBodyStrong.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 3),
            Text(
              _formatUpdatedAt(project.updatedAt),
              style: AppTheme.textCaption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? 'プロジェクト' : parts.last;
  }
}

class _MediaPickButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _MediaPickButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_MediaPickButton> createState() => _MediaPickButtonState();
}

class _MediaPickButtonState extends State<_MediaPickButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.loading ? null : (_) => _ctrl.forward(),
      onTapUp: widget.loading
          ? null
          : (_) {
              _ctrl.reverse();
              widget.onTap();
            },
      onTapCancel: widget.loading ? null : () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(
                color: AppTheme.borderLight.withValues(alpha: 0.6)),
            boxShadow: AppTheme.shadowMd,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color.withValues(alpha: 0.3),
                      widget.color.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                      color: widget.color.withValues(alpha: 0.3)),
                ),
                child: Icon(widget.icon, color: widget.color, size: 26),
              ),
              const SizedBox(width: AppTheme.spaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.sublabel,
                      style: AppTheme.textCaption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.bgTertiary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: widget.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          Text(label, style: AppTheme.textCaption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.05);
    const spacing = 36.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
