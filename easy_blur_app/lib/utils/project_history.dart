import 'dart:convert';
import '../models/models.dart';

/// プロジェクトの編集履歴をスナップショット方式で管理する。
///
/// 各編集操作の区切りで `push(project)` を呼ぶと、現在状態が
/// JSON シリアライズされてスタックに積まれる。`undo` / `redo` で
/// 前後の状態を JSON 文字列として返す（呼び出し側で EditorProject に復元）。
///
/// 上限はデフォルト50段。超過すると古いスナップショットから順に破棄。
class ProjectHistory {
  final List<String> _stack = [];
  int _index = -1;
  final int maxHistory;

  ProjectHistory({this.maxHistory = 50});

  bool get canUndo => _index > 0;
  bool get canRedo => _index < _stack.length - 1;
  int get length => _stack.length;

  /// 現在状態を履歴に積む。index より先の redo 分は破棄される。
  void push(EditorProject project) {
    final snapshot = jsonEncode(project.toJson());
    // 同一状態の連続 push は無視
    if (_index >= 0 && _stack[_index] == snapshot) return;

    // Redo バッファを切り詰める
    if (_index < _stack.length - 1) {
      _stack.removeRange(_index + 1, _stack.length);
    }
    _stack.add(snapshot);
    _index = _stack.length - 1;

    // 上限超過分を削除
    while (_stack.length > maxHistory) {
      _stack.removeAt(0);
      _index--;
    }
  }

  /// 1つ前の状態を返す。なければ null。
  EditorProject? undo() {
    if (!canUndo) return null;
    _index--;
    return _decode(_stack[_index]);
  }

  /// 1つ先の状態を返す。なければ null。
  EditorProject? redo() {
    if (!canRedo) return null;
    _index++;
    return _decode(_stack[_index]);
  }

  /// 履歴を初期化
  void clear() {
    _stack.clear();
    _index = -1;
  }

  EditorProject _decode(String json) {
    return EditorProject.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}
