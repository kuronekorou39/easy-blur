import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// プロジェクトの永続化を担うストレージ。
///
/// - 保存先: `ApplicationDocumentsDirectory/projects/<id>.json`
/// - 自動保存: `requestSave` を呼ぶとデバウンスで500ms後に書き込み
/// - 一覧: `list` で全プロジェクトを返す
/// - 削除: `delete(id)`
/// - 読み込み: `load(id)`
class ProjectStorage {
  static const _debounceMs = 500;
  static Directory? _cachedDir;
  static final Map<String, Timer> _pendingSaves = {};

  static Future<Directory> _dir() async {
    if (_cachedDir != null) return _cachedDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'projects'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// 即時保存
  static Future<void> saveNow(EditorProject project) async {
    project.updatedAt = DateTime.now();
    final dir = await _dir();
    final file = File(p.join(dir.path, '${project.id}.json'));
    final json = jsonEncode(project.toJson());
    await file.writeAsString(json, flush: true);
  }

  /// デバウンス付き保存。連続呼び出しは500msで束ねられ、最後の1回だけ保存。
  static void requestSave(EditorProject project) {
    _pendingSaves[project.id]?.cancel();
    _pendingSaves[project.id] =
        Timer(const Duration(milliseconds: _debounceMs), () async {
      _pendingSaves.remove(project.id);
      try {
        await saveNow(project);
      } catch (_) {
        // 失敗は無視。次回保存で上書き。
      }
    });
  }

  /// 保留中の保存をすぐに実行（画面を閉じる前などに呼ぶ）
  static Future<void> flush(EditorProject project) async {
    final timer = _pendingSaves.remove(project.id);
    if (timer != null) {
      timer.cancel();
      await saveNow(project);
    }
  }

  /// IDから読み込み。存在しない場合は null。
  static Future<EditorProject?> load(String id) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, '$id.json'));
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      return EditorProject.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 全プロジェクトを更新日降順でリスト
  static Future<List<EditorProject>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return [];
    final files =
        await dir.list().where((e) => e is File && e.path.endsWith('.json')).toList();
    final projects = <EditorProject>[];
    for (final f in files) {
      try {
        final text = await File(f.path).readAsString();
        final json = jsonDecode(text) as Map<String, dynamic>;
        projects.add(EditorProject.fromJson(json));
      } catch (_) {
        // 壊れたファイルはスキップ
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  static Future<void> delete(String id) async {
    _pendingSaves[id]?.cancel();
    _pendingSaves.remove(id);
    final dir = await _dir();
    final file = File(p.join(dir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  /// 元メディアファイルが存在しないプロジェクトを削除
  static Future<void> cleanupMissingMedia() async {
    final projects = await list();
    for (final proj in projects) {
      if (!await File(proj.mediaPath).exists()) {
        await delete(proj.id);
      }
    }
  }
}
