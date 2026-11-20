# App

iPad 向け Flutter アプリ。

## 構成
- `lib/app/` — アプリのシェル（NavigationRail）と機能レジストリ（`features.dart` に1行足すと機能追加）
- `lib/features/` — 各機能。`whiteboard/` は一時ホワイトボード（Apple Pencil・ペン固定・保存なし）
- `packages/pencil_canvas/` — PencilKit を埋め込む最小ローカルプラグイン

## ビルド
GitHub Actions（`.github/workflows/ios.yml`）で analyze / test と署名なし iOS ビルドを実行し、`app-unsigned.ipa` を artifact として出力します。
