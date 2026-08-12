# Easy Blur

画像・動画にモザイク/ぼかしをかけるツール集。

## Android アプリ (`easy_blur_app/`)

Flutter 製のモザイク・ぼかしエディター。画像と動画の両方に対応し、レイヤー・キーフレーム・Undo/Redo・自動保存などを備えています。編集はすべてデバイス内で処理されます。

### インストール

1. [最新リリース](https://github.com/kuronekorou39/easy-blur/releases/latest) から `easy-blur-vX.Y.Z-arm64.apk` をダウンロード
2. Android 端末でAPKを開いてインストール（「提供元不明のアプリ」の許可が必要な場合があります）

アプリのホーム画面下部に現在のバージョンが表示され、新しいリリースがあると更新リンクが表示されます。

### 開発

```bash
cd easy_blur_app
flutter pub get
flutter run
```

ランチャーアイコンは `assets/icon/` の PNG から生成しています。変更した場合は以下で再生成:

```bash
dart run flutter_launcher_icons
```

### リリース手順

1. `easy_blur_app/pubspec.yaml` の `version` を上げる
2. タグを打って push すると GitHub Actions が署名済み APK をビルドしてリリースを作成

```bash
git tag v0.7.0
git push origin v0.7.0
```

（APK のバージョン名はタグから自動注入されるため、タグと pubspec がずれてもタグが優先されます）

## Web ツール

- `index.html` — ブラウザで動く簡易モザイクツール
- `combine.html` — 画像結合ツール

ブラウザで直接開くだけで使えます。
