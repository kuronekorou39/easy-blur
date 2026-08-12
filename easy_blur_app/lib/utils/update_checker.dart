import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// 新しいリリースの情報
class ReleaseInfo {
  final String version;
  final String url;
  const ReleaseInfo({required this.version, required this.url});
}

/// GitHub Releases を参照してアプリの更新を確認する
class UpdateChecker {
  static const _latestReleaseApi =
      'https://api.github.com/repos/kuronekorou39/easy-blur/releases/latest';

  /// リリース一覧ページ（リンク先のフォールバックにも使う）
  static const releasesPageUrl =
      'https://github.com/kuronekorou39/easy-blur/releases';

  /// 現在のアプリバージョン（例: "0.7.0"）
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 新しいバージョンがあればそのリリース情報を返す。なければ null。
  /// 通信エラー時も null（更新確認の失敗は本体機能に影響させない）。
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final current = await currentVersion();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(_latestReleaseApi));
        request.headers
            .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) return null;
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tag = json['tag_name'] as String?;
        final url = json['html_url'] as String?;
        if (tag == null || url == null) return null;
        final latest = tag.startsWith('v') ? tag.substring(1) : tag;
        if (_isNewer(latest, current)) {
          return ReleaseInfo(version: latest, url: url);
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// a が b より新しいバージョンなら true（"1.2.3" 形式を数値比較）
  static bool _isNewer(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb;
    }
    return false;
  }
}
