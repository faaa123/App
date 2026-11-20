# 引き継ぎ：ネイティブ外枠（案③）への移行

新しいセッションの最初に、このファイルを読ませてから作業を始めること。

---

## 新しいセッションに渡すプロンプト

> `docs/HANDOFF_NATIVE_SHELL.md` を読んで、そこに書かれた「案③：ネイティブ外枠」を実装してください。
> まず §6 の「着手前に確認すること」を私に聞いてから始めてください。
> 修正は手元でコミットまで。push は私が「push して」と言ったときだけ行ってください。

---

## 1. プロジェクトの現状

- iPad 専用の Flutter アプリ。リポジトリ：`C:\Users\youta\ClaudeCode\App`（GitHub: `faaa123/App`、ブランチ `main`）
- **中心機能は学習スケジュール**。Android 版 `../LifeManagement`（StudyChime）を Dart に移植したもの。
  意図する仕様は `../LifeManagement/docs/spec.md` と `docs/DECISIONS.md` にある（**あちらのリポジトリは変更しないこと**）。
  - `lib/features/study/core/`：純ロジック（論理日の起点 4:00、半開区間のブロック、重複チェック、連動ずらし、並び替え、ポモドーロ、今の状態、統計/Streak、チャイム計画）
  - `lib/features/study/data/`：`StudyController`（JSON 永続化、日付の切り替わり処理、曜日プリセット、チャイム予約）
  - `lib/features/study/ui/`：今（カウントダウン＋1日の帯）／スケジュール（＋プリセット）／統計
  - チャイム：勉強⇄休憩の切り替わりを `flutter_local_notifications` で予約（7日分・最大60件、内容ベースの ID で差分登録）
- **副機能：一時的なホワイトボード**（`lib/features/whiteboard` ＋ ローカルプラグイン `packages/pencil_canvas`）
  - `PKCanvasView` を `UiKitView` で埋め込んでいる。Apple Pencil のみで描画、保存なし、指でパン・ピンチズーム（ボードは画面の3倍）
  - ツールパレットは PencilKit 標準（`PKToolPicker`）。スクイーズは PKToolPicker に任せ、ダブルタップはパレット非表示時のみ自前で処理（設定 → Apple Pencil の動作に従う）
  - 遅延対策：`DoNotBlockGesture` ポリシー、ネイティブのボタン、Flutter へのタッチ転送を無効化（`ForwardingGestureRecognizer` を名前で探して無効化）
  - **ユーザーはボードの機能追加を望んでいない**（最小限を維持）。遅延は最重要。
- 現在の外枠（Flutter）：`lib/app/shell.dart`。上部中央に浮かぶガラス風タブバー（`lib/app/glass.dart`）、背景はグラデーション。ボードは全画面で、左上のネイティブボタンでタブバーを出す。
- テーマ：ダーク＋ガラス調（`lib/app/app.dart` の `_glassTheme`）。日本語ロケール固定。

## 2. 環境と制約

- Windows。Flutter 3.50.1 は `C:\Users\youta\flutter\bin\flutter`（Dart 3.14）。Material は `package:material_ui/material_ui.dart` から import する。
- **このPCでは iOS/Swift をビルドできない。** Swift の変更は GitHub Actions（`.github/workflows/ios.yml`、`macos-latest`）でしか検証できない。
  Swift は API の存在を確かめてから書くこと。Flutter のエンジン側ヘッダは `C:\Users\youta\flutter\engine\src\flutter\shell\platform\darwin` で読める。
- 配布：署名なし IPA を CI の artifact から取得し、無料の Apple ID と Sideloadly で iPad に入れている。**有料の entitlement は使えない。**
- 確認：`flutter analyze` と `flutter test`（現在56件すべて通過）を必ず通すこと。
- コミット：メッセージの最後に Co-Authored-By などの帰属行を付ける。**push はユーザーの明示的な指示があるときだけ。**
  2026-11-20 時点で `c2750d8`（ガラス UI ＋ダブルタップ修正）が未 push。
- CI の Actions は SHA で固定、権限は `contents: read`。変更する場合もこの方針を守ること。
- やり取りは日本語で。ユーザーは結果を iPad の実機で確認する。

## 3. 案③の目的

- iPadOS 26 の**本物の Liquid Glass** を使う（タブバー、各画面上部のバーとボタン）。
- ユーザーの不満：「左端じゃま」「UI がださい」「せっかく iPad なんだから Liquid Glass」
- ボードを**完全ネイティブの画面**にして、タブバーを残したまま遅延を最小にする。
  以前「全画面ネイティブ」を提案したときは、左メニューが消えるのを理由に断られている。案③ならタブバーは残る。

## 4. 目指す構成

```
SceneDelegate（ネイティブ）
└─ UITabBarController（iPadOS 26 では上部に浮かぶ Liquid Glass タブバー）
    ├─ 今          → UINavigationController → Flutter（route: now）
    ├─ スケジュール → UINavigationController → Flutter（route: schedule）、右上に「プリセット」ボタン（ネイティブ）
    ├─ 統計        → UINavigationController → Flutter（route: stats）
    └─ ボード      → 完全ネイティブの UIViewController（PKCanvasView ＋ ツール/元に戻す/全消去）
```

方針：

- **Flutter エンジンは1つ**（`FlutterEngine` を SceneDelegate か AppDelegate で保持）。タブを切り替えたら `FlutterViewController` をそのタブに付け替え、
  MethodChannel（例：`app/shell`）で表示する画面を Dart に伝える。`StudyController` の状態はそのまま共有される。
  - 付け替えでちらつく場合の対策候補：切り替え前のスナップショットを重ねる／タブごとに `FlutterViewController` を持ってエンジンだけ付け替える。
  - FlutterEngineGroup で複数エンジンにする案は、状態が分かれる（Isolate が別になる）ので避ける。
- 左サイドバーは使わない（ユーザーが明確に嫌がった）。タブバーのみ。`UITabBarController.mode` は `.tabBar` にする。
- 各画面上部のタイトルと操作（スケジュールの「プリセット」など）はネイティブの navigation bar に移す。Flutter 側の AppBar は外す。
  - タブ内の Flutter から別画面（プリセット）へ進む方法は、Flutter 内の遷移のままでもよい。どちらにするか選んで、理由を記録すること。
- ダイアログ（ブロック編集、時刻選択など）は Flutter のまま（今のガラス調）。
- Flutter の外枠（`lib/app/shell.dart` の浮かぶタブバー、`ShellScope`、`immersive`）は不要になるので整理する。
  背景グラデーション（`GlassBackground`）は、各 Flutter 画面の背景として残してよい。
- ボード：`packages/pencil_canvas` の Swift（`PencilCanvasPlatformView` の中身：PKCanvasView の設定、PKToolPicker、ダブルタップ処理、ボードの3倍サイズ、ボタン）を、
  `UIViewController` に移すか共有する。ネイティブ画面ならタッチ転送の無効化（`BoardContainerView.stopFlutterTouchForwarding`）は不要。
  Flutter 側の `UiKitView` 経路は削除してよい（テスト用の代替表示が要るかは判断すること）。
- iPadOS 26 未満では標準タブバーになる（Liquid Glass 以外は同じように動けばよい）。
- 通知の前面表示（`AppDelegate` の `UNUserNotificationCenter.current().delegate`）と、`flutter_local_notifications` などのプラグイン登録
  （`GeneratedPluginRegistrant.register(with:)`）が、自前のエンジンでも確実に行われるようにすること。

## 5. 確認すること

- CI の `macos-latest` の Xcode が iOS 26 SDK を持っているか（Liquid Glass は iOS 26 SDK でビルドしたときだけ有効）。
  持っていなければ、Xcode のバージョンを指定する手順をワークフローに追加する（Action を使う場合は SHA で固定）。
- `flutter analyze` と `flutter test` を通す。外枠のテストは、Flutter 側の「route を受け取って画面を出す」部分を中心に書き直す。
- CI の iOS ビルドを通す（push はユーザーの許可を得てから）。
- 実機で見てもらうこと：
  - タブバーが Liquid Glass になっているか
  - タブ切り替えでちらつかないか
  - ボードの遅延
  - 曜日プリセット・チャイム・統計が今までどおり動くか
  - ペンのダブルタップとスクイーズ

## 6. 着手前に確認すること

1. iPad の iPadOS のバージョン（設定 → 一般 → 情報）。26 未満なら Liquid Glass にならないことを先に伝える。
2. ボード以外のタブで、画面上部のバー（大きなタイトル）を出すか。出さずに Flutter の画面をタブバーの直下から始めるか。
3. タブの並び順（現在：今／スケジュール／統計／ボード）と、起動時に開くタブ（現在：今）。

## 7. 参考：ここまでの経緯

- 改善ループ（セキュリティ・パフォーマンス・遅延・正しさ・文言・UI の6観点）で、40件以上を反映済み。
  まだ反映していない提案：
  - ロック画面のチャイム通知にブロック名が出る
  - アプリを開かないと数日でチャイムが止まることを画面で知らせる
  - 「＋勉強を追加」「＋休憩を追加」のワンタップ追加ボタン
  - アプリ名が「App」のまま
  - 同じ曜日に複数プリセットが割り当てられていても分からない
- メモリ（`~/.claude/projects/C--Users-youta-ClaudeCode-App/memory/`）に「ボードは最小限の副機能」と記録してある。
